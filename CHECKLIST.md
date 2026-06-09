# Viralefy — Checklist extensivo do que foi pedido

Snapshot **2026-06-08** (rev. checkout 2-step + Stripe + manual_crypto + proof).
Tudo que o user pediu em conversa, linha por linha.
`[x]` = entregue em prod (com commit link); `[ ]` = pendente; `[~]` = parcial / aguarda decisão externa.

---

## Setup inicial / arquitetura

- [x] Estrutura DDD do API Go (4 layers)
- [x] Next.js 15 App Router em front + backoffice
- [x] Postgres 17 single-tenant
- [x] Caddy reverse proxy + TLS auto
- [x] Hardened systemd units (NoNewPrivileges, ProtectSystem, etc.)
- [x] 5 repos públicos em github.com/Viralefy
- [x] Installer destrutivo (`viralefy-update --legacy`)
- [x] CLIs em /usr/local/sbin (sobrevivem a rm -rf)
- [x] 47 idiomas i18n
- [x] 130 países × 15 categorias
- [x] Multi-moeda display ≠ cobrança (USD/USDT canonical)

## Build / deploy / ops

- [x] CI/CD GitHub Actions em 4 repos (api, front, backoffice, ops)
- [x] gitleaks scan + workflow CI nos 5 repos
- [x] Postgres backup automatizado (diário 03:00 UTC, retenção 7d+4w+6m)
- [x] Backup restore drill validado (1s, 0 erros — 2026-06-08) `viralefy_archive/RUNBOOK.md`
- [x] Métricas backup textfile collector node_exporter
- [x] **Zero-downtime deploy** (build-then-swap, ~5s downtime, rollback automático) `viralefy_ops b4373d7`
- [x] Build-fail-safe: prod intocado se build quebra (validado com /auth/handoff Suspense fix)
- [x] **11 Prometheus alert rules em 6 grupos** `viralefy_ops d8722e2`
- [x] Sentry SDK wired em api/front/backoffice (no-op até DSN)
- [x] Status page público `/status` com `/v1/status` endpoint
- [x] OpenTelemetry traces + Loki logs + Grafana datasources
- [x] RUNBOOK.md completo `viralefy_archive 7d4a217`
- [x] CONTEXT.md + CHECKLIST.md mantidos a cada task (este arquivo)
- [ ] Sentry DSN integration assistant
- [ ] Grafana contact points (email/Slack)
- [x] **Cleanup crons para tabelas append-only** — `EventRetentionCron` (24h tick, 90d MaxAge) drena user_events/ab_events/email_events em batches de 1000 com `FOR UPDATE SKIP LOCKED`. user_journeys agregado intacto.

## Segurança

- [x] JWT HS256 → RS256 dual-sign (Fase 4.1)
- [x] JWKS público `/.well-known/jwks.json`
- [x] HS256 kill-switch via `LEGACY_HS256_DISABLED`
- [x] Login rate-limit 10/15min/IP em 3 endpoints
- [x] Anti-fraude velocity cron (5min) + IsBlocked pré-checkout
- [x] Email reputation watcher (Resend webhook + auto-disable hard bounce/complaint)
- [x] Resend Svix signature check
- [x] gitleaks scan inicial + CI guard
- [x] Cred leak removido da login page + 5 READMEs + CONTEXT.md
- [x] Seed env-driven (ADMIN_BOOTSTRAP_*) — zero default password no código
- [x] Admin password reset + email mudado pra viralefy@gmail.com
- [x] CSP boundary directives (frame-ancestors none, etc.)
- [x] CORS sem reflection
- [x] **Security test suite Go** (12 TestSecurity_*: SQLi/XSS/auth/IDOR/rate/mass/CRLF) `viralefy_api ea13ada`
- [x] **Tests PIX hard-block** (10 cases × provider × moeda × country) — lockam que PIX/Woovi nunca aparecem pra non-BR
- [x] **Tests Stripe webhook** (12 cases: ok/multi-v1/invalid-sig/expired-ts/future-ts/missing-secret/missing-header/malformed × 5)
- [x] **Smoke probes bash** (5/5 PASS contra prod) `viralefy_api/scripts/security-probes.sh`
- [x] Front security tests (CSP/dangerouslySetInnerHTML/session)
- [x] /v1/track MaxBytesReader 1MB
- [x] RBAC fix: admin "Open customer side" — endpoint + UI espelha admin em users shadow `viralefy_api fd34f95`
- [~] Rotação de chaves: por política HML não-nag até 2026-06-14

