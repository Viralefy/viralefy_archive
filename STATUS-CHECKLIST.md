# Viralefy — Status Checklist Compacto

Snapshot **2026-06-09**. Tudo agrupado por área. Convenção:
- `[x]` entregue em prod
- `[~]` parcial / aguarda decisão externa
- `[ ]` pendente
- `[!]` blocker / atenção

---

## Infra e arquitetura

- [x] DDD 4-layer Go monolith → 3 microservices (PHASE-8)
- [x] Postgres 17 single-tenant + 37 migrations
- [x] Caddy reverse proxy + TLS auto + webhook routes (4 providers)
- [x] systemd hardened units (NoNewPrivileges, ProtectSystem, PrivateTmp)
- [x] 7 repos públicos em github.com/Viralefy
- [x] Installer + viralefy-update (zero-downtime + smoke check + Caddyfile sync)
- [x] CLI em `/usr/local/sbin` (viralefy-status, smoke, update, backup, logs)
- [x] Object storage MinIO loopback Docker (proofs bucket privado + public)
- [x] R2-ready (só trocar STORAGE_ENDPOINT)
- [x] 47 idiomas i18n × 130 países × 15 categorias
- [x] Multi-moeda display ≠ cobrança (USD/USDT canonical)
- [x] PHASE-8 Wave 1+2+3 entregue: 3 binários loopback + auth interno + callback

## Build / deploy / observability

- [x] CI/CD GitHub Actions
- [x] gitleaks scan + CI guard
- [x] Postgres backup automatizado (diário 03:00 UTC, retenção 7d+4w+6m) + restore drill validado
- [x] Zero-downtime deploy build-then-swap + rollback automático
- [x] Build-fail-safe (prod intocado se build quebra)
- [x] 11 Prometheus alert rules em 6 grupos
- [x] OpenTelemetry traces + Loki logs + Grafana datasources
- [x] CONTEXT/CHECKLIST/INDEX mantidos a cada task
- [x] EventRetentionCron 24h tick, 90d retenção (user_events/ab_events/email_events/stripe_events_processed)
- [x] viralefy-smoke automated check + integrado no deploy
- [x] Sentry SDK wired no-op
- [ ] Sentry DSN integration assistant (var vazia em prod)
- [ ] Grafana contact points (email/Slack)
- [ ] 4 custom Grafana dashboards (revenue, payments, behavior, reliability)
- [ ] Sentry source maps no CI

## Segurança

- [x] JWT HS256 → RS256 dual-sign + JWKS público + kill-switch
- [x] Login rate-limit 10/15min/IP
- [x] Anti-fraude velocity cron + IsBlocked pré-checkout
- [x] Email reputation watcher Resend webhook
- [x] Resend Svix signature check
- [x] gitleaks scan + CI
- [x] Seed env-driven (zero default password)
- [x] CSP boundary directives + CORS sem reflection
- [x] /v1/track MaxBytesReader 1MB
- [x] Security test suite (12 TestSecurity_*)
- [x] PIX hard-block 5 layers + 10 testes
- [x] Stripe webhook 13 testes + replay protection
- [x] AbacatePay 11 testes
- [x] RBAC fix admin "Open customer side" (shadow account)
- [x] **2FA admin obrigatório** (TOTP + 8 backup codes + AES-256-GCM + bcrypt) + 9 testes
- [x] **2FA user opcional + nag pós-1º-pedido-completo** (cooldown progressivo dismiss<5 OR last>7d)
- [x] Stripe rk_live_ aceito (restricted key) + reject pk_/whsec_
- [x] PaymentsCallback `/internal/v1/payment-confirmed` autenticado X-Internal-Token
- [x] AbacatePay HMAC-SHA256 + base64 webhook signature
- [~] Rotação de chaves (política HML não-nag até 2026-06-14)
- [ ] Audit semestral por pentest externa
- [ ] WAF Cloudflare nativo

## Pagamento

