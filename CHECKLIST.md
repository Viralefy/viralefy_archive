# Viralefy — CHECKLIST.md

**Última atualização:** 2026-06-11 05:00 UTC

Convenção: `[x]` done · `[~]` parcial/decisão externa · `[ ]` pendente · `[!]` blocker · `[L]` LGPD/legal · `[T]` time-gated · `[$]` cliente fornecer · `[E]` externo (orçamento) · `[Q3]` planejado Q3 2026

---

## ✅ DONE — Estado consolidado de prod

### Cutover PHASE-9 (104+ rotas via dispatcher)

- [x] **Bucket 1** — /v1/plans*, /v1/categories*, /v1/currencies*, /v1/status*, /v1/country-ppp*, /v1/tax-rates*, /.well-known/jwks.json (7 rotas)
- [x] **Bucket 2 (a+b)** — /v1/me/* (38 rotas GET+POST+PUT+DELETE)
- [x] **Bucket 2c** — /v1/auth/* (6 rotas user+admin login/register/2fa) + viralefy_auth public routes
- [x] **Bucket 3** — /v1/admin/* (52+ rotas com RBAC)
- [x] **Bucket 4** — /v1/checkout (1 rota)
- [x] **Caddyfile default fallback** → dispatcher :8090
- [x] **Legacy api STOPPED + DISABLED** (2026-06-10 07:36 UTC, soak 14d até 2026-06-24)
- [x] **viralefy-update skipa legacy** (marker `/etc/viralefy/.legacy-deprecated`)
- [x] **JWKS bypass dispatcher** (SEV-2 fix 2026-06-11): Caddy direto → auth :8083 + Cache-Control 60s

### Segurança

- [x] **Coraza WAF SecRuleEngine On + Block real**
- [x] **SecDefaultAction phase 1/2 → deny,status:403**
- [x] **Coraza audit log JSON ativo**
- [x] **Coraza paranoia level 2** + bodyproc enforcement
- [x] **Exclusões CRS custom**: 900201 Stripe, 900300 reviews, 900601 password, 900700 REST methods, 900710/720 PL2, 900800/801/802 tracking URLs
- [x] **CORS preflight fix** (login estava quebrado pós-cutover, 405 → 204)
- [x] **Hot-set revogação E2E dispatcher**: 82ms (target ≤5s, 60x melhor)
- [x] **Defense-in-depth core ValidateToken** (RevocationCache + LISTEN/NOTIFY + 30s fallback)
- [x] **Host header tampering protection** (:443 catch-all → 421)
- [x] **Security headers em todos vhosts** (CSP, COEP/CORP, Permissions-Policy, HSTS preload)
- [x] **Permissions-Policy em api** (camera/microphone/geolocation/payment/usb negados — fix 2026-06-11)
- [x] **3 HIGH vulns fixados** (Go chi/jwt, npm tmp, rsa@0.9.10 risk-accepted)
- [x] **Pentest MEDIUM #4 #5 #7 #10 fixados** (host, CRLF, COEP/CORP, Server header)
- [x] **Reviews XSS audit + fix** — rule 900300 estava broken (URI errada + phase 1), 12 payloads testados

### Infraestrutura PHASE-9

- [x] **viralefy-core** (Go :8084) — defense-in-depth + métricas + 4 crons
- [x] **viralefy-auth** (Go :8083) — 14 endpoints + 6 public routes + rate-limit
- [x] **viralefy-dispatcher** (Rust :8090) — JWKS cache + hot-set ArcSwap + /metrics próprias
- [x] **Caddy + Coraza WAF buildado** via xcaddy + OWASP CRS 4.10
- [x] **postgres-exporter v0.17.1** com role read-only

### Observability completa

- [x] **6 dashboards Grafana** (revenue, payments, behavior, reliability, slo, phase9 com 26 painéis)
- [x] **15/16 Prometheus targets up**
- [x] **/health unificado** em todos services + backward compat (PHASE-10)
- [x] **/metrics em todos services**: core, auth, payments, sender, dispatcher, front, backoffice
- [x] **11 SLOs definidos** + 26 alerting rules
- [x] **Alertmanager skeleton** com inhibition rules
- [x] **Dispatcher p95 instrumentation bug fixed** (95µs = 528x headroom)
- [x] **Stripe reconcile freshness metric** (5 métricas Prometheus)

