# Viralefy — Fase 7: Plano Extensivo

Snapshot **2026-06-08**. Forward-looking roadmap pra fechar o último 15% da plataforma.
`[x]` entregue · `[ ]` pendente · `[~]` parcial / aguardando decisão externa · `[!]` blocker

Ordenado por **impacto × dependência** — primeiro o que destrava revenue, depois UX/segurança, depois growth.

---

## 7.1 — Object storage (R2 path com MinIO local)

**Motivação**: hoje proof_url é base64 inline na coluna `orders.proof_url` (TEXT). 1 proof ≈ 600KB base64 → 100 proofs ≈ 60MB no DB. Em escala (500 proofs/dia × 90d retention) → 27GB no DB = backup pesado, query slow, vacuum thrash.

**Path**: MinIO single-instance via Docker agora; troca de `STORAGE_ENDPOINT` pra Cloudflare R2 quando atingir volume (≥10GB). Código S3-compatível em ambos.

### Backend storage package
- [x] `viralefy_ops/config/docker-compose.storage.yml` — MinIO + mc init (buckets `viralefy-proofs` privado, `viralefy-public` download)
- [x] `viralefy_ops/installer/85-storage.sh` — gera credenciais aleatórias na 1ª install, idempotente
- [x] `viralefy_ops/config/env.template` — STORAGE_* vars documentadas
- [ ] `viralefy_api/internal/infrastructure/external/storage/s3.go` — wrapper minio-go (PutObject, GetObject, PresignedGetURL)
- [ ] `viralefy_api/internal/application/storage.go` — porta `ObjectStorage` (interface) pra trocar implementação sem tocar service
- [ ] `viralefy_api/internal/config/config.go` — `StorageConfig` parseado de env
- [ ] `viralefy_api/cmd/api/main.go` — instancia storage client, injeta no Handlers
- [ ] `viralefy_api/go.mod` — `github.com/minio/minio-go/v7` (~3MB, sem deps AWS SDK gigante)

### Proof upload refactor (base64 → object storage)
- [ ] `POST /v1/me/orders/:id/proof` aceita multipart/form-data; backend faz PutObject no bucket `viralefy-proofs` com key `proofs/{order_id}/{ts}-{rand}.{ext}`
- [ ] Validação no backend: max 5MB, MIME whitelist (image/png, image/jpeg, image/webp, application/pdf)
- [ ] `Order.ProofURL` passa a guardar a key (não a URL completa nem o base64)
- [ ] `GET` de proof gera presigned URL de 5min — backoffice e cliente leem assim, evita expor bucket público
- [ ] Migration 035: opção de migrar base64 existentes pra MinIO (best-effort batch script `scripts/migrate-proofs-to-storage.go`)
- [ ] CheckoutModal ProofUploadSection: troca FileReader.readAsDataURL → FormData + fetch multipart
- [ ] Backoffice ProofCard: chama `GET /v1/admin/orders/:id/proof-url` pra obter presigned URL antes de renderizar
- [ ] Tests: TestStorage_PutObject_RoundTrip / TestStorage_PresignedURL_Expires / TestProofUpload_MIMERejection

### Backup (proofs em MinIO)
- [ ] `viralefy-backup` (script) inclui `mc mirror local/viralefy-proofs /var/backups/viralefy-proofs/`
- [ ] Retenção igual ao Postgres (7d + 4w + 6m)

### R2 migration (futuro)
- [ ] Criar account R2 + access key
- [ ] Setar `STORAGE_ENDPOINT=https://<acct>.r2.cloudflarestorage.com` + `STORAGE_USE_SSL=true`
- [ ] Migrar buckets: `mc mirror local/viralefy-proofs r2/viralefy-proofs`
- [ ] Trocar env vars + restart API → zero downtime swap (mesmo padrão do current zero-downtime deploy)
- [ ] Decommissionar MinIO local quando confirmar 0 reads em 30d

---

## 7.2 — 2FA (admin obrigatório, user opcional pós-pedido)

