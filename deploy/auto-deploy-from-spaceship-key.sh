#!/usr/bin/env bash
# ============================================================================
# Self-contained custom-domain deployer for stablefold.org via Spaceship API.
# Run this ONCE when you have a Spaceship API key+secret.
#
# What it does:
#   1. Creates 4 A records + 1 CNAME at Spaceship for stablefold.org
#   2. Polls DoH (DNS-over-HTTPS) until DNS propagates globally
#   3. Restores CNAME file in repo + pushes to main (re-binds GH Pages)
#   4. Forces HTTPS via Pages API
#   5. Polls until Let's Encrypt SSL is provisioned (5-30 min)
#   6. Final HTTP/2 200 verification + Lighthouse on https://stablefold.org
#
# Usage:
#   export SPACESHIP_API_KEY="..."
#   export SPACESHIP_API_SECRET="..."
#   bash auto-deploy-from-spaceship-key.sh
#
# Refs:
#   Spaceship API:    https://docs.spaceship.dev/
#   GH Pages domains: https://docs.github.com/en/pages/configuring-a-custom-domain-for-your-github-pages-site
# ============================================================================
set -uo pipefail

DOMAIN="${DOMAIN:-stablefold.org}"
REPO="${REPO:-Fedorovskyfinance/stablefold-landing}"
LANDING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_IPS=("185.199.108.153" "185.199.109.153" "185.199.110.153" "185.199.111.153")
WWW_TARGET="fedorovskyfinance.github.io"

SPACESHIP_API_BASE="https://spaceship.dev/api/v1"
DOH_URL="https://cloudflare-dns.com/dns-query"

DNS_TIMEOUT=900    # 15 min for DNS propagation
SSL_TIMEOUT=2400   # 40 min for Let's Encrypt
POLL=20

log()   { echo "[$(date +%H:%M:%S)] $*"; }
fatal() { log "❌ $*"; exit 1; }

# ---- preflight ----
[ -z "${SPACESHIP_API_KEY:-}" ]    && fatal "SPACESHIP_API_KEY env var not set"
[ -z "${SPACESHIP_API_SECRET:-}" ] && fatal "SPACESHIP_API_SECRET env var not set"
command -v gh   >/dev/null || fatal "gh CLI not installed"
command -v curl >/dev/null || fatal "curl not installed"
command -v git  >/dev/null || fatal "git not installed"
gh auth status >/dev/null 2>&1 || fatal "gh not authenticated (run: gh auth login)"

log "=== Stablefold custom-domain deploy: $DOMAIN ==="

# ============================================================================
# Phase 1/6: Create DNS records at Spaceship
# ============================================================================
log "Phase 1/6: Creating DNS records at Spaceship for $DOMAIN..."

