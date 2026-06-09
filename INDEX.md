# Viralefy — Índice de Contexto

Snapshot **2026-06-09 (PHASE-8 Wave 3 + sweep E2E + AbacatePay)**.
Documento canônico de "leia primeiro" pra qualquer próxima sessão.

---

## 1. Estado da plataforma (em 1 minuto)

Marketplace de engajamento Instagram/TikTok, 130 países × 47 idiomas × 15 categorias. USD/USDT canonical, multi-moeda display.

**Estágio**: prod live, smoke E2E PASS contra `api.viralefy.com`. 3 microservices Go + 2 Next.js + Postgres + Caddy + MinIO + observability stack rodando.

**Pagamento ativo**:
- **Stripe** rk_live_ funcional (gera `cs_live_…` reais)
- **Heleket** integração ativa (genera `new-pay.heleket.com/pay/…`)
- **manual_pix** ativo (pix_key fixa: `contato@viralefy.com`)
- **AbacatePay** integrado mas gateway não cadastrado em prod ainda
- Woovi inactive, manual_crypto disponível, manual_usdt deprecated

**Auth**: 2FA admin obrigatório + user opcional (TOTP RFC 6238 + 8 backup codes + AES-256-GCM at-rest).

**Conversão**: phone OU telegram obrigatório no register. Email "checkout_paid" + telegram bot quando configurado.

---

## 2. Acesso

| Recurso | URL | Credencial |
|---|---|---|
| Storefront | https://www.viralefy.com | — |
| Backoffice | https://admin.viralefy.com | `viralefy@gmail.com` / `VfIULsiPGXKZGjGfu2yn!` (superadmin, 2FA enrolled) |
| API | https://api.viralefy.com | Bearer RS256 |
| Observability | https://obs.viralefy.com | `admin` / `6FU6jXSmzJlrPSCBJ6JNprW5dqMYCO1l` |
| SSH | `root@62.238.41.231` | `credentials` arquivo (`awk '/BEGIN OPENSSH/,/END OPENSSH/'`) |
| Postgres | local na VPS | senha em `/etc/viralefy/.env` |
| GitHub | github.com/Viralefy | 7 repos públicos |

VPS: Debian 13 trixie · 8 cores · 16GB · única instância.

---

## 3. Arquitetura (PHASE-8)

```
INTERNET → Caddy
   ├── www → viralefy-front (Next 15, :3000)
   ├── admin → viralefy-backoffice (:3001)
   └── api → viralefy-api (:8080) ← orchestrator
            │
            ├── HTTP loopback → viralefy-payments (:8081)
            │   ├── /internal/v1/charge (chamado pelo monolith)
            │   ├── /internal/v1/methods (chamado pelo handler)
            │   └── /internal/v1/webhooks/{stripe,heleket,woovi,abacatepay}
            │       └── callback POST :8080/internal/v1/payment-confirmed
            │            (X-Internal-Token gate)
            │
            └── HTTP loopback → viralefy-sender (:8082)
                ├── /internal/v1/send (email + telegram + raw passthrough)
                └── outbox tick 30s + retry exponencial 30s→24h
```

Auth interno: `INTERNAL_SHARED_SECRET` (32 bytes hex) em todo `X-Internal-Token`. Loopback-only = primeira barreira.

Object storage: MinIO Docker `/var/lib/viralefy-storage/`, S3-compat (proofs bucket privado + public). R2-ready.

---

## 4. Repositórios (7)

| Repo | Função | Status atual |
|---|---|---|
| viralefy_api | Monolith orchestrator | `ff293ab + d0285b1` |
| viralefy_payments | Providers + webhooks | `0e9bebd` |
| viralefy_sender | Email + telegram + outbox | `d0285b1` |
| viralefy_front | Next.js storefront | `1e0fcb0` |
| viralefy_backoffice | Next.js admin panel | `30b81f5` |
| viralefy_ops | systemd + installer + Caddy + CLIs | `a35fa07` |
| viralefy_archive | docs + memory (este repo) | atualizado nesta sessão |

---

## 5. Documentos no archive

| Doc | Conteúdo |
|---|---|
| **[INDEX.md](INDEX.md)** | este arquivo — entry point |
| **[STATUS-CHECKLIST.md](STATUS-CHECKLIST.md)** | checklist extensivo de tudo done + pending |
| [CONTEXT.md](CONTEXT.md) | snapshot detalhado (33 migrations, schemas, crons, endpoints) |
| [ROADMAP.md](ROADMAP.md) | histórico de fases entregues (0-7) |
| [PHASE-7-PLAN.md](PHASE-7-PLAN.md) | plano da fase 7 (storage, 2FA, dashboards) |
| [PHASE-8-MICROSERVICES.md](PHASE-8-MICROSERVICES.md) | plano da fase 8 (carve-out micros) |
| [MICROSERVICES-OPS.md](MICROSERVICES-OPS.md) | runbook de ops dos 3 binários |
| [RUNBOOK.md](RUNBOOK.md) | playbook prod (incidents, restore drill, deploy) |
| [COMPLIANCE.md](COMPLIANCE.md) | notas legais (GDPR, LGPD, EU VAT) |
| [RECOMMENDATIONS.md](RECOMMENDATIONS.md) | referência histórica |
| [AGENTS.md](AGENTS.md) | instruções pra subagentes |
| [diretrizes.md](diretrizes.md) | técnicas + convenções |
| memory/ | auto-memory (symlinkada de `~/.claude/.../memory/`) |

---

