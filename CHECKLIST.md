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
- [ ] Cleanup crons para tabelas append-only (user_events, ab_events, email_events)

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
- [ ] Stripe webhook signature verify + auto-paid (hoje cai em mark-as-paid manual)

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
- [x] Endpoint `POST /v1/me/orders/:id/proof` (JSON com data URL base64 até 800KB)
- [x] UI ProofUploadSection no step instructions (input file + nota TX hash)
- [ ] Object storage real (S3/MinIO) — hoje base64 inline; OK pra MVP

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