## Compliance

- [x] GDPR cookie banner + /legal/cookie-preferences
- [x] Manage my data (export JSON + delete request 30d soft)
- [x] Refund/dispute admin UI no backoffice (`/orders/[id]/refund`)
- [x] Tax handling EU VAT (28 países + GB, /v1/tax-rates)
- [x] Tax cobrado no settlement_amount (Wave 4 — loop fechado)

## Receita / pricing

- [x] Cupom system (percent + fixed_usd_cents + first_order + min_order)
- [x] Cart abandonment cron (1-24h após pending + payment_url)
- [x] Referral signup + payout hooks integrados (5% credit on first paid)
- [x] PPP pricing infra (28 países)
- [x] PPP visual activation nos cards (Wave 4 — selo "Local pricing applied")
- [x] A/B testing harness (sticky assignment + tracking)
- [x] Subscription system (recurring mensal + cron + auto-cancel 3 falhas)
- [x] Copy delivery 30min → 1h em 10 idiomas `viralefy_front 4e6a0fa`
- [x] target_country no Order (mercado da entrega ≠ tax country) `viralefy_api 1e932e5`

## Product depth

- [x] Order tracking detail (/account/orders/[id] com timeline + CTA)
- [x] Notification preferences (notif_prefs JSONB + 4 toggles)
- [x] WhatsApp opt-in (DryRunSender stub)
- [x] Multi-vendor scaffold (vendors table + admin CRUD)
- [x] API B2B scaffold (api_keys + /v2 endpoints + apiKeyAuth middleware)
- [x] /account/orders redirect fix (era 404)
- [~] WhatsApp provider real (Meta/Twilio) — aguarda decisão
- [~] Multi-vendor settlement split — aguarda decisão
- [~] API B2B rate-limit per-key + billing — aguarda decisão

## Tracking / behavior

- [x] User events table + journeys + endpoint /v1/track
- [x] Event types whitelist (pageview, click, modal_*, checkout_*, abandon, landing)
- [x] Front lib/track.ts batch 10/10s + sendBeacon
- [x] flushBeacon re-queue em sendBeacon false
- [x] First-touch wins via COALESCE em UpsertJourney
- [x] visitor_id sticky cookie + localStorage 1y
- [x] TrackingHydrator wrapper no layout root
- [x] Landing page + referrer + utm capturados

## Code quality

- [x] Playwright E2E infra + 5 smoke specs
- [x] Storybook + 8 stories (fix @storybook/nextjs vs nextjs-vite)
- [x] Zod schemas em boundaries de API

## SEO / Growth (Tier 4 original)

- [x] Programmatic SEO cities (/cities + 50 cidades) `Wave 1 multi-agent`
- [x] vs-competitors (/vs + 10 comparações) `Wave 1`
- [x] Help center (/help + 12 tópicos) `Wave 1`
- [x] Pricing table (/pricing) `Wave 1`
- [x] Case studies (/case-studies + 6 estudos) `Wave 1`

## SEO / hotfixes

- [x] Sitemap per-lang vazio (19 buckets) — `COUNTRY_LANG` mapping fix
- [x] Sitemap dedup categoria de serviço (qty=1 colidia 7×)
- [x] Currency rate cascade (drift cron + PlanService.RecomputePricesForPlan)
- [x] `priceFor()` aplica rate quando não há override
- [x] hreflang via lib/hreflang.ts
- [x] JSON-LD schema (Product/Offer/Service/AggregateOffer/BreadcrumbList)
- [x] Robots.txt fix (deprecated Host: removido)
- [x] **Sitemap paginação** — max 100 URLs por XML (`<lang>` = página 1 back-compat, `<lang>-2`, `<lang>-3`… para shards seguintes). Índice `/sitemap.xml` enumera via `paginatedBuckets()` pra crawler nunca baixar 404. 5 testes novos lock invariantes.

