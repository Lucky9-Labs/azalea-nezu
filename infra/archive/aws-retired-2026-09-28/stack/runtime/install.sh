#!/bin/bash
set -euo pipefail
set +x

artifacts_bucket="$1"
secret_name="$2"
destination=/home/ec2-user/SageMaker/azalea-nezu
socket=/var/run/tailscale/tailscaled.sock
state=/home/ec2-user/SageMaker/.azalea-tailscale.state

mkdir -p "$destination" /var/run/tailscale
aws s3 sync "s3://${artifacts_bucket}/repo/" "$destination/" --region us-west-2 --no-progress
chown -R ec2-user:ec2-user "$destination"

if ! command -v tailscale >/dev/null 2>&1; then
  curl --fail --silent --show-error --location https://tailscale.com/install.sh | sh
fi

auth_key="$(aws secretsmanager get-secret-value --secret-id "$secret_name" --region us-west-2 --query SecretString --output text)"
if [[ -z "$auth_key" || "$auth_key" == "None" ]]; then
  echo 'Tailscale auth secret has no value' >&2
  exit 1
fi

if [[ ! -S "$socket" ]]; then
  nohup tailscaled --tun=userspace-networking --state="$state" \
    --socket="$socket" --socks5-server=127.0.0.1:1055 \
    >/var/log/azalea-tailscaled.log 2>&1 &
fi

for attempt in 1 2 3 4 5 6 7 8 9 10; do
  [[ -S "$socket" ]] && break
  sleep 1
done

tailscale --socket="$socket" up --auth-key="$auth_key" \
  --hostname=azalea-sagemaker --accept-dns=false
unset auth_key

# Keep Silver current only when at least one read-only Bronze source is
# configured. The durable cursor remains in S3.
sudo -u ec2-user python3 -m pip install --user -r "$destination/requirements.txt"
sources_file="$destination/config/sources.json"
if sudo -u ec2-user env PYTHONPATH="$destination" python3 -c \
  'import sys; from azalea_pipeline.bronze import load_sources; raise SystemExit(0 if load_sources(sys.argv[1]) else 1)' \
  "$sources_file" >/dev/null 2>&1; then
  cat >/etc/systemd/system/azalea-silver-poll.service <<EOF
[Unit]
Description=Continuously pull Pi/VPS Bronze into Azalea Silver
After=network-online.target
ConditionPathExists=$sources_file

[Service]
Type=simple
User=ec2-user
WorkingDirectory=$destination
ExecStart=/usr/bin/python3 -u $destination/scripts/poll_silver.py --repo $destination --interval-seconds 30
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable --now azalea-silver-poll.service
echo 'Azalea notebooks, Tailscale, and Silver poller are ready.'
else
  systemctl disable --now azalea-silver-poll.service || true
  rm -f /etc/systemd/system/azalea-silver-poll.service
  systemctl daemon-reload
  echo 'No Bronze sources configured; Silver poller remains stopped.'
fi
