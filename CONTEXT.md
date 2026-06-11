# Viralefy — CONTEXT.md (snapshot pra compactação)

**Última atualização:** 2026-06-11 03:50 UTC (PHASE-9 fechado + hardening + LGPD adicional 3 itens + observability completa + external smoke ativo + internal smoke E2E checkout + test-cleanup cron)

Este arquivo é o "leia primeiro" pra qualquer próxima sessão. Resume estado factual sem narrativa.

---

## 1. Plataforma em 60s

Marketplace BR de engajamento Instagram/TikTok, **prod live em https://www.viralefy.com**, faturando. 130 países × 47 idiomas × 12 categorias ativas. USD/USDT canonical, multi-moeda display.

**VPS única:** Debian 13 trixie · 8c/16GB · 134GB livres · `root@62.238.41.231`.

**Faturamento ativo:**
- **Stripe** rk_live_ — webhooks em `api.viralefy.com/v1/webhooks/stripe`
- **Heleket** crypto, USDT settlement
- **AbacatePay** PIX dinâmico
- ~~manual_pix~~ desativado (legado, preserva orders)
- ~~woovi~~ inactive

**Autenticação:** JWT RS256 + 2FA TOTP. `kid=vfCOltLYjII` compartilhado entre legacy/core/auth.

---

## 2. Acesso

| Recurso | URL | Credencial |
|---|---|---|
| Storefront | https://www.viralefy.com | — |
| Backoffice | https://admin.viralefy.com | `viralefy@gmail.com` / `VfIULsiPGXKZGjGfu2yn!` (superadmin 2FA enrolled) |
| API | https://api.viralefy.com | Bearer RS256 |
| Observability | https://obs.viralefy.com | `admin` / `6FU6jXSmzJlrPSCBJ6JNprW5dqMYCO1l` |
| SSH | `root@62.238.41.231` | `awk '/BEGIN OPENSSH/,/END OPENSSH/' /media/sonne/Archives/projects/viralefy/credentials > /tmp/vf-ssh.key && chmod 600 /tmp/vf-ssh.key` |
| Postgres | local na VPS | senha em `/etc/viralefy/.env` |
| GitHub | https://github.com/Viralefy | 10 repos públicos |

---

## 3. Arquitetura PHASE-9 — 100% cutover ativo

```
INTERNET
   ↓
Caddy 2.11.3 + Coraza WAF + OWASP CRS 4.10 (SecRuleEngine ON, block real)
   ├── www → viralefy-front (Next 15, :3000)
   ├── admin → viralefy-backoffice (:3001)
   ├── obs → Grafana (:3030) [5 dashboards + Loki + Tempo + Alloy + Alertmanager skeleton]
   └── api → ROTEAMENTO POR PATH:
        │
        ├── /v1/plans*, /v1/categories*, /v1/currencies*, /v1/status*,
        │   /v1/country-ppp*, /v1/tax-rates*  → dispatcher :8090 → core :8084
        ├── /.well-known/jwks.json            → dispatcher :8090 → auth :8083
        ├── /v1/auth/*                        → dispatcher :8090 → auth :8083
        ├── /v1/me/*                          → dispatcher :8090 → core :8084
        ├── /v1/admin/*                       → dispatcher :8090 → core :8084
        ├── /v1/checkout                      → dispatcher :8090 → core :8084
        ├── /v1/webhooks/{stripe,heleket,...} → payments :8081 (direto)
        ├── /internal/*                       → 404 (defesa em profundidade)
        └── catch-all (paths novos)           → dispatcher :8090 (fallback)

viralefy-api LEGACY :8080 STOPPED + DISABLED (soak 14d até 2026-06-24).
Catch-all `:443 { tls internal; respond 421 }` pra Host header tampering.

Coraza rules: SQLi/XSS/RCE → 403 BLOCKED. PUT/PATCH/DELETE liberados
(exclusion 900700). Password password-manager (PL2) ok via 900601.
```

**Auth interno entre services:** `INTERNAL_SHARED_SECRET` em `X-Internal-Token`. Loopback-only.

