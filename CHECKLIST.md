# Viralefy — CHECKLIST.md

**Última atualização:** 2026-06-12

Convenção: `[x]` done · `[~]` parcial/decisão externa · `[ ]` pendente · `[!]` blocker · `[L]` LGPD/legal · `[T]` time-gated · `[$]` cliente fornecer · `[E]` externo (orçamento) · `[Q3]` planejado Q3 2026

---

## ✅ DONE — Sessão 2026-06-11 (auth UI / tracking / soft-delete / honeypot)

### Auth unificado
- [x] Login UI única em `auth.viralefy.com/login` com split-screen 2/3+1/3
- [x] Backend `LoginUser` aceita admin como fallback (mesma porta)
- [x] SSO callback via URL fragment (`/sso/callback` em www + admin)
- [x] auth.viralefy.com vhost + TLS Let's Encrypt + proxy /v1/auth + UI
- [x] Schema misalignment fix (access_token, User PascalCase, json.data fallback)
- [x] `parse2FAKey()` no auth-service (hex 64 → 32 bytes) — fixou 500 no /2fa
- [x] OTP autofill defenses (Bitwarden/1Password — honeypot inputs, data-bwignore)

### UI visual
- [x] 29 SVG icons substituem todos emojis na UI (-120KB Twemoji)
- [x] Flag SVG via flagcdn.com (fix bandeiras brancas)
- [x] Modal portal-based (escape stacking context do header sticky)
- [x] Hamburger megamenu de **services** (12 categorias agrupadas)
- [x] MegaMenuMarkets + Currency picker via portal modals
- [x] Split-screen AuthLayout (login + register) só em auth host

### Coraza WAF — silenciamento de regras instáveis
- [x] 932240/235/236/238/260 (RCE Unix) — disparava em cookies GA4
- [x] 942430/431/432/440/441/442 (SQL char/comment) — disparava em turnstile token
- [x] 931100/110/120/130 excluído de ARGS:return_to (SSO)
- [x] JWKS bypass via Caddy direto pro :8083

### SEO
- [x] robots.ts com regras IA crawlers (GPTBot/ClaudeBot/Google-Extended)
- [x] layout.tsx: themeColor, robots, keywords, OG/Twitter image
- [x] IndexNow re-disparado: **14.147 URLs** ok=true

### Tracking observability — admin panel
- [x] GET /v1/admin/users/{id}/journey
- [x] GET /v1/admin/visitors[?limit=&offset=]
- [x] GET /v1/admin/visitors/{vid}
- [x] JourneyPanel reusable component
- [x] /analytics/visitors page paginada
- [x] /analytics/visitors/{vid} drill-down
- [x] /users/{id} ganhou seção Tracking journey
- [x] /orders/{id} ganhou seção Attribution

### Soft + Hard delete (orders / invoices / users)
- [x] Migration 045 — colunas deleted_at, deleted_by_admin_id, delete_reason
- [x] Domain + repo + service + 9 endpoints
- [x] Middleware `RequireSuperadmin`
- [x] DeleteActions UI component (soft/hard/restore com confirmação dupla)
- [x] Wirings em /users/[id], /orders/[id], /invoices/[id]

### Trash tab (superadmin only)
- [x] Listas regulares filtram deleted_at IS NULL (workflow limpo)
- [x] GET /v1/admin/trash agregando 3 entidades
- [x] /trash page com 3 tabs + counts
- [x] Nav link superadmin-only

### Honeypot — superadmin invisível
- [x] Migration 046 — admin_honeypot_log table + 2 índices
- [x] Camuflagem: superadmin aparece como `manager` pra non-superadmin
- [x] Fake success em update_role/delete (200 OK, DB intocado, log)
- [x] Shadow-delete: target some da lista DAQUELE actor
- [x] GET /v1/admin/honeypot (RequireSuperadmin)
- [x] /honeypot page com Top Suspects + timeline
- [x] DeleteActions removido todo hint de role mais alta

### Bulk soft delete
- [x] 3 endpoints (orders/invoices/users) — max 200 ids
- [x] Hard bulk NÃO existe (proposital)
- [x] BulkActionsBar reusable component (sticky bottom)
- [x] Checkboxes nas 3 listings

### Admin session protection
- [x] AdminShell synchronous gate (sem flash de tela deslogada)
- [x] 401 interceptor + custom event session-expired
- [x] clearToken + redirect /login automático

---

## ✅ DONE — Estado consolidado de prod (anterior a 06-11)

