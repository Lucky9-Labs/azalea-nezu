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

echo 'Azalea notebooks and Tailscale are ready.'
