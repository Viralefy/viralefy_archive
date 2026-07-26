# Viralefy — CONTEXT.md (snapshot atual)

**Última atualização:** 2026-07-24 (front: ISR real via segmento `[locale]` + CSP estática — todas as landing pages orgânicas/pagas agora `x-nextjs-cache: HIT`; ver `task/2026-07-24-front-isr-organico-pago.md`, ADR-0015/0016. Branch `perf/front-locale-isr`.)

Este arquivo é o "leia primeiro" pra qualquer próxima sessão. Estado
factual sem narrativa.

---

## Acesso rápido

```bash
# SSH
awk '/BEGIN OPENSSH/,/END OPENSSH/' /media/sonne/Archives/projects/viralefy/credentials > /tmp/vf-ssh.key && chmod 600 /tmp/vf-ssh.key
ssh -i /tmp/vf-ssh.key root@62.238.41.231

# Health check
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-smoke'
```

**Admin (superadmin)**: `viralefy@gmail.com` / `VfIULsiPGXKZGjGfu2yn!`
2FA required — Google Authenticator.

**Postgres password**: `/etc/viralefy/.env DATABASE_URL`

---

## Arquitetura PHASE-9 (microserviços)

```
        www.viralefy.com (front Next.js :3000)
        admin.viralefy.com (backoffice Next.js :3001)
        auth.viralefy.com (UI login + /v1/auth/* + JWKS)
        api.viralefy.com (storefront + /v1/me/* + /v1/admin/*)
                │
                ▼
          Caddy + Coraza WAF (OWASP CRS 4.10)
                │
                ▼
          viralefy-dispatcher (Rust :8090)
                │
       ┌────────┼────────────────┐
       ▼        ▼                ▼
    core    payments         sender
   (:8084)  (:8081)          (:8082)
       │
       ▼
   viralefy-auth (:8083) — JWT mint, dual-sign RS256
       │
       ▼
   Postgres viralefy (15432)
```

10 repos:
- `viralefy_api` (legacy, STOPPED em soak)
- `viralefy_api_rust` (dispatcher)
- `viralefy_core` (domain Go)
- `viralefy_auth` (identity Go)
- `viralefy_payments` (Go)
- `viralefy_sender` (Go)
- `viralefy_front` (Next.js storefront)
- `viralefy_backoffice` (Next.js admin)
- `viralefy_ops` (Caddyfile, scripts, configs)
- `viralefy_archive` (docs — você está aqui)

---

## Auth — identidade unificada (2026-06-11)

- **Login UI única** em `auth.viralefy.com/login` com split-screen
  (2/3 brand pane + 1/3 form). www e admin redirecionam pra cá
- **Backend unificado**: `/v1/auth/user/login` aceita user OU admin
  (fallback de tabela). Mesmo token shape, role no JWT
- **SSO callback**: `window.location.replace(return_to#fragment)` com
  session no fragment URL → `/sso/callback` em cada subdomínio consome
  e persiste no localStorage local
- **2FA**: TOTP RFC 6238 + backup codes. Admin obrigatório, user opcional
- **JWT**: RS256, dual-sign, hot-set revogação via Postgres LISTEN/NOTIFY
- **`TWOFA_ENCRYPTION_KEY`**: hex 64 chars (32 bytes decoded). Tanto
  core quanto auth fazem `parse2FAKey()` agora

---

## Tracking observability (admin panel)

Stack:
- Client (front): captura utm, fbclid, gclid, referrer, landing_url,
  language, timezone, IP, UA, pageviews, modal events
- Backend (core): `user_events` (append-only) + `user_journeys` (1:1 agregado)
- Admin UI:
  - `/analytics/visitors` — todos visitors paginados
  - `/analytics/visitors/{vid}` — drill-down completo
  - `/users/{id}` — seção "Tracking journey"
  - `/orders/{id}` — seção "Attribution"

---

## Admin protections (2026-06-11)

### Tier de role
- **superadmin** — acesso total
- **manager / support / viewer** — admins normais com PermAdminsManage
- Superadmin é **INVISÍVEL** pra non-superadmin (camuflado como `manager`)

