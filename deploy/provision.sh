#!/usr/bin/env bash
# One-shot VPS provisioning for Stablefold landing
# Run on a fresh Ubuntu 24.04 LTS server as root (or with sudo)
# Usage: bash provision.sh
set -euo pipefail

DOMAIN="stablefold.com"
WWW_DOMAIN="www.stablefold.com"
LE_EMAIL="1millionfedorovsky@gmail.com"     # для уведомлений Let's Encrypt о просрочке

echo "=== [1/7] Updating system ==="
apt-get update -y
DEBIAN_FRONTEND=noninteractive apt-get upgrade -y

echo "=== [2/7] Installing nginx, certbot, ufw, fail2ban ==="
DEBIAN_FRONTEND=noninteractive apt-get install -y \
  nginx-extras certbot python3-certbot-nginx ufw fail2ban curl

echo "=== [3/7] Configuring UFW firewall ==="
ufw default deny incoming
ufw default allow outgoing
ufw allow OpenSSH
ufw allow 'Nginx Full'
ufw --force enable
ufw status

echo "=== [4/7] Preparing web roots ==="
mkdir -p /var/www/stablefold
mkdir -p /var/www/certbot
chown -R www-data:www-data /var/www/stablefold /var/www/certbot

echo "=== [5/7] Installing nginx config ==="
# Expecting deploy/nginx.conf in /tmp/stablefold-deploy/nginx.conf (rsynced before this script)
if [ -f /tmp/stablefold-deploy/nginx.conf ]; then
  cp /tmp/stablefold-deploy/nginx.conf /etc/nginx/sites-available/stablefold.conf
  ln -sf /etc/nginx/sites-available/stablefold.conf /etc/nginx/sites-enabled/stablefold.conf
  rm -f /etc/nginx/sites-enabled/default
fi

# Pre-SSL minimal config so certbot can answer ACME
cat > /etc/nginx/sites-available/stablefold-bootstrap.conf <<EOF
server {
    listen 80 default_server;
    listen [::]:80 default_server;
    server_name $DOMAIN $WWW_DOMAIN;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        root /var/www/stablefold;
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
# Use bootstrap until SSL is issued
ln -sf /etc/nginx/sites-available/stablefold-bootstrap.conf /etc/nginx/sites-enabled/stablefold-bootstrap.conf
rm -f /etc/nginx/sites-enabled/stablefold.conf

nginx -t
systemctl reload nginx

echo "=== [6/7] Issuing Let's Encrypt SSL cert ==="
certbot certonly --webroot -w /var/www/certbot \
  -d "$DOMAIN" -d "$WWW_DOMAIN" \
  --non-interactive --agree-tos -m "$LE_EMAIL" \
  --keep-until-expiring

echo "=== [7/7] Switching to production nginx config ==="
rm -f /etc/nginx/sites-enabled/stablefold-bootstrap.conf
ln -sf /etc/nginx/sites-available/stablefold.conf /etc/nginx/sites-enabled/stablefold.conf
nginx -t
systemctl reload nginx

# Auto-renewal already installed by certbot (systemd timer)
systemctl status certbot.timer --no-pager | head -5 || true

echo ""
echo "✅ Provision complete."
echo "   curl -sI https://$DOMAIN | head -1"
echo "   should return: HTTP/2 200"
