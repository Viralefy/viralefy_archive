# Viralefy — Contexto de continuidade

> Dump operacional para retomar o trabalho rapidamente. Atualizado em 2026-05-30.
> A fonte normativa de arquitetura é **`diretrizes.md` (v4.0)**. Tudo aqui é
> contexto situacional — o "estado do mundo".

---

## 1. TL;DR

Plataforma SaaS de venda de seguidores/curtidas/views para **Instagram e TikTok**,
com créditos, ledger, tickets de suporte, 67 subsites SEO por país, multi-moeda
(BRL/USD/EUR/BTC) com display ≠ liquidação, painéis backoffice com RBAC granular,
e integração de gateways de pagamento (Woovi/Heleket) + e-mail Resend.

**Em produção** em `viralefy.com` (Debian 13, Caddy + systemd, isolamento por usuário).

---

## 2. Acesso e infraestrutura

### 2.1 Servidor HML/produção

| | |
|---|---|
| Host | `viralefy.com` (IP 62.238.41.231) |
| OS | Debian 13 (trixie) — base Ubuntu compatível |
| SSH | `root@62.238.41.231` via chave Ed25519 (**ROTACIONAR** — foi colada em chat) |
| Recursos | 4 GB RAM, 38 GB disco |
| Stack | Go 1.26.3, Node 24.15.0, PostgreSQL 17 (fallback do installer), Caddy 2.11.3 |
| DNS | `viralefy.com`, `admin.viralefy.com`, `api.viralefy.com` apontam pro mesmo IP |
| TLS | Let's Encrypt via Caddy, auto-renova (cert atual válido até 2026-08-28) |

### 2.2 Domínios públicos

| URL | Aplicação |
|---|---|
| https://viralefy.com | Loja Next.js (porta 3000 loopback) |
| https://admin.viralefy.com | Backoffice Next.js (3001 loopback) |
| https://api.viralefy.com | API Go (8080 loopback) |

Caddy é a única superfície pública. Apps escutam só em `127.0.0.1`. IP externo
da máquina recusa conexão direta nos 8080/3000/3001 (verificado).

### 2.3 Layout do filesystem (produção)

```
/viralefy/                       # apagado a cada update
├── api/bin/viralefy-api         # binário Go (12-14 MB)
├── front/                       # Next.js standalone (npm run start)
├── backoffice/                  # Next.js standalone
├── ops/                         # installer scripts (este repo é Viralefy/viralefy_ops)
└── archive/                     # diretrizes + brand assets

/etc/viralefy/.env               # SOBREVIVE ao update destrutivo (0640 root:viralefy)
/etc/caddy/Caddyfile             # subset do .env + drop-in systemd
/etc/caddy/viralefy.env          # DOMAIN_* + CADDY_EMAIL (0640 root:caddy)
/etc/systemd/system/viralefy-*.service   # hardened (NoNewPrivileges, ProtectSystem=strict, ...)
/etc/systemd/system/caddy.service.d/viralefy.conf   # drop-in EnvironmentFile
/usr/local/sbin/viralefy-{update,status,logs}  # CLIs (sobrevivem ao rm -rf)
```

PostgreSQL fica em `/var/lib/postgresql/` (NÃO é tocado pelo update — banco
sobrevive). Service user por serviço: `viralefy-api`, `viralefy-front`,
`viralefy-backoffice`, sem shell, gid `viralefy`.

### 2.4 Variáveis de ambiente (em `/etc/viralefy/.env`)

```bash
PORT=8080
BIND_HOST=127.0.0.1
DATABASE_URL=postgres://viralefy:<gerado>@localhost:5432/viralefy?sslmode=disable
DATABASE_PASSWORD=<gerado 32 bytes>
JWT_SECRET=<gerado 64 bytes>
CORS_ORIGINS=https://viralefy.com,https://admin.viralefy.com

EMAIL_PROVIDER=resend
RESEND_API_KEY=re_j1Zar5tv_5w2Y5JrErHPLmfz9we7uqfh2  # ROTACIONAR — foi colada em chat
RESEND_FROM=onboarding@resend.dev   # test mode — entrega só pro dono da conta
RESEND_FROM_NAME=Viralefy
RESEND_BASE_URL=https://api.resend.com

NEXT_PUBLIC_API_URL=https://api.viralefy.com   # build-time
NEXT_PUBLIC_SITE_URL=https://viralefy.com      # build-time
SITE_URL=https://viralefy.com                  # backend usa pro logo em e-mails

DOMAIN_FRONT=viralefy.com
DOMAIN_BACKOFFICE=admin.viralefy.com
DOMAIN_API=api.viralefy.com
CADDY_EMAIL=schematizecode@gmail.com
```

