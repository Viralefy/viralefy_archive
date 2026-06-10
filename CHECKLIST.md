# Viralefy — CHECKLIST.md (priorizado pra próxima sessão)

**Última atualização:** 2026-06-10 (Bucket 1 + Bucket 2 ATIVOS em prod)

Convenção: `[x]` done · `[~]` parcial/decisão externa · `[ ]` pendente · `[!]` blocker/atenção.

---

## ESTADO CRÍTICO PRA NÃO REGREDIR

- [x] Migration tracker estilo Laravel — `schema_migrations` + checksum + auto-backfill prod legado
- [x] `Seed()` NÃO roda automático em boot (era a fonte de items que ressuscitavam)
- [x] `ON CONFLICT DO UPDATE` → `DO NOTHING` em seedRoles/seedCategories/seedPlans prices
- [x] Caddy bloqueia `/internal/*` externamente (404) — defesa em profundidade
- [x] CORE_PORT precedência sobre PORT (deploy paralelo sem editar .env compartilhado)

---

## DONE — sessões 2026-06-09 + 06-10

### PHASE-9 Bucket 1 cutover (2026-06-10 03:21 UTC)
- [x] Caddyfile com 7 `handle` blocks routing público read-only pra `:8090`
- [x] Parity test pré-swap (status+body identical legacy vs dispatcher)
- [x] `caddy validate` + `systemctl reload` (zero-downtime)
- [x] E2E externo HTTPS: 7/7 rotas 200 OK
- [x] Rotas não-Bucket-1 (auth-user, admin, checkout, webhooks, /internal/*) preservadas
- [x] Rollback path validado: swap back funciona com 0 downtime via reload
- [x] **Soak test 210 reqs sustained**: 0/210 falhas; p95 49-88ms; dispatcher 45MB RSS estável
- [x] Rate-limit confirmado: 429 throttling em burst >30 reqs/s/IP (comportamento correto)
- [x] Pushed: [Viralefy/viralefy_ops@6e0f8c5](https://github.com/Viralefy/viralefy_ops/commit/6e0f8c5)

### PHASE-9 Bucket 2 planejamento (2026-06-10)
- [x] Audit: legacy api JÁ tem dual-sign RS256+HS256 (`parseDualSign`)
- [x] Audit: RSA key compartilhada → tokens interchangeable entre legacy/core/auth
- [x] Audit: legacy NÃO tem /v1/refresh ou /v1/logout (só viralefy_auth)
- [x] Split: 2a (18 GETs) + 2b (20 mutations) + 2c (4 auth flows)
- [x] Doc: [PHASE-9-BUCKET-2-PLAN.md](PHASE-9-BUCKET-2-PLAN.md) (159 linhas)
- [x] Pushed: [Viralefy/viralefy_archive@c37f7c1](https://github.com/Viralefy/viralefy_archive/commit/c37f7c1)

### PHASE-9 Bucket 2 (2a+2b consolidados) cutover (2026-06-10 04:06 UTC)
- [x] Caddyfile com `handle /v1/me*` routing pra `:8090` (38 rotas)
- [x] Parity pré-swap: 401 sem Bearer em legacy+dispatcher (body shape idêntico)
- [x] `caddy validate` + `systemctl reload` (zero-downtime)
- [x] Smoke E2E HTTPS: 13 GETs + 5 POSTs → 401 (auth gate intacto)
- [x] Não-regressão: Bucket 1 200, admin/checkout/login ainda monolito
- [x] Rollback validado em ambas direções (0 downtime via reload)
- [x] Pushed: [Viralefy/viralefy_ops@0389cc0](https://github.com/Viralefy/viralefy_ops/commit/0389cc0)


### PHASE-9 Fase 9b — viralefy_auth completo
- [x] Domain layer (5 arquivos: user, admin, token, twofa, errors)
- [x] 5 postgres repos + db.go com AssertSchema falha-fast
- [x] token_service.go: mint RS256 + verify + hot-set + rotação refresh
- [x] auth_service.go: 14 endpoints (login/register/refresh/logout/2FA/password reset)
- [x] HTTP layer: gated por X-Internal-Token + JWKS público aberto
- [x] Binary 11MB Go, mem 7MB em prod no port `:8083`
- [x] Migration 039 auto-aplicada (refresh_tokens + revoked_jtis + password_resets)
- [x] Pushed: [Viralefy/viralefy_auth](https://github.com/Viralefy/viralefy_auth)

### PHASE-9 Fase 9d — viralefy_dispatcher (Rust) completo
- [x] Cargo + axum 0.7 + tokio + tower_governor + reqwest+rustls + sqlx+rustls + ammonia
- [x] `src/auth.rs`: JWKSCache TTL 60s + RevocationSet (bootstrap + LISTEN/NOTIFY + polling 5s)
- [x] `src/middleware.rs`: enforce_path_safety + require_auth + optional_auth
- [x] `src/proxy.rs`: resolve_upstream + reverse_proxy com headers safe-list + X-Internal-Token auto
- [x] `src/security.rs`: 9 patterns case-insensitive path traversal
- [x] `tower_governor`: 30 burst + 1/s per-IP (via ConnectInfo<SocketAddr>)
- [x] 12 tests unit + smoke E2E PASS contra 3 mocks (core/auth/payments)
- [x] Binary 7.2MB stripped release, mem 1.4MB em prod no port `:8090`
- [x] Pushed: [Viralefy/viralefy_dispatcher](https://github.com/Viralefy/viralefy_dispatcher)

### PHASE-9 Fase 9c — viralefy_core (Go) completo
- [x] Fork 1:1 do viralefy_api Go monolito
- [x] Module renomeado `github.com/Viralefy/viralefy_core`
- [x] cmd/api → cmd/core, binary `viralefy-core`
- [x] Paridade 100% com legacy (109 plans, 12 categorias, mesmo kid JWT)
- [x] Migration 039 nova (refresh_tokens + revoked_jtis + password_resets)
- [x] Build OK, suite tests 100% PASS
- [x] Deploy paralelo em prod no `:8084`, mem 14MB
- [x] Pushed: [Viralefy/viralefy_core](https://github.com/Viralefy/viralefy_core)

### PHASE-9 Fase 9a — Caddy + Coraza WAF
- [x] xcaddy v0.4.5 instalado na VPS
- [x] Caddy 2.11.3 + coraza-caddy/v2 buildado (binary 54MB)
- [x] OWASP CRS 4.10.0 instalado em `/etc/caddy/coraza/crs/` (46 rule files)
- [x] Caddyfile: `order coraza_waf first` + bloco coraza_waf no API
- [x] `SecRuleEngine DetectionOnly` + `SecAuditEngine On`
- [x] Validado em prod: SQLi `942100` + XSS `941xxx` detectados, requests passam 200
- [x] Pushed: [Viralefy/viralefy_ops](https://github.com/Viralefy/viralefy_ops)

### viralefy_ops integração PHASE-9
- [x] 3 systemd units hardened (core, auth, dispatcher)
- [x] viralefy-update suporta 10 repos com clone_optional + build_rust_svc
- [x] viralefy-smoke testa healths PHASE-9 com skip silencioso
- [x] installer/lib.sh PACKAGES expandido pra 8 packages
- [x] installer/60-systemd.sh instala (mas não enable) os 3 units novos

### Outras correções desta sessão
- [x] Stripe webhook reconfigurado (era pra `ganharfama.com`, agora `api.viralefy.com/v1/webhooks/stripe`)
- [x] Heleket `url_callback` configurado
- [x] Manual PIX desativado (active=false), histórico preservado
- [x] Gateway DELETE com FK violation → 409 CONFLICT (era 500)
- [x] Multi-currency providers consolidados: 1 card por gateway (não N)
- [x] Backoffice UI de admins management (`/admins`) — list/create/edit role/reset 2FA/delete
- [x] Invoice list hidratada (user_name + user_email via JOIN)
- [x] Marketplace items (bms_facebook/perfis_redes/emails_validados) removidos via migration 038
- [x] Bugs achados via sweep E2E (62 PASS) + ABAC autenticado (56/56 PASS, 0 IDOR, 0 RBAC bypass)
- [x] Contract tests inter-microservice (api+payments+sender) — drift detector
- [x] Stripe reconcile cron (5min tick, polling Sessions API pra webhooks perdidos)
- [x] PHASE-9-ARCHITECTURE.md (1056 linhas, 12 críticas adversariais aplicadas)

---

## PRÓXIMA SESSÃO — Cutover PHASE-9 (strangler por bucket)

### Bucket 1 — Public read-only ✅ (cutover 2026-06-10)
- [x] Caddyfile: trocar reverse_proxy `:8080` → `:8090` para:
  - [x] `/v1/plans*` (cobre listing + `/v1/plans/{id}/reviews` + `/v1/plans/{id}/payment-methods`)
  - [x] `/v1/categories*`, `/v1/currencies*`
  - [x] `/v1/status*`, `/v1/country-ppp*`, `/v1/tax-rates*`
  - [x] `/.well-known/jwks.json` → dispatcher → `:8083` (auth)
- [x] Parity test pré-swap: status+body bit-exact pra 7/7 paths
- [x] Smoke E2E pós-swap: HTTPS pública `api.viralefy.com` 200 pra 7/7 rotas
- [x] Rollback test: `caddy reload` é zero-downtime real (validado swap legacy↔dispatcher)
- [x] Commit: [Viralefy/viralefy_ops@6e0f8c5](https://github.com/Viralefy/viralefy_ops/commit/6e0f8c5)
- [ ] **Monitorar 24h erro rate + latência p95** (dispatcher vs legacy)
- [ ] Se estável 48h → Bucket 2

### Bucket 2 — User auth (semana 2-3) — VER [PHASE-9-BUCKET-2-PLAN.md](PHASE-9-BUCKET-2-PLAN.md)
Split em sub-buckets baseado em audit (legacy já dual-signs → canary desnecessário):
- [x] **Bucket 2a+2b** — `/v1/me/*` (38 rotas GET+POST+PUT+DELETE) ✅ cutover 06-10
- [ ] **Bucket 2c** — `/v1/auth/user/{register,login,login/2fa}` (4 rotas)
- [ ] Smoke E2E autenticado: register → login → 2FA enroll → orders → API key
- [ ] Validar 2FA persistido via auth-core compartilhando DB
- [ ] Hot-set revogação testado end-to-end (revogar JTI no auth, dispatcher rejeita em ≤5s)
- [ ] Reconciliação diária: nenhum order criado em path diferente
- [ ] Monitorar 24-48h Bucket 2 estável antes de 2c

### Bucket 3 — Admin (semana 4)
- [ ] Rotas: `/v1/admin/*` (52 rotas, RBAC com role permissions)
- [ ] Smoke RBAC: superadmin vs manager vs viewer
- [ ] Validar audit_log gravado pelo core
- [ ] Bulk approve proofs + edit gateways funcionais

### Bucket 4 — Checkout + webhooks (semana 5, shadow traffic)
- [ ] Shadow traffic: api duplica request pra dispatcher, log diff de response
- [ ] 72h shadow → canary 1% → 10% → 50% → 100%
- [ ] Reconciliação diária de orders criadas em cada path
- [ ] Stripe/Heleket/Abacate webhooks roteados pra `:8081` via dispatcher
- [ ] Run full E2E (register → checkout → webhook → order confirmed)
- [ ] Stripe reconcile cron continua rodando (defense in depth)

### Coraza WAF — DetectionOnly → Block (paralelo aos buckets)
- [ ] 14 dias monitorando false positives via journald
- [ ] Tuning `CRS_EXCLUSION_*` em `crs-setup.conf` por falsos positivos observados
- [ ] Mudar `SecRuleEngine On` (Block real)
- [ ] Validar com payloads benignos (search com payload nicho, upload PNG, markdown review)
- [ ] Dashboard Grafana de Coraza hits + falsos positivos

---

## PENDÊNCIAS GERAIS (não-PHASE-9)

### Cliente precisa fornecer
- [ ] Telegram bot TOKEN + CHAT_ID (notifs admin + checkout_paid)
- [ ] Sentry DSN + NEXT_PUBLIC_SENTRY_DSN
- [ ] Slack/Discord webhook URL (admin alerts)

### Engineering — médio impacto
- [ ] Object storage migration: proofs base64 antigos → MinIO keys
- [ ] Grafana contact points (email/Slack)
- [ ] 4 custom Grafana dashboards (revenue, payments, behavior, reliability)
- [ ] Sentry source maps no CI
- [ ] LGPD compliance review formal

### Engineering — baixo impacto
- [ ] Pentest externa (Tier 3 audit per PHASE-9 §13)
- [ ] WAF Cloudflare nativo (depois de Coraza estabilizar)
- [ ] DR drill provisão nova + restore < 30min (target)
- [ ] Playwright CheckoutModal E2E
- [ ] Lighthouse CI gate

### Decisão de produto pendente
- [~] Multi-vendor settlement model
- [~] WhatsApp provider real (decisão Meta vs Twilio)
- [~] API B2B billing tier
- [~] Subscription pause/resume
- [~] Blog content engine
- [~] Backlinks outreach

---

## CRITÉRIO DE "Fase 9 100% pronta"

- [ ] Bucket 1-4 cutover completo, tráfego 100% no dispatcher
- [ ] api legacy parado (systemctl stop viralefy-api) por 14 dias sem regressão
- [ ] api legacy removido do viralefy-update + repo arquivado
- [ ] Coraza em `SecRuleEngine On` por 30 dias sem falso positivo crítico
- [ ] 5 dashboards Grafana ativos
- [ ] Smoke E2E dual-mode (rollback path validado mensal)
- [ ] Pentest externo da nova arquitetura
- [ ] Runbook restore < 30min testado em DR drill

---

## COMANDOS RÁPIDOS

```bash
# Status full
ssh root@62.238.41.231 'viralefy-smoke && systemctl is-active viralefy-{api,payments,sender,auth,core,dispatcher,caddy}'

# Logs Coraza WAF (detecções)
ssh root@62.238.41.231 'journalctl -u caddy -f --since "5 min ago" | grep -E "coraza|waf"'

# Logs hot-set (revogações)
ssh root@62.238.41.231 'journalctl -u viralefy-dispatcher -f | grep -E "hot-set|revoked"'

# Forçar revogação de JTI (teste)
psql "$DATABASE_URL" -c "INSERT INTO revoked_jtis (jti, expires_at) VALUES ('test-jti', NOW() + INTERVAL '1 hour')"

# Migrate status
ssh root@62.238.41.231 'sudo -u viralefy-core bash -c "source /etc/viralefy/.env; /usr/local/sbin/viralefy-core migrate status"'

# Deploy zero-downtime
ssh root@62.238.41.231 'viralefy-update --yes'
```

---

## REPOS NO GITHUB

| Repo | URL |
|---|---|
| viralefy_api (legacy) | https://github.com/Viralefy/viralefy_api |
| viralefy_payments | https://github.com/Viralefy/viralefy_payments |
| viralefy_sender | https://github.com/Viralefy/viralefy_sender |
| viralefy_front | https://github.com/Viralefy/viralefy_front |
| viralefy_backoffice | https://github.com/Viralefy/viralefy_backoffice |
| viralefy_ops | https://github.com/Viralefy/viralefy_ops |
| viralefy_archive | https://github.com/Viralefy/viralefy_archive |
| **viralefy_core** | https://github.com/Viralefy/viralefy_core |
| **viralefy_auth** | https://github.com/Viralefy/viralefy_auth |
| **viralefy_dispatcher** | https://github.com/Viralefy/viralefy_dispatcher |