### Soft + Hard delete (3 entidades)
```
DELETE /v1/admin/{orders,invoices,users}/{id}            soft  (admins:manage)
DELETE /v1/admin/{orders,invoices,users}/{id}/hard       hard  (RequireSuperadmin)
POST   /v1/admin/{orders,invoices,users}/{id}/restore    undo  (RequireSuperadmin)
POST   /v1/admin/{orders,invoices,users}/bulk/soft-delete bulk  (admins:manage, max 200 ids)
```

Schema: `deleted_at + deleted_by_admin_id + delete_reason` em orders,
invoices, users.

### Trash + Honeypot pages (superadmin only)
- `/trash` — items soft-deletados agregados em 3 tabs
- `/honeypot` — log de tentativas de admin malicioso em superadmin
  com Top Suspects + timeline
- Regular admin lists filtram `deleted_at IS NULL` → workflow do
  dia-a-dia limpo

### Camuflagem do superadmin
- Lista de admins mascarra `role=superadmin` → `manager`
- Tentativas de update_role/delete em superadmin viram **fake success**
  (200 OK com view falsa, DB intocado, audit log em `admin_honeypot_log`)
- Shadow-delete: target some da lista DAQUELE actor depois
- UI removeu todo hint de role mais alta

---

## Coraza WAF — exclusões ativas

`coraza-crs-exclusions.conf`:

