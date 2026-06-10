# Viralefy — CHECKLIST.md (priorizado pra próxima sessão)

**Última atualização:** 2026-06-10 (PHASE-9 deployada paralelo em prod)

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

### Bucket 1 — Public read-only (semana 1)
- [ ] Caddyfile: trocar reverse_proxy `:8080` → `:8090` para:
  - [ ] `/v1/plans` (e variantes `/v1/plans/{id}/reviews`, `/v1/plans/{id}/payment-methods`)
  - [ ] `/v1/categories`, `/v1/currencies`
  - [ ] `/v1/status`, `/v1/country-ppp`, `/v1/tax-rates`
  - [ ] `/.well-known/jwks.json` → `:8083` (auth)
- [ ] Smoke E2E pós-swap: front + backoffice consumindo `:8090` via Caddy
- [ ] Monitorar erro rate 24h
- [ ] Rollback test: trocar de volta pra `:8080`, validar 2s downtime

### Bucket 2 — User auth (semana 2-3, canary)
- [ ] Caddyfile: canary 1% → 10% → 50% → 100% via Caddy upstream weight
- [ ] Rotas: `/v1/auth/user/*`, `/v1/me/*` (32 rotas)
- [ ] Smoke E2E autenticado: register → login → 2FA enroll → orders → API key
- [ ] Validar 2FA persistido via auth-core compartilhando DB
- [ ] Hot-set revogação testado end-to-end (revogar JTI no auth, dispatcher rejeita em ≤5s)
- [ ] Reconciliação diária: nenhum order criado em path diferente

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
