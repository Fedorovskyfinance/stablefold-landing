#!/usr/bin/env bash
# ============================================================================
# Deploy Stablefold lead-capture Worker to Cloudflare.
#
# Required env vars:
#   CF_API_TOKEN       — Cloudflare API token with scope "Workers Scripts:Edit"
#   CF_ACCOUNT_ID      — Cloudflare account ID (find in dashboard URL)
#   TG_BOT_TOKEN       — Telegram bot token from @BotFather
#   TG_CHAT_ID         — operator's chat_id with the bot
#
# Usage:
#   export CF_API_TOKEN=...
#   export CF_ACCOUNT_ID=...
#   export TG_BOT_TOKEN=...
#   export TG_CHAT_ID=...
#   bash deploy-worker.sh
# ============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

# Preflight
[ -z "${CF_API_TOKEN:-}" ]  && { echo "❌ CF_API_TOKEN env var not set"; exit 1; }
[ -z "${CF_ACCOUNT_ID:-}" ] && { echo "❌ CF_ACCOUNT_ID env var not set"; exit 1; }
[ -z "${TG_BOT_TOKEN:-}" ]  && { echo "❌ TG_BOT_TOKEN env var not set"; exit 1; }
[ -z "${TG_CHAT_ID:-}" ]    && { echo "❌ TG_CHAT_ID env var not set"; exit 1; }

export CLOUDFLARE_API_TOKEN="$CF_API_TOKEN"
export CLOUDFLARE_ACCOUNT_ID="$CF_ACCOUNT_ID"

echo "=== [1/4] Set worker secrets ==="
echo "$TG_BOT_TOKEN" | npx -y wrangler@latest secret put TG_BOT_TOKEN --name stablefold-leads
echo "$TG_CHAT_ID"   | npx -y wrangler@latest secret put TG_CHAT_ID   --name stablefold-leads

echo ""
echo "=== [2/4] Deploy worker ==="
npx -y wrangler@latest deploy

echo ""
echo "=== [3/4] Print workers.dev URL (use this in form fetch) ==="
WORKER_URL="https://stablefold-leads.${CF_ACCOUNT_ID}.workers.dev"
echo "  Default: $WORKER_URL"
echo "  Test it: curl -X POST $WORKER_URL -H 'Content-Type: application/json' -d '{\"name\":\"Test\",\"tg\":\"@test\",\"capital\":\"\$3-10k\",\"exp\":\"none\"}'"

echo ""
echo "=== [4/4] (Optional) Bind to stablefold.org/api/lead route ==="
echo "  This requires DNS to be on Cloudflare (currently on Spaceship NS)."
echo "  Skip for now — use workers.dev URL directly from form."

echo ""
echo "✅ Worker deployed."
