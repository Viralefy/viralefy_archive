# Viralefy — CHECKLIST.md

**Última atualização:** 2026-07-24

Convenção: `[x]` done · `[~]` parcial/decisão externa · `[ ]` pendente · `[!]` blocker · `[L]` LGPD/legal · `[T]` time-gated · `[$]` cliente fornecer · `[E]` externo (orçamento) · `[Q3]` planejado Q3 2026

---

## ✅ DONE — Sessão 2026-07-24 (front ISR: orgânico + pago)

Branch `perf/front-locale-isr`. Detalhe: `task/2026-07-24-front-isr-organico-pago.md`, ADR-0015/0016.

- [x] Diagnóstico: root layout lia `headers()`/`cookies()` → toda a árvore dinâmica;
      `revalidate` morto, metadata no `<body>`, Sentry no bundle
- [x] Restructure `app/[locale]/` (novo root layout via `params.locale`); middleware
      **rewrite** preservando URLs públicas; `src/i18n/locales.ts`
- [x] CSP estática; nonce/`strict-dynamic` removidos; `csp.ts` deletado; GTM externo;
      Sentry gated (0 chunks com "sentry"). **script-src precisa de `'unsafe-inline'`**
      (inline `__next_f` por página; custo do ISR no App Router — ADR-0016)
- [x] generateStaticParams **bottom-up**; country (130) + **todas** categorias (650)
      pré-renderizadas → ISR HIT; slug featured×planos (API no build)
- [x] pricing/cities/vs/[competitor] migradas `x-locale` → `params.locale`
- [x] `security.test.mjs` reescrito (contrato hash) + guarda de deriva
- [x] Build verde (4861 páginas); unit 507/507; i18n 7/0; a11y 5/0; pentest FE verde
- [x] PR #1 aberto; **CI (build-test+gitleaks) VERDE**; lighthouse/npm-audit vermelhos
      são PRÉ-EXISTENTES e não-bloqueantes (LH: CORS à API de prod na CI; audit: OTel via Sentry)
- [x] Verificado: `/`, `/us`, `/br`, `/jp`, `/pricing`, categorias (us/br/de/jp/kr/ng)
      todas `x-nextjs-cache: HIT`; `<html lang>` correto por URL; meta no `<head>`

### Aberto / débito desta task
- [~] `[slug]` (plano) só ISR completo com API acessível no build; senão on-demand
- [~] 404 estático EN (sem localização de copy; noindex)
- [ ] **Cutover prod (ADR-0016):** se GTM injeta pixels de terceiros (Meta/TikTok/Ads),
      adicionar hosts ao `script-src`/`img-src`/`connect-src` antes de habilitar
- [ ] Merge de `perf/front-locale-isr` → CI verde no GitHub → hml → prd (fluxo §21)

---

## ✅ DONE — Sessão 2026-07-21 (índice §39 + CI verde)

### Índice de funcionalidades (§39) — não existia
- [x] Gerador `viralefy_ops/lib/index/` (19 módulos, 1 função/arquivo, doc em todas)
- [x] CLI `viralefy_ops/bin/viralefy-index` + `make index` + README
- [x] `viralefy_archive/index/`: MAPA.md, INDEX_GLOBAL.md e 10 INDEX_FUNCTIONS_*
- [x] **M == N nos 10 serviços** (3728 funções), conferido contra contagem
      independente por ripgrep, arquivo a arquivo, nas 5 linguagens
- [x] Gate no CI: `ops` concilia M==N; `archive` falha se `index/` divergir do gerado
- [x] 2 bugs de enumeração corrigidos: método Go com receiver anônimo (25 funções
      fora) e CLIs do ops sem extensão (48 funções do control plane invisíveis)

