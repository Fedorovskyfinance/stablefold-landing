# Stablefold — Deploy Cheatsheet (Cloudflare Pages)

## Шаг 1 — Cloudflare аккаунт (5 мин)
1. Открой https://dash.cloudflare.com/sign-up
2. Email + пароль (использовать НЕ российский email)
3. Подтверди email

## Шаг 2 — Авторизация wrangler (1 мин)
```bash
cd /Users/fedorovsky/Downloads/крипта/landing
npx wrangler@latest login
```
Откроется браузер → авторизуй в Cloudflare → закроется автоматически.

## Шаг 3 — Деплой (10 секунд)
```bash
npx wrangler@latest pages deploy . --project-name=stablefold --commit-dirty=true
```

Первый раз спросит: `Create a new project? [Y/n]` → **Y**, production branch → `main`.

После деплоя получишь URL вида:
```
https://stablefold.pages.dev
https://abc123.stablefold.pages.dev   ← preview
```

## Шаг 4 — Кастомный домен (после покупки)
1. Купить домен на https://porkbun.com или https://namecheap.com.
   **Рекомендуемые варианты (все были свободны на 2026-05-12):**

   | Домен | Цена/год | Почему |
   |-------|----------|--------|
   | **stablefold.io** | $32 | TOP-1: чисто, технологично, идеально для финтеха |
   | **stablefold.com** | $11 | TOP-2: дешевле, привычнее для русскоязычной аудитории |
   | stablefold.finance | $30 | подчёркивает категорию |
   | stablefold.capital | $35 | премиум-tone |
   | stablefold.fund | $28 | |

   ⚠️ Перед покупкой ещё раз проверь availability на самом регистраторе.

2. В Cloudflare:
   - Pages → твой проект → Custom domains → Set up a domain
   - Введи домен → CF даст 2 nameserver-а

3. У регистратора:
   - Domain → Nameservers → Custom → впиши те 2 NS от CF
   - Подождать 10 мин — час (DNS propagation)

4. CF автоматически выдаст SSL (бесплатно, Let's Encrypt). HTTPS заработает сам.

## Шаг 5 — Что подменить ПЕРЕД продакшн-трафиком (TODO в коде)
В `index.html` найти `TODO(real-data)` и подставить:

| TODO | Где | Что |
|------|-----|-----|
| Telegram username | `landing/index.html` JS `TG_USERNAME` | твой реальный @username (без @) |
| Wallet команды | `.onchain-verify` | реальный публичный wallet 0x… + ссылка на Arbiscan |
| Реальные кейсы | proof-cards | минимум 3 с фото + TG + сумма депозита |
| Lead-magnet PDF | `#leadmagnet` anchor | URL на реальный PDF (можно положить в /landing/pdf/...) |
| Telegram канал ссылка | final CTA + footer | реальный t.me/... |
| Дата когорты | hero pill | когда определишь старт |

## Шаг 6 — Аналитика (опционально, 5 мин)
Лучшие cookie-less варианты:
- **Plausible** ($9/мес) — https://plausible.io — приватный, GDPR-clean
- **Cloudflare Web Analytics** (бесплатно, встроено) — Pages → Analytics

Для Meta Ads — Pixel + Conversions API подключим отдельным спринтом, после Meta-сертификации юр.лица.

## Откат
v1 версия лежит в `landing/index.v1.html`. Если что-то пошло не так:
```bash
mv landing/index.html landing/index.v3.html
mv landing/index.v1.html landing/index.html
npx wrangler@latest pages deploy . --project-name=stablefold --commit-dirty=true
```
