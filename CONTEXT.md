# Viralefy — Contexto geral

Snapshot **2026-06-09** (Phase 8 Wave 3 — 3 binários: api+payments+sender via loopback HTTP).

---

## 1. TL;DR — o que é

Marketplace de engajamento Instagram/TikTok com cobertura 130 países × 47 idiomas × 15 categorias. USD/USDT canonical; display multi-moeda (BRL/EUR/BTC/USDT). Stack: Go (API) + Next.js 15 (front + backoffice) + Postgres + Caddy + observability (Grafana/Loki/Tempo/Prometheus/Alloy).

**Estágio**: HML/POC funcional, payment via Manual PIX (BRL ativo) + Manual Crypto (1 gateway = 1 network × asset; admin cadastra USDT TRC20/BSC/POL, BTC, LTC, etc.). Stripe Checkout Session disponível (cartão internacional, REST direta sem stripe-go). Heleket inactive (aguarda aprovação). Woovi inactive.

**Checkout (rev. 2026-06-08)**: 4 steps — (1) details (perfil/cupom), (2) método de pagamento com transparência charged≠settlement, (3) instruções (QR/wallet/Stripe URL) + upload de comprovante, (4) success. Avisos críticos de rede crypto destacados em vermelho.

**Memory**: persistido em `viralefy_archive/memory/` (symlink reverso de `~/.claude/.../memory/`). Auto-memory funciona transparente.

**Tráfego**: catalógo 126 plans, sitemap 47 idiomas × per-lang, drift 0, status `operational`.

---

## 2. Acesso

| Recurso | URL | Credencial |
|---|---|---|
| Storefront | https://www.viralefy.com | — |
| Backoffice | https://admin.viralefy.com | `viralefy@gmail.com` / `VfIULsiPGXKZGjGfu2yn!` (superadmin) |
| API | https://api.viralefy.com | Bearer token (RS256) |
| Observability | https://obs.viralefy.com | `admin` / `6FU6jXSmzJlrPSCBJ6JNprW5dqMYCO1l` |
| SSH | `root@62.238.41.231` | `/media/sonne/Archives/projects/viralefy/credentials` (extrair com `awk '/BEGIN OPENSSH/,/END OPENSSH/'`) |
| Postgres | `psql -U viralefy -h localhost -d viralefy` na VPS | senha em `/etc/viralefy/.env DATABASE_URL` |
| GitHub | https://github.com/Viralefy | 5 repos públicos (api, front, backoffice, ops, archive) |

VPS escalada 2026-06-08: **8 cores · 16GB RAM**.

---

## 3. Arquitetura

**Fase 8 (DONE Wave 1-3)**: monólito quebrado em 3 binários Go que falam HTTP/JSON em loopback.

```
INTERNET
   │
[Caddy] → www                                       → next.js front     (Next 15 App Router, :3000)
       → admin                                      → next.js backoffice (Next 15,            :3001)
       → api.viralefy.com/*                         → viralefy-api      (Go orchestrator,    :8080)
       │   ├── /v1/webhooks/{stripe,heleket,woovi} ─┐
       │                                            │
       │                                            ▼  (reverse_proxy)
       │                            viralefy-payments (Go, 127.0.0.1:8081)  — providers + charges
       │                                            ▲   POST /internal/v1/payment-confirmed
       │                            ┌───────────────┘   (X-Internal-Token)
       │                            ▼
       │                     viralefy-api  ────► viralefy-sender (Go, 127.0.0.1:8082) — email + Telegram
       │
       └── obs.viralefy.com                          → Grafana

PostgreSQL 17 single-tenant (compartilhado pelos 3 services — split de DB fica pra Fase 9)
Grafana / Loki / Tempo / Prometheus / Alloy / node-exporter
viralefy-backup.timer (daily 03:00 UTC, 7d+4w+6m retenção)
```

**Portas**:
| Porta | Service | Bind |
|---|---|---|
| 3000 | viralefy-front | 127.0.0.1 |
| 3001 | viralefy-backoffice | 127.0.0.1 |
| 8080 | viralefy-api (orchestrator) | 127.0.0.1 |
| 8081 | viralefy-payments | 127.0.0.1 (loopback-only) |
| 8082 | viralefy-sender | 127.0.0.1 (loopback-only) |

