#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -e .env || -e secrets/rpc_secret ]]; then
  echo 'Existing VPS secrets found; refusing to overwrite.' >&2
  exit 1
fi

if ! id azalea-read >/dev/null 2>&1; then
  echo 'Create the azalea-read Unix user before VPS setup.' >&2
  exit 1
fi

mkdir -p secrets data/meta data/data bronze
umask 077
openssl rand -hex 32 > secrets/rpc_secret
cat > .env <<EOF
TAILSCALE_IPV4=REPLACE_WITH_VPS_TAILSCALE_IPV4
GARAGE_DEFAULT_ACCESS_KEY=GK$(openssl rand -hex 16)
GARAGE_DEFAULT_SECRET_KEY=$(openssl rand -hex 32)
GARAGE_DEFAULT_BUCKET=azalea-images
BRONZE_READ_GID=$(id -g azalea-read)
EOF
echo 'Set TAILSCALE_IPV4 in .env, then run docker compose up -d.'
