#!/usr/bin/env bash
# Deploy / re-deploy landing to VPS
# Usage:  ./deploy/deploy.sh <vps-ip-or-hostname>
# Example: ./deploy/deploy.sh 195.201.123.45
#         ./deploy/deploy.sh stablefold.org   (after DNS is up)
set -euo pipefail

HOST="${1:?Usage: $0 <vps-ip-or-hostname>}"
SSH_USER="root"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LANDING_DIR="$(dirname "$SCRIPT_DIR")"

echo "=== Syncing landing → $HOST:/var/www/stablefold ==="
rsync -avz --delete \
  --exclude='.git' \
  --exclude='index.v1.html' \
  --exclude='wrangler.toml' \
  --exclude='DEPLOY.md' \
  --exclude='deploy/' \
  -e "ssh -o StrictHostKeyChecking=accept-new" \
  "$LANDING_DIR/" "$SSH_USER@$HOST:/var/www/stablefold/"

echo "=== Reloading nginx ==="
ssh -o StrictHostKeyChecking=accept-new "$SSH_USER@$HOST" \
  'chown -R www-data:www-data /var/www/stablefold && nginx -t && systemctl reload nginx'

echo "=== Verifying ==="
ssh "$SSH_USER@$HOST" 'curl -sI -H "Host: stablefold.org" http://127.0.0.1/ | head -1'

echo ""
echo "✅ Deploy complete."
echo "   curl -sI https://stablefold.org | head -1   # после DNS propagation"