### Cutover PHASE-9
- [x] Bucket 1, 2 (a+b), 2c, 3, 4 — todos via dispatcher
- [x] Legacy api STOPPED em soak (até 2026-06-24)

### Test Kit PHASE-10 §22
- [x] CLI `viralefy-test` (smoke/pentest/security/hardening/authz/integration/chaos/simulated/unit)
- [x] 9 smoke + 27 pentest + 10 security + 10 hardening + 10 authz + 10 integration scripts
- [x] Simulated engine (Python) 125 routes × 6 personas × 26 injections

### Observability
- [x] 6 dashboards Grafana + 11 SLOs + 26 alerts
- [x] Prometheus + Loki + Tempo + Alloy + Alertmanager
- [x] External smoke (GitHub Actions cron 15min, 36 assertions off-prod)

### LGPD (parcial)
- [x] user_consent_log + user_deletion_requests (30d grace) + orders anonymize (5y)
- [x] Cookie consent gate (LGPD Art. 8 §3)
- [x] X-Analytics-Consent header gate em /v1/track

### Segurança
- [x] PENTEST baseline 2026-06-10: 0 CRITICAL, 3 HIGH fixed + 4 MEDIUM fixed
- [x] Coraza WAF Block mode (DetectionOnly → Block após 14d soak)
- [x] 2FA TOTP user + admin
- [x] JWT RS256 dual-sign + hot-set revogação
- [x] Renovate auto-merge + gitleaks + govulncheck CI

### Docs
- [x] 33+ MDs no archive
- [x] 10 ADRs (MADR format)
- [x] 11 runbooks operacionais

---

## 🔄 PENDING

### Time-gated `[T]`
- [ ] **2026-06-24** — remoção definitiva da viralefy_api legacy (14d soak)
- [ ] **2026-06-14** — fim do ambiente HML/POC (rotação de chaves Stripe/Heleket/Woovi vai voltar a ser questão)

### Cliente fornecer `[$]`
- [ ] SENTRY_DSN — observability errors
- [ ] TELEGRAM_BOT_TOKEN — notifs admin
- [ ] ADMIN_WEBHOOK_URL — alertas custom
- [ ] LHCI_GITHUB_APP_TOKEN — Lighthouse CI
- [ ] Renovate App install no github.com/Viralefy

### Externos `[E]` (orçamento)
- [ ] Pentest Tier 3 (third-party formal)
- [ ] LGPD lawyer review
- [ ] Cloudflare WAF (DECISION: ADR-0006 mantém Coraza por enquanto)
- [ ] Hetzner DR drill formal

### LGPD `[L]`
- [ ] **C1** — designação DPO formal
- [ ] **C2** — Política de Privacidade Art. 9 completa
- [ ] **C4** — Runbook ANPD pra incident response
- [ ] DPAs com processadores (Resend, Cloudflare, MaxMind, Stripe, etc.)
- [ ] Cross-border data transfer formal docs

### Tracking — melhorias possíveis
- [ ] Geoip lookup (IP → país) — MaxMind GeoLite2 + cache
- [ ] Funnel aggregate query (visitor → cart → checkout → paid)
- [ ] Export CSV das tabelas admin (visitors, journeys)

### Q3 2026 tech debt `[Q3]`
- [ ] Break `viralefy_core/internal/interface/http/handlers.go` (3325 linhas) por bounded context
- [ ] Generalizar `event_outbox` (atualmente só sender)
- [ ] Linter customizado pra DDD invariants (shared DB enforcement)
- [ ] `bluemonday.UGCPolicy()` em /v1/me/reviews body sanitization
- [ ] Centralizar `bcryptCost = 12` em const único (3 lugares atualmente)