**Object storage:** MinIO Docker `/var/lib/viralefy-storage/`, S3-compat (proofs bucket + public). Migrator binary criado, 0 rows pra migrar em HML (todos NULL ou já no MinIO).

---

## 4. 10 Repositórios (Viralefy GitHub org)

| Repo | Função | Estado |
|---|---|---|
| `viralefy_api` | Monolito Go LEGACY (port 8080) | STOPPED + DISABLED, soak até 2026-06-24 |
| `viralefy_payments` | Providers + webhooks (8081) | Live, /internal/metrics expostas |
| `viralefy_sender` | Email + telegram + outbox (8082) | Live, /internal/metrics expostas |
| `viralefy_front` | Next.js storefront | Live + cookie consent default-OFF |
| `viralefy_backoffice` | Next.js admin panel | Live + MOCK_AUTH bypass + /api/metrics |
| `viralefy_ops` | systemd + installer + Caddy + CLIs | Live, 5 timers + 26 alerts + 5 dashboards |
| `viralefy_archive` | docs + memory (este repo) | Live, 17+ runbooks/docs |
| **`viralefy_core`** | **Motor Go (port 8084)** | Live, defense-in-depth + métricas + reconcile + user-deletion |
| **`viralefy_auth`** | **Identidade Go (port 8083)** — JWT + 2FA + hot-set | Live, /internal/metrics + public auth routes |
| **`viralefy_dispatcher`** | **Borda Rust (port 8090)** — sanitiza + proxy + JWT verify | Live, hot-set ArcSwap lock-free + /metrics próprias |

---

## 5. Stack em prod (mem usage real)

| Port | Service | Mem | Linguagem |
|---|---|---|---|
| 8080 | ~~viralefy-api LEGACY~~ | STOPPED | Go |
| 8081 | viralefy-payments | 28MB | Go |
| 8082 | viralefy-sender | 28MB | Go |
| 8083 | viralefy-auth | 24MB | Go |
| 8084 | viralefy-core | 40MB | Go |
| 8090 | viralefy-dispatcher | 11MB | Rust |
| — | Caddy + Coraza | 100MB | Go + WAF |
| 9187 | postgres-exporter | 23MB | Go |

**Stack apps: ~260MB. Observability adicional (Prometheus+Grafana+Loki+Tempo+Alloy): ~1.2GB.**

---

## 6. Schema DB (44 migrations aplicadas)

Migration tracker tipo Laravel — `schema_migrations` com checksum SHA256, auto-backfill detecta prod legado, `Seed()` opt-in.

**Últimas migrations:**
- 040: proof_storage_key (orders.proof_storage_key + index)
- 042: user_deletion_grace_period (status enum + executed_at + error_message + orders nullable user_id + email/name snapshot)
- 043: user_deletion_drop_fk (FK user_deletion_requests.user_id → users dropada pra LGPD anonymization)
- 044: user_consent (user_consent_log + user_events.analytics_consent)

⚠️ 041 vazio (conflict de agents paralelos resolvido renomeando consent → 044). Não há migration 041 real.

**Núcleo:** users, admins, roles, role_permissions, plans, plan_prices, categories, orders (com email_at_purchase + name_at_purchase pra LGPD), order_refunds, order_proofs, payment_gateways, stripe_events_processed, credit_accounts, credit_transactions, invoices, profiles, subscriptions.

**Tracking + LGPD:** user_events (analytics_consent flag, IP/UA NULL se consent=false), user_journeys, ab_*, user_consent_log (append-only), user_deletion_requests (grace 30d).

**Segurança & PHASE-9:** admin_2fa, user_2fa, refresh_tokens (rotação), revoked_jtis (hot-set + LISTEN/NOTIFY canal `revoked_jtis_inserted`), password_resets, audit_log (imutável), idempotency_keys.

**Features:** coupons, reviews, tickets, ticket_messages, referral_rewards, api_keys, currencies, country_ppp, tax_rates, email_events, email_reputation, fraud_signals, fraud_blocks, vendors, user_contact.

---

## 7. Auth dual-sign + hot-set + defense-in-depth

