#!/usr/bin/env bash
# Auto-deploy chain: wait for DNS → restore CNAME → bind GH Pages → enable HTTPS → verify
# Usage: ./auto-deploy-on-dns.sh [domain]
# Default: stablefold.org
set -uo pipefail

DOMAIN="${1:-stablefold.org}"
REPO="Fedorovskyfinance/stablefold-landing"
LANDING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GH_IPS=("185.199.108.153" "185.199.109.153" "185.199.110.153" "185.199.111.153")
TIMEOUT_SEC=7200   # 2 hours (Spaceship propagation can be slow)
POLL_SEC=30
HEARTBEAT_EVERY=10  # log "still waiting" every N polls (= 5min)
START=$(date +%s)

log() { echo "[$(date +%H:%M:%S)] $*"; }

log "=== Auto-deploy chain for $DOMAIN started ==="
log "Repo: $REPO"
log "Working dir: $LANDING_DIR"
log "Timeout: ${TIMEOUT_SEC}s, poll every ${POLL_SEC}s"
log ""

# ---------- Phase 1: wait for DNS (via DoH — bypasses ISP UDP/53 hijacking) ----------
log "Phase 1/5: waiting for DNS to point at GitHub Pages IPs..."
log "  (using DNS-over-HTTPS via 1.1.1.1 — TLS, ISP cannot intercept)"
prev_state=""
poll_count=0

# resolve via DoH (returns space-separated A records, or empty)
resolve_doh() {
  curl -s -H 'Accept: application/dns-json' \
    "https://cloudflare-dns.com/dns-query?name=$1&type=A" \
    --max-time 8 2>/dev/null \
    | python3 -c "
import json, sys
try:
    d = json.load(sys.stdin)
    if d.get('Status') != 0:
        print('')
    else:
        print(' '.join(sorted(a.get('data','') for a in d.get('Answer', []) if a.get('type') == 1)))
except Exception:
    print('')
" 2>/dev/null
}

while true; do
  now=$(date +%s)
  elapsed=$((now - START))
  if [ $elapsed -gt $TIMEOUT_SEC ]; then
    log "❌ TIMEOUT after ${TIMEOUT_SEC}s. DNS never appeared. Aborting."
    exit 1
  fi

  result=$(resolve_doh "$DOMAIN")
  matched=0
  for ip in "${GH_IPS[@]}"; do
    if echo "$result" | grep -q "$ip"; then matched=$((matched+1)); fi
  done
  state="ips=[$result] matched=$matched/4"

  if [ "$state" != "$prev_state" ]; then
    log "  $state  (elapsed ${elapsed}s)"
    prev_state="$state"
  elif [ $((poll_count % HEARTBEAT_EVERY)) -eq 0 ]; then
    log "  …still waiting (elapsed ${elapsed}s, last seen: $state)"
  fi

  if [ "$matched" -ge 3 ]; then
    log "✅ DNS ready: $matched/4 GitHub Pages IPs resolving"
    break
  fi

  poll_count=$((poll_count + 1))
  sleep $POLL_SEC
done

# ---------- Phase 2: restore CNAME and push ----------
log ""
log "Phase 2/5: restoring CNAME and pushing to main..."
cd "$LANDING_DIR"
# Make sure we're on main
git checkout main >/dev/null 2>&1 || { log "❌ Could not checkout main"; exit 1; }
git pull --rebase >/dev/null 2>&1 || true

# Write CNAME
echo "$DOMAIN" > CNAME
git add CNAME
if git diff --cached --quiet; then
  log "  CNAME unchanged (already in repo)"
else
  git commit -m "Restore CNAME for $DOMAIN (DNS now resolves)" 2>&1 | tail -1 | sed 's/^/  /'
  git push 2>&1 | tail -1 | sed 's/^/  /'
fi

