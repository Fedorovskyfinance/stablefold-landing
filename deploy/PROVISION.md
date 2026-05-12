# Stablefold — VPS + Domain Provision (~25 минут)

## Что мы получим
- **VPS:** Hetzner CX22 (Falkenstein, DE) — €4.59/мес ≈ $5/мес
- **Домен:** stablefold.org на Porkbun — $11/год
- **Всего:** ~$71/год (≈ ₽6 700/год при курсе 95)
- **URL:** `https://stablefold.org` с автоматическим SSL (Let's Encrypt)

---

## ЧАСТЬ 1 — Hetzner VPS (~10 мин)

### 1.1 Регистрация
1. Открыть https://accounts.hetzner.com/signUp
2. Email (НЕ российский), пароль, подтверждение email
3. **Важно:** платёжный метод — Stripe принимает карты не-РФ. Если только РФ-карта — попробовать через Wise / Revolut / зарубежный счёт.

### 1.2 Создание сервера
1. Войти в https://console.hetzner.cloud/
2. **+ New Project** → имя `stablefold` → Create
3. **+ New Server**
4. Параметры:
   - **Location:** `Falkenstein` (DE) или `Helsinki` (FI) — без разницы для нашего трафика
   - **Image:** `Ubuntu 24.04`
   - **Type:** `Standard` → `CX22` (2 vCPU shared, 4 GB RAM, 40 GB SSD, €4.59/мес) — этого с запасом
   - **Networking:** оставить дефолт (Public IPv4 + IPv6)
   - **SSH keys:** **+ Add SSH Key** → имя `mac-fedorovsky` → вставить **публичный ключ** (см. ниже) → Add SSH key
   - **Name:** `stablefold-prod`
   - Остальное дефолт
5. **Create & Buy now** (€4.59 спишется при первом счёте, обычно через 30 дней)
6. Через ~30 секунд VPS готов. Скопировать **IPv4 адрес** из дашборда.

### Публичный SSH ключ (вставить в Hetzner на шаге 1.2):
```
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIF0rEmFdxvyDKHEvj/IPL4weR0Q4Jd0yBlbjS5etBru3 stablefold-deploy@MacBook-Pro-Fedorovsky
```

---

## ЧАСТЬ 2 — Домен на Porkbun (~5 мин)

1. Открыть https://porkbun.com/account/signup → регистрация (email + пароль, нерос. email)
2. Подтвердить email → войти
3. На главной: поиск `stablefold.org` → должен быть свободен ($11/год)
4. **Add to Cart → Checkout**
5. **Privacy:** WHOIS Privacy включён бесплатно — оставить
6. **Auto-renew:** оставить ВКЛ (потом не забудешь)
7. Оплатить (Stripe / Wise / зарубежная карта)
8. Готово — домен в `https://porkbun.com/account/domain_management`

**DNS пока НЕ настраивай — я сделаю после того, как ты дашь VPS IP.**

---

## ЧАСТЬ 3 — Передаёшь мне (1 минута)

Когда оба готовы — напиши в чат:

```
VPS IP: <тут IPv4>
Домен куплен: yes
```

Я дальше сделаю всё сам:
- SSH-зайду на VPS
- Установлю nginx + certbot
- Подниму Let's Encrypt SSL
- Залью лендинг
- Настрою DNS у Porkbun (через их API — нужен API key, см. ниже)
- Проверю https://stablefold.org

---

## ЧАСТЬ 4 — Опционально, Porkbun API key для авто-DNS

Если хочешь чтобы я сам прописал DNS у Porkbun (а не вручную):

1. Залогинься Porkbun → https://porkbun.com/account/api
2. Включи **API Access** для домена `stablefold.org` (галочка справа)
3. Сгенерируй ключи: **Create API Key**
4. Скопируй **API Key** + **Secret Key**
5. Передай их вместе с IP

Если не хочешь дать ключи — я дам тебе 2 строки A-записей, ты их вручную вставишь в Porkbun DNS Records (займёт 1 минуту).

---

## Что произойдёт ПОСЛЕ моих 10 минут провизии

1. `https://stablefold.org` — открывается с зелёным замком (HTTPS)
2. `https://www.stablefold.org` — редирект на `https://stablefold.org` (canonical no-www)
3. **GitHub Pages** (`fedorovskyfinance.github.io/stablefold-landing`) остаётся как зеркало / fallback
4. **Workflow редактуры:**
   - Локально правишь `landing/index.html`
   - `git add -A && git commit -m "..." && git push`
   - GitHub Pages обновляется автоматически
   - Чтобы обновить **продакшн VPS** — `bash deploy/deploy.sh stablefold.org` (один rsync, ~5 сек)

---

## Стоимость по месяцам

| | Месяц | Год |
|---|---|---|
| Hetzner CX22 | $5 | $60 |
| Porkbun .com | — | $11 |
| **Итого** | $5 / мес | **$71 / год** |

Можно отменить VPS в любой момент в Hetzner console — биллинг по часам.

---

## Если что-то пошло не так

- VPS не пингуется → проверить firewall на стороне Hetzner (обычно SSH 22 + HTTPS 443 открыты)
- DNS не разрешается через 30 минут → проверить A-записи на Porkbun
- HTTPS падает → ошибка certbot, я разберусь по логам `/var/log/letsencrypt/letsencrypt.log`
