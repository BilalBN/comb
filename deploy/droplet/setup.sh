#!/usr/bin/env bash
# One-time preparation of a fresh Ubuntu droplet for Comb. Safe to run again.
# Run as root:  bash deploy/droplet/setup.sh comb.yourdomain.com
set -euo pipefail

DOMAIN="${1:-}"
if [ -z "$DOMAIN" ]; then
  echo "Usage: bash deploy/droplet/setup.sh comb.yourdomain.com" >&2
  exit 2
fi
if [ "$(id -u)" -ne 0 ]; then
  echo "Run this as root (log in with: ssh root@<droplet-ip>)." >&2
  exit 2
fi
HERE="$(cd "$(dirname "$0")" && pwd)"

echo "==> Checking that $DOMAIN points at this droplet"
MY_IP="$(curl -fsS --max-time 3 http://169.254.169.254/metadata/v1/interfaces/public/0/ipv4/address 2>/dev/null || hostname -I | awk '{print $1}')"
DNS_IP="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk 'NR==1 {print $1}')"
if [ "$DNS_IP" != "$MY_IP" ]; then
  echo
  echo "  $DOMAIN resolves to: ${DNS_IP:-nothing yet}"
  echo "  This droplet's IP is: $MY_IP"
  echo
  echo "  The HTTPS certificate can only be issued once the domain points here."
  echo "  Fix the A record (or wait for DNS to update), then run this again."
  read -r -p "  Continue anyway? Comb will keep retrying the certificate. [y/N] " answer
  [ "$answer" = "y" ] || [ "$answer" = "Y" ] || exit 1
else
  echo "    OK: $DOMAIN -> $MY_IP"
fi

echo "==> Security updates install themselves"
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get install -y unattended-upgrades ufw ca-certificates curl git
dpkg-reconfigure -f noninteractive unattended-upgrades

echo "==> Firewall: only SSH, HTTP and HTTPS"
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable

echo "==> SSH: keys only, no passwords"
if [ -s /root/.ssh/authorized_keys ]; then
  cat > /etc/ssh/sshd_config.d/10-comb.conf <<'EOF'
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin prohibit-password
EOF
  if sshd -t; then
    systemctl reload ssh 2>/dev/null || systemctl reload sshd 2>/dev/null || true
  else
    rm -f /etc/ssh/sshd_config.d/10-comb.conf
    echo "    Left SSH settings unchanged (the new settings did not pass a check)."
  fi
else
  echo "    Skipped: no SSH key found for root, so password login stays on."
fi

echo "==> Swap (helps a 1 GB droplet during updates)"
if ! swapon --show | grep -q .; then
  fallocate -l 1G /swapfile
  chmod 600 /swapfile
  mkswap /swapfile >/dev/null
  swapon /swapfile
  grep -q '^/swapfile' /etc/fstab || echo '/swapfile none swap sw 0 0' >> /etc/fstab
  echo "    Added 1 GB of swap"
else
  echo "    Swap already on"
fi

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
  if docker compose exec -T comb python -c "import urllib.request; urllib.request.urlopen('http://127.0.0.1:8080/v1/health')" >/dev/null 2>&1; then break; fi
  sleep 2
done

echo
if docker compose exec -T comb test -f /data/SETUP_CODE.txt 2>/dev/null; then
  echo "Your one-time setup code (enter it in the Comb app):"
  echo
  echo "    $(docker compose exec -T comb cat /data/SETUP_CODE.txt)"
  echo
else
  echo "An account already exists on this server, so there is no setup code."
  echo "Add devices by pairing from a device you already have."
fi
echo "Check in a browser: https://$DOMAIN/v1/health"
echo "(The first visit can take a minute while the HTTPS certificate is issued.)"
