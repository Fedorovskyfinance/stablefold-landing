# Handoff — Phase B (Lead-capture via Telegram Bot + Cloudflare Worker)

**Date:** 2026-05-13
**Status:** code-complete, locally verified, **blocked on user-provided Cloudflare credentials**
**Resume from:** any future session — this document is self-contained.

---

## TL;DR for next session

```
Current state:
  • main branch          → Phase A live on https://stablefold.org/ (working, leads → localStorage only)
  • feature/phase-b-leads-bot → Worker code + form integration, NOT deployed to CF
  • Telegram bot          → @Stablefoldcryptobot LIVE, chat_id 755147536 verified, test msg delivered

What's needed to finish (~5 min once you have CF creds):
  1. CF_API_TOKEN     (scope: Edit Cloudflare Workers)
  2. CF_ACCOUNT_ID    (from CF dashboard right sidebar)
  3. Run: bash deploy/worker/deploy-worker.sh
  4. Take printed Worker URL → swap into landing/index.html <meta name="stablefold-worker">
  5. Merge feature/phase-b-leads-bot → main
  6. Smoke-test form on live stablefold.org → verify TG msg arrives
```

---

## Verified credentials (already in hand)

| Asset | Value | Verified how |
|-------|-------|--------------|
| TG_BOT_TOKEN | `8266146512:AAHq8DNfqT4xbR9p1KeY2249p2I_E4IfOX8` | getMe returned `Stablefoldcryptobot` |
| TG_CHAT_ID | `755147536` | getUpdates after /start; sendMessage returned `message_id: 3` |
| Bot username | `@Stablefoldcryptobot` | live link https://t.me/Stablefoldcryptobot |

⚠️ Both tokens already passed through chat (compromised by definition). After production deploy stabilizes — **revoke bot via @BotFather → /revoke → regenerate**, then update CF Worker secret.

---

## Still needed from user

| Asset | Where to get | How to obtain |
|-------|--------------|---------------|
| **CF_API_TOKEN** | https://dash.cloudflare.com/profile/api-tokens | Create Token → template "Edit Cloudflare Workers" → All accounts → Continue → Create → copy |
| **CF_ACCOUNT_ID** | https://dash.cloudflare.com (home) | Right sidebar "API" block → "Account ID" → copy |

---

## Code that already exists in `feature/phase-b-leads-bot` (pushed to GitHub)

```
landing/
├── index.html                                  ← form already has Worker fetch + honeypot
└── deploy/worker/
    ├── wrangler.toml                            ← CF Worker project config
    ├── src/index.js                             ← Worker: validate → sanitize → forward to TG
    ├── deploy-worker.sh                         ← one-shot deploy with env-vars
    └── .gitignore                               ← excludes .dev.vars
```

### What the Worker does (deploy/worker/src/index.js)

1. CORS preflight: allows POST/OPTIONS from `https://stablefold.org` only
2. Rate-limit: 5 req/min/IP (in-memory; resets on isolate cold start)
3. Honeypot: if `website` field filled (bot indicator) → silent 200 (no TG call)
4. Validation: requires `name` + `tg`; max body 4KB; max field 512 chars
5. Sanitization: strips control chars (\x00-\x1F), trims, HTML-escapes for TG output
6. Forward to TG: `bot.sendMessage` with HTML formatting + geo from `request.cf` (country/city) + IP from `CF-Connecting-IP` header

### Test results (all pass on local wrangler dev)