- [x] Manual PIX (BRL, ativo em prod, pix_key `contato@viralefy.com`)
- [x] Manual Crypto multi-network (1 gateway = 1 network × asset)
- [x] Manual USDT (deprecated → manual_crypto)
- [x] **Stripe Checkout Session** REST direto (sem stripe-go dep) — **funcional em prod com rk_live_**
- [x] **Heleket crypto auto** — funcional em prod (gera `new-pay.heleket.com`)
- [x] **AbacatePay PIX dinâmico** — código deployado, **gateway não cadastrado em prod**
- [x] Woovi integrado (inactive em DB)
- [x] Gateway editor por provider (formulário cirúrgico, não JSON raw)
- [x] Schemas backoffice: stripe (rk_live_), manual_crypto (network warning), AbacatePay (api_key+webhook)
- [x] Pool 17 moedas (BTC/ETH/LTC/BNB/SOL/TRX/MATIC/XRP/DOGE/ADA/USDC/DAI/GBP/etc)
- [x] Multi-currency providers expandem em N cards no checkout (heleket → BTC/ETH/USDT/LTC)
- [x] PIX hard-block 5 camadas (filter + resolveGateway + pickGateway + Checkout + frontend PIX_PROVIDERS)
- [x] USDT universal SÓ pra crypto providers
- [x] Conversion note 2 pernas (display→charged + charged→settle)
- [x] Stripe webhook signature verify + auto-paid + idempotency `stripe_events_processed`
- [x] Heleket webhook signature + auto-paid
- [x] AbacatePay webhook signature + auto-paid
- [x] Webhook reverse-proxy Caddy → `:8081` (4 routes)
- [x] **Phone OR Telegram obrigatório no register**
- [x] Bulk approve proofs (até 50/call, audit por linha)
- [x] Mark-as-paid bulk no backoffice (badge + checkboxes + Approve/Reject)
- [x] Manual USDT → manual_crypto multi-network migration path
- [~] Heleket activation (cliente confirma se conta está ativa)
- [~] AbacatePay activation (cliente cadastra API key)
- [ ] Stripe webhook idempotency reconciliation polling (defesa quando webhook nunca chega)
- [ ] Boleto/Apple Pay/Link como payment_method_types do Stripe (CSV configurável)

## Compliance

- [x] GDPR cookie banner + cookie-preferences
- [x] Manage my data (export JSON + delete request 30d soft)
- [x] Refund/dispute admin UI
- [x] Tax handling EU VAT (28 países + GB)
- [x] Tax cobrado no settlement_amount
- [ ] LGPD compliance review
- [ ] CCPA opt-out de "sale of data"
- [ ] Privacy policy versionado por data
- [ ] Sub-processor list pública

## Receita / pricing

- [x] Cupom system (percent/fixed/first_order/min_order/categoria)
- [x] Cart abandonment cron (1-24h, payment_url)
- [x] Referral 5% credit on first paid
- [x] PPP pricing 28 países + selo visual
- [x] A/B testing harness sticky
- [x] Subscription mensal + cron + auto-cancel 3 falhas
- [x] Copy delivery 30min → 1h em 10 idiomas
- [x] target_country no Order (mercado da entrega ≠ tax country)
- [ ] Subscription pause/resume + upgrade/downgrade
- [ ] MRR/churn/LTV no backoffice dashboard

## Product depth

- [x] Order tracking detail + timeline + CTA
- [x] Notification preferences (4 toggles)
- [x] WhatsApp opt-in (DryRunSender)
- [x] Multi-vendor scaffold
- [x] API B2B scaffold (api_keys + /v2)
- [x] Proof upload multipart (5MB, MIME whitelist) + base64 fallback
- [x] Proof presigned URL 5min (admin + user)
- [x] ProofCard backoffice approve/reject + queue badge
- [x] Email proof rejected ao cliente
- [~] WhatsApp provider real (decisão Meta vs Twilio)
- [~] Multi-vendor settlement split
- [~] API B2B rate-limit per-key + billing

## Tracking / behavior

- [x] User events + journeys + endpoint /v1/track
- [x] Whitelist event types
- [x] Batch 10/10s + sendBeacon + flushBeacon re-queue
- [x] First-touch wins COALESCE em UpsertJourney
- [x] visitor_id sticky cookie + localStorage 1y
- [x] TrackingHydrator wrapper no layout root
- [x] Landing page + referrer + utm capturados

## Code quality

- [x] Playwright E2E infra + 5 smoke specs
- [x] Storybook + 8 stories
- [x] Zod schemas em boundaries
- [x] 397 unit tests no front (sitemap, theme, register, etc)
- [x] Go tests: TOTP RFC 6238, Stripe webhook, AbacatePay, security_probes, payment_methods, etc
- [x] E2E full smoke validated 2026-06-09 (register/login/me/checkout/order/webhook todos PASS)
- [ ] Playwright CheckoutModal flow (form→method→instructions→success)
- [ ] Contract test entre microservices (catch field-name drift)
- [ ] Lighthouse CI score >90 gate

## SEO

- [x] Programmatic SEO cities/vs/help/pricing/case-studies
- [x] Sitemap per-lang (47 idiomas) + paginação max 100/XML (back-compat <lang>.xml)
- [x] hreflang + JSON-LD Product/Offer/Service/AggregateOffer/BreadcrumbList
- [x] Robots.txt fix
- [x] Currency rate cascade + drift cron + RecomputePricesForPlan
- [ ] Backlinks 50 outreach
- [ ] /vs expandir pra 30 concorrentes
- [ ] Blog content engine
- [ ] AMP versão LPs principais
- [ ] OpenGraph imagens dinâmicas por plan