| Rule | Por que |
|---|---|
| 900100 | Loopback bypass |
| 900200/201 | Stripe webhook (signature + body) |
| 900300 | /v1/me/reviews (markdown body+title) |
| 900601 | /v1/auth/* password (libinjection FPs) |
| 900700/710/720 | PUT/PATCH/DELETE + paranoia=2 + body parser |
| 900800/801/802 | RFI 931xxx em /v1/checkout, /v1/auth/, /v1/me/ |
| 900920 | 932240 (RCE) + 942430-442 (SQL char/comment) + 920230 (multi URL enc) — todos accuracy=0 |
| 900930 | 931xxx em ARGS:return_to (SSO callback) |

**Importante**:
- `systemctl reload caddy` NÃO recarrega ruleset Coraza —
  use `systemctl restart caddy` quando mexer em `coraza-*.conf`.
- Path correto do exclusions na máquina: `/etc/caddy/coraza/coraza-crs-exclusions.conf`
  (subpasta `coraza/` — Caddyfile faz `Include` desse path). NÃO deployar
  na raiz `/etc/caddy/` — fica ignorado e o restart "funciona" silenciosamente.

---

## Env vars críticas (`/etc/viralefy/.env`)

```bash
NEXT_PUBLIC_API_URL=https://api.viralefy.com
NEXT_PUBLIC_AUTH_URL=https://auth.viralefy.com      # API host
NEXT_PUBLIC_AUTH_UI_URL=https://auth.viralefy.com   # UI host
NEXT_PUBLIC_SITE_URL=https://www.viralefy.com
NEXT_PUBLIC_TURNSTILE_SITE_KEY=0x4AAAAAADbwrbYvD2Gb-ngm
NEXT_PUBLIC_WHATSAPP_NUMBER=...
INDEXNOW_KEY=adcfcb87889076210f395f754a9ad0c3
INDEXNOW_SECRET=10e251e0bc708f4f1f7e0500e0e80850edb0262d6a91357d
CORS_ORIGINS=https://viralefy.com,https://www.viralefy.com,https://admin.viralefy.com
TWOFA_ENCRYPTION_KEY=908306a8c491677121d626f2d2b4a93a10ec9369c2999b6e89e7f5ab137e70e9
```

---

## Schema DB

Migrations aplicadas: **000 → 046**

Últimas (2026-06-11):
- **045** `admin_softdelete` — soft delete em orders/invoices/users
- **046** `admin_honeypot` — tabela `admin_honeypot_log`

Ambas com sha256 checksum gravado em `schema_migrations`.

---

## Observability

- Prometheus + Grafana em `obs.viralefy.com`
- 6 dashboards (revenue, payments, behavior, reliability, slo, phase9)
- 11 SLOs + 26 alerting rules
- Loki + Tempo + Alloy + Alertmanager
- Test Kit §22: `viralefy-test [smoke|pentest|security|hardening|authz|integration|chaos|simulated|unit|all]`

---

## Day-to-day ops

```bash
# Deploy front + backoffice
viralefy-update front backoffice
# (falha no step de migrations por env perm, mas swap binário acontece antes —
#  workaround: systemctl restart manualmente após)

# Build + deploy binário Go manual (auth ou core)
cd <repo> && go build -o /tmp/bin ./cmd/...
scp /tmp/bin root@62.238.41.231:/tmp/bin-new
ssh root@62.238.41.231 'mv /tmp/bin-new /usr/local/sbin/viralefy-<svc> && systemctl restart viralefy-<svc>'

# Smoke
viralefy-smoke
viralefy-test smoke    # 9 scripts (mais completo)
viralefy-test pentest  # 27 scripts

# Restart services
systemctl restart viralefy-{core,auth,dispatcher,payments,sender,front,backoffice}

# Caddyfile
systemctl reload caddy   # config simples
systemctl restart caddy  # Coraza exclusions
```

---

## Repos no GitHub

| Repo | URL |
|---|---|
| viralefy_api | https://github.com/Viralefy/viralefy_api |
| viralefy_api_rust | https://github.com/Viralefy/**viralefy_dispatcher** (pasta local ≠ nome do remote) |
| viralefy_core | https://github.com/Viralefy/viralefy_core |
| viralefy_auth | https://github.com/Viralefy/viralefy_auth |
| viralefy_payments | https://github.com/Viralefy/viralefy_payments |
| viralefy_sender | https://github.com/Viralefy/viralefy_sender |
| viralefy_front | https://github.com/Viralefy/viralefy_front |
| viralefy_backoffice | https://github.com/Viralefy/viralefy_backoffice |
| viralefy_ops | https://github.com/Viralefy/viralefy_ops |
| viralefy_archive | https://github.com/Viralefy/viralefy_archive |

---

## Índice de funcionalidades (§39) — consulte ANTES de criar algo

Gerado por `viralefy_ops/bin/viralefy-index` a partir do código dos 10 repos.
Regenere e commite junto com a mudança — o CI deste repo falha se `index/` divergir.

- `index/MAPA.md` — grafo de serviços, pontos de entrada e saídas por repo
- `index/INDEX_GLOBAL.md` — repos, pastas, contratos, cobertura N/M por serviço
- `index/INDEX_FUNCTIONS_<serviço>.md` — uma linha por função (3728 no total)

Estado em 2026-07-21: **M == N nos 10 serviços**; dívida de doc-comment em 2286
das 3728 funções (61%) — gate disponível em `viralefy-index --strict-doc`.

---

## Estado do CI (2026-07-21)

Os 10 repos estavam vermelhos; foram destravados na sessão de 21/07:
gitleaks (action v2 passou a exigir licença paga em org → binário oficial),
pgx v5.7.4→5.9.2 (GO-2026-5004, SQL injection), Go 1.26.4→1.26.5 (GO-2026-5856),
sqlx `macros` removida no dispatcher (arrastava `rsa` vulnerável),
`npm ci --include=dev` nos jobs com `NODE_ENV=production`, shellcheck do ops.

---

## Sessão 2026-07-26 — sweep de SEO orgânico + AIO (viralefy_front)

Continuação do ISR (ADR-0015/0016). Otimizado o orgânico sem mudar URL:
FAQPage nas money pages (country/slug) + HowTo no help procedural + Review nodes;
`dateModified` e sitemap `lastmod` estáveis (fim do frescor falso de `new Date()`
sob ISR); og:image restaurada em 7 landings tier-4 + `legal`; hreflang tier-4
honesto (EN-only → x-default+en); tier de planos des-orfanizado (links `<a>`
server-side); `/llms.txt` no formato llmstxt.org + `/feed.xml` RSS, ambos gerados;
OG route ISR 1h; guard de build p/ `NEXT_PUBLIC_SITE_URL`. 520 unit tests (13
novos), build verde, render conferido, índice §39 regenerado.
Detalhe: [ADR-0017](adr/0017-front-organic-seo-aio-sweep.md) +
[task](task/2026-07-26-front-organico-seo-aio-sweep.md). Branch `perf/front-locale-isr` (PR #1).

## Docs índice

- `INDEX.md` — mapa de todos os MDs do archive
- `CHECKLIST.md` — done + pending priorizado
- `SESSION-2026-06-11.md` — detalhes da sessão de 11/06 (esta janela)
- `diretrizes.md` — engineering guidelines v4.0
- `PHASE-9-ARCHITECTURE.md` — desenho do sistema atual
- `RUNBOOK-*.md` (11) — operação por área
- `adr/0001-0010-*.md` — decisões arquiteturais