**Motivação**: admin tem acesso a refunds, mark-as-paid, RBAC, custom_data sensível dos clientes — credential leak = catástrofe. Cliente sem 2FA é OK até existir dado sensível (= primeiro pedido pago); depois nag.

**Algoritmo**: TOTP (RFC 6238) — funciona com Google Authenticator, Authy, 1Password, Bitwarden. SMS NÃO (SIM-swap). Backup codes (8 × 10-dígitos one-time) pra recovery.

### Schema (migration 036)
- [ ] `admin_2fa` table: `admin_id PK FK → admins(id), secret_encrypted TEXT, backup_codes_hashed TEXT[], enrolled_at TIMESTAMPTZ, last_used_at TIMESTAMPTZ`
- [ ] `user_2fa` table: idem mas FK → users(id), opcional
- [ ] `admins.requires_2fa BOOLEAN DEFAULT TRUE` — todos os admins existentes ganham TRUE no backfill
- [ ] `users.2fa_prompt_dismissed_count INT DEFAULT 0` — quantas vezes o user fechou o nag (cooldown progressivo)

### Crypto (secret encryption)
- [ ] TOTP secret cifrado em rest: AES-256-GCM com key da env `TWOFA_ENCRYPTION_KEY` (32 bytes base64)
- [ ] Instalador 30-secrets.sh gera key aleatória na 1ª install
- [ ] Backup codes hashed bcrypt (cost 10), comparison em constant-time

### Backend (Go)
- [ ] `internal/infrastructure/external/totp/totp.go` — wrapper sobre `github.com/pquerna/otp` (lightweight, sem deps de UI)
- [ ] `internal/application/twofa_service.go` — Enroll(adminID|userID) gera secret + QR otpauth://, Verify(code) checa TOTP atual + ±1 window
- [ ] `internal/domain/twofa.go` — types + repo interface

### Endpoints novos
- [ ] `POST /v1/admin/me/2fa/enroll` — gera secret novo, retorna QR data URL + backup codes (uma vez só, never again)
- [ ] `POST /v1/admin/me/2fa/verify` — valida primeiro código, ativa 2FA (flips `enrolled_at`)
- [ ] `POST /v1/auth/login` — quando admin tem 2FA, primeiro passo retorna `2fa_required: true` + `partial_token` (5min TTL, não autoriza endpoints)
- [ ] `POST /v1/auth/login/2fa` — body: `{partial_token, code}`. Sucesso → full JWT.
- [ ] `POST /v1/me/2fa/enroll`, `verify`, `disable` (espelhos do admin, pra user)
- [ ] `POST /v1/me/2fa/dismiss-prompt` — incrementa `2fa_prompt_dismissed_count`

### Flow admin (obrigatório)
- [ ] Login admin → `2fa_required:true` se ainda não enrolled → backoffice redireciona pra `/auth/setup-2fa` antes de qualquer outra tela
- [ ] /auth/setup-2fa mostra QR code + 8 backup codes (download .txt)
- [ ] Admin escaneia, digita primeiro código → enrolled, gera full JWT
- [ ] Logins subsequentes pedem código TOTP no mesmo step

### Flow user (opcional + nag pós-pedido)
- [ ] Após cada login do user, `GET /v1/me/notif-prefs` retorna `should_prompt_2fa: bool`
- [ ] `should_prompt_2fa = true` quando: (user tem ≥1 order com status='paid' E delivery_captured_at!=NULL) AND (user_2fa não existe) AND (`2fa_prompt_dismissed_count < 5` OR último dismiss > 7 dias)
- [ ] Front: modal `Setup2FAPrompt` na primeira tela do `/account/` quando true. Mostra: "Você tem N pedidos completos. Recomendamos proteger sua conta com 2FA — 30s pra ativar."
- [ ] Botões: "Ativar agora" (vai pra `/account/security/2fa`) | "Talvez depois" (dismiss, incrementa contador)
- [ ] **NÃO mostra** antes do 1º pedido completo — user fresh não tem dado pra proteger; encher saco = drop de conversão

