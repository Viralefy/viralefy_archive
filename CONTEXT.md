# Viralefy — CONTEXT.md (snapshot pra compactação)

**Última atualização:** 2026-06-11 05:00 UTC (PHASE-9 + PHASE-10 Test Kit + Hardening + LGPD parcial + 10 ADRs + observability completa + JWKS rate-limit fix SEV-2)

Este arquivo é o "leia primeiro" pra qualquer próxima sessão. Estado factual sem narrativa.

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
   ├── obs → Grafana (:3030) [6 dashboards + Loki + Tempo + Alloy + Alertmanager]
   └── api → ROTEAMENTO POR PATH:
        │
        ├── /.well-known/jwks.json            → DIRETO auth :8083 (SEV-2 fix bypass)
        ├── /v1/plans*, /v1/categories*, etc  → dispatcher :8090 → core :8084
        ├── /v1/auth/*                        → dispatcher :8090 → auth :8083
        ├── /v1/me/*                          → dispatcher :8090 → core :8084
        ├── /v1/admin/*                       → dispatcher :8090 → core :8084
        ├── /v1/checkout                      → dispatcher :8090 → core :8084
        ├── /v1/webhooks/{stripe,heleket,...} → payments :8081 (direto)
        ├── /internal/*                       → 404 (defesa em profundidade)
        └── catch-all (paths novos)           → dispatcher :8090 (fallback)

viralefy-api LEGACY :8080 STOPPED + DISABLED (soak 14d até 2026-06-24).
Catch-all `:443 { tls internal; respond 421 }` pra Host header tampering.

Coraza rules: SQLi/XSS/RCE → 403 BLOCKED.
PUT/PATCH/DELETE liberados (exclusion 900700).
Password password-manager (PL2) ok via 900601.
Tracking URLs liberadas em /v1/checkout, /v1/auth/*, /v1/me/* (900800-802).
Reviews body+title liberadas (900300 phase 2).
```

**Auth interno entre services:** `INTERNAL_SHARED_SECRET` em `X-Internal-Token`. Loopback-only.

**Object storage:** MinIO Docker `/var/lib/viralefy-storage/`, S3-compat. Migrator binary criado, 0 rows pra migrar em HML.

---

## 4. 10 Repositórios (Viralefy GitHub org)

| Repo | Função | Estado |
|---|---|---|
| `viralefy_api` | Monolito Go LEGACY (port 8080) | STOPPED + DISABLED, soak até 2026-06-24 |
| `viralefy_payments` | Providers + webhooks (8081) | Live, /health unificado + /internal/metrics |
| `viralefy_sender` | Email + telegram + outbox (8082) | Live, /health unificado + /internal/metrics |
| `viralefy_front` | Next.js storefront | Live + cookie consent default-OFF + /legal/cookies |
| `viralefy_backoffice` | Next.js admin panel | Live + MOCK_AUTH bypass + /api/metrics |
| `viralefy_ops` | systemd + installer + Caddy + CLIs + Test Kit §22 | Live, 7 timers + 26 alerts + 6 dashboards |
| `viralefy_archive` | docs + memory + ADRs + workflows | Live, 33 MDs + 10 ADRs |
| **`viralefy_core`** | **Motor Go (port 8084)** | Live, defense-in-depth + métricas + crons |
| **`viralefy_auth`** | **Identidade Go (port 8083)** — JWT + 2FA + hot-set | Live, /health + 6 public routes |
| **`viralefy_dispatcher`** | **Borda Rust (port 8090)** — sanitiza + proxy + JWT verify | Live, hot-set ArcSwap lock-free + /health + /metrics |

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
| 3000 | viralefy-front | ~100MB | Node |
| 3001 | viralefy-backoffice | ~200MB | Node |

**Stack apps: ~560MB. Observability adicional (Prometheus+Grafana+Loki+Tempo+Alloy): ~1.2GB.**

---

## 6. Schema DB (44 migrations aplicadas)

Migration tracker tipo Laravel — `schema_migrations` com checksum SHA256, auto-backfill detecta prod legado, `Seed()` opt-in.

**Últimas migrations:**
- 040: proof_storage_key (orders.proof_storage_key + index)
- 042: user_deletion_grace_period (status enum + executed_at + error_message + orders nullable user_id + email/name snapshot)
- 043: user_deletion_drop_fk (FK user_deletion_requests.user_id → users dropada pra LGPD anonymization)
- 044: user_consent (user_consent_log + user_events.analytics_consent)

⚠️ 041 vazio (conflict de agents paralelos resolvido renomeando consent → 044).

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
  - **Core Go** defense-in-depth via RevocationCache (LISTEN/NOTIFY + 30s poll fallback)
- **Refresh tokens:** rotação encadeada (anti-replay), TTL 30d, replay → force-logout do subject inteiro
- **JWKS:** Caddy bypass dispatcher (rate-limit fix SEV-2), Cache-Control 60s + 300s stale-while-revalidate

---

## 8. Env vars críticas em `/etc/viralefy/.env`

**Presentes em prod:** DATABASE_URL, JWT_SECRET + JWT_PRIVATE_KEY_PATH, TWOFA_ENCRYPTION_KEY, INTERNAL_SHARED_SECRET, RESEND_API_KEY, TURNSTILE_SECRET_KEY, STORAGE_ACCESS/SECRET_KEY (MinIO), PAYMENTS/SENDER_INTERNAL_URL, GRAFANA_ADMIN_PASSWORD, postgres_exporter password.

**Env por service (systemd unit):**
- core: `CORE_PORT=8084`
- auth: `VAUTH_BIND_ADDR=127.0.0.1:8083`, TTLs
- dispatcher: `VAPI_BIND_ADDR=127.0.0.1:8090`, `VAPI_*_URL`, `VAPI_JWKS_CACHE_TTL_SECS=60`, `VAPI_REVOKED_POLL_SECS=30`

**Opt-in pendentes (cliente fornecer):**
- `SENTRY_DSN` / `NEXT_PUBLIC_SENTRY_DSN`
- `SENTRY_AUTH_TOKEN` em GitHub Secrets
- `TELEGRAM_BOT_TOKEN` / `TELEGRAM_ADMIN_CHAT_ID`
- `ADMIN_WEBHOOK_URL` — Slack/Discord
- `LHCI_GITHUB_APP_TOKEN`
- Renovate GitHub App — instalar em github.com/Viralefy

---

## 9. Operação day-a-day

| Ação | Comando |
|---|---|
| Deploy | `ssh root@62.238.41.231 'viralefy-update --yes'` |
| Smoke (rapido) | `ssh root@62.238.41.231 'viralefy-test smoke'` |
| Full test suite | `ssh root@62.238.41.231 'viralefy-test all'` |
| Pentest | `ssh root@62.238.41.231 'viralefy-test pentest'` |
| Security | `ssh root@62.238.41.231 'viralefy-test security'` |
| Hardening | `ssh root@62.238.41.231 'viralefy-test hardening'` |
| Authz | `ssh root@62.238.41.231 'viralefy-test authz'` |
| Status | `ssh root@62.238.41.231 'viralefy-status'` |
| Logs core/auth/dispatcher | `journalctl -u viralefy-<svc> -f` |
| Logs Coraza | `tail -f /var/log/caddy-waf/audit.log` |
| Migrate | `sudo -u viralefy-core /usr/local/sbin/viralefy-core migrate {status,up}` |
| Backup manual | `viralefy-backup` |
| Reconcile drift | `systemctl start viralefy-reconcile` |
| Hard-delete users | `systemctl start viralefy-user-deletion` |
| Seed test data | `viralefy-test seed-all` |
| Clean test data | `viralefy-test clean-seeds` |

---

## 10. Coraza WAF — SecRuleEngine ON (Block real) ATIVO

- xcaddy v2.11.3 + coraza-caddy/v2 + OWASP CRS 4.10.0
- `SecRuleEngine On` (2026-06-10 12:20 UTC)
- `SecDefaultAction phase:1/2 → deny,status:403` (causa raiz do warning não-block)
- `SecAuditLog /var/log/caddy-waf/audit.log` JSON, RelevantStatus `.*`
- Paranoia level 2 + bodyproc enforcement

**Exclusões custom em `/etc/caddy/coraza/coraza-crs-exclusions.conf`:**
- `id:900201` Stripe webhook signature bypass
- `id:900300` /v1/me/reviews body+title (rule 941xxx XSS FPs) — fix 2026-06-11
- `id:900601` phase 2 — exclui ARGS:*password de rule 942100 (libinjection password-manager FP)
- `id:900700` phase 1 — `tx.allowed_methods=GET HEAD POST OPTIONS PUT PATCH DELETE`
- `id:900710/720` paranoia 2 + bodyproc enforcement
- `id:900800/801/802` — tracking URLs em /v1/checkout, /v1/auth/*, /v1/me/* (rule 931xxx RFI FP) — fix 2026-06-10

**Validado em prod — TODOS BLOCKED 403:** SQLi (4 variants), XSS (2 variants), Host header tampering → 421.

---

## 11. CORS + Security Headers

CORS na borda (Caddy responde preflight):
- `OPTIONS` → 204 + ACAO headers reflectindo Origin
- POST/GET com Origin → adiciona `Access-Control-Allow-Origin` dinâmico

Security headers em todos vhosts:
- HSTS preload, X-Content-Type-Options nosniff
- CSP (front com GTM/Cloudflare Turnstile, backoffice frame-ancestors none)
- Cross-Origin-Resource-Policy (same-site api+www, same-origin admin+obs)
- Cross-Origin-Embedder-Policy require-corp (backoffice apenas)
- **Permissions-Policy em API** (camera/microphone/geolocation/payment/usb negados) — fix 2026-06-11
- Referrer-Policy
- `-Server -X-Powered-By`

---

## 12. Observability completa

**Prometheus:** 15/16 targets up (legacy api desabilitado intencional).

**Services com /metrics + /health:** core, auth, payments, sender, dispatcher (próprias), front, backoffice (/api/metrics), caddy, postgres-exporter, node-exporter, prometheus, grafana, loki, tempo, alloy.

**Grafana 6 dashboards importados:**
- viralefy-revenue, viralefy-payments, viralefy-behavior, viralefy-reliability, viralefy-slo, viralefy-phase9 (26 painéis cross-service)

**SLOs (11):** api availability 99.5%, api p95 <500ms, **dispatcher overhead <50ms (atual 95µs = 528x headroom)**, payments webhook 99.9%, db query p95 <100ms, etc.

**Alerting (26 rules):** SLO burn-rate multi-window, ServiceDown, DBConnectionExhausted, DiskSpaceLow, BackupFailed, ReconcileDriftHigh, CorazaBlockSpike, AuthBruteforce, CertExpiringSoon. Alertmanager skeleton com inhibition rules. Webhook ADMIN_WEBHOOK_URL TODO cliente.

---

## 13. Cron jobs (systemd timers)

| Timer | Frequência | Função |
|---|---|---|
| viralefy-backup | daily 03:00 UTC | pg_dump compactado + retenção 7d/4w/6m |
| viralefy-backup-verify | daily 04:09 UTC | gzip integrity + schema check |
| viralefy-restore-drill | weekly Sun 05:09 UTC | sandbox Docker isolated |
| viralefy-reconcile | daily 03:37 UTC | 16 invariants de drift |
| viralefy-user-deletion | daily 03:53 UTC | hard-delete físico LGPD (grace 30d) |
| viralefy-test-cleanup | hourly :17 UTC | cleanup `*@viralefy.test` |
| viralefy-orders-anonymize | monthly 04:30 UTC | LGPD Art. 16 5y fiscal retention |

**Crons in-process (viralefy-core):**
- stripe_reconcile (5min)
- event_retention (24h)
- plan_price_drift (1h, samples logados — Q3 fix)
- review_request (1h)

---

## 14. Test Kit (PHASE-10, §22 diretrizes)

CLI `viralefy-test` em prod (`/usr/local/sbin/`) com subcommands:

| Modo | Scripts | Duração | Status |
|---|---|---|---|
| smoke | 9 | 3s | 9/9 pass ✅ |
| pentest | 27 OWASP | 21s | 27/27 pass ✅ |
| security | 10 | 1s | 9/10 (1 test script bug) |
| hardening | 10 | <1min | 6/10 + 4 findings (CAA, DNSSEC, HSTS preload, admin) |
| authz | 10 (RBAC + BOLA) | 186s | 10/10 pass ✅ |
| integration | 10 (E2E) | <3min | 1 pass + skips + 1 rate-limit collateral |
| chaos | 10 (3 gated) | <5min | 5 pass + 1 finding (JWKS rate-limit → SEV-2 FIXED) |
| simulated | engine Python | 5-15min | 19.500 combos (125 rotas × 6 personas × 26 injections) |
| unit | delega go test / npm test | 5-15min | - |
| all | tudo exceto chaos+unit | ~10min | - |
| full | + chaos + unit | ~20min | - |

External smoke (GH Actions cron 15min, off-prod): 36 assertions, 36/36 pass em dry-run.

---

## 15. Renovate (cliente precisa instalar App)

Config em 10 repos via central preset `viralefy_ops/renovate-config.json`. Schedule Monday 09:00 BRT, group por linguagem, automerge patches non-major.

**Vuln scans no CI:**
- Go: `govulncheck ./...` (continue-on-error: true)
- Rust: `cargo audit`
- Node: `npm audit --audit-level=high`

---

## 16. Documentos no archive (33 MDs + 10 ADRs)

Ver `INDEX.md` pra mapa completo. Highlights:
- CONTEXT.md (este), CHECKLIST.md, INDEX.md, diretrizes.md (normativo)
- ENGINEERING-CONFORMANCE-AUDIT.md (gap analysis)
- 11 runbooks (DR, Incident, Backup, User-deletion, Cookie, Proof, Smoke-admin, External-smoke, Renovate, Cloudflare, Operação geral)
- 4 baselines auditadas (Pentest, Coraza, Review XSS, LGPD)
- 10 ADRs em formato MADR
- SLO-DEFINITIONS, PHASE-7/8/9 plans, ROADMAP

---

## 17. Pra começar uma nova sessão

```bash
# 1. Extract SSH key
awk '/BEGIN OPENSSH/,/END OPENSSH/' /media/sonne/Archives/projects/viralefy/credentials > /tmp/vf-ssh.key && chmod 600 /tmp/vf-ssh.key

# 2. Quick health check
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-test smoke && systemctl is-active viralefy-{payments,sender,auth,core,dispatcher,caddy,postgres-exporter,backoffice,front}'

# 3. Read CHECKLIST.md pra ver done + pending

# 4. Check Prometheus alerts firing
ssh -i /tmp/vf-ssh.key root@62.238.41.231 \
  'curl -s http://127.0.0.1:9090/api/v1/alerts | jq ".data.alerts[] | select(.state==\"firing\") | {name: .labels.alertname, severity: .labels.severity}"'

# 5. Test cover
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'viralefy-test all 2>&1 | tail -20'

# 6. Recent commits across repos
for r in viralefy_{core,auth,api_rust,payments,sender,ops,front,backoffice,archive}; do
  echo "=== $r ===" && cd /media/sonne/Archives/projects/viralefy/$r && git log --oneline -3
done
```