**Fluxo loopback**:
1. Cliente → Caddy → `viralefy-api`.
2. Para checkout: api faz `POST 127.0.0.1:8081/internal/v1/charge` (token shared).
3. Para email/telegram: api faz `POST 127.0.0.1:8082/internal/v1/send`.
4. Webhook Stripe/Heleket/Woovi: Caddy `reverse_proxy` direto pra `127.0.0.1:8081`. Após validar assinatura, payments chama de volta `POST 127.0.0.1:8080/internal/v1/payment-confirmed` com `X-Internal-Token: $INTERNAL_SHARED_SECRET`; api executa `MarkOrderPaid` (domínio do pedido permanece no monólito).

**Auth interna**: `INTERNAL_SHARED_SECRET` (32 bytes hex) em `/etc/viralefy/.env`, gerado pelo `installer/30-secrets.sh`. Middleware em payments e sender rejeita 401 sem o header. Defesa-em-profundidade — loopback é a primeira barreira.

**Migrations**:
- monólito: 015→035 (donas das tabelas core, incluindo `payment_gateways`, `orders.proof_*`, `stripe_events_processed`).
- payments: `001_payments_init` é **idempotente** — `CREATE TABLE IF NOT EXISTS payment_gateways` (standalone install), `ALTER TABLE ... ADD COLUMN IF NOT EXISTS accepted_currencies`, `CREATE TABLE IF NOT EXISTS stripe_events_processed`. Em prod (DB compartilhado) tudo vira no-op.
- sender: `001_sender_outbox` + `002_telegram_chats` — tabelas novas, exclusivas do sender.

**DDD 4-layer** em cada binário: domain ↔ application ↔ infrastructure ↔ interface.

**Front**: Server components por padrão; client components onde tem state (CheckoutModal, CategoryCardGrid). 47 i18n packs (`src/i18n/languages.ts`). 28 países × PPP (`country_ppp`). 28 países EU+GB × VAT (`tax_rates`).

---

## 4. Schema PostgreSQL (33 migrations consumidas, 015 → 033)

| # | Migration | Tabela / Mudança |
|---|---|---|
| 015 | Reviews | `reviews` |
| 016 | Email reputation | `email_events`, `email_reputation` |
| 017 | Coupons | `coupons`, `coupon_redemptions` |
| 018 | Orders abandonment | `orders.abandonment_email_sent_at` |
| 019 | Users notif_prefs | `users.notif_prefs JSONB` |
| 020 | User data | `user_deletion_requests`, `users.deleted_at` |
| 021 | Country PPP | `country_ppp` (28 países) |
| 022 | Referrals | `users.referral_code`, `users.referred_by_user_id`, `referral_rewards` |
| 023 | A/B experiments | `ab_experiments`, `ab_assignments`, `ab_events` |
| 024 | Fraud signals | `fraud_signals`, `fraud_blocks` |
| 025 | Refunds | `order_refunds`, `orders.refunded_usd_cents` |
| 026 | Subscriptions | `subscriptions`, `orders.subscription_id` |
| 027 | Tax rates | `tax_rates` (28 países EU+GB), `orders.tax_*` |
| 028 | User WhatsApp | `users.whatsapp_*` |
| 029 | Vendors | `vendors`, `plans.vendor_id` |
| 030 | API keys | `api_keys` |
| 031 | Target country | `orders.target_country_code` |
| 032 | Gateway currencies | `payment_gateways.accepted_currencies TEXT[]` |
| 033 | User events | `user_events`, `user_journeys` |

Próxima migration livre: **034**.

---

## 5. Pagamento — providers