create_record() {
  local type="$1" name="$2" data="$3"
  local payload
  payload=$(printf '{"items":[{"type":"%s","name":"%s","address":"%s","ttl":600}]}' "$type" "$name" "$data")
  local resp
  resp=$(curl -sS -X PUT \
    -H "X-API-Key: $SPACESHIP_API_KEY" \
    -H "X-API-Secret: $SPACESHIP_API_SECRET" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$SPACESHIP_API_BASE/dns/records/$DOMAIN" \
    -w "\nHTTP_CODE=%{http_code}" 2>&1)
  local code
  code=$(echo "$resp" | grep -oE 'HTTP_CODE=[0-9]+$' | tail -1 | cut -d= -f2)
  echo "  $type $name → $data : HTTP $code"
  if [[ ! "$code" =~ ^2 ]]; then
    log "    Spaceship response: $(echo "$resp" | head -3)"
  fi
}

for ip in "${GH_IPS[@]}"; do
  create_record "A" "@" "$ip"
done
create_record "CNAME" "www" "${WWW_TARGET}."

# ============================================================================
# Phase 2/6: Wait for DNS propagation via DoH
# ============================================================================
log "Phase 2/6: Polling DoH until DNS propagates (timeout ${DNS_TIMEOUT}s)..."

START=$(date +%s)
prev=""
while true; do
  elapsed=$(( $(date +%s) - START ))
  [ $elapsed -gt $DNS_TIMEOUT ] && fatal "DNS propagation timeout after ${DNS_TIMEOUT}s"

  result=$(curl -s -H 'Accept: application/dns-json' \
    "$DOH_URL?name=$DOMAIN&type=A" --max-time 6 2>/dev/null \
    | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    print(' '.join(sorted(a.get('data','') for a in d.get('Answer', []) if a.get('type') == 1)))
except Exception:
    print('')
" 2>/dev/null)

  matched=0
  for ip in "${GH_IPS[@]}"; do
    echo "$result" | grep -q "$ip" && matched=$((matched+1))
  done

  state="ips=[$result] matched=$matched/4"
  if [ "$state" != "$prev" ]; then
    log "  $state  (elapsed ${elapsed}s)"
    prev="$state"
  fi

  [ "$matched" -ge 3 ] && { log "✅ DNS propagated"; break; }
  sleep $POLL
done

# ============================================================================
# Phase 3/6: Restore CNAME in repo + push
# ============================================================================
log "Phase 3/6: Restoring CNAME file in repo..."

cd "$LANDING_DIR"
echo "$DOMAIN" > CNAME
git add CNAME
if git diff --cached --quiet; then
  log "  (CNAME already up-to-date in last commit)"
else
  git commit -m "Bind $DOMAIN to GitHub Pages (DNS now propagated)" >/dev/null
  git push origin main >/dev/null 2>&1 || fatal "git push failed"
  log "  ✅ CNAME committed + pushed"
fi

# ============================================================================
# Phase 4/6: Re-bind GH Pages custom domain via API
# ============================================================================
log "Phase 4/6: Binding GH Pages custom domain via API..."

# delete + recreate Pages config to clear any stale state
gh api -X DELETE "/repos/$REPO/pages" >/dev/null 2>&1 || true
sleep 3
gh api -X POST "/repos/$REPO/pages" \
  -H "Accept: application/vnd.github+json" \
  --input - <<EOF >/dev/null 2>&1 || fatal "Pages create failed"
{"source": {"branch": "main", "path": "/"}, "cname": "$DOMAIN"}
EOF

# wait for status=built
START=$(date +%s)
while true; do
  elapsed=$(( $(date +%s) - START ))
  [ $elapsed -gt 300 ] && fatal "Pages build never completed"
  status=$(gh api "/repos/$REPO/pages" 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('status','?'))")
  log "  Pages status: $status (${elapsed}s)"
  [ "$status" = "built" ] && break
  sleep 10
done
log "  ✅ Pages bound to $DOMAIN"

# ============================================================================
# Phase 5/6: Enable HTTPS enforcement (waits for Let's Encrypt)
# ============================================================================
log "Phase 5/6: Enabling HTTPS (Let's Encrypt SSL provisioning, up to ${SSL_TIMEOUT}s)..."

# Try to enforce HTTPS — may fail until cert is issued, retry
START=$(date +%s)
while true; do
  elapsed=$(( $(date +%s) - START ))
  [ $elapsed -gt $SSL_TIMEOUT ] && fatal "SSL provisioning timeout"

  resp=$(gh api -X PUT "/repos/$REPO/pages" \
    -H "Accept: application/vnd.github+json" \
    --input - <<EOF 2>&1
{"https_enforced": true, "cname": "$DOMAIN"}
EOF
)
  if echo "$resp" | grep -qi "error\|fail"; then
    log "  HTTPS not yet ready (${elapsed}s): waiting for cert..."
    sleep 30
    continue
  fi

  # verify externally
  code=$(curl -sI --max-time 10 "https://$DOMAIN/" 2>/dev/null | head -1 | awk '{print $2}')
  log "  https://$DOMAIN/ → HTTP $code (${elapsed}s)"
  [ "$code" = "200" ] && break
  sleep 30
done
log "  ✅ HTTPS active on https://$DOMAIN"

# ============================================================================
# Phase 6/6: Final verification + Lighthouse
# ============================================================================
log "Phase 6/6: Final verification..."

curl -sI --max-time 10 "https://$DOMAIN/" | head -8
log ""
log "Running Lighthouse mobile..."
npx -y lighthouse@latest "https://$DOMAIN/" \
  --only-categories=performance,accessibility,best-practices,seo \
  --chrome-flags="--headless=new --no-sandbox" \
  --form-factor=mobile \
  --quiet \
  --output=json --output-path=/tmp/lh-stablefold-final.json 2>&1 | tail -2

python3 <<EOF
import json
d = json.load(open('/tmp/lh-stablefold-final.json'))
print('=== https://$DOMAIN/ Lighthouse ===')
for k,v in d['categories'].items():
    print(f'  {k:18s} {round((v.get("score") or 0)*100)}')
EOF

log ""
log "🎉 https://$DOMAIN/ LIVE"