# ---------- Phase 3: bind custom domain via gh API ----------
log ""
log "Phase 3/5: binding custom domain in GitHub Pages config..."
# Pages config might still exist with cname=null or be present
# Try PUT first (idempotent update); if that fails, recreate via DELETE+POST
PUT_RESULT=$(gh api -X PUT "/repos/$REPO/pages" \
  -H "Accept: application/vnd.github+json" \
  --input - <<EOF 2>&1
{"cname": "$DOMAIN", "https_enforced": false}
EOF
)
if echo "$PUT_RESULT" | grep -qi "error\|404\|422"; then
  log "  PUT failed: $PUT_RESULT"
  log "  Recreating Pages config..."
  gh api -X DELETE "/repos/$REPO/pages" 2>&1 | tail -1 | sed 's/^/  /'
  sleep 3
  gh api -X POST "/repos/$REPO/pages" \
    -H "Accept: application/vnd.github+json" \
    --input - <<EOF 2>&1 | head -1 | sed 's/^/  /'
{"source": {"branch": "main", "path": "/"}, "cname": "$DOMAIN"}
EOF
else
  log "  cname bound: $DOMAIN"
fi

# ---------- Phase 4: wait for cert + enable HTTPS ----------
log ""
log "Phase 4/5: waiting for Let's Encrypt SSL provisioning..."
HTTPS_OK=0
for i in $(seq 1 30); do
  sleep 30
  PAGES_INFO=$(gh api "/repos/$REPO/pages" 2>&1)
  STATE=$(echo "$PAGES_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('protected_domain_state','?'))" 2>/dev/null || echo "?")
  CNAME=$(echo "$PAGES_INFO" | python3 -c "import json,sys; d=json.load(sys.stdin); print(d.get('cname','?'))" 2>/dev/null || echo "?")
  log "  attempt $i/30 (after $((i*30))s): cname=$CNAME state=$STATE"

  # Try to enable https_enforced — succeeds only when cert is provisioned
  ENFORCE=$(gh api -X PUT "/repos/$REPO/pages" \
    -H "Accept: application/vnd.github+json" \
    --input - <<EOF 2>&1
{"https_enforced": true}
EOF
  )
  if ! echo "$ENFORCE" | grep -qi "error\|404\|422\|certificate does not exist"; then
    log "  ✅ HTTPS enforcement enabled — cert is ready"
    HTTPS_OK=1
    break
  fi
done
if [ $HTTPS_OK -eq 0 ]; then
  log "  ⚠ HTTPS still not provisioned after 15min. Will continue but expect HTTP only initially."
fi

# ---------- Phase 5: final verification ----------
log ""
log "Phase 5/5: final verification..."
sleep 10  # let GH propagate the cert + enforce
HTTPS_CODE=$(curl -sI "https://$DOMAIN/" --max-time 15 2>&1 | head -1 | awk '{print $2}')
HTTP_CODE=$(curl -sI "http://$DOMAIN/" --max-time 15 2>&1 | head -1 | awk '{print $2}')
WWW_CODE=$(curl -sI "https://www.$DOMAIN/" --max-time 15 -L 2>&1 | head -1 | awk '{print $2}')

log "  https://$DOMAIN/      → HTTP $HTTPS_CODE"
log "  http://$DOMAIN/       → HTTP $HTTP_CODE  (should redirect to HTTPS)"
log "  https://www.$DOMAIN/  → HTTP $WWW_CODE"

if [ "$HTTPS_CODE" = "200" ]; then
  log ""
  log "🎯 LIVE: https://$DOMAIN/"
  log "    Run: open https://$DOMAIN/"
  exit 0
elif [ "$HTTPS_CODE" = "" ] || [ "$HTTPS_CODE" = "000" ]; then
  log "⚠ HTTPS not yet reachable. Cert may still be provisioning (up to 60min)."
  log "  Re-check in 30 min: curl -sI https://$DOMAIN/"
  exit 2
else
  log "⚠ Unexpected HTTPS status. Manual investigation needed."
  exit 3
fi