| Provider | Status | Currencies | Como funciona |
|---|---|---|---|
| `manual_pix` | **active** (BRL) | `{BRL}` | Admin põe pix_key. Customer copia, paga, admin marca paid. |
| `manual_usdt` | available, customizar/ativar | `{USDT, USD}` default | Admin põe wallet_address + network (TRC20/ERC20/BEP20/Polygon/Solana) + memo opcional. Customer copia, paga, admin marca paid. |
| `heleket` | inactive (aguardando aprovação) | `{USDT, USD, EUR, BTC}` | Integração automática + webhook Svix |
| `woovi` | inactive | `{BRL}` | PIX automático via Woovi |

Validação no service: provider enum + accepted_currencies dedup/uppercase + bloqueia active sem currencies. Cascade lib (`providerDefaultCurrencies` em `gateway_service.go`).

---

## 6. Crons rodando

| Cron | Tick | O que faz |
|---|---|---|
| `viralefy-backup.timer` | diário 03:00 UTC | pg_dump + gzip + retenção |
| IdempotencyCleanupCron | 1h | Remove keys expirados |
| DeliveryCaptureCron | 15min | Snapshot 2ª fonte de verdade (24h pós-paid) |
| ReviewRequestCron | 1h | Email "how was your order?" 7d pós-paid |
| PlanPriceDriftCron | 1h | Métrica `viralefy_plan_price_drift_rows` |
| FraudVelocityCron | 5min | Agrega signals → fraud_signals |
| CartAbandonmentCron | 30min | Email "complete payment" 1-24h pós-pending |
| SubscriptionCron | 1h | Renovação mensal de subs |

---

## 7. Endpoints — superfície pública

```
GET    /health
GET    /ready
GET    /metrics                              # Prometheus
GET    /.well-known/jwks.json                # RS256

# /v1 público
GET    /v1/plans
GET    /v1/categories
GET    /v1/currencies
GET    /v1/country-ppp
GET    /v1/tax-rates
GET    /v1/status                            # overall + 3 services
POST   /v1/checkout                          # cupom + tax + target_country
POST   /v1/recovery-request
POST   /v1/coupons/validate
POST   /v1/ab/assign                         # rate-limited
POST   /v1/ab/track                          # rate-limited
POST   /v1/track                             # event behavior (MaxBytes 1MB)
GET    /v1/referrals/{code}/info
POST   /v1/webhooks/{woovi,heleket,resend}   # Svix sig pro Resend

# /v1/auth
POST   /v1/auth/login                        # admin (rate-limited 10/15min)
POST   /v1/auth/user/register                # rate-limited
POST   /v1/auth/user/login                   # rate-limited

# /v1/me (Bearer user)
GET    /v1/me/orders
GET    /v1/me/orders/{id}
GET    /v1/me/profiles | POST | DELETE
GET    /v1/me/credits | transactions | invoices
POST   /v1/me/recharge
GET    /v1/me/tickets | POST | replies
POST   /v1/me/reviews
GET    /v1/me/referral
GET    /v1/me/subscriptions | POST | DELETE
GET    /v1/me/notif-prefs | PUT
GET    /v1/me/whatsapp | PUT
GET    /v1/me/data/export
POST   /v1/me/data/deletion | DELETE
GET    /v1/me/api-keys | POST | DELETE
GET    /v1/me/journey

# /v1/admin (Bearer admin + RBAC)
POST   /v1/admin/me/become-customer          # cria shadow user + session
GET    /v1/admin/{plans,gateways,orders,tickets,users,coupons,fraud/signals,ab/experiments,vendors,...}
POST   /v1/admin/orders/{id}/refund
POST   /v1/admin/orders/{id}/mark-paid
PUT    /v1/admin/currencies/{code}

# /v2 B2B (X-API-Key)
GET    /v2/plans
GET    /v2/orders/{id}/status
```

---

## 8. Observabilidade

- Prometheus em `127.0.0.1:9090` com 11 alert rules em 6 grupos: `viralefy_uptime`, `viralefy_backup`, `viralefy_data_invariants`, `viralefy_payments`, `viralefy_security`, `viralefy_database`
- Grafana em `obs.viralefy.com` — datasources Prometheus + Loki + Tempo
- Loki captura logs estruturados JSON do API; alloy faz scrape
- node-exporter expõe textfile collector com métricas customizadas (`viralefy_backup_*`)
- Contact points no Grafana ainda vazios — alerta dispara mas não notifica até ser configurado

