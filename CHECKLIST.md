# Viralefy — CHECKLIST.md

**Última atualização:** 2026-06-11 03:30 UTC

Convenção: `[x]` done · `[~]` parcial/decisão externa · `[ ]` pendente · `[!]` blocker/atenção · `[L]` LGPD/legal · `[T]` time-gated · `[$]` cliente fornecer · `[E]` externo (orçamento)

---

## ✅ DONE — Estado de prod consolidado

### Cutover PHASE-9 (104+ rotas via dispatcher)

- [x] **Bucket 1** — /v1/plans*, /v1/categories*, /v1/currencies*, /v1/status*, /v1/country-ppp*, /v1/tax-rates*, /.well-known/jwks.json (7 rotas)
- [x] **Bucket 2 (a+b)** — /v1/me/* (38 rotas GET+POST+PUT+DELETE)
- [x] **Bucket 2c** — /v1/auth/* (6 rotas user+admin login/register/2fa) + viralefy_auth ganhou public routes
- [x] **Bucket 3** — /v1/admin/* (52+ rotas com RBAC)
- [x] **Bucket 4** — /v1/checkout (1 rota)
- [x] **Caddyfile default fallback** → dispatcher :8090 (era → legacy :8080)
- [x] **Legacy api STOPPED + DISABLED** (2026-06-10 07:36 UTC, soak 14d até 2026-06-24)
- [x] **viralefy-update skipa legacy** (marker `/etc/viralefy/.legacy-deprecated`)
- [x] **viralefy-smoke atualizado** (port :8090, mapping de health paths)

### Segurança

- [x] **External smoke (prod regression detector)** — GH Actions cron 15min, 36 assertions × 8 grupos, **inclui POST /v1/checkout com tracking.landing_url** (regression test pro FP Coraza 931130 de 2026-06-10). Runner externo (ubuntu-latest), zero footprint em prod. `RUNBOOK-EXTERNAL-SMOKE.md`. Dry-run local: 36/36 pass em ~1m45s.
- [x] **Coraza WAF SecRuleEngine On + Block real** (2026-06-10 12:20 UTC)
- [x] **SecDefaultAction phase 1/2 → deny,status:403** (causa raiz do warning não-block)
- [x] **Coraza audit log JSON ativo** (era 0 bytes, SecAuditLog estava comentado)
- [x] **Coraza paranoia level 2** + bodyproc enforcement (pentest #5)
- [x] **Exclusões CRS custom**: 900201 Stripe sig, 900601 password phase 2, 900700 REST methods, 900710/720 PL2
- [x] **Coraza exclusion 900300 (`/v1/me/reviews`) validada com payload real** (2026-06-11) — pré-stage apontava pra URI inexistente (`/v1/reviews`) e cobria só `body`. Audit confirmou: endpoint real é `/v1/me/reviews`, campos free-text são `body` E `title`, sem sanitização server-side (defesa = React JSX auto-escape). 12 payloads testados (markdown legit, script/img/svg/iframe/body XSS, SQLi, javascript:URL). Rule 900300 corrigida pra phase 2 + `ARGS:json.{body,title}` + variantes. `REVIEW-XSS-AUDIT.md`.
- [x] **CORS preflight fix** (login estava quebrado pós-cutover, 405 → 204)
- [x] **Hot-set revogação E2E dispatcher**: 82ms (target ≤5s, 60x melhor)
- [x] **Defense-in-depth core ValidateToken** (RevocationCache + LISTEN/NOTIFY + 30s fallback)
- [x] **Host header tampering protection** (:443 catch-all → 421 Misdirected Request)
- [x] **Security headers em todos vhosts** (CSP, COEP/CORP, Permissions-Policy, HSTS preload)
- [x] **3 HIGH vulns fixados** (Go chi/jwt outdated, npm tmp <0.2.6, rsa@0.9.10 risk-accepted)
- [x] **Pentest MEDIUM #4 #5 #7 #10 fixados** (host, CRLF, COEP/CORP, Server header)

### Infraestrutura paralela (PHASE-9 stack)

- [x] **viralefy-core** (Go :8084) — fork 1:1 do legacy api, defense-in-depth, métricas
- [x] **viralefy-auth** (Go :8083) — 14 endpoints + 6 public routes + rate-limit + /internal/metrics
- [x] **viralefy-dispatcher** (Rust :8090) — JWKS cache + hot-set ArcSwap lock-free + /metrics dedicadas + rate-limit per-IP
- [x] **Caddy + Coraza WAF buildado** via xcaddy + OWASP CRS 4.10
- [x] **postgres-exporter v0.17.1** com role read-only + systemd hardened

### Observability completa

- [x] **5 dashboards Grafana** importados (revenue, payments, behavior, reliability, slo)
- [x] **15/16 Prometheus targets up** (legacy disabled intencional)
- [x] **/metrics em todos services**: core, auth, payments, sender, dispatcher (próprias), front, backoffice
- [x] **11 SLOs definidos** (availability 99.5%, p95 latency, dispatcher overhead, webhook ingestion, etc.)
- [x] **26 alerting rules** (SLO burn-rate, ServiceDown, DBConnectionExhausted, BackupFailed, etc.)
- [x] **Alertmanager skeleton** com inhibition rules
- [x] **Dispatcher p95 instrumentation bug fixed** (era core sendo scrapeado via fallback; real overhead 95µs = 528x headroom)
- [x] **Stripe reconcile freshness metric** (5 métricas Prometheus + SLO firing→OK)
- [x] **SLO dashboard com error budget** (16 panels)