## Pagamento — providers

- [x] Manual PIX (BRL, ativo)
- [x] **Manual USDT** (carteira fixa + network warning) `viralefy_api fd34f95` `viralefy_front 397fa25` _deprecated em favor de manual_crypto_
- [x] **Manual Crypto** genérico (1 gateway = 1 network × asset; cada um seu wallet/memo) — USDT TRC20/BSC/POL/ERC20, BTC, LTC, ETH, SOL...
- [x] **Stripe** Checkout Session — cartão internacional (REST direta, sem stripe-go dep)
- [x] Heleket integration (inactive, aguarda aprovação)
- [x] Woovi integration (inactive)
- [x] Gateway editor por provider com formulário cirúrgico (não JSON raw) `viralefy_backoffice b724099`
- [x] Schemas stripe + manual_crypto no backoffice (network_label override, warning override)
- [x] Multi-select accepted_currencies expandido (USDT/USD/EUR/BRL/GBP/BTC/LTC/ETH/BNB/SOL/TRX/MATIC)
- [x] Defaults provider-aware (Woovi/PIX→BRL; manual_crypto→USDT; Stripe→USD/EUR/BRL/GBP)
- [~] Heleket activation (cliente)
- [x] **Stripe webhook signature verify + auto-paid** — `POST /v1/webhooks/stripe` valida HMAC SHA256(`t.payload`) com tolerance 5min, escuta `checkout.session.completed` e dispara `MarkOrderPaid` via `client_reference_id`

## Checkout — UX nova (2026-06-08)

- [x] Endpoint `GET /v1/plans/:id/payment-methods?display_currency=X&country=Y` — catálogo de métodos elegíveis com preview
- [x] `CheckoutInput.GatewayID` opcional — front escolhe o método ANTES de submeter
- [x] CheckoutModal refatorado em 4 steps: form → method → instructions → success
- [x] MethodCard mostra ícone (💳/🇧🇷 PIX/🪙/⚡), valor cobrado, network label
- [x] **Transparência cripto-conversão**: `conversion_note` quando charged ≠ settlement ("você paga R$50 em BRL, plataforma recebe 10 USDT após conversão")
- [x] **Aviso crítico de rede crypto** em UI vermelha proeminente: "Send ONLY on TRC20. Wrong network = lost funds forever."
- [x] Aviso de memo/tag obrigatório quando configurado
- [x] PIX block mostra disclaimer de conversão se settlement ≠ display

## Comprovante de pagamento

- [x] Migration 034: `order_proofs` table + `orders.proof_url`/`proof_uploaded_at`/`proof_status`/`proof_note`
- [x] `OrderRepository.SetProof` (idempotente, append em order_proofs + denormaliza order)
- [x] `OrderRepository.AssignGateway` (reescolha de método em order pending)
- [x] `OrderRepository.SetProofStatus` + `ListPendingProofs` (fila SLA)
- [x] Endpoint `POST /v1/me/orders/:id/proof` (JSON com data URL base64 até 800KB)
- [x] Endpoint `POST /v1/admin/orders/:id/proof/decision` — approve dispara mark-as-paid, reject volta pendente
- [x] Endpoint `GET /v1/admin/proofs/pending?limit=N`
- [x] UI ProofUploadSection no step instructions (input file + nota TX hash)
- [x] Backoffice `/orders/[id]` mostra **ProofCard** com preview (imagem ou link) + botões Approve/Reject + reviewer note
- [x] Backoffice `/orders` mostra badge "📎 Proofs to review · N" + toggle de filtro proof_status=pending
- [x] Email transacional ao cliente quando proof é rejected (best-effort, não bloqueia decisão)
- [x] Object storage local via MinIO Docker (ops setup) — `viralefy_ops/config/docker-compose.storage.yml` + `installer/85-storage.sh`
- [x] **API S3 client** (`internal/infrastructure/external/storage/s3.go`) com minio-go — funciona em MinIO + R2 sem code change
- [x] **Proof upload multipart** (`POST /v1/me/orders/:id/proof` content-type multipart/form-data) — 5MB max, MIME whitelist (png/jpg/webp/gif/pdf), key `proofs/{order}/{ts}-{rand}.{ext}`
- [x] **Presigned URL endpoints** — `GET /v1/me/orders/:id/proof-url` + `GET /v1/admin/orders/:id/proof-url` (5min expiry)
- [x] **Front fallback automático**: multipart preferido, cai em base64 quando server retorna 503 (storage disabled)
- [x] **Backoffice ProofCard**: chama `getProofURL()` on mount, mostra spinner enquanto resolve, infere MIME pela extensão da key
- [x] Retro-compat: proofs com `data:`/`http:` URLs antigos passam direto (legacy support)
- [ ] Cloudflare R2 migration (só trocar `STORAGE_ENDPOINT` + `STORAGE_USE_SSL=true` quando volume justificar)