---

## 3. Credenciais e segredos

> **⚠️ AÇÃO PENDENTE — ROTACIONAR**: chave SSH e Resend API key foram coladas
> em chat. Transcripts podem ser retidos. Rotacionar ambas no painel/servidor.

| | |
|---|---|
| **Admin superadmin (você)** | `schematizecode@gmail.com` / `WIc0z!j@?M@RZuAp` |
| **Admin seed legado** | `admin@viralefy.local` / `SimTest!Admin2026` (existe em prod, considerar remover) |
| **User QA** | `qa@viralefy.com` / `QaTest!2026` (criado durante smoke tests) |
| **GitHub** | `gh` autenticado como `Lucassa02` (escopo `repo`, `read:org`, `workflow`); acesso à org `Viralefy` (default branch `main`) |
| **Resend account owner** | `viralefy@gmail.com` (test mode só entrega pra esse e-mail) |

---

## 4. Repos no GitHub Viralefy (todos públicos, branch default `main`)

| Repo | URL | O que é |
|---|---|---|
| `viralefy_ops` | https://github.com/Viralefy/viralefy_ops | Installer destrutivo + systemd + Caddy |
| `viralefy_api` | https://github.com/Viralefy/viralefy_api | API Go (DDD em camadas) |
| `viralefy_front` | https://github.com/Viralefy/viralefy_front | Loja Next.js (67 subsites, i18n) |
| `viralefy_backoffice` | https://github.com/Viralefy/viralefy_backoffice | Backoffice Next.js |
| `viralefy_archive` | https://github.com/Viralefy/viralefy_archive | Diretrizes + brand + contexto (este repo) |

Autor dos commits: `Viralefy <dev@viralefy.local>` + `Co-Authored-By: Claude Opus 4.7 (1M context)`.
Convenção: **Conventional Commits**. Trunk-based: commits direto na `main` (em ambiente solo).

---

## 5. Stack e arquitetura

### 5.1 Camadas DDD (API Go)

```
internal/
├── domain/          # entities + repository interfaces; SEM imports de framework/IO
├── application/     # services (use cases), DTOs; depende só de domain
├── infrastructure/  # postgres repos, http clients externos (Resend, Woovi, Heleket); depende de domain + application
└── interface/       # http handlers + router (chi)
cmd/api/main.go      # wiring de tudo
```

- pgx/v5 para Postgres (pool)
- go-chi/chi/v5 para HTTP + middleware
- golang-jwt/jwt/v5 (HS256 — débito pra trocar pra RS256 em prod real, §14 diretrizes)
- golang.org/x/crypto/bcrypt (cost 12)
- html/template + net/smtp + http.Client para integrações

### 5.2 Front/Backoffice (Next.js 15 App Router)

- Server components + client components (`"use client"` em interativos)
- Context `Providers.tsx` segura moeda selecionada + sessão (localStorage)
- `lib/api.ts` é o cliente HTTP único; `lib/auth.ts` cuida da sessão
- 67 subsites por país em `[country]/page.tsx` (force-dynamic, JSON-LD inline, hreflang completo)

### 5.3 Tooling externo

- **Caddy 2.11** — TLS automático, headers de segurança (HSTS, X-Content-Type, COOP, frame-ancestors deny no backoffice)
- **Resend** (HTTP API) — provedor de e-mail; SMTP fallback compilado mas inativo
- **Woovi** — PIX, gateway inativo até admin colocar `app_id` em `gateway.config`
- **Heleket** — cripto (USDT/BTC), gateway inativo até `merchant_id` + `api_key`

---

## 6. Schema do banco (migrations aplicadas)

Migrations em `viralefy_api/internal/infrastructure/persistence/postgres/migrations/`,
rodadas pelo binário no startup (idempotentes com `IF NOT EXISTS` / `ON CONFLICT`).