### Ops automation

- [x] **viralefy-backup daily** — pg_dump compactado + retenção 7d/4w/6m
- [x] **viralefy-backup-verify daily** — gzip integrity + schema check + size anomaly
- [x] **viralefy-restore-drill weekly** — sandbox Docker isolated, 7s drill
- [x] **viralefy-reconcile daily** — 15 invariants de drift (orders/refresh_tokens/credits/etc)
- [x] **viralefy-user-deletion daily** — hard-delete físico LGPD grace 30d
- [x] **Backup loop bug 3 dias** fixado (chmod parent + capability)
- [x] **DR runbook + drill executado** — 9s warm cache / 1m45s cold projection vs 30min target = PASS

### LGPD (parcial)

- [x] **Endpoints LGPD existentes**: GET /v1/me/data/export, POST/DELETE /v1/me/data/deletion
- [x] **C3 RESOLVIDO** — Hard-delete cron implementado (Go + systemd timer)
- [x] **C5 RESOLVIDO** — Cookie consent default-OFF + backend skip PII se !consent
- [x] **user_consent_log table** (append-only, LGPD Art. 8 §6 prova de consent)
- [x] **user_events.analytics_consent** flag (privacy-by-default)
- [x] **Object storage migrator** (proofs base64 → MinIO, infra ready)
- [x] **LGPD self-audit baseline** (score BAIXA-MÉDIA, 5 gaps + roadmap 18d)

### Frontend polish

- [x] **Lighthouse CI gate** em front + backoffice
- [x] **Playwright CheckoutModal E2E** (11 testes desktop+mobile+a11y)
- [x] **data-testid** em CheckoutModal/BuyPlanCta/CouponInput
- [x] **@axe-core/playwright** a11y test ativo
- [x] **Sentry source maps no CI** (front + backoffice workflows)
- [x] **Cookie consent banner** com 4 categorias + audit log
- [x] **MOCK_AUTH bypass backoffice** pro Lighthouse dashboard

### Docs e runbooks (17+ files)

- [x] PHASE-9-ARCHITECTURE.md (1056 linhas)
- [x] PHASE-9-BUCKET-2-PLAN.md
- [x] CORAZA-SOAK-STATUS.md
- [x] PENTEST-BASELINE-2026-06-10.md (3 HIGH + 4 MEDIUM resolved, 3 deferred)
- [x] LGPD-BASELINE-2026-06-10.md
- [x] RUNBOOK-DR.md + drill executado
- [x] RUNBOOK-PROOF-MIGRATION.md + executado
- [x] RUNBOOK-USER-DELETION.md
- [x] RUNBOOK-COOKIE-CONSENT.md
- [x] RUNBOOK-BACKUP-VERIFY.md
- [x] RUNBOOK-INCIDENT-RESPONSE.md (955 linhas, 8 playbooks SEV1-4)
- [x] RUNBOOK-SMOKE-ADMIN.md (SQL-mint sem TOTP)
- [x] RUNBOOK-RENOVATE.md
- [x] SLO-DEFINITIONS.md
- [x] INCIDENT-ORDER-450F0E6F.md (reconcile FP)