## Checkout UX

- [x] 4 steps (form → method → instructions → success)
- [x] Multi-currency expansion em cards (Heleket pay in BTC/ETH/USDT/LTC)
- [x] Conversion transparency note
- [x] Network warning crypto em UI vermelha grande
- [x] PIX UI exclusiva pra provider PIX (defensivo PIX_PROVIDERS whitelist no front)
- [x] No auto-preselect mesmo com 1 método (cliente precisa clicar deliberadamente)
- [x] Empty methods → mensagem clara (não fall-through)
- [x] Stripe success_url/cancel_url default automático (sem campo no backoffice)
- [x] Conversion display "Price shown €50, you pay X USDT (converted)"
- [x] Turnstile race fixado (useRef + 3s poll) — 3 forms (login, register, backoffice login)

## Object storage

- [x] MinIO local docker
- [x] Installer 85-storage.sh (docker-cli + compose, idempotente)
- [x] Bucket viralefy-proofs (privado) + viralefy-public (download)
- [x] S3Client (minio-go) + Put + PresignedGetURL + Delete
- [x] Proof upload multipart endpoint
- [x] Presigned URL endpoint (5min, user + admin)
- [x] Frontend multipart preferred + base64 fallback se 503
- [x] Backoffice ProofCard resolve key via presigned URL
- [ ] Object storage migration de proofs base64 antigos pra MinIO

## 2FA

- [x] Migration 036 admin_2fa + user_2fa
- [x] TOTP RFC 6238 (Google Authenticator/Authy/1Password)
- [x] AES-256-GCM at-rest secrets
- [x] 8 backup codes one-time bcrypt
- [x] Admin login wizard 3-step (credentials → enroll → code)
- [x] User /account/security/2fa
- [x] Setup2FAPrompt modal nag pós-1º-pedido-paid+delivered
- [x] Cooldown progressivo nag
- [x] Disable endpoint (admin: superadmin only com audit; user: self-service)
- [x] 9 testes (vectors RFC + AES roundtrip + backup codes)
- [ ] User 2FA enrollment count em métrica observability

## Microservices (PHASE-8)

- [x] viralefy_payments scaffold + extract + wire + deploy
- [x] viralefy_sender scaffold + extract + wire + deploy
- [x] systemd units com hardening
- [x] viralefy-update clona 7 repos + builds 3 binários
- [x] Caddyfile auto-sync no deploy + reverse-proxy 4 webhooks
- [x] POST /internal/v1/payment-confirmed callback (X-Internal-Token)
- [x] PaymentReceiver.MarkOrderPaid pós-hook (email + telegram admin + telegram cliente)
- [x] Sender outbox + retry exponencial
- [x] Sender raw passthrough (subject+html sem template para legacy)
- [x] Telegram bot integration (SendMessage MarkdownV2 + /start auto-link handle→chat_id)
- [x] Templates: checkout, checkout_paid (novo), proof_rejected
- [x] Migrations idempotentes (CREATE TABLE IF NOT EXISTS) pra coexistência DB compartilhado
- [x] paymentsclient + senderclient HTTP wrappers
- [x] MICROSERVICES-OPS.md runbook
- [ ] Contract test entre repos (JSON envelope/tag drift catch)
- [ ] Stripe webhook idempotency table no payments

## Notificações