### Ops automation (7 timers ativos)

- [x] **viralefy-backup** daily 03:00 UTC
- [x] **viralefy-backup-verify** daily 04:09 UTC
- [x] **viralefy-restore-drill** weekly Sun 05:09 UTC
- [x] **viralefy-reconcile** daily 03:37 UTC (16 invariants)
- [x] **viralefy-user-deletion** daily 03:53 UTC (LGPD grace 30d)
- [x] **viralefy-test-cleanup** hourly :17 UTC (limpa `*@viralefy.test`)
- [x] **viralefy-orders-anonymize** monthly 04:30 UTC (LGPD Art. 16 5y)
- [x] **Backup loop bug 3 dias** fixado
- [x] **DR runbook + drill executado** — 9s warm cache / 1m45s cold projection
- [x] **Build automation reconcile/user-deletion no viralefy-update**

### LGPD

- [x] **Endpoints existentes**: GET /v1/me/data/export, POST/DELETE /v1/me/data/deletion, POST /v1/me/consent
- [x] **C3 RESOLVIDO** — Hard-delete cron implementado
- [x] **C5 RESOLVIDO** — Cookie consent default-OFF + backend skip PII se !consent
- [x] **user_consent_log table** (append-only, LGPD Art. 8 §6)
- [x] **user_events.analytics_consent** flag (privacy-by-default)
- [x] **/legal/cookies página pública** — inventário completo de cookies, multilíngue
- [x] **Consent renewal anual** — TTL 365d + re-prompt automático
- [x] **Orders anonymize 5y** — cron mensal + métricas textfile
- [x] **Object storage migrator** (proofs base64 → MinIO)
- [x] **LGPD self-audit baseline** (score BAIXA-MÉDIA, 5 gaps + roadmap 18d)

### Frontend polish

- [x] **Lighthouse CI gate** em front + backoffice
- [x] **Playwright CheckoutModal E2E** (11 testes desktop+mobile+a11y)
- [x] **data-testid** em CheckoutModal/BuyPlanCta/CouponInput
- [x] **@axe-core/playwright** a11y test ativo
- [x] **Sentry source maps no CI**
- [x] **Cookie consent banner** com 4 categorias + audit log + renovação anual
- [x] **MOCK_AUTH bypass backoffice** pro Lighthouse

### Test Kit (PHASE-10 §22 diretrizes)