| # | Migration | O que adiciona |
|---|---|---|
| 001 | `001_init.up.sql` | `users`, `plans`, `orders`, `payment_gateways`, `admins` (esquema base do MVP) |
| 002 | `002_features.up.sql` | `categories`, `currencies`, `plans.category`, multi-moeda em orders |
| 003 | `003_plan_prices.up.sql` | `plan_prices` (preço manual por moeda) |
| 004 | `004_rbac.up.sql` | `roles`, `role_permissions`, `admins.role` |
| 005 | `005_payment.up.sql` | `orders.payment_url`, `orders.payment_extra` JSONB |
| 006 | `006_helpdesk.up.sql` | `tickets`, `ticket_messages` |
| 007 | `007_profiles_credits.up.sql` | `profiles`, `plans.{platform,target_type}`, `orders.{profile_id,publication_url,payment_method,credits_used_cents}`, `credit_accounts`, `credit_transactions` (ledger), `invoices` |

### 6.1 Tabelas centrais (estado atual em prod)

- **users**: id, email, name, instagram (legacy/vazio), password_hash, created_at. RegisterInput NÃO pede mais @instagram.
- **profiles** (007): user_id + platform (`instagram`|`tiktok`) + handle + display_name + verified. Unique (user_id, platform, handle).
- **plans**: id, name, description, category, **platform** (`instagram`|`tiktok`), **target_type** (`profile`|`publication`), followers_qty, price_cents, currency=BRL, active, sort_order. `prices` vem por LEFT JOIN agregado em `plan_prices` (currency_code → amount string).
- **orders**: id, user_id, plan_id, status (`pending`|`paid`|`failed`|`cancelled`), amount_cents (BRL canônico), display/settlement currencies+amounts, gateway_id, external_ref, payment_url, payment_extra JSONB, **profile_id** | **publication_url** (alvo), **payment_method** (`gateway`|`credits`), **credits_used_cents**.
- **invoices** (007): igual a orders mas só pra recarga de créditos. Status `pending`|`paid`|`failed`|`cancelled` + `paid_at`.
- **credit_accounts** (007): user_id PK, balance_cents (int64, BRL cents).
- **credit_transactions** (007): ledger **imutável** (só INSERT). type (`recharge`|`spend`|`refund`|`adjustment`), `amount_cents` (signed: + entrada, − saída), `balance_after_cents` (snapshot pra auditoria), `order_id?`, `invoice_id?`, description, metadata JSONB. Invariante: `SUM(amount_cents) = credit_accounts.balance_cents`.
- **categories**: 10 categorias (`seguidores`, `engajamento`, `visualizacoes`, `servicos`, `curtidas`, `comentarios`, `compartilhamentos`, `salvamentos`, `reels`, `stories`).
- **currencies**: BRL, USD, EUR, BTC, USDT. `rate` (unidades por 1 BRL, baseline pra fallback), `display_enabled`, `settlement_code` (USD→USDT, demais self).
- **payment_gateways**: id, name, provider (`manual_pix`|`woovi`|`heleket`), active, config JSONB.
- **tickets** (006) + **ticket_messages** (006): status `open`|`pending`|`resolved`|`closed`; priority `low|normal|high|urgent`; author_type `user|admin`.
- **roles** + **role_permissions** + **admins.role** (004).

### 6.2 Atomicidade do ledger

`CreditRepo.Apply` faz tudo em uma transação Postgres:
1. `INSERT credit_accounts ON CONFLICT DO NOTHING` (garante existência)
2. `SELECT balance_cents FROM credit_accounts WHERE user_id=$1 FOR UPDATE` (lock pessimista)
3. Compute newBalance = oldBalance + amount_cents (signed)
4. `if newBalance < 0`: aborta com `ErrInvalidInput` (saldo nunca fica negativo)
5. `INSERT credit_transactions` com `balance_after_cents = newBalance`
6. `UPDATE credit_accounts SET balance_cents = newBalance`
7. `COMMIT`

---

## 7. RBAC — papéis e permissões

Permissões em `domain/authz.go`:

```
plans:read|write, gateways:read|write, currencies:read|write,
orders:read, tickets:read|write, admins:manage
```

Papéis (seed em `seedRoles`):

| Papel | Permissões |
|---|---|
| **superadmin** | TODAS (bypass via `Principal.Can` quando `role == "superadmin"`) |
| **manager** | plans:rw, gateways:rw, currencies:rw, orders:read, tickets:rw |
| **support** | plans:r, gateways:r, currencies:r, orders:read, tickets:rw |
| **viewer** | plans:r, gateways:r, currencies:r, orders:read, tickets:r |

