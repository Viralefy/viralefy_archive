# Viralefy — Context (snapshot 2026-06-01)

Este arquivo é o dossiê operacional pra qualquer sessão futura reconstruir o estado da plataforma sem perda. Combina com `COMPLIANCE.md` (auditoria viva vs `diretrizes.md`) e `diretrizes.md` (normativo).

## TL;DR

Marketplace global de seguidores / curtidas / comentários / compartilhamentos / views para Instagram e TikTok, mais 4 verticais novos (Account Recovery, Facebook BMs, perfis envelhecidos, e-mail packs).

- **Storefront**: https://www.viralefy.com (canônico em www; apex redireciona 301 + preserva path).
- **Admin**: https://admin.viralefy.com — login `admin@viralefy.local` / `SimTest!Admin2026`.
- **API**: https://api.viralefy.com — Go, chi, OTel, métricas Prometheus.
- **Observability**: https://obs.viralefy.com — Grafana 12 com dashboards de API.
- Stack rodando em **HML** (Hetzner CX31, Ubuntu 24.04) até ~2026-06-14. Após esse prazo decide-se ir pra PRD escalada.

15 categorias × 130 países × ~97 planos × 47 idiomas. Sitemap ~91k URLs indexadas via Bing IndexNow.

---

## 1. Acesso e infraestrutura

### Servidor (HML)
- **IP**: `62.238.41.231`
- **Domínio**: `viralefy.com` (DNS A record apex + www em Cloudflare).
- **Hetzner CX31**: 4 vCPU, 8 GB RAM, 80 GB SSD.
- **SSH**: chave em `/media/sonne/Archives/projects/viralefy/credentials`; instalada em `~/.ssh/viralefy_hml` (perms 600).
- Acesso: `ssh -i ~/.ssh/viralefy_hml root@62.238.41.231`.

### Domínios públicos servidos por Caddy
- `viralefy.com` → 301 redir https://www.viralefy.com{uri} (canônico flipped 2026-06-01).
- `www.viralefy.com` → 127.0.0.1:3000 (loja Next.js).
- `admin.viralefy.com` → 127.0.0.1:3001 (backoffice Next.js).
- `api.viralefy.com` → 127.0.0.1:8080 (Go API).
- `obs.viralefy.com` → 127.0.0.1:3030 (Grafana).

### Filesystem prod (`/viralefy/` é DESTRUTIVO em `viralefy-update`)
- `/viralefy/api/` — Go binário + .next caches limpos antes de cada update.
- `/viralefy/front/` — Next.js build artifacts.
- `/viralefy/backoffice/` — Next.js build artifacts.
- `/viralefy/ops/` — clone do viralefy_ops, recreado a cada update.

Persistente (NÃO mexe em update):
- `/etc/viralefy/.env` — segredos (perms 0640, owner root:viralefy).
- PostgreSQL data em `/var/lib/postgresql/`.
- `/etc/caddy/`, `/etc/grafana/`, `/etc/loki/`, `/etc/tempo/`, `/etc/prometheus/`, `/etc/alloy/`.

### Variáveis de ambiente importantes (`/etc/viralefy/.env`)
```
PORT=8080
BIND_HOST=127.0.0.1
DATABASE_URL=postgres://viralefy:<pw>@localhost:5432/viralefy?sslmode=disable
JWT_SECRET=<64 chars>
CORS_ORIGINS=https://viralefy.com,https://www.viralefy.com,https://admin.viralefy.com

EMAIL_PROVIDER=resend
RESEND_API_KEY=re_j1Zar5tv_5w2Y5JrErHPLmfz9we7uqfh2
RESEND_FROM=onboarding@resend.dev

INDEXNOW_KEY=adcfcb87889076210f395f754a9ad0c3
INDEXNOW_SECRET=<24 chars>

NEXT_PUBLIC_API_URL=https://api.viralefy.com
NEXT_PUBLIC_SITE_URL=https://www.viralefy.com
NEXT_PUBLIC_TURNSTILE_SITE_KEY=0x4AAAAAADbwrbYvD2Gb-ngm

TURNSTILE_SECRET_KEY=0x4AAAAAADbwrTQJnw7luIYexVo_3uQBYcw

ADMIN_WEBHOOK_URL=         # vazio → no-op; cole Slack/Discord webhook quando quiser

DOMAIN_FRONT=viralefy.com
DOMAIN_BACKOFFICE=admin.viralefy.com
DOMAIN_API=api.viralefy.com
DOMAIN_OBS=obs.viralefy.com
CADDY_EMAIL=schematizecode@gmail.com

GRAFANA_ADMIN_PASSWORD=<32 chars>
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
OTEL_SERVICE_NAME=viralefy-api
```

