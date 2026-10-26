# Running Comb on a DigitalOcean droplet

The droplet only ever holds encrypted data. It needs a domain name pointing
at it so Caddy can get an HTTPS certificate.

## What you need

- A droplet: Ubuntu 24.04, Basic, 1 GB RAM, Bangalore (BLR1) region
- A domain or subdomain, for example `comb.yourdomain.com`, with an **A
  record** pointing to the droplet's IP address
- SSH access to the droplet

## Steps

1. Point the domain at the droplet (A record → droplet IP) and wait until
   `ping comb.yourdomain.com` shows that IP.
2. SSH in and get the code:
   ```bash
   ssh root@<droplet-ip>
   git clone https://github.com/BilalBN/comb.git
   cd comb
   ```
3. Run the setup script with your domain:
   ```bash
   bash deploy/droplet/setup.sh comb.yourdomain.com
   ```
   It turns on automatic security updates, opens only SSH/80/443, installs
   Docker, starts Comb behind Caddy, and prints the one-time setup code.
4. Open `https://comb.yourdomain.com/v1/health` in a browser. You should see
   `"status":"ok"`.

## Updating

```bash
cd ~/comb
git pull
cd deploy/droplet
docker compose up -d --build
```

## Data and backups

Encrypted data lives in the Docker volume `droplet_comb-data`. Nightly
encrypted backups to Backblaze B2 and GitHub are added in M1.