### Dependency management

- [x] **Renovate config em 10 repos** (central preset + per-repo)
- [x] **govulncheck no CI** dos Go services
- [x] **cargo audit no CI** do dispatcher
- [x] **npm audit no CI** do front + backoffice

### Smoke admin Bucket 3 RBAC

- [x] **27/27 endpoints superadmin** OK (200)
- [x] **5/5 writes viewer** → 403 (RBAC OK)
- [x] **Hot-set revogação E2E em admin** → 1.75s
- [x] **Audit log gravado pelo core** (não pelo legacy)

### Critério "Fase 9 100% pronta" — 8/10 cumpridos

- [x] **Bucket 1-4 cutover completo, tráfego 100% no dispatcher**
- [x] **Hot-set revocation funcionando E2E** (82ms)
- [x] **Defense-in-depth core ValidateToken**
- [x] **5+ dashboards Grafana ativos**
- [x] **Smoke E2E dual-mode** (rollback validado todos buckets)
- [x] **api legacy parado** (soak iniciado)
- [x] **Runbook restore < 30min validado em DR drill**
- [x] **Coraza Block ATIVO**
- [ ] **api legacy removido** — esperando soak 14d até 2026-06-24
- [ ] **Pentest externo Tier 3** — orçamento

---

## ⏳ PENDÊNCIAS — Priorizado

### Time-gated (não pode acelerar)

- [ ] **[T]** **2026-06-24**: Soak legacy 14d completo → remover viralefy_api de viralefy-update + arquivar repo
- [ ] **[T]** **Após 14d soak Coraza** sem FP crítico → marcar produção estável
- [ ] **[T]** **Após 30d Coraza Block**: arquivar `CORAZA-SOAK-STATUS.md` como histórico

### Cliente precisa fornecer