JWT admin carrega `typ:"admin"` + `role:"<code>"`. Permissões são **sempre
recarregadas do DB** por request (nunca confiamos no JWT pra perms).
JWT user carrega `role:"user"`. AdminAuth exige `typ:"admin"`, UserAuth exige
`role:"user"` — cross-role bloqueado.

ABAC implementado em `application/abac.go`: mudança de taxa de câmbio > 25%
exige `superadmin` (avaliado no `AdminUpdateCurrency`).

---

## 8. Features implementadas (estado atual)

### 8.1 Loja (viralefy_front)

- **67 subsites por país** em `/[country]` (37 SEPA + 30 Américas), cada um com:
  - hreflang completo (66 alternates + x-default)
  - JSON-LD: Organization, WebSite, WebPage (inLanguage), BreadcrumbList, Service+AggregateOffer+Offer
  - `<article lang>` semântico, `<nav aria-label="Breadcrumb">`, canonical, OG, Twitter card
- **Variante A/B `/v2/[country]`** — layout calculadora (slider de quantidade + tabela comparativa), `noindex` com canonical pra v1
- **Multi-moeda no header** — selector populado de `/v1/currencies`, persiste em localStorage
- **Autocadastro no checkout** — gera senha forte (crypto/rand), envia via e-mail HTML branded
- **Login/registro de usuário** — registro sem `@` agora (apenas nome+e-mail+senha)
- **`/account`** — cards de Perfis, Créditos, Suporte + histórico de compras
- **`/account/profiles`** — CRUD de perfis IG/TikTok com validação de handle
- **`/account/credits`** — saldo, presets de recarga (R$50–2000), ledger completo
- **Tickets de suporte** (`/tickets`, `/tickets/new`, `/tickets/[id]`)
- **404 customizado** em escopo com mercados sugeridos
- **Redirects 308** das URLs antigas (`/pt/seguidores-brasileiros` → `/br`)
- **Logo SVG-like PNG** em `/logo.png` (42 KB, 2471×704 transparente)
- **CheckoutModal v3**: detecta `plan.target_type`, mostra selector de perfil (logado) ou input de URL de publicação; opção "pagar com créditos" quando saldo cobre o preço

### 8.2 Backoffice (viralefy_backoffice)

Sidebar: Pedidos · Clientes · Serviços · Moedas · Gateways · Recargas · Suporte

- **`/dashboard`** — pedidos com botão "Marcar pago" em pendings (gating `admins:manage`)
- **`/users`** — lista de clientes com saldo, busca por nome/email
- **`/users/[id]`** — detalhe completo (saldo, perfis, ledger paginado, form de ajuste manual com Δ e descrição)
- **`/plans`** — CRUD com categoria + preço por moeda (criar + editar). Gating `plans:write`.
- **`/currencies`** — edita rate/display/settlement de cada moeda
- **`/gateways`** — select de provider (manual_pix/woovi/heleket) com config JSON livre
- **`/invoices`** — recargas filtradas por status, botão "Marcar paga" (gating `admins:manage`) dispara CreditService.Recharge
- **`/tickets`** + **`/tickets/[id]`** — fila com filtros, thread, alterar status/priority, responder (notifica cliente por e-mail)

### 8.3 API (viralefy_api) — rotas

Públicas:
```
GET  /health, /ready
GET  /v1/plans, /v1/categories, /v1/currencies
POST /v1/checkout              # OptionalUserAuth: aceita token (créditos/perfis) ou anônimo (autocadastro)
POST /v1/auth/login            # admin
POST /v1/auth/user/{register,login}
POST /v1/webhooks/woovi        # assinatura HMAC-SHA256 verificada no handler
POST /v1/webhooks/heleket      # assinatura md5(base64(body sem sign)+api_key)
```

User auth (`/v1/me`):
```
GET    /orders
GET    /profiles, POST /profiles, DELETE /profiles/{id}
GET    /credits, GET /transactions, POST /recharge, GET /invoices
GET    /tickets, POST /tickets, GET /tickets/{id}, POST /tickets/{id}/messages
```