### Tests
- [ ] TestTOTP_RFC6238_Vectors — usa vectors oficiais
- [ ] TestEnroll_GeneratesUniqueSecret
- [ ] TestVerify_RejectsExpiredCode + AcceptsWindow±1
- [ ] TestLogin_AdminBlockedUntilEnrolled
- [ ] TestLogin_UserOptional_ProceedsWithoutCode
- [ ] TestBackupCode_OneTimeUse
- [ ] TestPromptLogic_HiddenBeforeFirstPaidOrder
- [ ] TestPromptLogic_CooldownAfterDismiss

### Recovery (admin perdeu device)
- [ ] Superadmin pode resetar 2FA de outro admin via backoffice `/admins/[id]/reset-2fa` (audit log gravado)
- [ ] User esqueceu 2FA + backup codes → suporte humano via ticket (manual reset com KYC)

---

## 7.3 — Stack de pagamento (fechar últimas pontas)

### Stripe (cartão internacional)
- [x] Provider implementado com Checkout Session REST direta
- [x] Webhook signature verify + auto-paid
- [ ] Stripe webhook idempotency table (event_id seen) — protege contra Stripe re-deliver double-fire em janela onde MarkOrderPaid ainda não escreveu `paid`
- [ ] Suporte a `customer_email` recebido no webhook pra reconciliar quando `client_reference_id` ausente (orders feitos via Stripe Payment Link, sem checkout session original do código)
- [ ] Métricas `stripe_session_to_paid_seconds` (latência cliente fecha checkout → webhook chega) — pinpoint problemas de delay
- [ ] Dashboard Stripe: revenue, conversion, decline reasons

### Heleket (crypto auto)
- [x] Webhook handler + signature verify
- [~] Activation client-side — conta aguardando aprovação
- [ ] Smoke test em sandbox quando Heleket liberar staging URL
- [ ] Documentar mapping pay_currency → Heleket invoice (BTC vs USDT-TRC20 vs ETH-ERC20)

### Manual Crypto
- [x] Provider + per-network gateway model
- [ ] Cron de cleanup pra wallet addresses unused (configuração inicial deixa N rows que admin nunca ativa)
- [ ] Histórico de tx hashes anexados em proofs — view consolidada no backoffice pra detectar fraude (mesma tx hash em 2 orders)

### Manual PIX
- [x] Provider + pix_key
- [x] Hard-block pra non-BR
- [ ] Suporte a múltiplas chaves (admin cadastra N PIX, rotação manual)
- [ ] QR code dinâmico (gerar BR Code com amount + identifier) em vez de chave estática

### Mark-as-paid bulk
- [ ] Backoffice: `/orders?proof_status=pending` ganha checkbox por row + botão "Approve N selected"
- [ ] Endpoint `POST /v1/admin/proofs/bulk-decision` — body `{order_ids: [...], decision: "approved", note: ""}`
- [ ] Limite 50 orders por call (anti foot-gun)
- [ ] Audit log: cada decision linha individual

### Refund expansion
- [x] Refund pra créditos
- [ ] Refund crypto manual: admin marca refund_requested → email com instruções pro cliente enviar wallet pra reembolso
- [ ] Refund Stripe: chamar Stripe API `/v1/refunds` automaticamente
- [ ] Cron de refund pending > 7d → alerta no Slack

---

## 7.4 — Observabilidade & SRE

### Sentry (já wired, falta DSN)
- [ ] Onboarding assistant em `viralefy-status` que verifica se `SENTRY_DSN` está setado e reporta uptime
- [ ] Source maps upload no CI pra api/front/backoffice (Sentry CLI no GitHub Actions)
- [ ] Sentry Slack/email integration

### Grafana contact points
- [ ] Configurar contact point Slack via API (webhook URL no env)
- [ ] Configurar contact point email (SMTP via Resend)
- [ ] Notification policies: P1 (revenue drop, payment failures) → Slack + email; P2 (drift, slow queries) → Slack only
- [ ] Silenciar durante maintenance windows (admin override)