- [ ] **[$]** `TELEGRAM_BOT_TOKEN` + `TELEGRAM_ADMIN_CHAT_ID` (notifs admin + checkout)
- [ ] **[$]** `SENTRY_DSN` + `NEXT_PUBLIC_SENTRY_DSN`
- [ ] **[$]** `SENTRY_AUTH_TOKEN` em GitHub Secrets (source maps CI)
- [ ] **[$]** `ADMIN_WEBHOOK_URL` (Slack/Discord pra alertas Prometheus)
- [ ] **[$]** `LHCI_GITHUB_APP_TOKEN` em GitHub Secrets (Lighthouse status checks)
- [ ] **[$]** **Instalar Renovate GitHub App** em github.com/Viralefy (https://github.com/apps/renovate)
- [ ] **[$]** Configurar Grafana contact points (após webhook fornecido)

### Externos (orçamento)

- [ ] **[E]** **Pentest externo Tier 3** (R$ 30-80k esperado) — focar IDOR/BOLA/business logic que self-pentest não cobre
- [ ] **[E]** **LGPD review formal** com advogado especialista (R$ 5-20k)
- [ ] **[E]** **Cloudflare WAF Business plan** ($200/mês) — após Coraza estável 30d
- [ ] **[E]** **Hetzner DR drill real** (cliente API token + sandbox CX22 ~€0.01/h)

### LGPD gaps (depende de cliente + jurídico)

- [ ] **[L]** **C1**: Designar DPO/Encarregado + criar `dpo@viralefy.com`
- [ ] **[L]** **C2**: Política de Privacidade atender Art. 9 LGPD (bases legais por finalidade, retenção, controlador, direitos, ANPD peticionar)
- [ ] **[L]** **C4**: Runbook ANPD 72h (notificação de incidente)
- [ ] **[L]** Termos de uso revisão jurídica
- [ ] **[L]** Cross-border data transfer formal (Art. 33) — Stripe Irlanda, Heleket, Resend

### Posso fazer em sessões futuras (tech debt)

#### Médio impacto
- [ ] **Server-side review sanitization (bluemonday.UGCPolicy)** — `ReviewService.Create` aceita HTML cru hoje; defesa única é JSX auto-escape no front (REVIEW-XSS-AUDIT.md). Defense-in-depth: sanitizar `body`+`title` antes do INSERT pra cobrir consumers não-React (admin futura UI, RSS, email digest, mobile).
- [ ] **Build automation reconcile/user-deletion no viralefy-update** (hoje scp manual)
- [ ] **Adicionar audit_log no InvoiceService.AdminMarkPaid** (silent hoje, dificultou investigação 450f0e6f)
- [ ] **Invariante reconcile**: `manual_paid_no_proof` (manual_pix paid sem order_proofs row)
- [ ] **Cloudflare WAF setup runbook** + DNS migration
- [ ] **Custom Grafana queries** pra metrics de PHASE-9 services (já scraped, ainda não em dashboard)
- [ ] **Plan_prices BTC drift** investigation (2 rows detectadas pelo cron, expected ou bug?)

#### Baixo impacto / Polish
- [ ] **Health paths standardization** (PHASE-10 tech debt — heterogeneity documented no smoke)
- [ ] **Stripe reconcile cron disable no legacy** — já moot (legacy parado)
- [ ] **DR drill executado em Hetzner real** (precisa cliente fornecer API token)
- [ ] **Smoke admin com TOTP físico** (precisa cliente ou TOTP shared)
- [ ] **Padronizar `/health` em todos services** (vs atual mix `/health`, `/internal/health`, `/_health`)

#### LGPD additional (não-bloqueadores)
- [ ] **Anonimização orders.email_at_purchase** após 5 anos fiscal
- [ ] **Padronizar consent renovação anual** com banner re-prompt
- [ ] **Cookie list pública** (legal/cookies page com lista atualizada)
- [ ] **Data Processing Agreements (DPAs)** com Stripe/Resend/Heleket/AbacatePay

### Decisão de produto pendente (não-tech)

- [ ] **[~]** Multi-vendor settlement model
- [ ] **[~]** WhatsApp provider real (Meta vs Twilio)
- [ ] **[~]** API B2B billing tier
- [ ] **[~]** Subscription pause/resume
- [ ] **[~]** Blog content engine
- [ ] **[~]** Backlinks outreach

### Tech debt observado / não-bloqueador

- [ ] **Migration tracker single-id** (timestamp-based ao invés de sequential N) — evita conflito agents paralelos
- [x] **dispatcher poll_secs 5s → 30s** (LISTEN/NOTIFY handles real-time)
- [ ] **Coraza paranoia 2 monitoring** — observar novos FPs em soak
- [x] **Order 450f0e6f resolved** (FP do manual_pix design)
- [ ] **/v1/reviews markdown injection** exclusion já preparada (não validada em real review yet)

### Smoke E2E gaps

- [ ] **E2E real authenticated user**: register → login → 2FA enroll → orders → API key (precisa test infra)
- [x] **Hot-set revogação real-time E2E** com user real (validado com test users 82ms + admin 1.75s)
- [x] **Reconciliação diária de orders** entre paths legacy vs core (legacy parado = não aplica; reconcile cron ativo)
- [ ] **Stripe sandbox**: full E2E checkout → webhook → order confirmed (precisa sandbox key)

---

## 🚨 Estado crítico pra não regredir

- [x] Migration tracker estilo Laravel — `schema_migrations` + checksum + auto-backfill prod legado
- [x] `Seed()` NÃO roda automático em boot
- [x] `ON CONFLICT DO UPDATE` → `DO NOTHING` em seeds
- [x] Caddy bloqueia `/internal/*` externamente (404)
- [x] CORE_PORT precedência sobre PORT
- [x] **CORS na borda do Caddy** (login depende, fix em 06-10 16:10 UTC)
- [x] **Coraza SecDefaultAction phase 1/2 → deny** (sem isso warning não block)
- [x] **Hot-set revocation enforce_hot_set middleware no dispatcher** (sem isso revoke = no-op)
- [x] **CRS exclusions ordem importa** (Include antes de rules/*.conf)
- [x] **Caddy restart vs reload** quando Coraza config muda (reload incremental, não rebuilda Coraza instance)
- [x] **viralefy-api scrape commented** em prometheus.yml (alertas ApiDown senão firing)

---

## 📊 Métricas operacionais (snapshot 2026-06-10 18:30 UTC)

| Métrica | Valor |
|---|---|
| Services active | 7/7 (api stopped intencional) |
| Prometheus targets up | 15/16 |
| Coraza Block rate (test) | 100% (SQLi+XSS+RCE → 403) |
| Hot-set revoke latency | 82ms (target ≤5s) |
| Dispatcher overhead p95 | 95µs (target ≤50ms = 528x headroom) |
| Backup state | 4 dumps recentes, 0 hard issues |
| TLS grade | A (testssl) |
| WAF block rate (pentest) | 82.4% (14/17 attack types) |
| Govulncheck vulns | 0 chamadas em todos services Go |
| Total stack RAM | ~260MB (apps) + 1.2GB (observability) |
| Smoke E2E | 100% pass |

---

## Quick commands

```bash
# Health check completo
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-smoke && systemctl is-active viralefy-{payments,sender,auth,core,dispatcher,caddy,postgres-exporter} && systemctl list-timers | grep viralefy'

# Logs Coraza WAF
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'tail -f /var/log/caddy-waf/audit.log'

# Logs hot-set
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'journalctl -u viralefy-dispatcher -f | grep -E "hot-set|revoked|NOTIFY"'

# Force revoke JTI (test)
psql "$DATABASE_URL" -c "INSERT INTO revoked_jtis (jti, expires_at) VALUES ('test-jti', NOW() + INTERVAL '1 hour'); SELECT pg_notify('revoked_jtis_inserted', 'test-jti');"

# Migrate status
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'sudo -u viralefy-core /usr/local/sbin/viralefy-core migrate status'

# Prometheus alerts firing
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'curl -s http://127.0.0.1:9090/api/v1/alerts | jq ".data.alerts[] | select(.state==\"firing\")"'

# Deploy zero-downtime
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-update --yes'

# Reconcile drift manual
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'systemctl start viralefy-reconcile && journalctl -u viralefy-reconcile --since "10 sec ago" -o cat | tail -5'

# User deletion cron manual
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'systemctl start viralefy-user-deletion && journalctl -u viralefy-user-deletion --since "10 sec ago" -o cat | tail -10'
```

---

## Repos no GitHub

| Repo | URL | Estado |
|---|---|---|
| viralefy_api (legacy) | https://github.com/Viralefy/viralefy_api | STOPPED, soak |
| viralefy_payments | https://github.com/Viralefy/viralefy_payments | Live |
| viralefy_sender | https://github.com/Viralefy/viralefy_sender | Live |
| viralefy_front | https://github.com/Viralefy/viralefy_front | Live + consent banner |
| viralefy_backoffice | https://github.com/Viralefy/viralefy_backoffice | Live |
| viralefy_ops | https://github.com/Viralefy/viralefy_ops | Live |
| viralefy_archive | https://github.com/Viralefy/viralefy_archive | Live (este repo) |
| **viralefy_core** | https://github.com/Viralefy/viralefy_core | Live (motor principal) |
| **viralefy_auth** | https://github.com/Viralefy/viralefy_auth | Live |
| **viralefy_dispatcher** | https://github.com/Viralefy/viralefy_dispatcher | Live (Rust) |

---

## 🎯 Próxima sessão — Priorizar

1. **Verificar prod healthy** (smoke + alerts)
2. **Check 2026-06-24 soak** se chegou — remover legacy api do repo
3. **Cliente forneceu Sentry/Telegram/Slack?** → configurar
4. **Cliente instalou Renovate App?** → primeiros PRs devem aparecer
5. **Pentest externo Tier 3** scheduled?
6. **Tech debt baixo impacto**: padronizar /health, anonimizar orders após 5 anos, etc.
