# Viralefy — Contexto de continuidade

> Dump operacional para retomar trabalho sem reconstruir do zero. Atualizado em 2026-05-31.
> Substitui revisões anteriores. A fonte normativa de arquitetura é **`diretrizes.md` (v4.0)**,
> auditoria viva em **`COMPLIANCE.md`**, este doc é "estado do mundo".

---

## 1. TL;DR

Plataforma SaaS pra venda de seguidores/curtidas/views/serviços premium em
**Instagram e TikTok**, com créditos, ledger, tickets, **130 subsites SEO por
país**, multi-moeda (USD canônico — BRL/EUR/USDT/BTC computados), 7 categorias
**split por plataforma** (seguidores_instagram, seguidores_tiktok, ...,
servicos), painel backoffice com RBAC granular, gateways Woovi (BRL/Pix) +
Heleket (cripto), e-mail Resend, **observability stack completa** (Grafana +
Loki + Tempo + Prometheus + Alloy + OTel) e GTM-K7GQ4H32.

**Produção** em `viralefy.com` (Debian 13, Caddy + systemd, single host bare-metal).
**Fase**: HML/POC, 15-day result test (até ~2026-06-14).

---

## 2. Acesso e infraestrutura

### 2.1 Servidor

| | |
|---|---|
| Host | `viralefy.com` (IP 62.238.41.231) |
| OS | Debian 13 (trixie) — Linux 6.x |
| SSH | `root@62.238.41.231` via Ed25519 key em `/media/sonne/Archives/projects/viralefy/credentials` |
| Recursos | 4 GB RAM, 38 GB disco |
| Stack | Go 1.26.3, Node 24.15.0, PostgreSQL 17, Caddy 2.11.3, Grafana 12, Loki 3.3.2, Tempo 2.7.1, Prometheus 3.x, Alloy 1.x |
| TLS | Let's Encrypt via Caddy, auto-renova |

> **Nota**: chave SSH e Resend API key foram coladas em chat anteriormente.
> Rotação não é obrigatória neste momento (HML/POC) — ver `memory/no-secret-rotation-nag.md`.

### 2.2 Domínios públicos

| URL | Serviço | Port loopback |
|---|---|---|
| https://viralefy.com | Loja Next.js | 3000 |
| https://www.viralefy.com | Redirect 301 → apex | (Caddy) |
| https://admin.viralefy.com | Backoffice Next.js | 3001 |
| https://api.viralefy.com | API Go | 8080 |
| https://obs.viralefy.com | **Grafana UI** (precisa DNS A record!) | 3030 |

**Caddy** é a única superfície pública. Apps escutam só em 127.0.0.1.
Headers de segurança aplicados via Caddy + `next.config.ts`.

### 2.3 Filesystem produção

```
/viralefy/                       # APAGADO a cada viralefy-update (destrutivo)
├── api/bin/viralefy-api         # binário Go (~12 MB)
├── front/                       # Next.js standalone
├── backoffice/                  # Next.js standalone
├── ops/                         # installer scripts
└── archive/                     # diretrizes + brand

/etc/viralefy/.env               # SOBREVIVE (0640 root:viralefy)
/etc/caddy/Caddyfile             # subset + drop-in systemd
/etc/caddy/viralefy.env          # DOMAIN_FRONT/BACKOFFICE/API/OBS

# OBSERVABILIDADE — sobrevive ao update
/etc/{grafana,loki,tempo,prometheus,alloy}/  # configs
/var/lib/{grafana,loki,tempo,prometheus,alloy}/  # dados persistentes

/etc/systemd/system/viralefy-{api,front,backoffice}.service
/etc/systemd/system/{grafana-server,loki,tempo,prometheus,alloy,node-exporter}.service
/etc/systemd/system/caddy.service.d/viralefy.conf

/usr/local/sbin/viralefy-{install,update,status,logs}  # CLIs persistentes
```

PostgreSQL em `/var/lib/postgresql/` — não é tocado pelo update.
Service users: `viralefy-api`, `viralefy-front`, `viralefy-backoffice`,
`grafana`, `loki`, `tempo`, `prometheus`, `alloy`, `node-exporter` —
todos sem shell, gid `viralefy` para os de app.

### 2.4 Variáveis de ambiente (em `/etc/viralefy/.env`)

```bash
# ---- API ----
PORT=8080
BIND_HOST=127.0.0.1
DATABASE_URL=postgres://viralefy:<gerado>@localhost:5432/viralefy?sslmode=disable
DATABASE_PASSWORD=<gerado 32>
JWT_SECRET=<gerado 64>
CORS_ORIGINS=https://viralefy.com,https://admin.viralefy.com

# ---- Email (Resend, em test mode — entrega só pro dono) ----
EMAIL_PROVIDER=resend
RESEND_API_KEY=re_j1Zar5tv_5w2Y5JrErHPLmfz9we7uqfh2
RESEND_FROM=onboarding@resend.dev
RESEND_FROM_NAME=Viralefy
RESEND_BASE_URL=https://api.resend.com

# ---- Bing IndexNow ----
INDEXNOW_KEY=adcfcb87889076210f395f754a9ad0c3   # casa com /public/<key>.txt
INDEXNOW_SECRET=<gerado 48>                      # gate /api/indexnow

# ---- Next.js (build-time) ----
NEXT_PUBLIC_API_URL=https://api.viralefy.com
NEXT_PUBLIC_SITE_URL=https://viralefy.com
NEXT_PUBLIC_WHATSAPP_NUMBER=                     # vazio → botão escondido

# ---- Caddy domains ----
DOMAIN_FRONT=viralefy.com
DOMAIN_BACKOFFICE=admin.viralefy.com
DOMAIN_API=api.viralefy.com
DOMAIN_OBS=obs.viralefy.com                      # precisa DNS A record
CADDY_EMAIL=schematizecode@gmail.com

# ---- Observabilidade ----
GRAFANA_ADMIN_PASSWORD=<gerado 32>               # admin / esta senha
OTEL_EXPORTER_OTLP_ENDPOINT=http://127.0.0.1:4318
OTEL_SERVICE_NAME=viralefy-api
```