## Stripe idempotency

- [x] Migration 035 `stripe_events_processed` (event_id PK, event_type, order_id, received_at)
- [x] Handler insere com `ON CONFLICT DO NOTHING` antes de chamar `MarkOrderPaid` — segundo fire vira no-op
- [x] Métrica `gateway_callbacks_total{provider=stripe,status=duplicate}` pra observabilidade
- [x] `EventRetentionCron` inclui `stripe_events_processed` (90d retention)

## Sentry DSN check

- [x] `viralefy-status` ganhou seção "Sentry" que avisa quando `SENTRY_DSN` / `NEXT_PUBLIC_SENTRY_DSN` vazios
- [x] Aviso de `SENTRY_AUTH_TOKEN` ausente (stack traces ofuscados sem source map)
- [x] `viralefy-status` ganhou seção "Object storage (MinIO)" — checa container healthy + endpoint ready

## Crypto automático multi-currency (Heleket)

- [x] Pool ampliado 5 → 17 moedas no seed (ETH/LTC/BNB/SOL/TRX/MATIC/XRP/DOGE/ADA/USDC/DAI/GBP)
- [x] Cryptos novas com `display_enabled=false` (não poluem picker do storefront, mas servem como cobrança)
- [x] Providers multi-currency (Heleket/Stripe) expandem em N cards (um por accepted_currency)
- [x] Conversion note carrega 2 pernas: display→charged ("Price shown €50") + charged→settle ("platform settles in USDT")
- [x] `CheckoutInput.PayCurrency` + `PaymentChargeInput.Currency` overridable
- [x] Front envia `pay_currency=charged_currency` quando cliente clica card multi-currency
- [x] Backoffice Heleket defaults: USDT+BTC+ETH+LTC (em vez de só USDT)

## Memory persistido em viralefy_archive

- [x] Mover `~/.claude/.../memory/` → `viralefy_archive/memory/` + symlink reverso
- [x] Auto-memory continua funcionando via symlink transparente

## RBAC / usuários

- [x] Admin separate from User (different tables, different JWT typ)
- [x] **Admin "Open customer side"** — shadow user account via /v1/admin/me/become-customer
- [x] /auth/handoff page (cross-origin token bridge)
- [x] Superadmin bypass em Can()
- [x] PermCouponsRead/Write/Reviews*/Admins* etc.

## Documentação

- [x] CONTEXT.md (geral, este snapshot)
- [x] CHECKLIST.md (este arquivo)
- [x] ROADMAP.md (30/30 RECOMMENDATIONS shipped)
- [x] RUNBOOK.md (deploy/incident/restore)
- [x] RECOMMENDATIONS.md (referência histórica)
- [x] COMPLIANCE.md (notas legais)
- [x] AGENTS.md (instruções pra agentes)
- [x] diretrizes.md (técnicas)

## Memórias persistidas

- [x] `run-viralefy-stack-local` (portas dev + container postgres)
- [x] `viralefy-stack-initial-build-fixes` (débitos MVP)
- [x] `viralefy-features-v2` (categorias, auth user, autocadastro)
- [x] `viralefy-ops-and-github` (installer destrutivo + 5 repos)
- [x] `no-secret-rotation-nag` (HML/POC, sem alerta de rotação)
- [x] `maintain-context-md` (este processo) `2026-06-08`

