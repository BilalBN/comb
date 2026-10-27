# Running Comb on a DigitalOcean droplet

The droplet only ever holds encrypted data. It needs a domain name pointing
at it so Caddy can get an HTTPS certificate.

## What you need

- A droplet: Ubuntu 24.04, Basic, 1 GB RAM, Bangalore (BLR1), with your SSH
  key added
- A subdomain, for example `comb.yourdomain.com`, with an **A record**
  pointing to the droplet's IP. Add it wherever the domain's name servers
  are (`dig +short NS yourdomain.com` tells you: BigRock hosting → cPanel
  Zone Editor; BigRock DNS → DNS Management; Cloudflare → Cloudflare).

## Install

1. Check the domain points at the droplet: `ping comb.yourdomain.com`
   should show the droplet's IP.
2. Log in and get the code:
   ```bash
   ssh root@<droplet-ip>
   git clone https://github.com/BilalBN/comb.git
   cd comb
   ```
3. Run the setup script with your domain:
   ```bash
   bash deploy/droplet/setup.sh comb.yourdomain.com
   ```
   It checks the domain points here, turns on automatic security updates,
   opens only SSH/80/443, switches SSH to keys only, adds swap, installs
   Docker, starts Comb behind Caddy, and prints the one-time setup code.
4. Open `https://comb.yourdomain.com/v1/health` in a browser. You should see
   `"status":"ok"`.

## Updating

After a change is merged to `main`:

```bash
ssh root@<droplet-ip>
bash ~/comb/deploy/droplet/update.sh
```

Your data stays in the Docker volume `droplet_comb-data`; only the program
is replaced.

## Handy commands

```bash
cd ~/comb/deploy/droplet
docker compose ps                 # is it running?
docker compose logs --tail 50 comb
docker compose logs --tail 50 caddy   # HTTPS certificate problems show here
docker compose restart
```

## Moving to another server

Copy the `droplet_comb-data` volume (or restore a backup) to the new
machine, run the same setup there, and change the A record to the new IP.
The apps keep working because they use the domain, not the IP.

## Backups

Nightly encrypted backups to Backblaze B2 and GitHub are added later in M2.