---

## 3. Credenciais

| Item | Onde está | Status |
|---|---|---|
| SSH key Ed25519 root@62.238.41.231 | `/media/sonne/Archives/projects/viralefy/credentials` | Rotação opcional HML |
| Postgres password | `/etc/viralefy/.env` (`DATABASE_PASSWORD`) | Gerado, persistente |
| JWT secret | `/etc/viralefy/.env` (`JWT_SECRET`) | Gerado. **Migrar pra RS256 — viola §14 MUST** |
| Resend API key | `/etc/viralefy/.env` (`RESEND_API_KEY`) | Test mode (só dono recebe). Rotação opcional |
| Grafana admin | `/etc/viralefy/.env` (`GRAFANA_ADMIN_PASSWORD`) | Gerado, persistente |
| IndexNow secret | `/etc/viralefy/.env` (`INDEXNOW_SECRET`) | Gerado |
| Admin Viralefy | `schematizecode@gmail.com / WIc0z!j@?M@RZuAp` | Superadmin, criado manualmente |

---

## 4. Repos (5 públicos em https://github.com/Viralefy)

| Repo | Stack | Função |
|---|---|---|
| [viralefy_api](https://github.com/Viralefy/viralefy_api) | Go 1.26.3 + chi/v5 + pgx/v5 + slog + Prometheus + OTel | API de domínio (auth, planos, checkout, pedidos, créditos, ledger, tickets, gateways, webhooks) |
| [viralefy_front](https://github.com/Viralefy/viralefy_front) | Next.js 15 App Router + React 19 + TS | Loja pública, 130 subsites SEO, search marketplace, theme switcher |
| [viralefy_backoffice](https://github.com/Viralefy/viralefy_backoffice) | Next.js 15 + TS | Painel admin (gestão de planos, gateways, moedas, usuários, créditos, tickets, ledger) |
| [viralefy_ops](https://github.com/Viralefy/viralefy_ops) | Bash | Installer destrutivo + systemd hardening + Caddy + observabilidade |
| [viralefy_archive](https://github.com/Viralefy/viralefy_archive) | MD | `diretrizes.md`, `CONTEXT.md`, `COMPLIANCE.md`, brand assets |

---

## 5. Arquitetura

```
                ┌──────────────────────────────────────────────┐
Internet  ────► │  Caddy 2.11 (443/80, único acessível)        │
                │  ├ viralefy.com ────► viralefy-front :3000   │
                │  ├ www.viralefy.com → redirect 301 → apex    │
                │  ├ admin.viralefy.com → viralefy-backoffice  │
                │  ├ api.viralefy.com → viralefy-api :8080     │
                │  └ obs.viralefy.com ────► grafana :3030      │
                └──────────────────────────────────────────────┘
                          │             │             │
                          ▼             ▼             ▼
              Next.js 15      Next.js 15        Go API
              (storefront)    (admin)           (chi router)
                                                │
              ┌─────────────────────────────────┴─────────────┐
              │                                                │
        OTLP /4318                              PG :5432
        Tempo (traces)                          Postgres 17
        scrape /metrics                          (single schema —
        Prometheus :9090                          API + backoffice
                                                  compartilham — débito)
        journalctl → Alloy → Loki :3100
        Grafana :3030 ← datasources (Loki+Tempo+Prom)
```

**Camadas da API** (Go DDD-light):
```
viralefy_api/
├── cmd/api/main.go
├── internal/
│   ├── domain/           # admin, authz, category, credit, currency,
│   │                       gateway, invoice, order, plan, profile,
│   │                       ticket, user (entities)
│   ├── application/      # auth, checkout, credit, currency, email,
│   │                       gateway, invoice, payment_receiver, plan,
│   │                       profile, ticket, user_auth services + ABAC
│   ├── infrastructure/
│   │   ├── observability/   # logger.go, metrics.go, tracing.go (NOVO)
│   │   ├── persistence/postgres/  # repos + seed.go + migrations
│   │   └── external/{email,payment}/  # ACL pro Resend/Woovi/Heleket
│   ├── interface/http/   # router, handlers, middleware + observability.go
│   └── config/
├── docs/openapi.yaml
└── tests/  (vazio — débito)
```

**Inversão de dependência**: domain → não importa nada. application → domain.
infrastructure → domain + application. interface → application.

---

## 6. Schema PostgreSQL

**Migrations** em `internal/infrastructure/persistence/postgres/migrations/`
(idempotentes `IF NOT EXISTS`, **sem `down` — débito §10**).

Tabelas principais:

| Tabela | Função | Nota |
|---|---|---|
| `categories` | 7 codes split por plataforma | seguidores_instagram, seguidores_tiktok, engajamento_instagram, engajamento_tiktok, visualizacoes_instagram, visualizacoes_tiktok, servicos |
| `currencies` | BRL, USD, EUR, USDT, BTC | rate stored, USD virou canônico no seed |
| `plans` | 109 plans ativos | UNIQUE em (category, name) via `plans_category_name_key`; preços USD round |
| `plan_prices` | 5 currencies por plan | UPSERT no seed (`ON CONFLICT DO UPDATE`) |
| `payment_gateways` | Woovi (BRL), Heleket (cripto) | |
| `users` | clientes (auto-cadastro no checkout) | bcrypt |
| `profiles` | Instagram/TikTok handles por user | platform + handle (sem `@`) |
| `orders` | pedidos (pending/paid/failed/cancelled) | display_currency + settlement_currency podem diferir |
| `invoices` | recargas de crédito | display vs settlement amounts |
| `credit_accounts` | saldo por user | balance_cents |
| `credit_transactions` | ledger imutável | type recharge/spend/refund/adjustment; balance_after_cents |
| `admins` | usuários do backoffice | |
| `roles` + `role_permissions` | RBAC | superadmin/manager/support/viewer |
| `admin_roles` | many-to-many | |
| `tickets` + `ticket_messages` | helpdesk | status: open/pending/resolved/closed |
| `audit_logs` | trilha de auditoria | uso parcial, débito §16.6 |

**IDs**: `gen_random_uuid()` (UUIDv4). Débito §10: deveria ser UUIDv7/ULID.
**Timestamps**: `timestamp with time zone now()` (UTC sempre) ✅.

### 6.1 Catálogo de planos (109 total)

| Categoria | Plans | Range USD |
|---|---:|---|
| `seguidores_instagram` | 18 | $2.50 → $4,000 (100 → 1M, c/ tiers intermediários 750/1.5k/7.5k/15k/75k) |
| `seguidores_tiktok` | 10 | $5 → $200 (100 → 10k, capped per spec, 2× IG/k) |
| `engajamento_instagram` | 29 | $1 → $280 (likes/comments/shares/saves) |
| `engajamento_tiktok` | 22 | $2 → $260 (2× IG) |
| `visualizacoes_instagram` | 15 | $1.50 → $800 (Reels target_type=publication, Stories=profile) |
| `visualizacoes_tiktok` | 7 | $20 → $1,400 (video views, 2× IG) |
| `servicos` | 8 | $39 → $499 |

Serviços premium: Profile audit ($39), Competitor analysis ($79), Monthly
management ($99), Anti-shadowban package ($129), New account setup ($149),
Account recovery ($199), Verification support ($299), Product launch ($499).

---

## 7. RBAC

**Roles**: `superadmin`, `manager`, `support`, `viewer`.
**Permissions**: `plans:read/write`, `gateways:read/write`, `currencies:read/write`,
`orders:read`, `tickets:read/write`, `admins:manage`.

**ABAC** (`application/abac.go`): permissions sempre relidas da DB por request
(JWT só carrega `admin_id` + `typ`). JWT `typ` claim distingue admin vs user
pra evitar confusão (`typ=admin` ou `typ=user`).

**JWT atual**: HS256 — **viola §14 MUST** (deve ser RS256/EdDSA em fluxo público).
Débito Tier 1.

---

## 8. Frontend (viralefy_front)

### 8.1 i18n

- **`src/i18n/languages.ts`**: 47 LangCodes (pt/en/es/es_AR/fr/de/it/nl + 18 EU
  outros + 17 asiáticos/africanos + ru). Pack rico em 8 idiomas
  (en/pt/es/es_AR/fr/de/it/nl/ru), resto cai em en via spread `{...en}`.
- **`src/i18n/countries.ts`**: 130 países (americas 30, sepa 37, asia 33,
  africa 16, oceania 4, europe_other 10). Cada um com h1/title/description/intro
  em script nativo, currencyHint ISO 4217, htmlLang BCP47.
- **`src/i18n/categories.ts`**: 7 CategoryCodes, slugs ASCII-safe por idioma
  (`/br/seguidores-instagram`, `/us/instagram-followers`, `/de/instagram-follower`,
  `/ru/podpisciki-instagram`, etc). `LongCopy` rica em 8 idiomas (paragraphs
  500+ palavras quando rica, fallback en para outros).
- **`src/i18n/legal.ts`**: 6 docs legais (privacy/terms/cookies/refund/about/
  contact) × 7 idiomas (en/pt/es/fr/de/it/nl/ru). Outros caem em en.

### 8.2 Roteamento

| Rota | Função |
|---|---|
| `/` | Home global EN. `<html lang="en">` |
| `/{country}` | 130 subsites SEO. Lang derivado de `langOfCountry(code)` |
| `/{country}/{category-slug}` | Página de categoria (~910 combinações) |
| `/{country}/{category-slug}/{qty}-{slug}` | Página de plano dedicada |
| `/legal/{doc}?lang={code}` | 6 docs × 47 idiomas |
| `/account`, `/account/credits`, `/account/profiles` | User area (auth required) |
| `/tickets`, `/tickets/new`, `/tickets/[id]` | Helpdesk |
| `/login`, `/register` | Auth (UI em inglês) |
| `/og/[...slug]` | OG image dinâmica 1200×630 (Next 15 ImageResponse) |
| `/api/geo` | Geo-IP → country/currency |
| `/api/orders-today` | Proxy LiveCounter (synthetic fallback) |
| `/api/indexnow` | Submit URLs ao Bing (gated por INDEXNOW_SECRET) |
| `/api/metrics` | Prometheus metrics do Next.js |
| `/sitemap.xml` | Sitemap index (48 buckets) |
| `/sitemap/{lang}.xml` | Per-language sitemap |
| `/robots.txt` | Allow tudo exceto `/account`, `/tickets`, `/login`, `/register`, `/api/` |
| `/{indexnow-key}.txt` | IndexNow ownership (já no /public) |

### 8.3 Componentes-chave

- **Header.tsx**: sticky com blur, responsivo (desktop single row, mobile drawer).
  Logo + MegaMenuMarkets + SearchBar + ThemeToggle + Currency + Auth.
- **MegaMenuMarkets.tsx**: dropdown 2-col (Américas+SEPA | Ásia+África+Oceania+Europa-outros)
  com filtro inline + autofocus.
- **SearchBar.tsx**: marketplace-style. Index estático em module-load
  (130 × 7 = 910 hits). Match token-AND com normalização NFD (sem acento),
  bônus em fronteira de palavra + match em nome do mercado.
  Atalho `/` foca de qualquer lugar. ArrowUp/Down + Enter navega.
- **ThemeToggle.tsx + lib/theme.ts**: dark/light com anti-flash inline script
  no `<head>`. Light theme tem `--accent #00b89a` (neon escurecido pra legibilidade).
- **TrustSignals.tsx**: server component, 3 emoji chips (refill/password/delivery)
  em 8 idiomas. Variants `default` e `compact`.
- **LiveCounter.tsx**: client widget bottom-right, polling 60s, dismissable.
- **WhatsAppButton.tsx**: flutuante bottom-left, só renderiza se
  `NEXT_PUBLIC_WHATSAPP_NUMBER` setado E lang ∈ {pt, es, es_AR}.
- **CategoryGroupedGrid.tsx**: home/country. Agrupa por categoria, ordena por qty.
- **CategoryCardGrid.tsx + QuantitySlider.tsx**: nas páginas de categoria.
  Variant A (cards com link "+") + Variant B (slider com tabela comparativa).
- **CheckoutModal.tsx**: modal de compra com TrustSignals no header.
- **Footer.tsx**: links legais + 18 mercados + disclaimer não-afiliado.

### 8.4 Design system

Paleta neon cyan-mint (`#00fed6` = logo color), fundo cool-dark (`#04080c`).
- **`--accent #00fed6`** (dark), **#00b89a** (light)
- **`--gradient`**: linear-gradient cyan → teal → azul profundo (`#00fed6 → #08b0c4 → #03517a`)
- Glows neon em hover/focus
- Backdrop-blur sticky header
- `body` com radial-gradient sutil neon no topo + azul-noite no rodapé (fixed)
- Twemoji CDN substitui emoji unicode por SVG (universal, fix bandeirinhas brancas)
- GTM-K7GQ4H32 inline + `<noscript>` iframe

### 8.5 SEO

- **Sitemap index** → 48 per-language sitemaps via Next 15 `generateSitemaps()`.
- **hreflang completo**: 128 alternate links por página (130 países + x-default).
- **JSON-LD enriquecido**: Organization (com `@id`, logo ImageObject, contactPoint
  multi-lang, sameAs GitHub) + WebSite (publisher por ref, SearchAction) + WebPage
  + BreadcrumbList + Service (`serviceType: "Social media growth"`) + AggregateOffer
  (priceCurrency USD canônico, priceValidUntil +1 ano, sku=plan.id) + Product
  (em página de plano) + FAQPage (em página de categoria).
- **Metadata**: applicationName, authors, creator, publisher, formatDetection,
  OG siteName/type/locale, Twitter card, icons.
- **OG images dinâmicas**: `/og/[...slug]` por país + categoria + plano.
- **Bing IndexNow**: 15,493 URLs já aceitas, gate por secret no endpoint.
- **GTM-K7GQ4H32** instalado no `<head>` (afterInteractive) + `<noscript>` no body.
- **robots.txt** rota dinâmica via `app/robots.ts`.

### 8.6 Segurança (next.config.ts)

- **CSP** completa relaxando GTM (googletagmanager.com) + Twemoji (cdn.jsdelivr.net) + API
- **X-Frame-Options: DENY**
- **X-Content-Type-Options: nosniff**
- **Referrer-Policy: strict-origin-when-cross-origin**
- **Permissions-Policy** bloqueando camera/microphone/geolocation/interest-cohort
- **Cross-Origin-Opener-Policy: same-origin**
- **poweredByHeader: false** (sem X-Powered-By: Next.js)

---

## 9. Observabilidade (NOVO — esta sessão)

### 9.1 Stack instalada

| Componente | Porta | Função |
|---|---|---|
| Grafana | 3030 | UI em https://obs.viralefy.com. Datasources: Loki/Tempo/Prom |
| Loki | 3100 | Log aggregation, filesystem storage, 7d retention |
| Tempo | 3200 / 4317 / 4318 | Trace storage, OTLP HTTP+gRPC receiver |
| Prometheus | 9090 | Scrape /metrics da API + node-exporter + self |
| Alloy | 12345 | Lê journalctl → ships pra Loki |
| node_exporter | 9100 | Host metrics |

**Configs** em `/etc/{componente}/`, **dados** em `/var/lib/{componente}/`.
Tudo sobrevive ao update destrutivo do `/viralefy/`.

### 9.2 Dashboards provisionados

- `dashboards/viralefy-api.json` (auto-provisionado): RED panels (rate, errors,
  duration p50/p95/p99), error ratio, DB queries/s, gateway callbacks, RSS/heap.
- Folder "Viralefy" criado automaticamente na UI.

### 9.3 API instrumentada

- **slog JSON** estruturado: `trace_id`, `request_id`, `method`, `path`,
  `status`, `duration_ms`. PII masking helpers (`MaskEmail`, `MaskPhone`,
  `MaskCPF`, `MaskToken`).
- **Prometheus**: `http_requests_total{method,path,status}`,
  `http_request_duration_seconds{method,path}`,
  `db_query_duration_seconds{query_type}`,
  `gateway_callbacks_total{provider,status}` + Go runtime metrics.
- **OTel**: OTLP HTTP exporter → Tempo (`localhost:4318`), W3C TraceContext +
  Baggage + B3 propagators, parent-based ratio sampler.
- **`/metrics`** endpoint + **`/ready`** com `db.Pool().Ping()` (2s timeout).

### 9.4 Front instrumentado

- **`/api/metrics`** Prometheus text (process_*, uptime, RSS, heap, eventloop_lag).
- OTel client-side **deferred** (env vars já no service file).

---

## 10. Pagamentos

- **Woovi**: BRL via Pix. Webhook HMAC-SHA256.
- **Heleket**: cripto. Webhook md5 sign.
- **PaymentReceiver pattern** (idempotente). Webhook + admin manual mark-paid.
- **Currency display ≠ settlement**: cliente vê USD/BRL, paga em BRL ou cripto.
- Plan stored em USD; conversion via fixed rates inline no seed (USD→BRL=5.41, USD→EUR=0.92, USD→BTC=0.0000103).

---

## 11. Sistema de testes

Tudo em `viralefy_front/tests/`:

| Suite | Counts | Comando |
|---|---|---|
| Unit (node:test + loader hook .ts) | **273/273 PASS** (~2.5s) | `npm test` |
| Coverage | **85.18%** lines, 89.44% branches | `npm run test:coverage` |
| Smoke (bash + curl) | **57 PASS** / 0 FAIL / 19 INFO em 76 checks | `npm run test:smoke` |
| Pentest (bash + curl + openssl) | **54 PASS** / 0 FAIL / 7 INFO em 61 probes | `npm run test:pentest` |
| Emulated browse | **8/8 PASS** | `npm run test:emulated:browse` |
| Emulated i18n | **8/8 PASS** | `npm run test:emulated:i18n` |
| Emulated API contracts | **20/20 PASS** | `npm run test:emulated:contracts` |
| Emulated a11y | **10/10 PASS** | `npm run test:emulated:a11y` |
| Emulated checkout | cria pending order na API | `npm run test:emulated:checkout` |
| `test:all` | suite completa | `npm run test:all` |

API Go: **0% cobertura** (zero testes) — débito Tier 1/§22.

**Débito §22.1**: suíte deveria viver em `viralefy_ops/tests/` com CLI
`viralefy test smoke|integration|...`. Hoje mora no front, single CLI via
`npm`.

---

## 12. Comandos operacionais

### 12.1 Deploy

```bash
# do laptop, com SSH key
ssh root@62.238.41.231 'viralefy-update'    # DESTRUTIVO: rm -rf /viralefy/*
# pulla main, builda, restart systemd units

ssh root@62.238.41.231 'viralefy-status'    # checa todos os services
ssh root@62.238.41.231 'viralefy-logs api'  # journalctl
                                            # mappers: api/front/backoffice/caddy
                                            # grafana/loki/tempo/prom/alloy/node/obs
```

### 12.2 IndexNow re-ping

```bash
SECRET=$(ssh root@62.238.41.231 'cat /root/.viralefy-secrets/indexnow_secret')
curl -X POST -H "x-indexnow-secret: $SECRET" \
  -H "Content-Type: application/json" \
  https://viralefy.com/api/indexnow -d '{}'
```

### 12.3 DB

```bash
ssh root@62.238.41.231 'sudo -u postgres psql viralefy -c "..."'

# Dump (manual — débito automatizar)
ssh root@62.238.41.231 'sudo -u postgres pg_dump viralefy | gzip > /tmp/dump.sql.gz'
```

### 12.4 Acesso Grafana

```bash
# DNS A record obs.viralefy.com → 62.238.41.231 (pra cert ACME)
# Senha em /etc/viralefy/.env (GRAFANA_ADMIN_PASSWORD)

# Sem DNS, via SSH tunnel:
ssh -L 3030:127.0.0.1:3030 root@62.238.41.231
# Abre http://localhost:3030 (admin / senha do .env)
```

### 12.5 Testes

```bash
cd viralefy_front

npm test                            # 273 unit, ~2.5s
npm run test:coverage               # com relatório
SITE_URL=https://viralefy.com bash tests/smoke/run.sh
SITE_URL=https://viralefy.com API_URL=https://api.viralefy.com bash tests/pentest/probes.sh
npm run test:emulated:browse
npm run test:emulated:i18n
npm run test:emulated:contracts
npm run test:emulated:a11y
npm run test:all                    # tudo
```

---

## 13. Checklist — Estado atual

### ✅ Implementado e deployado

- [x] Plataforma SaaS funcional (loja + backoffice + API + auth + checkout + créditos + ledger + tickets)
- [x] 130 países × 7 categorias × ~100 plans = ~91k URLs únicas indexáveis
- [x] 8 idiomas com pacote rico (en/pt/es/es_AR/fr/de/it/nl/ru)
- [x] 47 LangCodes total
- [x] 7 categorias split por plataforma (IG/TT separadas)
- [x] USD canonical pricing, BRL/EUR/USDT/BTC computados
- [x] Tier intermediários de qty (100, 250, 500, 750, 1k, 1.5k, 2.5k, ...)
- [x] TikTok = 2× Instagram, capped em 10k followers
- [x] 7 categorias, UNIQUE em (category, name) — sem duplicates
- [x] Header responsivo (drawer mobile)
- [x] MegaMenu de mercados (130 países, 2 col + filtro)
- [x] SearchBar marketplace (910 entries, normalização NFD, atalho `/`)
- [x] Theme switcher (dark default + light) com anti-flash
- [x] Twemoji (bandeirinhas SVG universais)
- [x] Default currency USD (era BRL)
- [x] **Geo-IP currency auto-pick** (Tier 1)
- [x] **TrustSignals component** (Tier 1, 8 idiomas)
- [x] **LiveCounter widget** (Tier 1, synthetic fallback)
- [x] **OG images dinâmicas** (Tier 1)
- [x] **WhatsApp button** (Tier 1, BR/LATAM gated)
- [x] GTM-K7GQ4H32 inline + noscript
- [x] Sitemap index + 48 per-language
- [x] hreflang completo em todas as páginas
- [x] JSON-LD enriquecido (5 blocos por país, FAQPage em cat, Product em plan)
- [x] Bing IndexNow (15,493 URLs aceitas)
- [x] robots.txt dinâmico
- [x] Security headers (CSP completa, X-Frame, Permissions-Policy, COOP)
- [x] www.viralefy.com → 301 → apex (cert ACME emitido)
- [x] **Observability stack** completa (Grafana + Loki + Tempo + Prometheus + Alloy + node_exporter)
- [x] **API instrumentada** (slog JSON + Prometheus /metrics + OTel /4318 + /ready)
- [x] **Front /api/metrics** Prometheus text
- [x] Suíte de testes 273 unit + smoke 76 + pentest 61 + emulated 5 suites
- [x] Coverage 85.18% lines
- [x] `viralefy-status` health check expandido
- [x] `viralefy-logs` mappers pra todos os services novos
- [x] `viralefy-update` destrutivo idempotente
- [x] `COMPLIANCE.md` audit vs `diretrizes.md` v4.0 commitado

### 🟡 Tier 1 — PRD blockers (resolver antes de escalar)

- [ ] **§14 JWT RS256** (atualmente HS256 — viola MUST). Risco real: vazamento de JWT_SECRET → forjar tokens.
- [ ] **§12 Rate limiting** distribuído (Redis) — endpoints sem proteção contra brute force
- [ ] **§12 Idempotency-Key** em writes (checkout, orders) — risco de double-charge em retries
- [ ] **§21 CI/CD GitHub Actions** mínimo (build + tests on PR)
- [ ] **Postgres backup** automatizado (pg_dump diário + retention 14d + S3/B2 weekly)
- [ ] **DNS A record obs.viralefy.com → 62.238.41.231** pra Grafana via ACME (depende do user)
- [ ] **API Go com testes** (cobertura 0% hoje)

### 🟠 Tier 2 — Resiliência + segurança (1-2 semanas)

- [ ] **§9 Outbox Pattern** pra checkout + email atômicos
- [ ] **§18 Resiliência** em external calls (timeout/retry/circuit-breaker em Resend/Woovi/Heleket)
- [ ] **§13 Security pipeline**: Dependabot + Semgrep + Gitleaks + Trivy
- [ ] **§31 Feature flags** (GrowthBook self-host ou Unleash)
- [ ] **§32 LGPD** endpoints de export/delete + classificação de dados
- [ ] **Abandoned cart cron** (backend) — coluna `notified_abandoned_at` em orders + cron horário
- [ ] **Email verification** antes do checkout (magic link/6 dígitos)
- [ ] **Cart multi-plan** (1 checkout pode ter N items)
- [ ] **Cupons + promoções**
- [ ] **Upsell post-purchase** (compra seguidores → sugere engagement)
- [ ] **Stripe gateway** com iDEAL/Bancontact/SEPA Direct Debit/Klarna (mercado EU)
- [ ] **Reviews + AggregateRating schema**
- [ ] **§25-26 Runbook + oncall** documentados
- [ ] **§27 ADRs** redigir 0001-0004 (bare-metal vs k8s, HS256 temporário, schema compartilhado, Grafana self-hosted)

### 🟢 Tier 3 — Tech debt + escala (1+ mês)

- [ ] **§22.1 Test kit unificado** em `viralefy_ops/tests/` com CLI `viralefy test smoke|...`
- [ ] **§16.6 Trilha de auditoria** imutável em `audit_logs` append-only
- [ ] **§10 Migrations reversíveis** com `down`
- [ ] **§2/§10 Schema separation** API ↔ backoffice (backoffice consome API)
- [ ] **§11 Redis cache** pra plans/categories/currencies
- [ ] **§14 Refresh tokens rotativos** com detecção de reuso
- [ ] **§21 Artefato imutável** — versionar releases com tag + manter imagens
- [ ] **§21 Kubernetes + Helm** (se justificar)
- [ ] **§30 SLOs** em `/docs/slo.md` + error budget
- [ ] **§32 DPIA** pra tratamentos de alto risco
- [ ] **Float64 → decimal** no API Go (valores monetários)
- [ ] **Apagar admin@viralefy.local** seed de PRD
- [ ] **CheckoutModal i18n** nos 8 idiomas com Pack rico
- [ ] **Blog/content marketing** em PT/EN/ES (long-tail SEO)
- [ ] **OTel client-side Next.js** (`@vercel/otel`)
- [ ] **Cloudflare na frente** (passa CF-IPCountry header, geo-IP currency funciona de verdade)
- [ ] **Affiliate/reseller program**
- [ ] **Account creator service** (premium, alta margem)
- [ ] **Native rich copy em 18+ idiomas** (hoje só 8)
- [ ] **Order tracking real-time** (drip campaign config)
- [ ] **Mobile app** (eventualmente)

### 🔴 Conhecidos pendentes do user

- [ ] **DNS A record `obs.viralefy.com → 62.238.41.231`** pra Grafana via cert ACME
- [ ] **Set `NEXT_PUBLIC_WHATSAPP_NUMBER`** em `/etc/viralefy/.env` pra ativar botão BR/LATAM
- [ ] **Cloudflare proxy** (se quiser geo-IP real via `CF-IPCountry` header)
- [ ] **Rotação de chaves** (SSH + Resend) — opcional HML, mandatório PRD
- [ ] **Implementar `/v1/stats/orders-today`** no API Go pra LiveCounter consumir números reais

---

## 14. Decisões e quirks importantes

### 14.1 Decisões arquiteturais (sem ADR ainda — débito §27)

- **Bare-metal + systemd vs Kubernetes**: escolhido por simplicidade e custo
  no POC (single $X/mês VPS). Trade-off: sem auto-scale, sem rolling deploy.
  ADR 0001 a redigir.
- **Schema compartilhado API + backoffice**: viola §2/§10 mas acelerou POC.
  Backoffice fala SQL direto no schema da API. ADR 0003.
- **JWT HS256**: viola §14 MUST. Aceitável só no POC. ADR 0002 com plano de
  migração pra RS256.
- **Stack observabilidade self-hosted no mesmo host**: viola implicitamente
  §16 (não dedicado) mas evita complexidade de Grafana Cloud em POC. ADR 0004.
- **USD como moeda canônica do seed** (era BRL): trocado nesta sessão.
  `seedPlanPrices` usa rates inline (USDT=1, EUR=0.92, BRL=5.41, BTC=0.0000103).
- **Seed UPSERT por (category, name)**: era natural-key tuple mas engagement
  sub-tipos (likes/comments/shares/saves) compartilham `(category, platform,
  target_type, qty)` — colidia. Name é identificador físico único.

### 14.2 Quirks operacionais

- **`/viralefy/` é APAGADO** a cada `viralefy-update`. Coisas que devem
  sobreviver: `/etc/viralefy/.env`, `/etc/caddy/*`, `/etc/grafana/*`,
  `/var/lib/grafana/*`, `/var/lib/postgresql/*`, etc.
- **Caddy emite cert ACME só pra domínios com DNS apontado**. `obs.viralefy.com`
  precisa do A record antes do primeiro deploy ou continua com erro de cert.
- **Resend em test mode**: só entrega pro dono da conta (`viralefy@gmail.com`).
  Pra produção real precisa verificar domínio (`viralefy.com`) no painel Resend.
- **GTM noscript iframe** dentro do `<body>` é exigido — segue snippet oficial.
- **Twemoji** substitui emoji unicode por `<img class="emoji">` SVG via
  `MutationObserver` (pra cobrir Next.js client nav).
- **Anti-flash de tema**: inline script em `<head>` antes do React hidratar.
- **Sitemap index NÃO é auto-gerado** pelo Next.js 15 — feito manualmente em
  `app/sitemap.xml/route.ts`. `generateSitemaps()` só gera os per-id em
  `/sitemap/{id}.xml`.
- **Currency cookie name**: `viralefy_currency`. Theme: `viralefy_theme`.
- **Search atalho `/`**: foca o input de qualquer página (estilo GitHub).
- **WhatsApp button**: hidden por default se `NEXT_PUBLIC_WHATSAPP_NUMBER` vazio.
- **LiveCounter**: fallback synthetic determinístico seedado por minuto
  (~180 ±8%) quando API `/v1/stats/orders-today` não responde.
- **Plans com `currency='BRL'` legacy**: alguns plans antigos ainda têm
  currency=BRL no `plans.currency`. Seed UPDATE não toca esse campo. Cosmético.

### 14.3 Memory persistente do assistant

Em `/home/sonne/.claude/projects/-media-sonne-Archives-projects-viralefy/memory/`:

- `run-viralefy-stack-local.md` — Go fora do PATH, Postgres em container 15432
- `viralefy-stack-initial-build-fixes.md` — MVP non-compiling fixes
- `viralefy-features-v2.md` — categorias, auth user, autocadastro
- `viralefy-ops-and-github.md` — installer destrutivo, systemd, 5 repos
- `no-secret-rotation-nag.md` — não nag sobre rotação no HML/POC

---

## 15. Commits mais relevantes

### viralefy_archive
- `713aba3` — COMPLIANCE.md auditoria vs diretrizes.md v4.0
- `f9694d2` — CONTEXT.md (versão anterior, agora substituída por este)

### viralefy_front (top recentes)
- `1125bd3` — Tier 1 features (geo-IP, TrustSignals, LiveCounter, OG, WhatsApp)
- `558f3d3` — /api/metrics Prometheus
- `f1498ea` — 7 categorias split por plataforma + USD pricing
- `dfa5841` — test scope expansion (130→255 unit, 80 smoke, 61 pentest)
- `317b5da` — EN fallback + theme + Twemoji + ru countries + sitemap-index + CSP
- `dd0b3e1` — USD default + GTM + 60 mercados (126→130) + suite testes
- `299f32e` — neon cyan palette + responsive mobile header
- `ed3df8f` — MegaMenu Markets + SearchBar marketplace + 5 services
- `c76ded2` — root = global EN + country pages + category + per-plan + IndexNow

### viralefy_api
- `2f47f54` — observability (slog + Prometheus + OTel + /ready)
- `7b844ec` — seed UPSERT por (category, name)
- `6f28190` — 7 categorias split por plataforma + USD canonical + 107 plans
- `63f848d` — seed lookup name+category pra servicos

### viralefy_ops
- `f610389` — fix Grafana (`grafana server` subcmd + --homepath)
- `ef634df` — observability stack installer (Grafana + Loki + Tempo + Prom + Alloy)
- `a934902` — Caddy site block pra www.$DOMAIN_FRONT → 301 apex
- `585eb47` — INDEXNOW_KEY + INDEXNOW_SECRET no template do .env

### viralefy_backoffice
- Sem mudanças recentes nesta sessão. Usa pages de admin já existentes.

---

## 16. Sugestões priorizadas (Tier 2 a explorar)

Sugestões aceitas pelo user e ainda não implementadas — pode pegar em qualquer
ordem quando voltar:

1. **JWT RS256** (§14 MUST) — 1 dia
2. **Rate limiting** middleware chi + Idempotency-Key (§12) — 1 dia
3. **CI/CD GitHub Actions** (§21) — 1 dia
4. **Abandoned cart cron** backend (depende do anterior) — 2 dias
5. **ADRs 0001-0004** — 2h
6. **Postgres backup** automatizado — 4h
7. **Cart multi-plan** + **Upsell post-purchase** — 2 dias
8. **Stripe + métodos EU** (iDEAL/Bancontact/SEPA) — 3 dias
9. **Reviews schema** + AggregateRating — 1 dia
10. **Outbox pattern** + DLQ (§9) — 2 dias

---

## 17. Para retomar trabalho rápido

1. `cd /media/sonne/Archives/projects/viralefy`
2. `git -C viralefy_archive pull` (pra ver este CONTEXT atualizado)
3. `git -C viralefy_front log --oneline -5` (ver últimos commits)
4. `ssh -i credentials root@62.238.41.231 'viralefy-status'` (verificar saúde)
5. Para nova feature: branch `feature/<slug>` em qualquer repo, push direto
   a `main` quando OK (trunk-based, sem PR review).
6. Deploy: `viralefy-update` (DESTRUTIVO).
7. Smoke check: `npm test && SITE_URL=https://viralefy.com npm run test:smoke`
   em `viralefy_front/`.

**Atalho de teclado no site**: `/` foca a busca.

**URLs importantes**:
- Loja: https://viralefy.com / https://www.viralefy.com (301)
- API: https://api.viralefy.com (`/health`, `/ready`, `/metrics`, `/v1/...`)
- Admin: https://admin.viralefy.com
- Grafana: https://obs.viralefy.com (admin / senha em `/etc/viralefy/.env`)
- Bing webmaster: indexnow já configurado em `/adcfcb87889076210f395f754a9ad0c3.txt`

---

**Última revisão completa**: 2026-05-31 (fim da sessão observabilidade + Tier 1).