### CI — os 10 repos estavam vermelhos
- [x] gitleaks: action v2 exige licença paga em org → binário oficial v8.30.1 (10 repos)
- [x] **pgx v5.7.4 → v5.9.2** — GO-2026-5004, SQL injection alcançável (5 repos Go)
- [x] **Go 1.26.4 → 1.26.5** — GO-2026-5856 (ECH/crypto-tls); CI saiu de "1.25"
- [x] dispatcher: feature sqlx `macros` removida (arrastava `rsa` RUSTSEC-2023-0071);
      ignore documentado em `.cargo/audit.toml`
- [x] backoffice: modal de criar admin traduzido (teste `no-pt-regression`)
- [x] front + backoffice: `npm ci --include=dev` nos jobs com NODE_ENV=production
- [x] ops: shellcheck limpo (SC2015 no `viralefy-update` engolia falha de cópia)

### Higiene
- [x] `AGENTS.md` da raiz: 4 → 10 repos, aponta pro CLAUDE.md v0.7.0 + índice
- [x] `credentials` (chave SSH root) removido do índice do git + `.gitignore`
      — estava staged; nunca entrou em commit

### Qualidade de frontend — atacada (sessão 2026-07-21, parte 3)

**e2e do front: 25/25 verde** (era 10 passando, 15 falhando, e antes disso a suíte
nem executava). Dois BUGS DE PRODUTO achados pelos testes:
- [x] **Página estourava 131px na horizontal no mobile** — `.site-header__search`
      quer cair numa 2ª linha (`flex: 1 0 100%`), mas o `.site-header__row` virou
      `nowrap` no fix do BUG-13. scrollWidth 524 num viewport de 393; controles
      ficavam inalcançáveis sob o overlay do checkout. Wrap reativado só ≤760px.
- [x] **`<Flag>` mentia a proporção** — a flagcdn serve `/w20/` na proporção real
      de cada país (Canadá 20x10, Nepal 20x24, Suíça 20x20) e o componente
      declarava 3:2 pra todas. Migrado pro canvas fixo `/20x15/`.
- [x] `alt` redundante (leitor anunciava "Argentina Argentina") → prop
      `nameIsAdjacent` nos 13 call sites em que o nome já está ao lado
- [x] WCAG 2.5.3 no seletor de moeda: `aria-label` escondia o "$ USD" visível
- [x] `data-testid` de `plan-card` e `status-badge` adicionados no componente
- [x] Testes reconciliados com a UI: CTA mora na página de plano; modal ganhou
      passo "Review"; banner LGPD interceptava cliques; `/login` faz handoff SSO;
      corridas reais (waitForRequest tardio, batch de 10s, rota 404)

- [x] **Contraste do tema claro reprovava WCAG AA** — `--accent: #00b89a` dava
      **2.52:1** sobre branco (mínimo 4.5:1 pra texto normal). Só apareceu no CI
      porque o Chrome headless roda com `prefers-color-scheme: light`, e o tema
      segue essa preferência — ou seja, atingia todo usuário com SO em claro.
      Agora `#00806b` (4.88:1 sobre branco, 4.61:1 sobre o `--bg`) e hover
      `#00604f` (7.54:1).

- [x] **Três elementos com par cor/fundo travado no tema errado** (mesma família
      do item acima): o badge de passo do checkout e o `.skip-link` usavam texto
      escuro fixo sobre `--accent` (que virou escuro no tema claro) → token novo
      `--on-accent`; e o `LiveCounter` (pill fixo bottom-right) tinha fundo
      escuro FIXO com `color: var(--text)`, que no tema claro vira quase-preto —
      **1.27:1, texto invisível**. Agora cor clara fixa pareada com o fundo fixo.
- [x] **Duas camadas a mais, achadas pelo CI depois:** o `<span>` aninhado e o
      botão de fechar do `LiveCounter` ainda usavam `--muted` sobre o fundo fixo
      (2.59:1), e a tabela de planos reprovava em `td-has-header` — a coluna do
      botão era `<th />` vazio. `scope="col"` sozinho NÃO resolveu (medido); o
      axe exige nome acessível, então o cabeçalho leva `cta.buy` oculto via
      `.sr-only` (utilitário que não existia). Página de categoria fechou em
      **a11y 1.0, contrast 1, td-has-header 1**.