### Dashboards customizados
- [ ] Revenue dashboard: daily revenue (display + settlement), conversion funnel, top categories, top countries
- [ ] Payment dashboard: gateway success rate, time-to-paid p50/p99, refund rate, chargeback rate
- [ ] Behavioral dashboard: visitors → cart → checkout → paid funnel, journey first-touch attribution
- [ ] Reliability dashboard: API p95 latency, error rate por endpoint, queue depth de crons
- [ ] SEO dashboard: sitemap shard count, IndexNow ping rate, Search Console (via API) impressions

### Logs structured
- [x] slog JSON em prod
- [ ] Correlation ID propagado em todo log de uma request (já tem RequestID middleware mas não em todos os logs)
- [ ] Sampling em endpoints high-traffic (track, plans list) pra Loki não engasgar

### Alertas extra
- [x] 11 alerts em 6 groups
- [ ] Alert "proof_pending > 24h" — comprovante anexado sem revisão há mais de 1d
- [ ] Alert "stripe_webhook_failure_rate > 5%" — Stripe re-entregando muito
- [ ] Alert "heleket_no_callback_24h" — gateway ativo mas sem callback há 24h (provavelmente desativado lá)

---

## 7.5 — Product depth

### WhatsApp real provider
- [~] Decisão: Meta Cloud API vs Twilio
- [ ] Custos: Meta ~$0.02/msg, Twilio $0.005/msg + Twilio número
- [ ] Implementação após decisão
- [ ] Templates aprovados (BR + EN + ES)
- [ ] Opt-in já existe (DryRunSender), basta trocar adapter

### Multi-vendor settlement
- [~] Decisão: pagar vendors em USDT vs PIX BR vs ACH US
- [ ] Schema: `vendor_settlements` (id, vendor_id, period_start, period_end, gross_cents, fees_cents, net_cents, status, paid_at)
- [ ] Cron mensal: agrega orders.vendor_id × period
- [ ] Backoffice: tela `/vendors/[id]/settlements` com botão "Mark as paid"

### API B2B billing
- [~] Decisão de pricing
- [ ] Rate limit per-key (Redis ou in-memory por enquanto?) — token bucket 1000 req/h por padrão
- [ ] Usage tracking: incrementa contador por API key + endpoint
- [ ] Backoffice: `/api-keys/[id]/usage` mostra gráfico 30d
- [ ] Cron mensal: gera invoice baseado em tier (free 1k/h, paid $X por 10k/h)

### Subscription enhancements
- [x] Recurring mensal + cron + auto-cancel 3 falhas
- [ ] Pause/resume manual pelo user (mantém subscription, não cobra)
- [ ] Upgrade/downgrade (plan switching com proration)
- [ ] Subscription analytics: churn rate, MRR, LTV no backoffice

### Order tracking improvements
- [x] Timeline + CTA
- [ ] Estimated delivery time baseado em histórico do plan (mediana de últimos 100 paid → delivered)
- [ ] Status webhook pra cliente registrar (similar a Stripe webhook — push em vez de poll)
- [ ] Order status email cadenced (paid, delivery_started, delivery_completed)

---

## 7.6 — Security hardening (pós-2FA)

- [ ] Rate-limit distribuído (Redis vs in-memory atual): in-memory funciona em single-instance; pra HA precisa Redis
- [ ] CSRF tokens em mutations do backoffice (atualmente confia em SameSite=Lax + Bearer; defesa em profundidade)
- [ ] Content Security Policy stricter — atualmente bloqueia frame-ancestors mas permite inline styles; tightening pra remove `'unsafe-inline'`
- [ ] Subresource Integrity em assets cross-origin (Stripe.js, Turnstile)
- [ ] Auditoria semestral via pentest externa (Bishop Fox, NCC ou similar)
- [ ] WAF (Cloudflare nativo) — bloqueia padrões comuns de SQLi/XSS antes de chegar no Caddy
- [ ] DNS CAA records (limita quais CAs podem emitir certs viralefy.com)
- [ ] DMARC + SPF + DKIM pra emails (`resend.com` já tem mas precisa policy `p=reject`)

### Sensitive data handling
- [ ] Encryption-at-rest dos campos `users.tracking_data` que incluem IP (LGPD/GDPR)
- [ ] Auto-purge dos campos PII após delete request (hoje é soft delete)
- [ ] Right-to-explanation (LGPD): user pede explicação de decisão automatizada (cupom rejeitado, fraud block)