## 6. Estado dos providers em prod (DB query)

```
heleket    active  USDT/USD/EUR/BTC  → Heleket
manual_pix active  BRL               → contato@viralefy.com
stripe     active  BRL/GBP/EUR/USD   → rk_live_ funcional
woovi      inactive BRL              → não configurado
```

AbacatePay: provider implementado (`viralefy_payments`), schema no backoffice, mas gateway row **não criado em prod**. Cliente precisa criar API key + cadastrar no `/gateways`.

---

## 7. Configurações em `/etc/viralefy/.env`

Variáveis críticas presentes em prod:
- `DATABASE_URL` · `JWT_SECRET` · `JWT_PRIVATE_KEY_PATH`
- `TWOFA_ENCRYPTION_KEY` (32 bytes hex)
- `INTERNAL_SHARED_SECRET` (microservices)
- `RESEND_API_KEY` · `RESEND_FROM=contato@viralefy.com`
- `TURNSTILE_SECRET_KEY` (anti-bot ativo)
- `STORAGE_ACCESS_KEY` / `STORAGE_SECRET_KEY` (MinIO)
- `PAYMENTS_INTERNAL_URL=http://127.0.0.1:8081`
- `SENDER_INTERNAL_URL=http://127.0.0.1:8082`

Variáveis opt-in pendentes (vazias):
- `SENTRY_DSN` / `NEXT_PUBLIC_SENTRY_DSN` (Sentry no-op)
- `TELEGRAM_BOT_TOKEN` / `TELEGRAM_ADMIN_CHAT_ID` (telegram channel no-op)
- `ADMIN_WEBHOOK_URL` (Slack/Discord no-op)

---

## 8. Operação do dia-a-dia

| Ação | Comando |
|---|---|
| Deploy | `ssh root@62.238.41.231 'viralefy-update --yes'` (zero-downtime, ~2 min, smoke automático) |
| Smoke health | `viralefy-smoke` |
| Status geral | `viralefy-status` |
| Logs API | `journalctl -u viralefy-api -f` |
| Logs payments | `journalctl -u viralefy-payments -f` |
| Logs sender | `journalctl -u viralefy-sender -f` |
| Restore Postgres | vide [RUNBOOK.md](RUNBOOK.md) (validated drill 2026-06-08) |

---

## 9. Pendências ativas (vide [STATUS-CHECKLIST.md](STATUS-CHECKLIST.md))

**Cliente precisa fornecer:**
- AbacatePay API key (`abc_live_…`) + webhook secret
- Telegram bot token (opcional)
- Sentry DSN (opcional)
- ADMIN_WEBHOOK_URL Slack/Discord (opcional)

**Engineering pendente:**
- Object storage proof URL refactor (base64 → MinIO key) parcial — multipart upload existe; migração de proofs antigos não
- Grafana contact points + 4 custom dashboards (PHASE-7 §7.4)
- Sentry source maps no CI
- Multi-vendor settlement model (decisão de produto)
- WhatsApp provider real (decisão Meta vs Twilio)

---

## 10. Recent session log (2026-06-09)

### Manhã
8 bugs encontrados e corrigidos:
1. Stripe checkout 422 (pay_currency ignored em multi-currency)
2. event_retention_cron 42703 (column name errado)
3. Caddy webhooks 404 (handle_path strip)
4. Caddyfile nunca syncava em deploy
5. paymentsclient ↔ payments envelope mismatch (500 em payment-methods)
6. Turnstile race (422 missing token na 1ª tentativa)
7. Email "checkout_paid" never sent (sender template required vs raw)
8. **`/internal/v1/*` exposto via Caddy** — bloqueado na borda (`ops 98b08ce`)

### Tarde — hardening + pendências fechadas
- E2E sweep externo: 62 PASS (rotas públicas + auth gates + webhooks + IDOR sem auth + RBAC sem auth + CORS + idempotência + rate-limit)
- ABAC/RBAC autenticado: **56/56 PASS** — 2 users seeded direto no DB + admin viewer + tokens RS256 mintados via `pyjwt`. Validou:
  - User A não acessa `/me/orders/{ORDER_B}` (404, sem leak)
  - User A não vê orders de B na lista
  - User A não pode revogar API key/profile de B
  - Token de user é rejeitado em `/admin/*` (401)
  - Token admin é rejeitado em `/me/*` (401)
  - Admin `viewer` tem `*:read`, é negado em `*:write`, `coupons:read`, `admins:manage` (403)
  - JWT forjado com `role=superadmin` (sig inválida) → 401
  - JWT `alg=none` attack → 401
  - JWT expirado → 401
- Contract tests inter-microservice (api↔payments↔sender): 6 testes novos no api + 4 no payments + 4 no sender — drift de tag/envelope falha CI nos 2 lados juntos. Cobre os 2 bugs históricos que vazaram QR/email
- Stripe reconcile cron (5min tick, 50 orders/batch) — polling de Stripe Sessions API pra orders pending > 10min cujo webhook caiu. `api 14fe8d7` em prod, log `stripe reconcile cron started` confirmado

Phase 8 entregue: 3 binários, loopback HTTP, internal token, callback `/payment-confirmed`, outbox + retry, Telegram bot integration, AbacatePay PIX dinâmico, contract tests, reconcile cron, defesa em profundidade na borda.

Próxima sessão: começar lendo `STATUS-CHECKLIST.md` pra ver pendências priorizadas. Pendências top: AbacatePay gateway row em prod (cliente fornece API key), Telegram bot ativar, Sentry DSN.