Admin (`/v1/admin`, com RBAC per-route):
```
GET    /me                                  # qualquer admin
GET    /roles                               # PermAdminsManage
GET    /plans      (PermPlansRead)
POST   /plans      (PermPlansWrite)
PUT    /plans/{id} (PermPlansWrite)
DELETE /plans/{id} (PermPlansWrite)
GET    /gateways   (PermGatewaysRead)
POST   /gateways   (PermGatewaysWrite)
PUT/DELETE /gateways/{id}
GET    /orders     (PermOrdersRead)
POST   /orders/{id}/mark-paid          (PermAdminsManage)  # via PaymentReceiver, idempotente
GET    /currencies (PermCurrenciesRead)
PUT    /currencies/{code} (PermCurrenciesWrite) [ABAC: >25% exige superadmin]
GET    /tickets, /tickets/{id} (PermTicketsRead)
POST   /tickets/{id}/messages, PATCH /tickets/{id} (PermTicketsWrite)
GET    /invoices            (PermOrdersRead)
POST   /invoices/{id}/mark-paid (PermAdminsManage)  # dispara CreditService.Recharge
GET    /users, /users/{id} (PermOrdersRead)
POST   /users/{id}/credits/adjust (PermAdminsManage)
```

### 8.4 Validador (`application/validate.go`)

Server-side, primeira defesa pra evitar pedido para a plataforma errada:

```go
ValidateHandle(domain.Platform, handle string) error
ValidatePublicationURL(domain.Platform, url string) error
NormalizeHandle(s string) string  // remove @, trim, lowercase
```

Regex:
- IG handle: `^[A-Za-z0-9](?:[A-Za-z0-9_.]{0,28}[A-Za-z0-9])?$` (1–30 chars)
- TikTok handle: `^[A-Za-z0-9_.]{2,24}$`
- IG URL: `https?://(www\.)?instagram\.com/(p|reel|tv)/[A-Za-z0-9_-]+/?(\?.*)?$`
- TikTok URL: `https?://(www\.|m\.)?tiktok\.com/@[^/]+/video/\d+/?(\?.*)?$` ou `vm.tiktok.com/<id>`

Aplicado em `ProfileService.Add` e `CheckoutService.resolveTarget`.

### 8.5 E-mails HTML (`application/email_template.go`)

Templates branded em `html/template`:
- `BuildCheckoutEmail` — pedido recebido com QR PIX/copia-cola, ou carteira cripto, ou pix_key manual; se `account_created` mostra credenciais; gradient header com logo
- `BuildTicketReplyEmail` — notificação quando admin responde ticket

URL do logo: `{SITE_URL}/logo.png` (derivado de `cfg.SiteURL`).
Fallback text/plain pra clientes sem HTML.

### 8.6 Catálogo de planos seeded (114 planos)

- **Instagram**: 63 profile + 30 publication (seguidores 100–1M, curtidas, comentários, compartilhamentos, salvamentos, reels, stories, visualizações legacy, engajamento combinado)
- **TikTok**: 8 profile + 13 publication (seguidores 500–1M, curtidas, views, comments, shares)
- **Serviços** (consultoria): auditoria, gestão mensal, lançamento de produto

Seed é idempotente por `(name, category)`. Acrescentar planos novos: adiciona entrada na lista de `seedPlans` em `viralefy_api/internal/infrastructure/persistence/postgres/seed.go` e roda `viralefy-update` — preço manual editado no admin não é destruído.

### 8.7 Multi-moeda (preço manual)

- `plan_prices(plan_id, currency_code, amount TEXT)` — fonte da verdade
- `CurrencyService.QuoteForPlan(prices, brlCents, displayCode)` resolve `displayAmount` (do mapa manual ou fallback BRL*rate) e `settlementAmount` (mesma lógica pra `display.SettlementCode`)
- Regra USD: `display_enabled=true`, `settlement_code=USDT` → exibe `$` mas cobra USDT. USDT é display-disabled mas usado como settlement.

### 8.8 Pagamento

Roteamento por moeda de liquidação (`CheckoutService.pickGateway`):
- BRL → Woovi (PIX) → fallback `manual_pix`
- USDT/BTC → Heleket (cripto) → fallback default ativo
- Outros → default ativo

`PaymentRegistry` no `application/payment.go` indexa providers; `infrastructure/external/payment/{woovi,heleket,manual}.go` são adapters HTTP/no-op.