- **Mint:** todos services emitem RS256 com `kid=vfCOltLYjII`
- **Verify:** RS256 primário + HS256 fallback
- **2FA:** TOTP RFC 6238 + AES-256-GCM secret encryption + bcrypt backup codes
- **Hot-set revogação E2E em 82ms** (target ≤5s, 60x melhor):
  - **Dispatcher Rust** via PgListener + ArcSwap<HashSet> (lock-free reads)
  - **Core Go** defense-in-depth via RevocationCache (LISTEN/NOTIFY + 30s poll fallback) — bypass dispatcher também rejeita
- **Refresh tokens:** rotação encadeada (anti-replay), TTL 30d, replay → force-logout do subject inteiro

---

## 8. Env vars críticas em `/etc/viralefy/.env`

**Presentes em prod:** DATABASE_URL, JWT_SECRET + JWT_PRIVATE_KEY_PATH, TWOFA_ENCRYPTION_KEY, INTERNAL_SHARED_SECRET, RESEND_API_KEY, TURNSTILE_SECRET_KEY, STORAGE_ACCESS/SECRET_KEY (MinIO), PAYMENTS/SENDER_INTERNAL_URL, GRAFANA_ADMIN_PASSWORD, postgres_exporter password (em `/etc/viralefy/postgres-exporter.env`).

**Env por service (systemd unit):** core CORE_PORT=8084, auth VAUTH_BIND_ADDR/TTLs, dispatcher VAPI_BIND_ADDR + VAPI_*_URL + VAPI_JWKS_CACHE_TTL_SECS=60 + VAPI_REVOKED_POLL_SECS=30.

**Opt-in pendentes (cliente fornecer):**
- `SENTRY_DSN` / `NEXT_PUBLIC_SENTRY_DSN` — error tracking
- `SENTRY_AUTH_TOKEN` — GitHub Secret pra source maps CI
- `TELEGRAM_BOT_TOKEN` / `TELEGRAM_ADMIN_CHAT_ID`
- `ADMIN_WEBHOOK_URL` — Slack/Discord
- `LHCI_GITHUB_APP_TOKEN` — Lighthouse status checks
- Renovate GitHub App — instalar via https://github.com/apps/renovate

---

## 9. Operação day-a-day

| Ação | Comando |
|---|---|
| Deploy | `ssh root@62.238.41.231 'viralefy-update --yes'` |
| Smoke | `ssh root@62.238.41.231 'viralefy-smoke'` |
| Status | `ssh root@62.238.41.231 'viralefy-status'` |
| Logs core/auth/dispatcher | `journalctl -u viralefy-<svc> -f` |
| Logs Coraza | `tail -f /var/log/caddy-waf/audit.log` |
| Migrate | `sudo -u viralefy-core /usr/local/sbin/viralefy-core migrate {status,up}` |
| Backup/Verify/Restore | `viralefy-backup`, `viralefy-backup-verify`, `viralefy-restore-drill` |
| Reconcile drift | `systemctl start viralefy-reconcile` |
| Hard-delete users | `systemctl start viralefy-user-deletion` |

---

## 10. Coraza WAF — SecRuleEngine ON (Block real) ATIVO