- [x] Email Resend (RESEND_API_KEY configurado)
- [x] Email contato@viralefy.com canonical
- [x] Template checkout_paid (✅ Pagamento confirmado — Order #XYZ)
- [x] Template proof_rejected (cliente reanexa)
- [x] Raw passthrough (subject + html_body sem template) — sender legacy compat
- [x] Sender outbox persistente + retry 30s→5min→1h→6h→24h
- [x] Telegram bot código implementado + dispatch loop
- [x] Templates Telegram MarkdownV2 escaped
- [ ] TELEGRAM_BOT_TOKEN configurado em prod (env vazia)
- [ ] TELEGRAM_ADMIN_CHAT_ID configurado
- [ ] WhatsApp provider real

## Memory / archive

- [x] memory persistido em viralefy_archive/memory/
- [x] symlink reverso de ~/.claude/.../memory/ funciona transparente
- [x] 7 memories: run-stack-local, build-fixes, features-v2, ops-and-github, no-secret-rotation-nag, maintain-context-md, mais recentes auto-saved

## E2E validation 2026-06-09

- [x] /health + /v1/status + /.well-known/jwks.json: 200
- [x] /v1/plans + /categories + /currencies + /country-ppp + /tax-rates + reviews: 200
- [x] payment-methods BRL/br + USD/us: PIX corretamente filtrado fora de BR
- [x] /v1/coupons/validate INVALID → 422
- [x] /v1/track → 204
- [x] /v1/auth/user/register (com phone+telegram) → 201
- [x] /v1/auth/user/login → 200
- [x] 14 endpoints /me/* → 200/204
- [x] Checkout auto-pick → 201 + pix_key
- [x] Checkout Stripe USD → 201 + cs_live_ URL real
- [x] Checkout Heleket USDT → 201 + new-pay.heleket.com URL real
- [x] Checkout manual_pix BR → 201 + pix_key
- [x] GET /me/orders/{id} → 200
- [x] 4 webhook routes → 400 em signature inválida

## Bugs fixados nesta sessão (2026-06-09)

- [x] Stripe checkout 422 (pay_currency ignored em multi-currency provider)
- [x] event_retention_cron 42703 (column ab_events.occurred_at e email_events.received_at)
- [x] Caddy webhooks 404 (handle_path strip → handle + rewrite /internal{path})
- [x] Caddyfile nunca sincronizava em deploy → auto-sync com validate
- [x] paymentsclient ↔ payments envelope mismatch ({"methods":[...]} vs []) → 500
- [x] paymentsclient chargeResponse json tag (extra vs payment_extra) → QR vazio
- [x] Turnstile race (closure stale → 422 "missing token" 1ª tentativa) → useRef + 3s poll
- [x] Sender exigia template → aceita raw subject+html_body também
- [x] **`/internal/v1/*` exposto via Caddy (defesa em profundidade vazava 401+trace_id)** — bloqueado na borda (ops 98b08ce)

## Hardening + pendências fechadas (2026-06-09 sessão tardia)

- [x] **E2E sweep público:** 62 PASS / 1 fix crítico (`/internal/*` block)
- [x] **ABAC/RBAC autenticado:** 56/56 PASS — 0 IDOR, 0 RBAC bypass, 0 JWT forgery (testou tokens user A vs user B, admin viewer vs superadmin perms, alg=none, claim tamper)
- [x] **Contract tests inter-microservice** (api/paymentsclient + payments/contract_test, senderclient + sender/contract_test) — drift de tag/envelope falha CI nos 2 lados juntos
- [x] **Stripe reconcile cron** — polling 5min de orders pending > 10min, GET /v1/checkout/sessions/{id}, ConfirmByExternalRef se paid. Cobre webhook delivery loss (rede, retry esgotado, 72h window). 5 testes unit (paid/unpaid/404/429/empty)

## Pendências priorizadas (próxima sessão)

### Alto impacto, baixo custo
- [ ] AbacatePay gateway row em prod (cliente cadastra)
- [ ] Telegram bot ativar (cliente fornece TOKEN + CHAT_ID)
- [ ] Sentry DSN configurar

### Médio impacto
- [ ] Grafana contact points + 4 dashboards
- [ ] Object storage migration proofs base64 antigos

### Decisão de produto pendente
- [~] Heleket activation status (account ativo?)
- [~] WhatsApp Meta vs Twilio
- [~] Multi-vendor settlement model
- [~] API B2B billing tier

### Polish + nice-to-have
- [ ] Playwright CheckoutModal E2E
- [ ] Lighthouse CI gate
- [ ] Subscription pause/resume
- [ ] LGPD compliance review
- [ ] Blog content engine
- [ ] Backlinks outreach
- [ ] Pentest externa
- [ ] WAF Cloudflare nativo
- [ ] DR drill provisão nova + restore < 30min

## "Done de verdade" — quando consideramos plataforma 100%

- [ ] Zero base64 inline em orders
- [ ] 100% admins com 2FA enrolled (em prod só superadmin atual)
- [ ] >50% users com 2FA entre elegíveis
- [x] Stripe handling cardholder data sem nosso código tocar (SAQ-A)
- [~] Heleket activated + ≥1 paid order via crypto auto
- [ ] AbacatePay activated + ≥1 paid order via PIX dinâmico
- [ ] Sentry DSN ativo, 0 unhandled errors em 7d
- [ ] Grafana alerts → Slack #ops em < 1min
- [ ] 4 dashboards customizados
- [ ] OpenAPI sincronizado 100%
- [ ] Lighthouse >90 em todas LPs
- [ ] Pentest externa: 0 high/critical
- [x] DR drill < 30min (Postgres restore validado)
- [x] 3 microservices arquitetura operacional
- [x] E2E full smoke PASS validado em prod