> **Importante**: o installer regenera o `.env` a cada `viralefy-update`. Todas as vars precisam estar em `30-secrets.sh` (export list + heredoc) pra sobreviver. Turnstile/ADMIN_WEBHOOK foram corrigidos em [`b0a0445`](https://github.com/Viralefy/viralefy_ops/commit/b0a0445).

### Credenciais admin storefront / backoffice
- Admin backoffice: `admin@viralefy.local` / `SimTest!Admin2026`. Único admin seedado em [`seed.go:seedAdmin`](viralefy_api/internal/infrastructure/persistence/postgres/seed.go).
- Grafana: `admin` / `$GRAFANA_ADMIN_PASSWORD`.
- PostgreSQL: usuário `viralefy` com senha gerada por `30-secrets.sh`.

### Rotação de chaves
**Não rotacionar nada até 2026-06-14 sem solicitação explícita.** HML/POC; ambiente descartável. Memory `no-secret-rotation-nag` cobre.

---

## 2. Repositórios GitHub (org `github.com/Viralefy`)

| Repo | Conteúdo | Linguagem |
|---|---|---|
| `viralefy_api` | API REST DDD 4-layer | Go 1.23, chi, pgx |
| `viralefy_front` | Storefront i18n multilíngue | Next.js 15 App Router |
| `viralefy_backoffice` | Admin dashboard | Next.js 15 App Router |
| `viralefy_ops` | Installer + systemd units + Caddyfile | Bash + configs |
| `viralefy_archive` | CONTEXT.md + COMPLIANCE.md + diretrizes.md | Markdown |

Local: `/media/sonne/Archives/projects/viralefy/{repo}/`.

---

## 3. Arquitetura

```
┌──────────────────────────────────────────────────────────────────┐
│                         Caddy 2.11                               │
│  (TLS auto Let's Encrypt + HSTS + security headers)              │
└─────────┬──────────────┬──────────────┬──────────────┬──────────┘
          │              │              │              │
       :3000          :3001           :8080         :3030
          │              │              │              │
       Front          Backoffice       API           Grafana
       (Next)         (Next)           (Go)          (+ Loki, Tempo,
                                                       Prometheus, Alloy)
                                          │
                                          ▼
                                      Postgres 17
                                       (port 5432)
```

### DDD layers (Go API)
```
internal/
├── domain/                  # entidades + value objects + repo interfaces
├── application/             # use cases / services
├── infrastructure/
│   ├── persistence/postgres # pgx repos
│   ├── external/
│   │   ├── email/           # SMTP + Resend
│   │   ├── payment/         # Woovi + Heleket + manual Pix
│   │   ├── turnstile/       # Cloudflare anti-bot
│   │   ├── notify/          # webhook Slack/Discord
│   │   └── metrics/         # scrape OG IG/TikTok pra baseline
│   └── observability/       # logger + metrics + tracer (OTel)
└── interface/http/          # chi router + handlers + middlewares
                             # (Idempotency, RateLimiter, AdminAuth, etc.)
```

### Frontend (Next.js)
- `src/app/` — App Router pages
- `src/components/` — UI components
- `src/i18n/` — `categories.ts`, `countries.ts`, `languages.ts`, `legal.ts`
- `src/lib/` — `api.ts`, `tracking.ts`, `format.ts`, `auth.ts`, `geo-currency.ts`
- `tests/unit/` — node:test (47 arquivos, 276 testes)
- `tests/smoke/`, `tests/pentest/`, `tests/emulated/` — bash + node

---

## 4. Schema PostgreSQL (14 migrations, 26 tabelas)

### Tabelas principais
- `users` — id, email, name, password_hash, **tracking_data jsonb** (first-touch), created_at
- `admins` — id, email, password_hash, name, role_code
- `roles` + `role_permissions` — RBAC
- `currencies` — code, name, symbol, **rate (USD-base)**, decimals, kind, display_enabled, settlement_code, sort_order
- `categories` — code, label, sort_order, active
- `plans` — id, name, description, category, platform, target_type, followers_qty, price_cents, currency, prices(jsonb), active, sort_order
- `plan_prices` — plan_id, currency_code, amount (manual override)
- `payment_gateways` — id, name, provider, active, config
- `profiles` — id, user_id, platform, handle, display_name, verified
- `credit_accounts` + `credit_transactions` — ledger atômico
- `invoices` — recargas de saldo
- `orders` — colunas explodidas (ver §5)
- `tickets` + `ticket_messages` — helpdesk
- `idempotency_keys` — TTL 24h (migration 012)
- `audit_log` — append-only (migration 012)

### orders (após migrations 010, 012, 013, 014)
```
id              text pk
user_id         text → users
plan_id         text → plans
status          text  (pending|paid|failed|cancelled)
amount_cents    int   (USD cents — base canônica)
currency        text  ("USD")
display_currency, display_amount, settlement_currency, settlement_amount
gateway_id, external_ref, payment_url, payment_extra jsonb
profile_id, publication_url
payment_method  ("gateway" | "credits"), credits_used_cents
custom_data     jsonb  (form recovery/BM/perfil — replayed no ticket)
ticket_id       text → tickets  (set após pagamento confirmar em categoria high-touch)
tracking        jsonb  (UTM/fbclid/gclid/ttclid/referrer/landing_url + server IP/UA)
baseline_metrics jsonb, baseline_captured_at, baseline_source  (scrape OG pré-entrega)
delivery_metrics jsonb, delivery_captured_at, delivery_source  (scrape OG pós-entrega)
created_at, updated_at
```

### Catálogo de planos (97 ativos em 15 categorias)
| Categoria | Plans | Faixa USD |
|---|---|---|
| `seguidores_instagram` | 18 | $2.50 – $4,000 |
| `seguidores_tiktok` | 10 | $5 – $200 |
| `curtidas_instagram` | 11 | $1 – $280 |
| `curtidas_tiktok` | 9 | $2 – $160 |
| `comentarios_instagram` | 6 | $5 – $120 |
| `comentarios_tiktok` | 5 | $10 – $130 |
| `compartilhamentos_instagram` | 12 (shares + saves) | $3 – $130 |
| `compartilhamentos_tiktok` | 6 | $8 – $260 |
| `visualizacoes_instagram` | 15 (Reels + Story) | $1.50 – $800 |
| `visualizacoes_tiktok` | 7 | $20 – $1,400 |
| `servicos` | 7 (consultoria) | $39 – $499 |
| `recuperacao_perfil` | 1 (`Account recovery`) | **$10,000** |
| `bms_facebook` | 4 (Trial → Premium $5k daily cap) | $40 – $450 |
| `perfis_redes` | 7 (IG + TT aged) | $30 – $300 |
| `emails_validados` | 6 | $5 – $280 |

Categorias `recuperacao_perfil`, `bms_facebook`, `perfis_redes` abrem ticket automático após payment confirmar (handoff manual). Constante `CategoriesOpeningTicket` em [`payment_receiver.go`](viralefy_api/internal/application/payment_receiver.go) espelhada em `TICKET_OPENING_CATEGORIES` em [`categories.ts`](viralefy_front/src/i18n/categories.ts).

### Moedas (USD-base canônica)
```
USDT  rate=1.0      symbol=$  sort=1  display=true
USD   rate=1.0      symbol=$  sort=2  display=true
EUR   rate=0.92     symbol=€  sort=3  display=true
BRL   rate=5.41     symbol=R$ sort=4  display=true
BTC   rate=0.0000103 symbol=₿  sort=5  display=true
```
USDT é o display default. Migration 011 fez o flip BRL→USD-base. Front fallback chain: `currency || USDT || USD || cents/100`. Backoffice usa `$X.XX` em todo formatter.

---

## 5. RBAC + ABAC

- `roles`: superadmin, manager, support, viewer
- `role_permissions(role_code, permission)`: plans:read/write, gateways:read/write, currencies:read/write, orders:read, tickets:read/write, admins:manage
- `Principal` na sessão admin tem permissions[]; middleware `RequirePermission(perm)` checa antes do handler
- ABAC implícito: `MeListTickets` retorna só os do user_id do token; `Profiles.GetForUser` checa ownership

### Débito conhecido §14 (diretrizes)
JWT HS256 com chave compartilhada. PRD exige RS256/EdDSA com kid rotation. ADR-0003 pendente. **Não migrar até 2026-06-14.**

---

## 6. Frontend (`viralefy_front`)

### Roteamento
- `/` — home global (en, hreflang `x-default` + `en`)
- `/<country>` — landing por país (130 países; pt/es/fr/de/it/nl/ru + 16 outros)
- `/<country>/<category-slug>` — landing por categoria do país (15 categorias × 130 países × 9 idiomas = ~17k URLs)
- `/<country>/<category-slug>/<qty>-<category-slug>` — SEO próprio por plano (~80k URLs)
- `/marketplace` — hub global em inglês (3 cards)
- `/marketplace/{facebook-bms,aged-profiles,validated-emails}` — LPs globais sem país
- `/legal/{privacy,terms,cookies,refund,about,contact}?lang=<code>` — legais multilíngues
- `/login`, `/register`, `/account`, `/account/credits`, `/account/profiles`, `/tickets`, `/tickets/[id]`, `/tickets/new`
- `/og/[...slug]` — Image Response (gradiente cyan, VIRALEFY, country EN via Intl.DisplayNames)

### Recovery LP (custom)
- `/<country>/recuperacao-de-perfil` (e variantes locais: `account-recovery`, `recuperacion-de-cuenta`, `recuperation-de-compte`, `konto-wiederherstellung`, `recupero-account`, `accountherstel`, `vosstanovlenie-akkaunta`).
- Em vez de `CategoryCardGrid`, renderiza `RecoveryForm` com handle, platform, ban_date, estimated_reason, last_publication_url, description, contact email/name, Turnstile.
- POST `/v1/recovery-request` cria order pending no plano de $10k com snapshot do form em `custom_data`. Após pagamento confirmar, abre ticket automático.

### i18n (47 idiomas em PACKS)
- `categories.ts` — `CategoryCode` union (15), `CATEGORY_LABEL`, `CATEGORY_SLUG`, `categoryUnit()` (followers/likes/comments/shares/views), `COPY` map
- `countries.ts` — 130 países com h1, title, description, htmlLang, region, flag, currencyHint
- `languages.ts` — `PACKS` (47 LangCode), `tr()` com fallback en
- `legal.ts` — 6 docs jurídicos em pt/en/es/fr/de/it/nl/ru

### Componentes principais
- `Header.tsx` — sticky, dark/light theme toggle, Currency select, search, Markets MegaMenu, **Support badge** (count de tickets open+pending, polling no mount + troca de rota), responsivo (drawer mobile)
- `CheckoutModal.tsx` — fluxo de checkout multi-passo (profile/publication URL, payment method, CustomDataFields condicional), Idempotency-Key UUID por click
- `RecoveryForm.tsx` — formulário dedicado da LP de recovery
- `CustomDataFields.tsx` — campos extras por categoria (BMs: use_case/pixel_id/preferred_nick/ad_accounts; perfis: niche/audience_country/min_age_months; emails: niche/use_case/country)
- `Turnstile.tsx` — widget Cloudflare (managed mode, appearance interaction-only), gated por `NEXT_PUBLIC_TURNSTILE_SITE_KEY`
- `CategoryCardGrid.tsx` — cards com `hideDetailLink?` (true em marketplace global)
- `QuantitySlider.tsx`, `CategoryGroupedGrid.tsx`, `Footer.tsx`, `LiveCounter.tsx`, `TrustSignals.tsx`, `SearchBar.tsx`, `MegaMenuMarkets.tsx`, `WhatsAppButton.tsx`, `ThemeToggle.tsx`

### Design system
Cyan neon brand color `#00fed6` (logo). Background `#04080c`. Light theme via `[data-theme="light"]` override. Anti-flash inline script no `<html>` antes do React. Twemoji para flags (CDN `cdn.jsdelivr.net/gh/jdecked/twemoji@latest`).

### SEO
- `<title>` template `%s | Viralefy` no root layout; pages com brand suffixo já presente usam `{ absolute: ... }` pra evitar duplicação
- `noindex` em `/login`, `/register`, `/account/*`, `/tickets/*` (cada um com `layout.tsx` próprio)
- JSON-LD: Organization, WebSite, WebPage (com `inLanguage`), BreadcrumbList, Service (sem `inLanguage` — só CreativeWork aceita), AggregateOffer (priceCurrency USD), FAQPage, Product
- Hreflang em todas as páginas geo-segmentadas (camelCase é o que Next emite — Google aceita)
- Bing IndexNow: `pages.viralefy.com/<INDEXNOW_KEY>.txt` + API ping

### Tracking (lib/tracking.ts + Providers)
`initTracking()` no useEffect dos Providers captura:
- UTM (utm_source/medium/campaign/term/content) — first-touch wins até update por novo param
- Click IDs: fbclid (deriva _fbc), gclid, ttclid, msclkid, irclickid, li_fat_id
- Cookies Meta: _fbp e _fbc (se setados pelo pixel; senão derivamos)
- client_id (UUID em localStorage cross-session)
- referrer, landing_url, landing_at
- Browser: language, timezone, screen, viewport, user_agent
- sessionStorage em `viralefy_tracking`

`getTracking()` anexa em payloads:
- CheckoutModal: enviado em `tracking` request body
- RecoveryForm: enviado em `tracking`
- Register: enviado em `tracking`

Backend `enrichTracking()` adiciona server-side (não-forjeável):
- server_ip (via X-Forwarded-For do Caddy)
- server_user_agent, server_accept_language
- server_submitted_at

Tudo grava em `orders.tracking` e `users.tracking_data` (first-touch). Indexes em fbclid, gclid, client_id e utm_campaign.

### Tests (276 passing, node:test)
- `categories.test.mjs` — 15 codes
- `plan-slugs.test.mjs` — slug round-trip
- `search-corpus.test.mjs`, `search-edge.test.mjs` — busca de marketplace
- `sitemap-split.test.mjs` — split por idioma
- `jsonld.test.mjs`, `jsonld-deep.test.mjs`, `jsonld.schema.test.mjs`
- `format.test.mjs` — USDT/USD/EUR/BRL formatting + null fallback USD
- `theme.test.mjs` — light/dark switcher
- `geo-currency.test.mjs` — USDT como default global
- `legal.test.mjs`

### Segurança CSP (next.config.ts)
```
script-src: self + unsafe-inline + unsafe-eval + googletagmanager + jsdelivr + challenges.cloudflare.com
frame-src: googletagmanager + challenges.cloudflare.com
connect-src: self + api.viralefy.com + analytics + googletagmanager + challenges.cloudflare.com
frame-ancestors: none
```
Turnstile precisa de challenges.cloudflare.com nos 3.

---

## 7. Backoffice (`viralefy_backoffice`)

### Páginas (App Router)
- `/login` — Turnstile (appearance always pra feedback visual)
- `/dashboard` — métricas: tiles (revenue/orders/paid/conv rate), status breakdown, top 5 categorias por receita, mini bar chart SVG 30 dias. Fonte: `GET /v1/admin/metrics/summary`.
- `/orders` — lista com filtros (status + busca) + coluna **Cliente** (nome clicável → `/users/[id]` + email muted). Rows clicáveis → `/orders/[id]`.
- `/orders/[id]` — detalhe completo. `OrderDetail` = `{order, profile, user}`. Cards: Pedido, **Cliente** (Link `/users/[id]`), **Alvo** (perfil clicável pra Instagram/TikTok público + Link "Ver outros perfis"; ou URL pra publication), Valores, Status (editor: `admins:manage` troca status direto OU `Marcar como pago` dispara hook completo). **BaselineDeliveryCard** com 2 colunas (JSON snapshot + source badge + captured_at) + botão "Capturar agora". Custom data + Tracking em JSON viewer.
- `/invoices` — lista clicável (rows + botão Abrir + botão Pagar quando pending+admins:manage)
- `/invoices/[id]` — detalhe da recarga. `InvoiceDetail` = `{invoice, user}`. Cards: Cliente (Link), Valor, Status & gateway, Datas. Botão "Marcar como paga".
- `/plans` — lista com **Editar** (link), Desativar/Ativar (toggle), Excluir. Form de novo plano (inline) com platform + target_type.
- `/plans/[id]/edit` — editor COMPLETO: nome, descrição, categoria, plataforma (IG/TT/FB), target_type (profile/publication), quantidade, sort_order, preços por moeda, ativo.
- `/users`, `/users/[id]` — listagem + detalhe com adjustCredits
- `/tickets`, `/tickets/[id]` — helpdesk admin (lista, filtros status, reply, patch)
- `/currencies` — editor de rate/symbol/display_enabled/settlement_code
- `/gateways` — CRUD gateways

### Endpoints admin do API
- `/v1/admin/me`, `/v1/admin/roles`
- `/v1/admin/plans` (GET, POST), `/v1/admin/plans/{id}` (PUT, DELETE) — todos com audit log
- `/v1/admin/gateways` (CRUD)
- `/v1/admin/currencies` (GET, PUT)
- `/v1/admin/orders` (GET list com user JOIN), `/v1/admin/orders/{id}` (GET com hidrate, PATCH), `/v1/admin/orders/{id}/mark-paid` (POST + hooks completos), `/v1/admin/orders/{id}/capture-metrics` (POST baseline|delivery)
- `/v1/admin/metrics/summary` (GET)
- `/v1/admin/tickets`, `/v1/admin/tickets/{id}` (GET, POST mensagens, PATCH status/priority)
- `/v1/admin/invoices` (GET list), `/v1/admin/invoices/{id}` (GET com user hidrato), `/v1/admin/invoices/{id}/mark-paid` (POST)
- `/v1/admin/users` (GET list), `/v1/admin/users/{id}` (GET), `/v1/admin/users/{id}/credits/adjust` (POST)

Permissões: `PermOrdersRead` pra ler, `PermAdminsManage` pra ações críticas (mark-paid, patch status, capture-metrics).

### Auth backoffice
- JWT TTL 24h, secret em `.env`
- `setSession(token, role, permissions)` em localStorage
- `can(perm)` checa lista local
- `AdminShell` redireciona pra `/login` se sem token

---

## 8. Backend (`viralefy_api`)

### Stack
- Go 1.23 + chi v5
- pgx v5 (sem ORM)
- bcrypt cost 12 (passwords)
- JWT HS256 (dev/HML — RS256 pendente)
- OpenTelemetry SDK (OTLP HTTP exporter → Tempo)
- slog JSON (PII masking helpers em obs/logger.go)
- Prometheus client_golang (`/metrics` endpoint)

### Middlewares (chi-style)
- `middleware.RequestID`, `middleware.RealIP`
- `otelhttp.NewHandler` — span por request, propaga W3C TraceContext
- `ObservabilityMiddleware` — log estruturado por request
- `middleware.Recoverer`
- `cors.Handler` — origens em CORS_ORIGINS
- `IdempotencyMiddleware(db)` — header `Idempotency-Key`, hash SHA256 do body, cache 24h só pra 2xx, retorna 409 se key+body diferente
- `RateLimiter(30, time.Minute).Middleware()` — token bucket per-IP in-memory (chi-only HML; trocar pra Redis em PRD)
- `AdminAuth(auth)`, `UserAuth(auth)`, `OptionalUserAuth(auth)`

Aplicados:
- `/v1/checkout` e `/v1/recovery-request`: `mutationLimiter + idem + optionalUserAuth`
- `/v1/auth/*`: Turnstile validation (no handler)

### Services principais (`internal/application/`)
- `PlanService` — Create/Update/Delete com audit, GetByID, ListByCategory, ListPublic, ListAdmin
- `CheckoutService` — Checkout (gateway/credits paths), Email enviado, fireBaselineCapture async pós Order.Create
- `CurrencyService` — QuoteForPlan (USD-base), ListDisplayable
- `CreditService` — Spend/Recharge/AdminAdjustment (ledger atômico)
- `InvoiceService` — Create (cria charge no gateway), AdminMarkPaid (credita saldo via CreditService.Recharge), AdminGet, AdminList
- `TicketService` — Open (categorias high-touch), ListForUser, ReplyAsUser/Admin, AdminUpdateStatus/Priority, **CountOpenForUser** (badge no header)
- `AuthService` (admin), `UserAuthService` (loja) — Login/Register; UserAuth grava tracking em `users.tracking_data`
- `ProfileService` — Add com validador, **GetByID** (pra hydrate em admin order detail)
- `PaymentReceiver` — `ConfirmByExternalRef` (webhook fluxo), `MarkOrderPaid` (admin fluxo), `onOrderPaid` central que dispara: `maybeOpenTicket` (categorias high-touch), `sendConfirmationEmail` (templates diferentes para auto vs handoff manual), `notifyAdmin` (webhook só pra high-touch com link pro ticket)
- `AuditService` — Log (com IP, UA, path, method em metadata)
- `MetricCaptureService` — `CaptureBaseline`/`CaptureDelivery` (best-effort scrape OG via `infrastructure/external/metrics`)

### External integrations (`infrastructure/external/`)
- `email/` — Resend API (primário) + SMTP fallback. `LogSender` quando key vazia.
- `payment/` — `WooviProvider` (Pix BRL), `HeleketProvider` (USDT/BTC), `ManualPIXProvider`
- `turnstile/` — POST `https://challenges.cloudflare.com/turnstile/v0/siteverify` com 5s timeout. `Enabled()` retorna `secretKey != ""`.
- `notify/` — `WebhookClient` Slack-compatible. POST JSON `{text}`. `Enabled()` retorna `URL != ""`.
- `metrics/` — `Service.CaptureProfile` e `CapturePublication` via User-Agent realista + parse OG description (regex K/M/B + thousands separators).

### Webhooks
- POST `/v1/webhooks/woovi` — Woovi callback
- POST `/v1/webhooks/heleket` — Heleket callback
- Sem auth — assinatura validada no handler

---

## 9. Observabilidade

### Stack instalado (via `viralefy_ops/installer/80-observability.sh`)
- **Grafana 12** em `:3030` (atrás de https://obs.viralefy.com)
- **Loki 3** em `:3100` — logs JSON
- **Tempo 2** em `:3200` — traces W3C
- **Prometheus** em `:9090` — métricas
- **Alloy** em `:12345` — collector (scrapes node-exporter + ships logs/metrics)
- **node-exporter** em `:9100`

Todos bind 127.0.0.1; só Grafana exposto via Caddy.

### API instrumentação
- `observability.InitLogger(LoggerConfig{...})` — slog JSON, masking
- `observability.InitMetrics()` — http_requests_total, http_request_duration_seconds, db_query_duration_seconds, gateway_callbacks_total
- `observability.InitTracer(TracingConfig{...})` — OTLP HTTP exporter
- `ObservabilityMiddleware` — extrai trace_id do span, request_id do chi
- `observability.FromContext(ctx)` — logger contextualizado

Dashboards: `viralefy-api` em Grafana com p50/p90/p99 latency, req/s, error rate, top paths, gateway callbacks.

---

## 10. Pagamentos

### Gateways configurados (seed em `seedGateway`)
- **Woovi (PIX)** — provider `woovi`, settlement BRL, inactive by default
- **Heleket (cripto)** — provider `heleket`, settlement USDT/BTC, inactive by default
- **PIX Manual** — provider `manual_pix`, settlement BRL, active (default HML)

### Pricing (USD canônico)
- `plans.price_cents` é USD cents
- `plan_prices(plan_id, currency_code, amount)` armazena overrides por moeda
- `CurrencyService.QuoteForPlan(ctx, prices, usdCents, displayCode)` resolve display + settlement
- Fallback: se moeda escolhida não tem `amount` em `plan_prices`, deriva via `currencies.rate` (USD-base)
- `seedPlanPrices` usa rates inline (USDT=1, USD=1, EUR=0.92, BRL=5.41, BTC=0.0000103)

### Fluxo de pagamento
1. `CreateCheckout` cria Order pending; chama `gw.CreateCharge` → external_ref + payment_url
2. Provider redireciona usuário; após pagamento, dispara webhook
3. `PaymentReceiver.ConfirmByExternalRef` valida + atualiza status → `onOrderPaid`
4. `onOrderPaid` fanout:
   - `maybeOpenTicket` (recuperacao_perfil, bms_facebook, perfis_redes) — Open com subject `[<cat>] Order #<id> — <name>` + body com dump do CustomData
   - `sendConfirmationEmail` — templates auto vs handoff
   - `notifyAdmin` — webhook Slack/Discord só pra high-touch

### Idempotência
- POST `/v1/checkout` e `/v1/recovery-request` aceitam header `Idempotency-Key`
- Frontend gera UUID por click (`crypto.randomUUID()` em [api.ts](viralefy_front/src/lib/api.ts))
- Middleware cacheia resposta 2xx por 24h. F5/duplo-click devolve mesma resposta.

---

## 11. Testes

| Suite | Conteúdo | Status |
|---|---|---|
| `tests/unit/*.test.mjs` | node:test + ts-loader hook | **276 passing** |
| `tests/smoke/run.sh` | curl smoke (sitemap, /, /br, /us, /api) | OK |
| `tests/pentest/probes.sh` | headers, CSP, XFO, SQL injection, XSS | OK |
| `tests/emulated/browse-flow.mjs` | playwright-like via node:fetch + jsdom | OK |
| `tests/emulated/checkout-flow.mjs` | fluxo de compra completo | OK |
| `tests/emulated/i18n-flow.mjs` | 47 idiomas | OK |
| `tests/emulated/api-contracts.mjs` | shape validation | OK |
| `tests/emulated/accessibility.mjs` | axe-core via node | OK |

Backend tests **0%** (débito Tier 1 §22 diretrizes).

---

## 12. Comandos operacionais

### Deploy completo (destrutivo — preserva /etc/viralefy/.env e DB)
```bash
ssh -i ~/.ssh/viralefy_hml root@62.238.41.231 'viralefy-update'
```

### Verificar status
```bash
ssh -i ~/.ssh/viralefy_hml root@62.238.41.231 'viralefy-status'
ssh ... 'systemctl status viralefy-{api,front,backoffice}'
```

### Logs ao vivo
```bash
ssh ... 'journalctl -u viralefy-api -f'
ssh ... 'journalctl -u caddy -f'
```

### PostgreSQL query
```bash
ssh ... "sudo -u postgres psql viralefy -c 'SELECT ...'"
```

### IndexNow ping
```bash
cd viralefy_front && npm run indexnow
```

### Testes unitários front
```bash
cd viralefy_front && npm test
```

### Build Go API local
```bash
cd viralefy_api && go build ./...
```

### Type-check Next
```bash
cd viralefy_front && ./node_modules/.bin/tsc --noEmit
cd viralefy_backoffice && ./node_modules/.bin/tsc --noEmit
```

---

## 13. Checklist atual

### ✅ Done desde início + esta sessão

- DDD 4-layer API com JWT auth + RBAC
- Storefront i18n 47 idiomas, 130 países
- 15 categorias (split de engagement + marketplace + recovery)
- USD-base canônica (migration 011)
- 97 plans ativos seedados
- Pagamentos: Woovi + Heleket + PIX manual
- Bing IndexNow integration
- Observabilidade stack completo (Grafana/Loki/Tempo/Prometheus/Alloy)
- 276 unit tests passando
- SEO: title.template + noindex auth pages + JSON-LD compliant + hreflang
- Twemoji para flags universais
- Light/dark theme com anti-flash
- Marketplace global em `/marketplace/{slug}` (BMs, perfis, emails)
- Recovery LP per country com form custom + Turnstile
- Account Recovery $10,000 USD com 30-day refund guarantee
- Tracking jsonb em orders + users (UTM/fbclid/gclid/etc.)
- Turnstile no /login + /register + admin /login
- Idempotency middleware + rate-limit middleware
- Audit log de plan mutations
- Post-payment hooks: email + ticket + admin webhook
- Support badge no header (count tickets open+pending)
- `/dashboard` rework com métricas (tiles + chart 30d)
- `/orders` separada + `/orders/[id]` com profile/user hidratados (clicáveis) + baseline/delivery metric viewer + capture button
- `/invoices` lista clicável + `/invoices/[id]` detalhe + user hidratado
- `/plans/[id]/edit` editor completo (nome/desc/categoria/plataforma/target_type/qty/order/preços/ativo)
- WWW canonical migration (Caddy redir apex → www)
- CSP atualizada pra Turnstile (script-src + frame-src + connect-src)
- Installer fix: Turnstile + ADMIN_WEBHOOK_URL persistem cross-update

### 🟡 Tier 1 — PRD blockers (não bloqueiam HML)
- JWT RS256 migration (§14)
- Cron de cleanup `idempotency_keys` expiradas
- CI/CD GitHub Actions
- Postgres backup automation (atualmente sem)
- API Go tests (0% cobertura)
- DNS A record pra `obs.viralefy.com` (já tem — verificar Cloudflare)
- Cron de captura `delivery_metrics` 24h após order virar paid

### 🟠 Tier 2 — resiliência + features
- Outbox Pattern pra email/webhook (atualmente fire-and-forget)
- Stripe gateway
- Reviews schema (Product.aggregateRating)
- Runbook + on-call procedures
- ADRs 0001-0004 (USD-base, Turnstile, Idempotency, Tracking)
- LGPD endpoints (export, delete user)
- Endpoint admin pra ler audit log (`GET /v1/admin/audit/{type}/{id}`)
- Meta Conversions API (CAPI) emitter (dados já estão coletados em `orders.tracking`)
- Google Ads Enhanced Conversions
- TikTok Events API
- Cupons / desconto
- Refresh tokens
- Helper de PIX padrão BR
- Webhook Slack/Discord do admin (URL ainda vazia)

### 🟢 Tier 3 — escala
- Redis cache (rate-limiter, sessions)
- K8s migration
- Schema separation API↔backoffice
- Test kit unified em viralefy_ops/
- Audit trail immutable (hash chain)
- Migrations reversible (todas têm .down.sql mas auto-rollback não testado)
- SLOs (sloth) + error budgets
- DPIA (LGPD)
- float64 → decimal em preços
- Mobile app (React Native?)
- Affiliate program
- Account creator service (anti-throttling de criação de IG)
- Blog conteúdo SEO

### 🔴 Pendências do user
- Cloudflare Proxy pra `viralefy.com` (atualmente DNS only?) — aumenta cache + WAF
- DNS A record pra `obs.viralefy.com` (verificar)
- Setar `NEXT_PUBLIC_WHATSAPP_NUMBER` em `.env` se quiser botão flutuante (front layout.tsx render gated)
- Setar `ADMIN_WEBHOOK_URL` em `.env` quando criar Slack/Discord webhook
- `/v1/stats/orders-today` endpoint backend (front já consulta com fallback sintético)

---

## 14. Decisões + quirks

### Arquitetura
- **DDD 4-layer**: domain (entidades + repo interfaces) → application (use cases) → infrastructure (repos + external) → interface (HTTP/router). Sem ORM (pgx puro).
- **USD-base canônica** em moedas e pricing. BRL é subsidiária. Migration 011 + seed inline rates.
- **Categorias 15 split**: engagement separado em 3 primitivas (likes/comments/shares incluindo saves), × 2 plataformas. Mais seguidores ×2, views ×2, servicos, recuperacao_perfil, bms_facebook, perfis_redes, emails_validados.
- **Idempotency cache** SHA256 do body. F5 ou duplo-click reutiliza key gerada por React state (não regenera key); replay 24h.
- **Tracking first-touch + enrichment** server-side. Cliente envia UTM/cookies/contexto; backend adiciona IP+UA (não-forjeáveis). Persist em orders.tracking E users.tracking_data (se conta criada no checkout anônimo).

### Operacionais
- **Installer destrutivo**: `/viralefy/*` é apagado a cada `viralefy-update`. Persistência: `/etc/viralefy/.env`, `/var/lib/postgresql/`, `/etc/{caddy,grafana,loki,tempo,prometheus,alloy}/`. **TODA env var precisa estar no heredoc do `30-secrets.sh` pra sobreviver — erro comum é appendar manualmente e esperar persistir.**
- **www → apex 301**: Caddy serve www como canônico, apex redireciona 301 preservando path/query. Bookmarks antigos continuam vivos.
- **OTel HTTP middleware** vem ANTES do ObservabilityMiddleware (que lê o span do contexto).
- **Goroutine pós Order.Create** com `context.Background` pra sobreviver ao cancel do request (`fireBaselineCapture`).
- **Scraping IG/TikTok** funciona pra perfis públicos com poucos requests/dia. Em escala vai cair em `manual_pending`. Substituir por 3rd-party em PRD.

### Gotchas
- **Edit tool às vezes falha silenciosamente** quando arquivo não foi lido antes na sessão. Sempre verificar diff (`git diff`) antes de commit. Aprendido em commit [`ce1691d`](https://github.com/Viralefy/viralefy_backoffice/commit/ce1691d) (re-fix de invoices).
- **CSP precisa de `challenges.cloudflare.com`** em script-src + frame-src + connect-src pra Turnstile funcionar. Sem isso o widget falha silenciosamente.
- **Service.inLanguage** não é válido em Schema.org (só CreativeWork). Removido em [`6a591dc`](https://github.com/Viralefy/viralefy_api/commit/6a591dc).
- **next/og crash em Árabe**: satori não suporta GSUB format 3 (ligaduras longas). Workaround: OG image usa `Intl.DisplayNames("en")` pra country name. Localização fica no `<title>` e `og:title` apenas.
- **Twitter metadata shallow-merge**: page-level `twitter: {...}` substitui inteiro o layout's. `site` + `creator` precisam ser repetidos em cada page que customiza twitter.
- **IDE diagnostics são frequentemente stale** quando se faz duas Edits consecutivas. `go build ./...` é a fonte de verdade.

### Memória persistente (recall em sessões futuras)
- `run-viralefy-stack-local.md` — Go fora do PATH, Postgres :15432
- `viralefy-stack-initial-build-fixes.md` — issues iniciais do MVP
- `viralefy-features-v2.md` — categorias, auth, autocadastro
- `viralefy-ops-and-github.md` — installer + 5 repos
- `no-secret-rotation-nag.md` — **NÃO** mencionar rotação até 2026-06-14

---

## 15. Commits-chave (recentes)

### viralefy_api
- `64b0e9e` — feat(admin): AdminGetInvoice + OrderView JOIN users
- `f30896f` — feat: hydrate profile+user; baseline/delivery metric capture (Migration 014)
- `5f724fb` — feat: Turnstile on auth, tracking jsonb, admin orders detail/patch + metrics
- `cda5681` — feat: idempotency, rate-limit, audit log, post-payment hooks
- `8836707` — feat(currency): USDT default
- `b9e2f7f` — feat(catalog): split engagement category

### viralefy_front
- `3c0a94e` — fix(csp): allow challenges.cloudflare.com (Turnstile)
- `052d44a` — feat: Turnstile on /login + /register, tracking lib
- `ade2186` — feat: support badge, custom forms, refund 30-day, /marketplace global
- `89c34c9` — feat: USD as primary, recovery LP, marketplace categories
- `b8e7d2b` — fix(i18n,currency): kill BRL/PT leakage on non-BR pages

### viralefy_backoffice
- `ce1691d` — fix(invoices): aplicar de fato a lista clicável (commit anterior só pegou o import)
- `10179df` — feat(admin): /invoices/[id], orders mostra cliente, /plans 'Editar' completo
- `a675cb9` — feat(orders): detail page hydrates profile/user; baseline/delivery
- `2429f0c` — feat: Turnstile on admin login; /dashboard métricas; /orders dedicada

### viralefy_ops
- `b0a0445` — fix(installer): persist Turnstile + ADMIN_WEBHOOK_URL
- `ca6b138` — ops: canonical apex → www
- `f610389` — fix(grafana): subcommand + homepath flag

### viralefy_archive
- `ce7af3f` — docs: CONTEXT.md atualizado (anterior)

---

## 16. Próximas sugestões priorizadas

Em ordem de impacto × esforço (1=quick win, 10=longo):

1. **(2)** Cron pra `CaptureDelivery` 24h após order virar paid. Usa o que já existe (`MetricCaptureService`). Confirma entrega independente do gateway.
2. **(2)** Endpoint admin pra ler audit log: `GET /v1/admin/audit/{type}/{id}`. Backend pronto, falta handler + UI viewer no backoffice.
3. **(3)** Backup PostgreSQL automatizado (pg_dump diário → S3/Backblaze).
4. **(4)** Meta Conversions API emitter — disparar PageView/AddToCart/Purchase com fbc/fbp/IP/UA já coletados em `orders.tracking`. Greatly improve ad spend ROAS.
5. **(4)** Cron cleanup `idempotency_keys` expiradas (else tabela cresce).
6. **(5)** Stripe gateway (cobertura cards globais).
7. **(5)** CI/CD GitHub Actions: lint + test + build verification (não deploy).
8. **(6)** JWT RS256 com kid rotation (§14 diretrizes).
9. **(7)** Outbox Pattern pra email/webhook (atualmente fire-and-forget).
10. **(8)** Endpoint /v1/stats/orders-today (front já consulta com fallback).
11. **(9)** Redis pra rate-limiter (escala horizontal).
12. **(10)** K8s migration.

---

## 17. Como retomar trabalho rápido

1. **Ler este arquivo** + `viralefy_archive/COMPLIANCE.md` + `viralefy_archive/diretrizes.md`.
2. **Verificar memórias** persistentes em `~/.claude/projects/-media-sonne-Archives-projects-viralefy/memory/`.
3. **`cd viralefy_<pkg> && git pull`** em cada repo.
4. **`ssh -i ~/.ssh/viralefy_hml root@62.238.41.231 'viralefy-status'`** pra ver serviços.
5. **`curl -sk https://api.viralefy.com/v1/plans | jq '.data | length'`** — sanity check API.
6. **`grep -r "TODO\|FIXME" viralefy_*/src 2>/dev/null | head`** — débitos.
7. Pra mudanças backend: `go build ./...` é a fonte de verdade (IDE pode mentir).
8. Pra mudanças frontend: sempre `git diff <file>` antes de commit. Edit tool às vezes deixa state inconsistente.
9. Deploy: `git push` em cada repo + `ssh ... 'viralefy-update'`.

### URLs importantes
- https://www.viralefy.com — loja (canônica)
- https://admin.viralefy.com — backoffice
- https://api.viralefy.com — API REST
- https://obs.viralefy.com — Grafana
- https://github.com/Viralefy — 5 repos (público)
- https://challenges.cloudflare.com/turnstile/v0/api.js — Turnstile (gated por CSP)

### Atalho `/`
A loja tem busca tipo marketplace ativada por `/` (atalho global tipo GitHub) — usuário digita "seguidores brasil" e cai no agrupamento.

---

**Última atualização**: 2026-06-01. Próxima compactação esperada: quando novos features grandes (Meta CAPI, Stripe, K8s) forem adicionados.