### Audit log expansion
- [x] Logging básico em mark-as-paid, refund, perm changes
- [ ] Audit em PII access (admin abriu user detail page)
- [ ] Audit em 2FA reset (superadmin → admin)
- [ ] Retention de audit log: 365d separado das tabelas event (compliance)

---

## 7.7 — SEO & growth (Tier 5)

- [x] Tier 4 (cities, vs, help, pricing, case-studies)
- [ ] Backlinks: lista de 50 sites pra outreach (estilo SaaSrank, Product Hunt)
- [ ] Comparison pages /vs expandir (atual 10 → 30 concorrentes)
- [ ] Blog content engine: 50 posts por categoria
- [ ] Schema.org enrichment: FAQPage em /help/[topic], BreadcrumbList em todas as LP
- [ ] OpenGraph imagens dinâmicas por plan (com price + countries served)
- [ ] AMP versão das LPs principais (instagram-followers, tiktok-followers)
- [ ] Hreflang audit semestral via Screaming Frog
- [ ] Core Web Vitals tracking: PageSpeed Insights via Lighthouse CI no GitHub Actions

---

## 7.8 — Testing & quality

### Coverage gaps
- [x] Security test suite (12 TestSecurity_*)
- [x] Stripe webhook tests
- [x] PIX hard-block tests
- [ ] CheckoutModal Playwright E2E (form → method → instructions → success)
- [ ] AdminProofDecision Playwright (admin upload + approve + verify mark-as-paid fired)
- [ ] PaymentMethodOption snapshot tests (todos os providers × moedas)
- [ ] Front: visual regression via Storybook + Chromatic (ou Percy)
- [ ] Back: contract test entre front+back via OpenAPI schema

### OpenAPI
- [x] OpenAPI YAML inicial
- [ ] Atualizar com novos endpoints (`/v1/plans/:id/payment-methods`, `/v1/me/orders/:id/proof`, `/v1/admin/orders/:id/proof/decision`, `/v1/admin/proofs/pending`, `/v1/webhooks/stripe`)
- [ ] Gerar client TS automaticamente pra `viralefy_front/src/lib/api.ts` (substituir manual types)
- [ ] Mock server via Prism pra contract tests
- [ ] Publicar swagger UI em `api.viralefy.com/docs`

### CI improvements
- [x] gitleaks scan
- [ ] Dependency review (GitHub Advisory) — falha CI se dep nova tem CVE alta/crítica
- [ ] License check — falha se dep GPL/AGPL entrou
- [ ] Bundle size budget — front bundle > X KB falha CI
- [ ] Lighthouse CI — score < 90 falha CI

---

## 7.9 — DX (developer experience)

- [ ] `Makefile` no api repo com targets canônicos: `make test`, `make lint`, `make migrate`, `make seed-local`
- [ ] Pre-commit hooks via `pre-commit` (gitleaks, gofmt, eslint, prettier)
- [ ] Docker compose pra local dev (Postgres + MinIO + Redis quando vier)
- [ ] Seed de dados de demo (5 users, 10 orders em vários estados, 3 admins)
- [ ] Storybook integration tests via Test Runner
- [ ] CONTRIBUTING.md com fluxo de PR + commit conventions
- [ ] Changelog automatizado (release-please ou similar)
- [ ] Tab autocomplete pra `viralefy-status`, `viralefy-update` (completion file)

---

## 7.10 — Documentação

- [x] CONTEXT.md + CHECKLIST.md mantidos a cada task
- [x] RUNBOOK.md (deploy/incident/restore)
- [ ] Atualizar CONTEXT.md com payment provider expansion + 2FA + storage
- [ ] PLAYBOOK pra:
  - "Cliente reclamou que pagou mas order não ativou" → diagnóstico passo-a-passo
  - "Stripe webhook não chegou" → como buscar event_id no dashboard
  - "MinIO cheio" → como expandir disco / migrar pra R2
  - "2FA admin perdido" → recovery process