- xcaddy v2.11.3 + coraza-caddy/v2 + OWASP CRS 4.10.0
- `SecRuleEngine On` (2026-06-10 12:20 UTC)
- `SecDefaultAction phase:1/2 → deny,status:403` (causa raiz do não-bloquear: era `pass`)
- `SecAuditLog /var/log/caddy-waf/audit.log` JSON, RelevantStatus `.*`
- Paranoia level 2 + bodyproc enforcement (pentest fix #5)

**Exclusões custom em `/etc/caddy/coraza/coraza-crs-exclusions.conf`:**
- `id:900201` Stripe webhook signature bypass
- `id:900601` phase 2 — exclui ARGS:*password de rule 942100 (libinjection FP em senhas password-manager)
- `id:900700` phase 1 — `tx.allowed_methods=GET HEAD POST OPTIONS PUT PATCH DELETE`
- `id:900710` paranoia 2
- `id:900720` bodyproc enforcement

**Validado em prod — TODOS BLOCKED 403:** SQLi (4 variants), XSS (2 variants), Host header tampering → 421.

**Legitimate traffic intacto:** registers com password password-manager → 201, GETs → 200, REST methods PUT/PATCH/DELETE → 401 (auth gate, não WAF).

---

## 11. CORS + Security Headers

CORS na borda (Caddy responde preflight, evita 405 do dispatcher):
- `OPTIONS` → 204 + ACAO headers reflectindo Origin
- POST/GET com Origin → adiciona `Access-Control-Allow-Origin` dinâmico

Security headers em todos vhosts:
- HSTS preload, X-Content-Type-Options nosniff
- CSP (front: GTM/Cloudflare Turnstile permitidos; backoffice: frame-ancestors none)
- Cross-Origin-Resource-Policy (same-site front+api, same-origin backoffice+obs)
- Cross-Origin-Embedder-Policy require-corp (backoffice apenas)
- Permissions-Policy, Referrer-Policy
- `-Server -X-Powered-By`

---

## 12. Observability completa

**Prometheus:** 15/16 targets up (legacy api desabilitado intencional).

**Services com /metrics:** core, auth, payments, sender, dispatcher (próprias), front, backoffice (/api/metrics), caddy, postgres-exporter, node-exporter, prometheus, grafana, loki, tempo, alloy.

**Grafana 5+ dashboards importados:**
- viralefy-revenue, viralefy-payments, viralefy-behavior, viralefy-reliability, viralefy-slo (error budget + burn rate), viralefy-api-red (pre-existente).

**SLOs (11):** api availability 99.5%, api p95 <500ms, **dispatcher overhead <50ms (atual 95µs = 528x headroom)**, payments webhook 99.9%, db query p95 <100ms, etc.

**Alerting (26 rules):** SLO burn-rate multi-window, ServiceDown, DBConnectionExhausted, DiskSpaceLow, BackupFailed, ReconcileDriftHigh, CorazaBlockSpike, AuthBruteforce, CertExpiringSoon, etc. Alertmanager skeleton com inhibition rules. Webhook ADMIN_WEBHOOK_URL TODO cliente.

---

## 13. Cron jobs (systemd timers)

| Timer | Frequência | Função |
|---|---|---|
| viralefy-backup | daily 03:00 UTC | pg_dump compactado + retenção 7d/4w/6m |
| viralefy-backup-verify | daily 04:09 UTC | gzip integrity + schema check + size anomaly |
| viralefy-restore-drill | weekly Sun 05:09 UTC | sandbox Docker isolated, restore 7s |
| viralefy-reconcile | daily 03:37 UTC | 15 invariants de drift (orders, refresh_tokens, credits, etc) |
| viralefy-user-deletion | daily 03:53 UTC | hard-delete físico LGPD (grace 30d → exec) |
| viralefy-orders-anonymize | monthly dia 1 04:30 UTC | anonimização PII em orders >5y (Receita 5y + LGPD Art. 16). Sentinela `[ANONYMIZED]` preserva id/total/currency/gateway_id (fiscais). Métricas `viralefy_orders_anonymized_total` + `viralefy_orders_anonymize_pending_count` (textfile collector). |

**Crons in-process (rodam dentro de viralefy-core):**
- stripe_reconcile (5min, polling Stripe Sessions API + métricas Prometheus)
- event_retention (24h, max 90d em user_events/email_events/ab_events)
- plan_price_drift (1h, alerta drift entre plan_prices)
- review_request (1h, batch 50, delay 7d pós-delivery)

---

## 14. Renovate (cliente precisa instalar App)

Config em 10 repos via central preset `viralefy_ops/renovate-config.json`. Schedule Monday 09:00 BRT, group por linguagem, automerge patches non-major, lockfile maintenance mensal. Vulnerability alerts trigger urgent labels.

**Vuln scans no CI:**
- Go: `govulncheck ./...` (continue-on-error: true)
- Rust: `cargo audit`
- Node: `npm audit --audit-level=high`
- Workflow `security.yml` em auth/payments/sender/api_rust

---

## 14.B Test Kit `<project>_ops/tests/` (§22.3 diretrizes)

| modo | scripts | onde | gate |
|---|---|---|---|
| smoke | 7 | viralefy_ops/tests/smoke/ | sempre roda |
| pentest | 5+ | viralefy_ops/tests/pentest/ | sempre roda |
| security | 1 | viralefy_ops/tests/security/ | sempre roda |
| **integration** | **10** (2026-06-11) | viralefy_ops/tests/integration/ | requer seeds + env (SUPERADMIN_PASS, STRIPE_WEBHOOK_SECRET, DATABASE_URL) |
| **chaos** | **10** (2026-06-11) | viralefy_ops/tests/chaos/ | service-kill/db-disconnect/partition-test gated por `EDUCE_CHAOS_ALLOW=1` |

Helpers em `tests/lib.sh`: `test_section`, `test_pass`, `test_fail`,
`test_skip`, `test_summary`, `http_call`, `assert_http_in`,
`assert_http_status`, `assert_json_field`, `assert_header_present`,
`assert_no_pii`.

Skip vs fail: scripts skipam graciosamente quando env/deps ausentes
(retornam exit 0 e contam só skip); falhas reais são exit 1 + banner FAIL.

Findings recentes pela run em HML (2026-06-11): JWKS endpoint sob
IPLimiter (SEV-2 — bumpar quota). Detalhes em CHECKLIST.md.

---

## 15. Documentos no archive (referência)

| Doc | Conteúdo |
|---|---|
| **CONTEXT.md** | este arquivo |
| **CHECKLIST.md** | done + pending priorizado |
| PHASE-9-ARCHITECTURE.md | plano original (1056 linhas) |
| PHASE-9-BUCKET-2-PLAN.md | split 2a/2b/2c (159 linhas) |
| CORAZA-SOAK-STATUS.md | re-audit + fix dos FPs |
| **PENTEST-BASELINE-2026-06-10.md** | self-pentest baseline + resolved findings |
| **LGPD-BASELINE-2026-06-10.md** | self-audit + 5 gaps + roadmap 18d |
| RUNBOOK-DR.md | disaster recovery, 6 fases, drill 9s warm |
| RUNBOOK-PROOF-MIGRATION.md | base64 → MinIO |
| RUNBOOK-USER-DELETION.md | LGPD hard-delete cron |
| RUNBOOK-COOKIE-CONSENT.md | LGPD Art. 8 4 categorias |
| RUNBOOK-BACKUP-VERIFY.md | backup + verify + restore drill |
| **RUNBOOK-INCIDENT-RESPONSE.md** | 955 linhas, 8 playbooks (SEV1-4) |
| RUNBOOK-SMOKE-ADMIN.md | SQL-mint admin token, RBAC E2E sem TOTP |
| **RUNBOOK-EXTERNAL-SMOKE.md** | GH Actions cron 15min, 36 assertions × prod, regression test Coraza 931130 |
| RUNBOOK-RENOVATE.md | install + automerge + triagem |
| **SLO-DEFINITIONS.md** | 11 SLOs + error budgets + burn rate |
| INCIDENT-ORDER-450F0E6F.md | reconcile FP investigation |

---

## 16. Pra começar uma nova sessão

```bash
# 1. Extract SSH key
awk '/BEGIN OPENSSH/,/END OPENSSH/' /media/sonne/Archives/projects/viralefy/credentials > /tmp/vf-ssh.key && chmod 600 /tmp/vf-ssh.key

# 2. Quick health check
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-smoke && systemctl is-active viralefy-{payments,sender,auth,core,dispatcher,caddy,postgres-exporter}'

# 3. Read CHECKLIST.md pra ver done + pending

# 4. Check Prometheus alerts firing
ssh -i /tmp/vf-ssh.key root@62.238.41.231 \
  'curl -s http://127.0.0.1:9090/api/v1/alerts | jq ".data.alerts[] | select(.state==\"firing\") | {name: .labels.alertname, severity: .labels.severity}"'

# 5. Recent commits across repos
for r in viralefy_{core,auth,api_rust,payments,sender,ops,front,backoffice,archive}; do
  echo "=== $r ===" && cd /media/sonne/Archives/projects/viralefy/$r && git log --oneline -3
done
```