---

## 9. Segurança

- **JWT RS256 dual-sign** com kill-switch (`LEGACY_HS256_DISABLED`); JWKS público
- **Login rate-limit** 10/15min por IP em /auth (3 endpoints)
- **Fraud check pré-checkout**: IsBlocked(email) + IsBlocked(ip)
- **CSP boundary**: frame-ancestors none, object-src none, base-uri self, form-action self
- **GDPR cookie banner** + /legal/cookie-preferences + manage-data (export + 30d deletion)
- **Anti-fraude velocity** cron (5min): email 3/24h warn + 10/h block; ip 10/h block
- **Security test suite** Go (12 TestSecurity_*): SQLi/XSS/auth bypass/IDOR/rate-limit/mass assignment/CRLF
- **Smoke probes** bash: 5/5 PASS contra prod
- **gitleaks** CI em 5 repos + .gitleaksignore para leaks históricos
- **Sentry** SDK wired em api/front/backoffice (no-op até DSN configurado)
- **Senha admin viralefy@gmail.com** — não tem nag de rotação (HML)

---

## 10. Deploy

**Zero-downtime via build-then-swap** (atualizado Fase 8 — 3 binários):
```
viralefy-update --yes        # padrão, ~5s downtime
viralefy-update --legacy     # destrutivo (~5-10min) — só emergência
viralefy-smoke               # smoke test pós-deploy (auto-rodado pelo update)
```

1. Clone **7 repos** (api, payments, sender, front, backoffice, ops, archive) em `/viralefy.next/` em paralelo aos serviços live
2. Build paralelo: 3 Go (api/payments/sender) + 2 Node (front/backoffice)
3. Atomic mv `/viralefy → /viralefy.prev` + `/viralefy.next → /viralefy`
4. Copy binários microservices pra `/usr/local/sbin/viralefy-{payments,sender}` (ExecStart dos units aponta lá)
5. Restart na ordem certa: `viralefy-{payments,sender}` PRIMEIRO, depois `viralefy-{api,front,backoffice}`
6. Healthcheck loopback 30s nos 3 services + front (rollback automático)
7. `viralefy-smoke` verifica contrato HTTP: 3 healths + `GET /v1/plans` + `POST /v1/me/2fa/status` (sem token → 401)

**Build inteligente**: API Go + 2 Next.js builds em paralelo. Aproveita 8 cores. Total ~3-5min sem nenhum impacto em prod até o swap.

**Build-fail-safe**: se algum build falha, `/viralefy/` permanece intocado. Reportar erro no log e exit. Já validado em prod (fix do `/auth/handoff` Suspense).

---

## 11. Tests

- API Go: `go test -count=1 ./...` → application + interface/http verde
- Front Next: `npm test` → 385/385+ (zod schemas + sitemap integrity + security probes + format)
- Backoffice Next: `npm test` (4 tests)
- CI/CD GitHub Actions em 4 repos (api/front/backoffice/ops) + gitleaks em todos os 5

---

## 12. Tracking (Wave 5)

- `user_events` (append-only granular) + `user_journeys` (1:1 first-touch wins via COALESCE)
- Front `lib/track.ts` + `TrackingHydrator` em layout root
- Event types whitelist: pageview, click, modal_open, modal_close, checkout_start, checkout_complete, abandon, landing
- Batch 10 events/10s + flush via sendBeacon on `beforeunload` (com re-queue se sendBeacon false)
- visitor_id sticky cookie + localStorage 1y
- Endpoint `/v1/track` MaxBytesReader 1MB, sempre 204

---

## 13. Tabelas que crescem (atenção)

| Tabela | TTL | Cleanup |
|---|---|---|
| `idempotency_keys` | 24h | IdempotencyCleanupCron |
| `user_events` | TODO: append-only | **policy a definir** |
| `ab_events` | TODO: append-only | **policy a definir** |
| `email_events` | TODO: append-only | **policy a definir** |
| `audit_log` | nunca | auditoria |