**Webhooks** (`infrastructure/external/payment/webhooks.go`):
- Woovi: `VerifyWooviWebhook(body, x-webhook-signature, secret)` via HMAC-SHA256 base64
- Heleket: `VerifyHeleketWebhook(body, api_key)` via md5(base64(body sem sign)+api_key)
- Dispatcher: `application.PaymentReceiver.ConfirmByExternalRef` — acha invoice OU order via `GetByExternalRef`, marca paga (idempotente). Invoice paga dispara `CreditService.Recharge`.

Status atual em prod: **Woovi e Heleket inactive** (sem app_id/merchant_id reais). `manual_pix` é o fallback ativo. Pra ativar: backoffice → Gateways → editar com credenciais reais + webhook_secret (Woovi) e ativar.

---

## 9. Diretrizes (resumo do que importa)

`viralefy_archive/diretrizes.md` v4.0 é a fonte normativa. Pontos críticos:

- **MUST**: separação de camadas (domain/application/infrastructure/interface), inversão de dependência (domain não conhece infra), uso de pgx para Postgres, JWT RS256/EdDSA em prod (HOJE estamos em HS256 — débito conhecido), CORS específico por origem
- **MUST observability**: logs JSON estruturados com trace_id/correlation_id; nunca logar senhas, tokens, PII. RED por endpoint, USE pra infra, OTel para tracing
- **MUST auditoria**: operações sensíveis em trilha append-only (parcialmente atendido via `credit_transactions`)
- **MUST testes**: 80% domain / 70% application / 40% infra / 60% global (HOJE: ~0% — débito)
- **MUST cobertura crítica**: auth, pagamento, autorização, multi-tenancy (multi-tenancy não aplicável aqui)
- Cada decisão arquitetural relevante vira **ADR** em `docs/adr/` do serviço afetado

---

## 10. Comandos rápidos

### 10.1 Deploy (destrutivo)

```bash
# Pela primeira vez numa máquina nova:
curl -fsSL https://raw.githubusercontent.com/Viralefy/viralefy_ops/main/bin/bootstrap.sh \
  | sudo RESEND_API_KEY=re_xxx \
         DOMAIN_FRONT=viralefy.com \
         DOMAIN_BACKOFFICE=admin.viralefy.com \
         DOMAIN_API=api.viralefy.com \
         CADDY_EMAIL=ops@viralefy.com \
         bash

# Update (após git push origin main):
sudo viralefy-update          # interativo, pede confirmação
sudo viralefy-update --yes    # CI/scripts
```

O update faz `rm -rf /viralefy/{api,front,backoffice,ops,archive}` → reclone → rebuild → restart. `/etc/viralefy/.env` e Postgres são preservados. O CLI mora em `/usr/local/sbin/` (fora de `/viralefy/`) então sobrevive ao próprio rm.

### 10.2 Diagnóstico

```bash
viralefy-status                       # systemd + portas + healthchecks (loopback e públicos)
viralefy-logs api -n 200              # journalctl -u viralefy-api
viralefy-logs caddy -f                # tail Caddy
viralefy-logs all -f                  # todos
```

### 10.3 Localmente

```bash
# API:
cd viralefy_api
go build ./... && go vet ./...
DATABASE_URL='postgres://viralefy:viralefy@localhost:15432/viralefy?sslmode=disable' go run ./cmd/api

# Front/Backoffice:
cd viralefy_front && npm run dev   # porta 3000
cd viralefy_backoffice && npm run dev   # porta 3001

# Postgres local (a senha do role em dev é "viralefy"):
docker run -d --name viralefy_pg_test \
  -e POSTGRES_USER=viralefy -e POSTGRES_PASSWORD=viralefy -e POSTGRES_DB=viralefy \
  -p 15432:5432 postgres:16-alpine

# Mailpit para testar e-mails sem Resend:
docker run -d --name viralefy_mailpit -p 18025:8025 -p 11025:1025 axllent/mailpit
# UI em http://localhost:18025
```

### 10.4 Hash bcrypt manual (criar admin)

```bash
cat > /tmp/hash.go <<'GO'
package main
import ("fmt"; "os"; "golang.org/x/crypto/bcrypt")
func main(){ h,_:=bcrypt.GenerateFromPassword([]byte(os.Args[1]),12); fmt.Print(string(h)) }
GO
cd viralefy_api && go run /tmp/hash.go "MinhaSenh@123"
```

⚠️ **NUNCA** passe o hash via `psql -tAc "$(cat ...)"` — bash re-expande `$2a$12$` e trunca. Use `psql -f arquivo.sql` direto.

---