- [x] **CLI `viralefy-test`** com 14 subcommands
- [x] **tests/lib.sh** (helpers compartilhados)
- [x] **tests/smoke/** — 9 scripts (9/9 pass em 3s)
- [x] **tests/pentest/** — 27 scripts OWASP (27/27 pass em 21s)
- [x] **tests/security/** — 10 scripts (9/10 pass)
- [x] **tests/hardening/** — 10 scripts (6/10 pass + 4 findings reais)
- [x] **tests/authz/** — 10 scripts RBAC + BOLA (10/10 pass em 186s)
- [x] **tests/integration/** — 10 scripts E2E
- [x] **tests/chaos/** — 10 scripts (3 gated por env destrutivo)
- [x] **tests/simulated/** — engine Python (125 rotas × 6 personas × 26 injections = 19.500 combos)
- [x] **tests/seeds/** — 5 personas SQL idempotentes
- [x] **External smoke** GitHub Actions cron 15min (36 assertions)
- [x] **summary.json schema** §22.2 (fonte única pra dashboards)

### Engineering Conformance (§22 diretrizes)

- [x] **10 ADRs criados** em formato MADR (shared DB, HTTP loopback, bcrypt 12, legacy soak, single tenant, Coraza, migrations seq, Next.js, multi-repo, payment ACL)
- [x] **ENGINEERING-CONFORMANCE-AUDIT.md** com tabela §0-§35 + DDD audit por repo + roadmap Q3
- [x] **DDD compliance verified**: 0 imports proibidos em domain/ em todos os 5 Go repos
- [x] **payments + sender = referência limpa** (0 imports cross, arquivos < 500 linhas)

### Docs e runbooks (33 MDs + 10 ADRs no archive)

Ver `INDEX.md` para mapa completo.

### Dependency management

- [x] **Renovate config em 10 repos** (central preset + per-repo)
- [x] **govulncheck no CI** dos Go services
- [x] **cargo audit no CI** do dispatcher
- [x] **npm audit no CI** do front + backoffice

### Smoke admin Bucket 3 RBAC

- [x] **27/27 endpoints superadmin** OK
- [x] **5/5 writes viewer** → 403 (RBAC OK)
- [x] **Hot-set revogação E2E em admin** → 1.75s
- [x] **Audit log gravado pelo core**

### Critério "Fase 9 100% pronta" — 8/10 cumpridos

- [x] **Bucket 1-4 cutover completo, tráfego 100% no dispatcher**
- [x] **Hot-set revocation funcionando E2E** (82ms)
- [x] **Defense-in-depth core ValidateToken**
- [x] **6 dashboards Grafana ativos** (+1 phase9)
- [x] **Smoke E2E dual-mode** (rollback validado todos buckets)
- [x] **api legacy parado** (soak iniciado)
- [x] **Runbook restore < 30min validado em DR drill**
- [x] **Coraza Block ATIVO**
- [ ] **api legacy removido** — esperando soak 14d até 2026-06-24
- [ ] **Pentest externo Tier 3** — orçamento

---

## 🚨 Incidentes resolvidos esta semana

| Data | Evento | Severidade | Status |
|---|---|---|---|
| 2026-06-10 | CORS preflight 405 (login quebrado) | SEV-2 | ✅ FIXED |
| 2026-06-10 | Coraza RFI rule 931130 bloqueando tracking URLs | SEV-2 | ✅ FIXED |
| 2026-06-10 | Coraza PUT/PATCH/DELETE bloqueado | SEV-2 | ✅ FIXED |
| 2026-06-10 | Coraza password 942100 FP | LOW | ✅ FIXED |
| 2026-06-10 | viralefy-backup loop falha 3 dias | SEV-3 | ✅ FIXED |
| 2026-06-11 | JWKS rate-limited 429 | **SEV-2** | ✅ FIXED |
| 2026-06-11 | Backoffice down 502 (killed pelo systemd) | SEV-2 | ✅ FIXED (restart) |
| 2026-06-11 | API missing Permissions-Policy | LOW | ✅ FIXED |
| 2026-06-10 | Order 450f0e6f FP reconcile (manual_pix) | LOW | ✅ FIXED (query refine) |

---

## ⏳ PENDÊNCIAS — Priorizado

### Time-gated (não pode acelerar)

- [ ] **[T]** **2026-06-24**: Soak legacy 14d completo → remover viralefy_api de viralefy-update + arquivar repo
- [ ] **[T]** **Após 14d Coraza sem FP crítico** → marcar produção estável
- [ ] **[T]** **Após 30d Coraza Block**: arquivar `CORAZA-SOAK-STATUS.md` como histórico

### Cliente precisa fornecer

- [ ] **[$]** `TELEGRAM_BOT_TOKEN` + `TELEGRAM_ADMIN_CHAT_ID` (notifs admin + checkout)
- [ ] **[$]** `SENTRY_DSN` + `NEXT_PUBLIC_SENTRY_DSN`
- [ ] **[$]** `SENTRY_AUTH_TOKEN` em GitHub Secrets (source maps CI)
- [ ] **[$]** `ADMIN_WEBHOOK_URL` (Slack/Discord pra alertas Prometheus)
- [ ] **[$]** `LHCI_GITHUB_APP_TOKEN` em GitHub Secrets
- [ ] **[$]** **Instalar Renovate GitHub App** em github.com/Viralefy
- [ ] **[$]** Configurar Grafana contact points (após webhook fornecido)

### Externos (orçamento)

- [ ] **[E]** **Pentest externo Tier 3** (R$ 30-80k) — focar IDOR/BOLA/business logic
- [ ] **[E]** **LGPD review formal** com advogado especialista (R$ 5-20k)
- [ ] **[E]** **Cloudflare WAF Business** ($200/mês) — após Coraza estável 30d (gate: >5M req/dia OU primeiro DDoS L7)
- [ ] **[E]** **Hetzner DR drill real** (API token + sandbox CX22)

### LGPD gaps (depende de cliente + jurídico)

- [ ] **[L]** **C1**: Designar DPO/Encarregado + criar `dpo@viralefy.com`
- [ ] **[L]** **C2**: Política de Privacidade atender Art. 9 LGPD
- [ ] **[L]** **C4**: Runbook ANPD 72h (notificação de incidente)
- [ ] **[L]** Termos de uso revisão jurídica
- [ ] **[L]** Cross-border data transfer formal (Art. 33)
- [ ] **[L]** DPAs (Data Processing Agreements) com Stripe/Resend/Heleket/AbacatePay

### Findings do Test Kit (Q3)

- [ ] **CAA records ausentes** em viralefy.com (qualquer CA pode emitir cert)
- [ ] **DNSSEC** zona viralefy.com não assinada
- [ ] **HSTS preload list** — submeter em https://hstspreload.org/?domain=viralefy.com
- [ ] **Manager POST /v1/admin/plans → 500** — handler validation bug
- [ ] **Backoffice systemd OOM/idle kill** — investigar `Stopping` no journal

### Tech debt — Médio impacto (Q3 2026)

- [ ] **[Q3]** Quebrar `handlers.go` do `viralefy_core` (3325 linhas) por bounded context (auth/checkout/orders/admin/plans)
- [ ] **[Q3]** Quebrar `handlers.go` do `viralefy_api` legacy (3125 linhas) — N/A após remove 2026-06-24
- [ ] **[Q3]** Generalizar `event_outbox` no core (hoje só sender)
- [ ] **[Q3]** Linter custom impedindo queries cross-context na shared DB (ADR-0001)
- [ ] **[Q3]** Migration tracker timestamp-based (evita conflito agents paralelos)
- [ ] **[Q3]** **Reviews backend bluemonday.UGCPolicy()** — hoje defesa única é React JSX escape
- [ ] **[Q3]** Centralizar `bcryptCost` em `shared/crypto`
- [ ] **[Q3]** Cloudflare setup runbook + DNS migration (gate: >5M req/dia)

### Tech debt — Baixo impacto

- [ ] **Padronizar /health endpoint response shape** (uniformizar JSON keys)
- [ ] **DR drill executado em Hetzner real** (precisa cliente fornecer API token)
- [ ] **Smoke admin com TOTP físico** (precisa cliente)
- [ ] **Padronizar `paid_at` column** entre orders e invoices
- [ ] **Plan_prices BTC drift** — front sobrescreve baseline (Q3 fix UX form)

### LGPD additional (não-bloqueadores)

- [ ] **Padronizar consent renovação** com banner UX mais sutil
- [ ] **DPIA** (Data Protection Impact Assessment) — auditoria interna formal
- [ ] **Política de retenção** por tipo de dado documentada
- [ ] **Processo formal de direitos do titular** (atendimento)

### Decisão de produto pendente (não-tech)

- [ ] **[~]** Multi-vendor settlement model
- [ ] **[~]** WhatsApp provider real (Meta vs Twilio)
- [ ] **[~]** API B2B billing tier
- [ ] **[~]** Subscription pause/resume
- [ ] **[~]** Blog content engine
- [ ] **[~]** Backlinks outreach

### Smoke E2E gaps (precisam credenciais reais)

- [ ] **Smoke E2E admin com TOTP** (cliente forneça secret)
- [ ] **Stripe sandbox**: full E2E checkout → webhook → order confirmed (precisa sandbox key)
- [ ] **Heleket sandbox**: webhook signature validation real
- [ ] **AbacatePay sandbox**: PIX dinâmico flow real

---

## 🚨 Estado crítico pra não regredir

- [x] Migration tracker estilo Laravel — `schema_migrations` + checksum + auto-backfill
- [x] `Seed()` NÃO roda automático em boot
- [x] `ON CONFLICT DO UPDATE` → `DO NOTHING` em seeds
- [x] Caddy bloqueia `/internal/*` externamente (404)
- [x] CORE_PORT precedência sobre PORT
- [x] **CORS na borda do Caddy** (login depende, fix 06-10)
- [x] **Coraza SecDefaultAction phase 1/2 → deny** (sem isso warning não block)
- [x] **Hot-set revocation enforce_hot_set middleware no dispatcher**
- [x] **CRS exclusions ordem importa** (Include antes de rules/*.conf)
- [x] **Caddy restart vs reload** quando Coraza config muda
- [x] **viralefy-api scrape commented** em prometheus.yml (alertas ApiDown senão firing)
- [x] **JWKS bypass dispatcher rate-limit** (Caddy proxy direto pra auth, SEV-2)
- [x] **Coraza 931xxx (RFI) exclusions em paths com tracking URLs**
- [x] **Permissions-Policy em API** (defense-in-depth)
- [x] **Backoffice systemd MUST stay active** (502 quando killed)

---

## 📊 Métricas operacionais (snapshot 2026-06-11 05:00 UTC)

| Métrica | Valor |
|---|---|
| Services active | 9/9 (api stopped intencional) |
| Prometheus targets up | 15/16 |
| Coraza Block rate (test) | 100% (SQLi/XSS/RCE/Method tampering → 403) |
| Hot-set revoke latency | 82ms (target ≤5s) |
| Dispatcher overhead p95 | 95µs (target ≤50ms = 528x headroom) |
| JWKS availability | 100% (Caddy bypass dispatcher rate-limit) |
| Backup state | 4 dumps recentes, 0 hard issues |
| TLS grade | A (testssl) |
| WAF block rate (pentest) | 100% (27/27 OWASP scripts) |
| Govulncheck vulns | 0 chamadas em todos services Go |
| Total stack RAM | ~560MB (apps) + 1.2GB (observability) |
| Smoke E2E | 9/9 pass em 3s |
| Pentest | 27/27 pass em 21s |
| Authz | 10/10 pass em 186s |

---

## Quick commands

```bash
# Health check completo
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-test smoke && systemctl is-active viralefy-{payments,sender,auth,core,dispatcher,caddy,postgres-exporter,backoffice,front} && systemctl list-timers | grep viralefy'

# Full test suite
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-test all'

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
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'systemctl start viralefy-reconcile && journalctl -u viralefy-reconcile --since "10 sec ago" -o cat | tail -10'

# Backup verify
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-backup-verify'

# Seed test data
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-test seed-all'

# Clean test users
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-test clean-seeds'
```

---

## Repos no GitHub

| Repo | URL | Estado |
|---|---|---|
| viralefy_api (legacy) | https://github.com/Viralefy/viralefy_api | STOPPED, soak até 2026-06-24 |
| viralefy_payments | https://github.com/Viralefy/viralefy_payments | Live |
| viralefy_sender | https://github.com/Viralefy/viralefy_sender | Live |
| viralefy_front | https://github.com/Viralefy/viralefy_front | Live + cookies/legal |
| viralefy_backoffice | https://github.com/Viralefy/viralefy_backoffice | Live |
| viralefy_ops | https://github.com/Viralefy/viralefy_ops | Live + Test Kit §22 |
| viralefy_archive | https://github.com/Viralefy/viralefy_archive | Live (este repo) |
| **viralefy_core** | https://github.com/Viralefy/viralefy_core | Live (motor principal) |
| **viralefy_auth** | https://github.com/Viralefy/viralefy_auth | Live |
| **viralefy_dispatcher** | https://github.com/Viralefy/viralefy_dispatcher | Live (Rust) |

---

## 🎯 Próxima sessão — Priorizar

1. **Verificar prod healthy** (`viralefy-test smoke` + check alerts)
2. **Check 2026-06-24** se chegou — remover legacy api do repo + arquivar
3. **Cliente forneceu Sentry/Telegram/Slack?** → configurar
4. **Cliente instalou Renovate App?** → primeiros PRs aparecem segunda-feira
5. **Pentest externo Tier 3** scheduled?
6. **CAA records + DNSSEC** — fix DNS findings hardening
7. **Submit HSTS preload list**
8. **Q3 refactor**: handlers.go por bounded context (start by /v1/auth/* extraction)