- [ ] Diagrama de arquitetura atualizado (Mermaid em CONTEXT.md)
- [ ] API reference em `/docs` (gerado da OpenAPI)
- [ ] Onboarding doc pra novo engineer: setup local em <30min

---

## 7.11 — Compliance & legal

- [x] GDPR cookie banner
- [x] Manage my data (export/delete)
- [x] Tax (EU VAT 28 países)
- [ ] LGPD compliance review (Brazil — equivalente GDPR mas diferenças em consent + DPO)
- [ ] CCPA (California) — opt-out de "sale of data" mesmo que não vendemos
- [ ] Cookie scanner automatizado (Klaro ou Osano) pra manter list atualizado
- [ ] Privacy policy versionado (cada update mostra "Última atualização: YYYY-MM-DD")
- [ ] Terms of Service review legal antes de scale internacional
- [ ] PCI-DSS SAQ-A (autorize Stripe assume todo o handling de card data — basta certificar SAQ-A)
- [ ] Sub-processor list pública (Resend, Stripe, Cloudflare, etc.)

---

## 7.12 — Infrastructure

### Scaling path
- [ ] Multi-region read replicas Postgres (current: single VPS 8c/16GB)
- [ ] Redis cluster pra cache + rate limit distribuído
- [ ] CDN (Cloudflare) pra static assets + images
- [ ] Auto-scaling: VPS atual aguenta ~10k req/min sustained; > isso precisa scale horizontal

### Disaster recovery
- [x] Postgres backup diário + restore drill (1s, 0 errors)
- [ ] Backup offsite (current local only) — sync pra B2 ou R2
- [ ] DR runbook: provisionar VPS nova + restore < 30min
- [ ] Chaos engineering: kill aleatório de services pra testar recovery

### Monitoring expansion
- [ ] SLO tracking: API uptime 99.9%, payment success >99%
- [ ] Error budget enforcement
- [ ] On-call rotation (PagerDuty / Opsgenie quando crescer team)

---

## Priorização sugerida pra próximas sprints

| Sprint | Foco | Items |
|---|---|---|
| **1 (urgent)** | Storage MinIO + Stripe robustness | 7.1 (storage API), 7.3 (Stripe idempotency), 7.4 (Sentry DSN setup) |
| **2 (security)** | 2FA admin | 7.2 (schema + endpoints + admin flow + tests) |
| **3 (UX)** | 2FA user + proof bulk | 7.2 (user opt-in flow), 7.3 (mark-as-paid bulk) |
| **4 (ops)** | Grafana contacts + dashboards | 7.4 (contact points, 4 dashboards) |
| **5 (testing)** | E2E + OpenAPI sync | 7.8 (Playwright + OpenAPI + Lighthouse CI) |
| **6 (growth)** | SEO Tier 5 + blog | 7.7 (50 backlinks, content engine) |

---

## Métricas de "done" — quando consideramos a plataforma 100%

- [ ] Zero base64 inline em orders (todos proofs em storage)
- [ ] 100% admins com 2FA enrolled
- [ ] >50% users com 2FA (entre os elegíveis)
- [ ] Stripe handling cardholder data sem nosso código tocar nada (SAQ-A)
- [ ] Heleket activated + pelo menos 1 paid order via cripto auto
- [ ] Sentry DSN ativo, 0 unhandled errors em 7d
- [ ] Grafana alerts → Slack #ops em < 1min
- [ ] 4 dashboards revenue/payment/behavior/reliability + 1 SEO
- [ ] OpenAPI bate 100% com endpoints reais
- [ ] Lighthouse score > 90 em todas as LPs
- [ ] Pentest externa: 0 high/critical findings
- [ ] DR drill: provisão nova + restore < 30min (executado e documentado)

---

## Links

- [CONTEXT.md](CONTEXT.md) — snapshot atual da plataforma
- [CHECKLIST.md](CHECKLIST.md) — histórico do que o user pediu
- [ROADMAP.md](ROADMAP.md) — fases 0-6 entregues
- [RUNBOOK.md](RUNBOOK.md) — playbook de ops
