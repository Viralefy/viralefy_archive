---
date: 2026-06-15
session: round 21 (4 tracks paralelos)
---

# Round 21 — débitos de infra + áreas pouco varridas

Sequência rounds 13-20. Após DoD pillars do round 20, agora foco em débitos recorrentes + backoffice.

## FEITO

### Track JJ — viralefy-update restart fix (débito de 7 sessões resolvido)
- **Bug recorrente:** desde round 14, viralefy-update fazia swap (mv binary) mas systemd não restart. PID antigo segurava inode. Round 20 viralefy-core ficou active 22h após mv recente.
- **Causa:** `stop || true` engole erro; `start` vira no-op quando unit já está active.
- **Fix:** nova função `restart_and_verify(svc)` em `bin/viralefy-update`:
  - `systemctl restart` (idempotente, força SIGTERM + spawn)
  - Polling `is-active` 45s, abort em `failed`
  - Assert `ActiveEnterTimestamp > DEPLOY_T0_EPOCH` — se AET < T0, fatal "restart não pegou; PID ainda tem binário antigo"
  - Aplica nos 7 services em ordem: payments → sender → core → auth → dispatcher → api (se !SKIP) → front → backoffice
- **Validado prod:** SCP do script novo + deploy completo. 7 services com age 16-47s no fim do deploy. Sem restart manual.

### Track KK — senderclient.ErrNotFound (paralelo paymentsclient)
- **Aplicado padrão do round 20** no senderclient pra consistência.
- Outros clients auditados:
  - `paymentsclient`: já feito (round 20)
  - `senderclient`: sentinel adicionado + test
  - `email`/`notify`/`turnstile`/`payment`/`storage`: terceiros, n/a
  - `jwtkeys`/`totp`: não são HTTP clients
- **Sem bug ativo:** todos call sites do senderclient são fire-and-forget (erro logado/descartado), então não havia bug de 500 propagado. Sentinel fica como padrão pra futuro.
- **+1 test:** `TestSend_404MapsToErrNotFound`

### Track LL — Simulated noise reduction (156 → 0 REVIEW)
- **classify() reescrita** com 3 regras de noise reduction:
  - `HOSTILE_INJECTION_TYPES × HOSTILE_DEFENSE_CODES` ({400,401,403,404,413,415,422,429}) → AUTO
  - 429 com `Retry-After` OU expected → AUTO (rate limiter funcionando)
  - 401 antes de 404 em auth_required + persona deny → AUTO (auth gate)
- **5xx e transport error** continuam REVIEW (em `--strict` viram FAIL)
- **Novas opções:**
  - `--no-rate-limit-noise`: pula rotas com 429 expected (3120 reqs a menos)
  - `--strict`: promove REVIEW → FAIL pra CI
- **Output:** AUTO=22152 / REVIEW=0 / FAIL=0 (era 156 REVIEW). Zero 5xx em todos os modos.
- **Honestidade do agente:** os 156 REVIEW do round 20 não eram falsos-positivos — eram 500s reais do bug de PublicListPaymentMethods (corrigido em `viralefy_core@eb636b6`). Agora as regras absorvem tráfego legítimo + flagam regressão real.

### Track NN — Backoffice audit (primeiro touch nos rounds 13-21)
- **10 bugs fechados:**
  - NN-501: `next.config.ts` ganha 7 security headers (CSP, X-Frame-Options DENY, nosniff, Referrer-Policy, Permissions-Policy, HSTS, X-Robots-Tag noindex)
  - NN-502: `public/robots.txt` criado (`Disallow: /`)
  - NN-503: layout metadata `robots: { index:false, follow:false, nocache:true }` + skip-link
  - NN-504: globals.css `.skip-link` (off-screen until focus)
  - NN-505: `<main id="main">` para skip target
  - NN-506: **119 `<th>` sem `scope="col"`** em 16 arquivos — script Python idempotente
  - NN-507: admins dialog aria-labelledby
  - NN-508: admins inputs email/name maxLength + minLength + autoComplete
  - NN-509: tickets[id]/users[id]/plans[id]/edit + plans inputs maxLength (6 campos)
  - NN-510: skip-link mantido em EN (admin EN-only por convenção)
- **Build:** tsc verde, 19/19 pages.
- **Débitos:** CSP `script-src 'unsafe-inline'` → migrar pra nonce, 2FA UI audit, contraste/foco visual, CSRF/SameSite cookies admin, cookies theme/currency (backoffice não tem switcher).

## Deploy + smoke
- `viralefy-update` rodou completo (com fix JJ)
- 7 services active com age 16-47s (era restart manual obrigatório)
- `viralefy-smoke` 13/13 verde

## Commits da sessão
- `viralefy_ops@d5d5b5f` — viralefy-update restart_and_verify + simulated noise -1
- `viralefy_core@df24b8e` — senderclient.ErrNotFound sentinel + test
- `viralefy_backoffice@a72cc77` — audit 10 bugs (security + a11y)

## EM ABERTO

### Backoffice débitos remanescentes
- CSP `script-src 'unsafe-inline'` (migrar pra nonce — refactor médio com Next 15 nonce API)
- 2FA UI audit dedicada
- Audit visual contraste/foco (WCAG AA)
- CSRF/SameSite cookies admin
- Cookies theme/currency (backoffice não tem switcher hoje)

### dispatcher build falha por cargo missing
- `cargo: command not found` no host de build. Restart fica com binário antigo. Não bloqueia rounds futuros, mas dispatcher Rust não consegue atualizar via viralefy-update.

### simulated: regras conservadoras
- `--strict` é a mais defensiva. Default permite injection×defense codes como AUTO. Se algum dia um 400 voltar a ser regressão, vai passar despercebido — tradeoff explícito.

## Total acumulado após round 21
- Rounds 13-21: ~32 tracks paralelos
- Bug Medium descoberto + corrigido (round 20)
- 13 testes silenciados consertados (round 20)
- viralefy-update restart bug eliminado (round 21)
- 4 ADRs retroativos criados (round 20)
- pentest + simulated agora rodam regularmente (round 20)
- Backoffice ganhou primeira atenção em 9 rounds (round 21)
- Bugs do QA fechados: ~197/213 (92%) + 10 NN no backoffice
- Tests: 405 → 501 + 1 novo em senderclient
- Smoke prod: 8 → 13 asserts
- Pentest: 0 → 358 asserts
- Simulated: 0 → 142 rotas × 6 personas × 26 injections
- ADRs: 14
- 10 CLAUDE.md em todos repos
- Hooks context-monitor + precompact-backup ativos
