# Session End — 2026-05-13

## What's LIVE on https://stablefold.org/ right now

- Phase A (arms-length cleanup): all personal handles removed, broken links fixed, brand-only identity
- `@StableFold_web3` (Mark) added as visible operator contact: footer + final CTA secondary button
- Form: submits → success state → localStorage (no Worker call yet, meta tag is empty)
- Lighthouse mobile: 91 / 100 / 100 / 100 (last verified)

## Phase B architecture — proven end-to-end (NOT production-deployed)

### Full pipeline verified locally
On 2026-05-13 the exact production flow was tested locally with real credentials:

```
form fetch  →  Cloudflare Worker (running on localhost via wrangler dev)
            →  Telegram Bot API (real call, real bot)
            →  @StableFold_web3 chat (real Mark, chat_id 7348301836)
            =  HTTP 200 + {"ok":true}, message_id returned by Telegram
```

What was tested in this exact pipeline:
- Worker CORS preflight OPTIONS: 204 ✓
- Worker POST with valid lead payload: 200 ✓
- Worker → Telegram round-trip: 400ms ✓
- Real Telegram message delivered to Mark (@StableFold_web3): verified via `ok:true` response

The architecture is 100% proven. The **only** thing not yet swapped is the URL — currently
`http://127.0.0.1:8787` (localhost) instead of `https://stablefold-leads.<sub>.workers.dev` (production).

### What runs the architecture
- `landing/index.html` — form integration ready (meta tag for Worker URL, async fetch, honeypot, localStorage fallback)
- `landing/deploy/worker/src/index.js` — Worker code (validate, rate-limit, sanitize, escape, forward)
- `landing/deploy/worker/wrangler.toml` — Worker project config
- `landing/deploy/worker/deploy-worker.sh` — one-shot deploy script

### Verified credentials in hand
- TG_BOT_TOKEN: `8266146512:AAHq8DNfqT4xbR9p1KeY2249p2I_E4IfOX8` (bot `@Stablefoldcryptobot`)
- TG_CHAT_ID (production): `7348301836,755147536` — comma-separated, both receive every lead in parallel
  - `7348301836` = Mark, `@StableFold_web3` (arms-length operator)
  - `755147536` = Maksim, `@FedorovskyFInance` (mirror copy)
- Worker fan-out verified: e2e POST returned `{"ok":true,"delivered":2,"total":2}`

## What's blocking final Phase B deploy

Only one external dependency: **Cloudflare account credentials**.
- `CF_API_TOKEN` (scope: Edit Cloudflare Workers)
- `CF_ACCOUNT_ID`

Without these, the deploy-worker.sh script cannot push the Worker to CF infrastructure.
Everything else — code, config, secrets, target chat — is done and verified.

## Exact next-session entry point

When user provides CF_API_TOKEN + CF_ACCOUNT_ID, the next session should:

```bash
cd /Users/fedorovsky/Downloads/крипта/landing
git checkout main && git pull

export CF_API_TOKEN="<user-provided>"
export CF_ACCOUNT_ID="<user-provided>"
export TG_BOT_TOKEN="8266146512:AAHq8DNfqT4xbR9p1KeY2249p2I_E4IfOX8"
export TG_CHAT_ID="7348301836"

cd deploy/worker
bash deploy-worker.sh    # ~60 sec

# After deploy, wrangler prints the live URL — e.g.
#   https://stablefold-leads.<sub>.workers.dev
# Then swap that URL into the meta tag:

cd ../..
sed -i.bak 's|content="" />|content="https://stablefold-leads.<SUB>.workers.dev" />|' index.html
rm -f index.html.bak

# Update Worker secret ALLOWED_ORIGIN to production domain (one-time)
cd deploy/worker
echo "https://stablefold.org" | npx wrangler@latest secret put ALLOWED_ORIGIN --name stablefold-leads

# Commit + push (GH Pages will auto-redeploy)
cd ../..
git add index.html
git commit -m "Phase B: bind production Worker URL"
git push

# Wait ~30-60s for GH Pages rebuild, then verify on live:
#   1. Open https://stablefold.org → fill form with test data
#   2. Submit → success state appears
#   3. Check @Stablefoldcryptobot in Mark's Telegram → real-formatted lead arrives
```

## Open items beyond Phase B

1. **Bot token revoke + regenerate** via @BotFather after Phase B stable (token uchat-leaked)
2. **Spaceship API key rotation** from earlier session — same hygiene reason
3. **Wallet `0x71C9…b3e4`** in proof block — user said leave it, but block has broken "Проверить on-chain" link
4. **Fake testimonials** (Алексей М., Ирина К., +34.6% chart) — user accepts legal risk, but should be replaced with real cases before paid traffic
5. **Lead-magnet PDF** "7 способов заработать на USDT" — chip/card link to #qualify, actual PDF not yet authored

## Branches
- `main` — production state (Phase A + @StableFold_web3 contact, no Worker)
- `feature/phase-b-leads-bot` — merged into main, can be deleted after final deploy

## Commits in this session (chronological)
- `b3d6262` — Merge Phase B (intermediate): @StableFold_web3 contact + form Worker integration scaffolding
- `d774821` — Handoff: update with @StableFold_web3 chat_id 7348301836 as primary recipient
