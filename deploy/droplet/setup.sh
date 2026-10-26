#!/usr/bin/env bash
# One-time preparation of a fresh Ubuntu droplet for Comb.
# Run as root:  bash deploy/droplet/setup.sh comb.yourdomain.com
set -euo pipefail

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "Usage: bash deploy/droplet/setup.sh comb.yourdomain.com" >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Security updates install themselves"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades ufw ca-certificates curl
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Firewall: only SSH, HTTP and HTTPS"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> Docker"
if ! command -v docker >/dev/null; then
  curl -fsSL https://get.docker.com | sh
fi

echo "==> Comb"
echo "COMB_DOMAIN=$DOMAIN" > "$HERE/.env"
chmod 600 "$HERE/.env"
cd "$HERE"
docker compose up -d --build

echo
echo "Waiting for the server to start..."
for _ in $(seq 1 30); do
  if docker compose exec -T comb test -f /data/SETUP_CODE.txt 2>/dev/null; then break; fi
  sleep 2
done
echo "Your one-time setup code (enter it in the Comb app):"
docker compose exec -T comb cat /data/SETUP_CODE.txt || echo "  run: docker compose exec comb cat /data/SETUP_CODE.txt"
echo
echo "Check: https://$DOMAIN/v1/health"