## 11. Débitos conhecidos (ordem de prioridade)

| Prioridade | Item | Onde está |
|---|---|---|
| 🔴 alta | **Rotacionar chave SSH** (colada em chat) | servidor |
| 🔴 alta | **Rotacionar Resend API key** (colada em chat) | painel Resend + .env |
| 🟡 média | Email de confirmação quando webhook marca pagamento | `CheckoutService.sendCheckoutEmail` ou novo "OrderPaidEmail" disparado de `PaymentReceiver.ConfirmByExternalRef` |
| 🟡 média | Backup do Postgres (pg_dump diário + retenção 14d) | systemd timer no `viralefy_ops` |
| 🟡 média | CI/CD com GitHub Actions | `.github/workflows/deploy.yml` em cada repo SSHando + viralefy-update |
| 🟡 média | Webhook → e-mail "pedido confirmado" | hook em PaymentReceiver |
| 🟢 baixa | JWT RS256 em vez de HS256 (§14 diretrizes) | trocar `jwt.SigningMethodHS256` + key pair em config |
| 🟢 baixa | Cobertura de testes (≥60% global, ≥80% domain) | criar `tests/` em cada camada |
| 🟢 baixa | Outbox pattern p/ checkout (DB + email não atômicos) | `domain/outbox.go` + worker |
| 🟢 baixa | Observabilidade Grafana/Loki/Tempo (§16) | install no `viralefy_ops` + OTel SDK no API |
| 🟢 baixa | Float64 → big.Rat/decimal pra cálculos de câmbio | `currency_service.go` |
| 🟢 baixa | Admin seed `admin@viralefy.local` ainda existe em prod | DELETE manual via SQL |
| 🟢 baixa | Front: localizar `CheckoutModal` nos 6+ idiomas | hoje só PT |

---

## 12. Quirks e armadilhas conhecidas

- **`pkill -f '/tmp/viralefy-api'`** mata o próprio shell em scripts que contêm essa string. Use `fuser -k 8080/tcp`.
- **Debian 13 não tem `postgresql-16`** no apt — o installer faz fallback para `postgresql` (PG 17). Comportamento esperado.
- **NextJS 15** parâmetros de rota são `Promise<Params>` — sempre `await`.
- **`html/template` em e-mail** escapa por padrão; o template usa estruturas HTML inline (table-based layout) por compat com clientes de e-mail antigos.
- **`gofmt`** roda automaticamente nos edits e reformata structs (campos ficam alinhados); diagnósticos da IDE podem aparecer defasados entre edits — confie no `go build`/`go vet` em vez disso.
- **`Edit`/`Write` exigem `Read` prévio do arquivo na mesma sessão**. Se o arquivo foi criado nessa sessão por `Write`, a próxima `Edit` precisa de `Read` antes (depende do estado interno do harness — sempre faça Read se o Edit falhar).
- **Resend test mode** só entrega pra `viralefy@gmail.com`. Outros destinatários retornam 403 com mensagem clara. Pra ativar pra qualquer cliente: verifique um domínio em https://resend.com/domains e troque `RESEND_FROM` no `.env`.
- **Caddyfile usa `{$VAR}`** que substitui de `EnvironmentFile`. Mudar domínio = editar `.env` + `systemctl restart caddy` (ou `viralefy-update`).

---

## 13. Próximos passos sugeridos (não vinculantes)

1. Configurar Woovi e Heleket reais via backoffice (Gateways) — webhooks já estão prontos pra receber
2. **Email de confirmação automático** quando webhook marca pagamento (PaymentReceiver hook)
3. Backup do Postgres + restore documentado
4. ADRs para decisões maiores (multi-currency, ledger, RBAC) — `viralefy_archive/adr/`
5. Cobertura de testes mínima nos caminhos críticos (checkout, ledger Apply, validador)
6. CI/CD que dispara `viralefy-update` por SSH ao push na `main`

---

## 14. Como ler este contexto

- Para retomar trabalho: leia §2 (acesso), §6 (schema), §8 (features) e §10 (comandos)
- Para mudanças arquiteturais: leia `diretrizes.md` v4.0 primeiro
- Para entender o estado de cada feature: o "Resumo final" do último PR/commit em cada repo é ground truth (use `gh pr list`/`git log --oneline`)
- Para depurar produção: `viralefy-logs <serviço> -n 200 --no-pager` via SSH