- [ ] **Suspeita não confirmada — Footer.** `background: rgba(20,20,31,0.5)` sobre
      o `--bg` claro compõe um cinza médio (#84868e); por cálculo, o texto
      `--muted` (#5a6878) fica em **1.57:1**. O axe não flagrou (talvez não
      resolva o alpha sobre o gradiente do body), então não mexi — precisa de
      confirmação visual no tema claro antes de tocar.

**Lighthouse do front: 53 asserções falhando → 20.** best-practices 0.93 → 0.96,
a11y 1.0, performance 1.0.
- [x] `metadata.icons` apontava pra 2 arquivos inexistentes (404 por página)
- [x] `/login` saiu das URLs auditadas (só redireciona pro SSO → `chrome-error://`)
- [x] Assertions contraditórias desligadas (auditoria pulada que o preset exigia
      ter rodado; auditorias que não produzem valor). Thresholds intactos.

**Lighthouse do backoffice: 28 falhas → 1.** /dashboard com performance 1.0,
a11y 1.0, best-practices 0.96, seo 1.0.
- [x] Auditava `/login`, que é stub de redirect → trocado por `/dashboard`
- [x] favicon 404 (único erro de console) → `public/icon.svg`
- [x] logo da sidebar servia 2471px pra renderizar 98px → dimensões corrigidas

### Em aberto — 2 causas-raiz no front + 1 tradeoff no backoffice

- [ ] **Layout raiz é dinâmico e isso custa caro.** `src/app/layout.tsx` faz
      `await headers()` + `await cookies()` pro i18n/tema. Consequências medidas:
      (a) resposta vem com `Cache-Control: private, no-store` → reprova `bf-cache`;
      (b) `<title>` e `<meta name="description">` são **streamados pro BODY**, não
      pro `<head>` — o Lighthouse pontua `meta-description` 0 e a categoria SEO
      fica em 0.92; crawler sem JS não lê a descrição;
      (c) **o `export const revalidate = 1800` da home não tem efeito** — a página
      é SSR a cada request, exatamente o problema que o round 23 dizia ter
      resolvido. Corrigir = tirar `headers()/cookies()` do layout raiz (middleware
      + segmento de rota). Refactor com raio grande (26 idiomas): merece ADR.
- [ ] **Stub da API criado mas ainda não plugado no CI.** `viralefy_front/scripts/
      test-api-stub.mjs` + `tests/fixtures/*.json` (`npm run test:api-stub`) servem
      plans/categories/currencies/ppp/tax-rates/status/reviews. Com ele, todas as
      páginas renderizam 200 e 16 testes passam — mas o teste mobile do checkout
      regride ("Failed to fetch" no passo de método de pagamento) por motivo ainda
      não isolado, então o CI segue apontando pra API de produção (que é onde a
      suíte fecha 25/25). Isolar e plugar: tira a dependência de prod do CI.
- [ ] **CI audita localhost contra a API de produção** → as chamadas client-side
      (`/v1/currencies`, `/v1/country-ppp`) batem em CORS e viram erro de console
      (`errors-in-console` 0). Além de sujar a métrica, faz o CI depender de prod
      estar no ar. Correto: subir um stub da API no job.
- [ ] **`unused-javascript`** — no backoffice são 78KB de 117KB do SDK do Sentry
      (replay já desligado). Reduzir = lazy-load ou tirar do client: decisão de
      observabilidade, não fix mecânico.

### Em aberto — outros
- [ ] Dívida de doc-comment: **2286 das 3728 funções** (61%) sem doc de contexto (§3/§6).
      Atacar por serviço, começando pelo `core`. Não gerar em massa por IA.
- [ ] Mapa de endpoints (§39, superfície de ataque) — `route-registry-2026-06-15.md`
      é o insumo, `/pentest-endpoints` o gerador
- [ ] Repo raiz do workspace sem remote, com arquivos nunca commitados

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
