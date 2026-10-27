#!/usr/bin/env bash
# Updates the Comb server on the droplet to the latest code on main.
# Run as root:  bash ~/comb/deploy/droplet/update.sh
# Your data stays in its Docker volume; only the program is replaced.
set -euo pipefail
cd "$(dirname "$0")/../.."

echo "==> Getting the latest code"
git switch -q main
git pull --ff-only

echo "==> Rebuilding and restarting"
cd deploy/droplet
docker compose up -d --build
docker image prune -f >/dev/null

echo
docker compose ps
echo
echo "Done. Check: https://$(grep '^COMB_DOMAIN=' .env | cut -d= -f2)/v1/health"