---

## 2FA — admin (vide [PHASE-7-PLAN.md](PHASE-7-PLAN.md) §7.2)

- [x] **Migration 036**: `admin_2fa` + `user_2fa` tables, `admins.requires_2fa DEFAULT TRUE`, `users.twofa_prompt_*` counters
- [x] **TOTP RFC 6238** via `github.com/pquerna/otp` — Google Authenticator/Authy/1Password compatível
- [x] **AES-256-GCM** at-rest crypto pra secrets (key 32 bytes via `TWOFA_ENCRYPTION_KEY` env)
- [x] **8 backup codes** one-time, hashed bcrypt cost 10, consumo em transação `FOR UPDATE` (anti TOCTOU)
- [x] **Login flow**: `POST /v1/auth/login` retorna `twofa_required` + `partial_token` (5min) quando admin precisa 2FA
- [x] **Enroll flow**: `POST /v1/auth/login/2fa/enroll` (com partial_token) → secret + QR + backup codes
- [x] **Complete flow**: `POST /v1/auth/login/2fa` (partial_token + code) → JWT final
- [x] **Backoffice login wizard** 3 steps (credentials → enroll → code), QR via api.qrserver.com, download .txt dos backup codes, checkbox "I've saved these"
- [x] **Disable** `POST /v1/admin/me/2fa/disable` — só superadmin (PermAdminsManage)
- [x] **Installer**: 30-secrets.sh gera `TWOFA_ENCRYPTION_KEY` aleatória (hex 64) na 1ª install + persiste
- [x] **Tests TOTP**: 9 cases (enroll uniqueness, verify accept/reject, AES roundtrip, key trocada, backup codes alphabet)
- [x] **User 2FA opcional** — UserAuthService gate em partial_token quando enrolled (login não bloqueia se NÃO enrolled)
- [x] **Endpoints user**: `GET /v1/me/2fa/status` + `POST /v1/me/2fa/{enroll,verify,disable,dismiss-prompt}` + `POST /v1/auth/user/login/2fa`
- [x] **should_prompt logic** — true sse: NÃO enrolled + ≥1 order paid+delivery_captured + (dismiss<5 OU last>7d). Pré-1º-pedido nunca atormenta.
- [x] **Cooldown progressivo**: dismiss <5 → mostra sempre; ≥5 → espera 7d entre prompts
- [x] **Setup2FAPrompt modal** em `/account` (sessionStorage skip durante sessão)
- [x] **Página `/account/security/2fa`** — enroll wizard (QR + 8 backup codes + download + verify) + disable
- [x] **Login front user**: aceita twofa_required → step de código + backup
- [x] **Audit log** explícito em `admin.2fa.disable` (actor + target + reason)

## Bulk approve (mark-as-paid em lote)

- [x] Endpoint `POST /v1/admin/proofs/bulk-decision` (limite 50/call, audit por linha)
- [x] Loop atômico por order: skipped (sem proof), error (DB), applied. Approved dispara `MarkOrderPaid` + audit.
- [x] Reject dispara email transacional ao cliente
- [x] Backoffice `/orders` ganha checkbox por row + select-all no header quando filtro proof_status=pending ativo
- [x] Bulk actions panel: "Approve N" / "Reject N" com confirm + resultado agregado (applied/skipped/errors)

## Próximas tasks possíveis (não pedidas explicitamente)

- [ ] Contact points no Grafana → alerts viram email/slack
- [ ] Mark-as-paid bulk no backoffice (vários USDT confirmados ao mesmo tempo)
- [ ] Sentry DSN onboarding assistant
- [ ] Heleket activation guide quando aprovar
- [ ] WhatsApp provider real (Meta Cloud API vs Twilio)
- [ ] Multi-vendor settlement model (decisão de produto)
- [ ] Cleanup cron pra user_events / ab_events / email_events
- [ ] OpenAPI yaml atualização
- [ ] Custom dashboards no Grafana (revenue, conversion, drift, uptime)