---

## 14. Diretórios

```
/media/sonne/Archives/projects/viralefy/
├── credentials               # SSH key
├── viralefy_api/             # Go DDD (orchestrator, :8080)
├── viralefy_payments/        # Go DDD (providers + charges + webhooks, :8081)
├── viralefy_sender/          # Go DDD (email + telegram outbox, :8082)
├── viralefy_front/           # Next.js storefront (:3000)
├── viralefy_backoffice/      # Next.js admin (:3001)
├── viralefy_ops/             # Installer + config + bin
├── viralefy_archive/         # Docs (este arquivo, ROADMAP, RUNBOOK, MICROSERVICES-OPS, etc.)
└── memory/                   # Auto-memory persistente
```

Na VPS:
```
/viralefy/{api,payments,sender,front,backoffice,ops,archive}   # atual — 7 repos
/viralefy.next/                                 # staging durante deploy
/viralefy.prev/                                 # backup do anterior (cleanup async)
/usr/local/sbin/viralefy-payments              # binário microservice (ExecStart)
/usr/local/sbin/viralefy-sender                # binário microservice (ExecStart)
/usr/local/sbin/viralefy-{update,status,logs,backup,smoke}  # CLIs persistentes
/etc/viralefy/.env                              # secrets, mode 0640 root:viralefy
                                                # inclui INTERNAL_SHARED_SECRET
/var/backups/viralefy/dump-*.sql.gz             # backups com retenção
/etc/prometheus/{prometheus.yml,alerts.yml}     # 11 rules em 6 groups
```

---

## 15. Documentos vivos no archive

| Arquivo | Pra que serve |
|---|---|
| [CONTEXT.md](CONTEXT.md) | Este snapshot. Lê primeiro em qualquer próxima sessão. |
| [CHECKLIST.md](CHECKLIST.md) | Tudo que o user pediu × done/pending |
| [ROADMAP.md](ROADMAP.md) | Roadmap por fase + status (30/30 RECOMMENDATIONS + Waves 4 + 5) |
| [RUNBOOK.md](RUNBOOK.md) | Ops playbook (deploy, incident, restore) |
| [PHASE-7-PLAN.md](PHASE-7-PLAN.md) | Plano Fase 7 (2FA + sec hardening) |
| [PHASE-8-MICROSERVICES.md](PHASE-8-MICROSERVICES.md) | Plano Fase 8 (carve-out payments + sender) |
| [MICROSERVICES-OPS.md](MICROSERVICES-OPS.md) | Runbook curto: migrations, debug, secret rotation, Telegram bot local |
| [RECOMMENDATIONS.md](RECOMMENDATIONS.md) | Lista original de 30 itens (referência histórica) |
| [COMPLIANCE.md](COMPLIANCE.md) | Notas legais (GDPR/PT-BR) |
| [AGENTS.md](AGENTS.md) | Instruções pra agentes |
| [diretrizes.md](diretrizes.md) | Diretrizes técnicas do projeto |

---

## 16. O que está completo e pronto pra revenue

- Storefront em 47 idiomas, 130 países, 15 categorias × Instagram/TikTok
- Checkout com cupom + VAT EU + PPP visual + tax cobrado + target_country
- Pagamento Manual PIX (BRL) + Manual USDT (crypto) ativos
- Admin tem botão "Open customer side" pra testar sem outro registro
- Cron de cart abandonment + email já dispara
- Subscription mensal com cron de renovação
- Referral com signup + payout hooks integrados
- Fraud pre-checkout block
- 11 alert rules vivas em Prometheus
- Backup diário com restore drill validado (1s, 0 erros)
- Zero-downtime deploy ativo (5s downtime, build-fail-safe)

**Não pronto** (decisão de produto):
- Heleket activation (aguardando)
- Sentry DSN (criar conta + paste no env)
- Grafana contact points (email/slack)
- WhatsApp provider real (DryRun stub serve por ora)
- Multi-vendor settlement split
- API B2B rate-limit per-key
- Cleanup crons pra `user_events` / `ab_events` / `email_events`