### Bugs reportados
- [ ] POST /v1/admin/plans 500 em duplicate — **root cause 2026-06-12**:
      constraint `plans_category_name_key UNIQUE(category,name)` retorna pg
      23505, mas `writeError` em [core http/response.go:27-56](../viralefy_core/internal/interface/http/response.go#L27-L56) não
      mapeia `*pgconn.PgError` → cai no default INTERNAL_ERROR/500 em vez
      de 409 Conflict. Fix: detectar Code==23505 → `domain.ErrConflict`,
      Code==23503 (FK) → `domain.ErrInvalidInput`. Afeta toda entidade
      cujo repo retorna pgx err raw em UNIQUE/FK violation.
- [ ] `writeError` não loga o erro raw — 500s ficam silenciosos no journald.
      Adicionar `slog.Warn("handler error", "err", err.Error())` no default branch.
- [ ] plan_prices BTC drift UX (override form não persiste)

### DNS findings (auditoria 2026-06-10)
- [ ] CAA records pra letsencrypt.org
- [ ] DNSSEC habilitar
- [ ] HSTS preload submission (hstspreload.org)

### Possíveis próximos (não comprometido)
- [ ] Extend soft delete pra subscriptions (4ª entidade)
- [ ] Soft delete pra profiles, reviews, tickets
- [ ] auth.viralefy.com como SSO completo (cookies httponly Domain=.viralefy.com)
- [ ] Notificação por email/Telegram quando honeypot dispara
- [ ] Rate-limit + auto-ban no honeypot (threshold de tentativas)

---

## 🛡️ Estado crítico pra não regredir

1. Backoffice systemd **MUST** stay active (502 quando killed)
2. JWKS via Caddy direto pro :8083 (rate limit do dispatcher mata)
3. Front + backoffice precisam de `NEXT_PUBLIC_AUTH_URL` + `NEXT_PUBLIC_AUTH_UI_URL`
4. `TWOFA_ENCRYPTION_KEY` em hex 64 chars (NÃO bytes raw)
5. Coraza exclusions de ARGS:return_to + cookies GA4 + turnstile_token
6. `systemctl restart caddy` (NÃO reload) pra mudanças em coraza-*.conf
7. Schema migrations checksum precisa do sha256 real (não "manual")
8. `viralefy-update` falha em migrations — workaround: systemctl restart manual
9. Honeypot fake-success NÃO pode gerar 403 (revela existência da role)
10. DeleteActions sem hint "requires superadmin" (revela hierarquia)
11. Lista de admins precisa filtrar role==superadmin pra non-superadmin
12. Trash + Honeypot nav links GATED por `isSuperadmin()`
13. Bulk endpoints CAP de 200 ids por call
14. SSO `return_to` validado contra allowlist `*.viralefy.com`
15. Session no fragment URL (`#`), NÃO query string (`?`)
16. `replaceState` limpa fragment após consumir (não vaza em Referer)

---

## Métricas operacionais snapshot

- **Smoke**: 9/9 OK
- **Pentest**: 27/27 OK
- **Services up**: 7/7 (front, backoffice, core, auth, dispatcher, payments, sender)
- **Migrations aplicadas**: 000-046 (último: admin_honeypot)
- **URLs no IndexNow**: 14.147 submetidas em 2026-06-11

---

## Quick commands

```bash
# Acesso
ssh -i /tmp/vf-ssh.key root@62.238.41.231

# Smoke + Test Kit
viralefy-smoke
viralefy-test smoke    # 9 scripts
viralefy-test pentest  # 27 scripts
viralefy-test all      # tudo

# Deploy (front/backoffice via updater)
viralefy-update front backoffice
# (depois: systemctl restart viralefy-* manualmente — updater falha no step migrations)

# Build + deploy Go binary manual
cd <repo>
PATH=$PATH:/usr/local/go/bin CGO_ENABLED=0 GOOS=linux GOARCH=amd64 \
  go build -ldflags "-s -w" -o /tmp/bin ./cmd/<svc>
scp -i /tmp/vf-ssh.key /tmp/bin root@62.238.41.231:/tmp/bin-new
ssh -i /tmp/vf-ssh.key root@62.238.41.231 \
  'mv /tmp/bin-new /usr/local/sbin/viralefy-<svc> && systemctl restart viralefy-<svc>'

# Apply migration manualmente
scp -i /tmp/vf-ssh.key migrations/NNN.up.sql root@62.238.41.231:/tmp/
ssh -i /tmp/vf-ssh.key root@62.238.41.231 \
  "set -a; source /etc/viralefy/.env; psql \"\$DATABASE_URL\" -f /tmp/NNN.up.sql"
SHA=$(sha256sum migrations/NNN.up.sql | awk '{print $1}')
ssh -i /tmp/vf-ssh.key root@62.238.41.231 \
  "set -a; source /etc/viralefy/.env; psql \"\$DATABASE_URL\" -c \"INSERT INTO schema_migrations (version, name, checksum, duration_ms) VALUES ('NNN', '<name>', '$SHA', 0) ON CONFLICT (version) DO NOTHING;\""

# Caddy
systemctl reload caddy   # config simples
systemctl restart caddy  # coraza-*.conf
```