| Test | Result |
|------|--------|
| OPTIONS preflight | 204 with correct CORS headers ✓ |
| GET / | 405 Method Not Allowed ✓ |
| POST valid lead | reaches TG API (502 with fake chat_id is expected, will be 200 with real) ✓ |
| Invalid JSON | 400 ✓ |
| Honeypot filled | 200 silent reject (no TG call) ✓ |
| Missing required fields | 400 ✓ |
| Bad Origin | 403 ✓ |
| Oversized body (5KB) | 413 ✓ |
| HTML injection in name | reaches TG with `&lt;script&gt;` escaped ✓ |
| Browser e2e (fetch interception) | POST fired, success state shown, localStorage updated ✓ |
| Direct TG sendMessage | `message_id: 3` (real msg in user's Telegram) ✓ |

---

## Deploy procedure (next-session ready)

```bash
cd /Users/fedorovsky/Downloads/крипта/landing
git checkout feature/phase-b-leads-bot
git pull

# Set creds (user provides CF_API_TOKEN, CF_ACCOUNT_ID)
export CF_API_TOKEN="<from user>"
export CF_ACCOUNT_ID="<from user>"
export TG_BOT_TOKEN="8266146512:AAHq8DNfqT4xbR9p1KeY2249p2I_E4IfOX8"
export TG_CHAT_ID="755147536"

# Deploy Worker
bash deploy/worker/deploy-worker.sh
# → output prints the workers.dev URL: https://stablefold-leads.<subdomain>.workers.dev

# Update the meta tag in index.html with the actual worker URL
# Replace the localhost URL with the production one:
sed -i.bak 's|content="http://127.0.0.1:8787"|content="https://stablefold-leads.<subdomain>.workers.dev"|' index.html
rm -f index.html.bak

# Update Worker ALLOWED_ORIGIN to production domain (one-time secret)
echo "https://stablefold.org" | npx wrangler@latest secret put ALLOWED_ORIGIN --name stablefold-leads --cwd deploy/worker

# Commit + merge to main
git add index.html
git commit -m "Phase B: bind production Worker URL https://stablefold-leads.<subdomain>.workers.dev"
git push

git checkout main
git merge feature/phase-b-leads-bot --no-ff -m "Merge Phase B: live lead-capture pipeline"
git push

# Smoke test on live (after GH Pages rebuild ~30-60s)
curl -sI https://stablefold.org/   # → HTTP/2 200

# E2E from real browser
# 1. Open https://stablefold.org → fill form with fake test data
# 2. Submit → should see success state
# 3. Check Telegram @Stablefoldcryptobot → should receive formatted lead
```

---

## Risks / things to watch

1. **CF Workers free tier limits**: 100k req/day. We expect <50/day. Comfortable margin.
2. **Bot token in repo**: deploy-worker.sh expects TG_BOT_TOKEN as env var; never committed. .dev.vars is gitignored.
3. **CORS misconfig**: Worker only allows origin `https://stablefold.org`. If you ever move to apex+www, need to allow both or do redirect at GH Pages level (already done — www → apex).
4. **Rate-limit cold-start reset**: in-memory map resets when Worker isolate is recycled (~hours). For real DDoS protection, bind a KV namespace and persist there. Free tier KV: 1k writes/day — enough.
5. **Bot username is public** (`@Stablefoldcryptobot`) — anyone searching "Stablefold" finds it. **Not a security issue** (token is separate), but **reduces isolation** because the brand name is visible. If absolute anonymity needed: rename bot via @BotFather → /setusername → something neutral like `s_concierge_bot`.

---

## What was completed in this session (2026-05-12 / 2026-05-13)

### Phase A — Arms-length cleanup (DEPLOYED, live)
- Removed all `@stablefold_team`, `@web3_trail`, `@podpolniy_biznes`, `hello@stablefold.io` from copy
- Removed broken footer links (YouTube, Telegram-channel, email)
- Brand href `#` → `/`
- Lead-magnet chip + inline card route to `#qualify` (not external personal channels)
- Final CTA "Написать в Telegram" button removed (only form remains)
- Form submit: localStorage capture + in-page success state (no TG-deeplink leak)
- Live Lighthouse: 91/100/100/100, LCP 1.3s, CLS 0, FAILS: clean

### Phase B — Lead capture via Telegram bot (CODE-COMPLETE, deploy blocked)
- Cloudflare Worker (validate, rate-limit, honeypot, escape, forward to TG)
- One-shot deploy script with env-var credentials
- Form integration: meta tag + async fetch + honeypot field + localStorage fallback
- All tests pass (9 curl + 1 browser e2e + 1 real TG sendMessage)
- Branch pushed: feature/phase-b-leads-bot

---

## Open items beyond Phase B

- Spaceship API keys (from earlier session) — still need revoke + regenerate
- Bot token — revoke + regenerate after production stable
- Wallet placeholder block `0x71C9…b3e4` — user said "не трогай", but block is non-functional
- Fake testimonials (Алексей М., Ирина К., +34.6%) — user said "оставить как есть, все так делают" — legal risk in RF
- Real lead-magnet PDF "7 способов заработать на USDT" — chip+card link to #qualify; actual PDF not yet authored

---

## How to resume in next session

If user says "deploy phase b" or "продолжай deploy":
1. Read this document
2. Check `git log feature/phase-b-leads-bot --oneline` for any new commits
3. Ask user for CF_API_TOKEN + CF_ACCOUNT_ID
4. Execute "Deploy procedure" section above
5. Verify on live → send screenshot of incoming TG message
