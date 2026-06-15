---
date: 2026-06-15
session: round 20 (4 tracks paralelos + bug Medium descoberto/corrigido)
---

# Round 20 — Aplicação da skill padroes-engenharia v5.3

Sequência rounds 13-19. Foco em fechar lacunas de DoD (§35): pentest, simulated, testes silenciados, ADRs.

## FEITO

### Track FF — Pentest forms (skill §22.8)
- **Script:** `viralefy_front/tests/pentest/forms.sh` (executável, ~31KB)
- **Andaime:** lib.sh com fallback embutido (útil em prod host sem skill); test_section/assert_http_in/assert_no_500/assert_no_echo/assert_no_leak; test_summary
- **Cobertura:**
  - POST /v1/checkout: 47 asserts
  - POST /v1/auth/user/register: 47
  - POST /v1/me/tickets: 49
  - POST /v1/me/tickets/{id}/messages: 35
  - POST /v1/me/profiles: 62
  - POST /v1/me/api-keys: 53
  - POST /v1/me/data/deletion: 65
  - **Total: 358 passes / 0 falhas**
- **Vetores por campo:** SQLi (5), XSS (5), traversal (4), unicode/null/RTL (5), type confusion (5+), boundary (0/1/max/oversized até 1MB), malformed JSON, mass-assignment, schemes hostis
- **Códigos observados:** 200, 400, 401, 404, 422, 429. **Zero 500.** Zero eco cru. Zero stack trace.
- **Self-check** (skill §22): `PENTEST_SELFCHECK=1` força FAIL conhecido (esperado 5xx em GET /v1/plans com SQLi → vem 200 ok). Prova reporter sabe falhar.

### Track GG — Simulated routes × personas × injections (skill §22.8)
- **Script:** `viralefy_ops/tests/simulated/run.py` validado
- **Route registry:** `viralefy_archive/route-registry-2026-06-15.md` (humano, 142 rotas)
- **Inventário:** `viralefy_ops/tests/simulated/routes-inventory.json` — 125 → 142 rotas. +17 que estavam no router mas faltavam (soft/hard delete, restore, bulk soft-delete, trash, honeypot, user journey, visitors)
- **Cobertura: 142/142 (100%).** Zero rotas fantasma, zero rotas mortas.
- **Execução prod:**
  - Full matrix vs core :8084 loopback: 22152 req, 156 REVIEW (todos analisados como falsos-positivos UI/rate-limit)
  - Control-only vs core :8084: 852 req, 6 REVIEW
  - WAN api.viralefy.com: 852 req, 1 REVIEW
- **Defesa confirmada:** dispatcher Rust com tower_governor (30 burst + 1/s/IP) derruba 96% das requests em 429 quando rodadas via :8090 (rate limiter funcionando)

### Bug Medium descoberto + corrigido (Track GG → 3 commits core)
- **Bug:** `GET /v1/plans/{id}/payment-methods` retornava **500** quando UUID era sintaticamente válido mas inexistente.
- **Causa:** `paymentsclient.doJSON` retornava string `fmt.Errorf("HTTP 404")` sem sentinel mapeavel. writeError caía no default 500.
- **Fix em 3 camadas:**
  1. `paymentsclient.ErrNotFound` sentinel: doJSON wrappeia 404 via `fmt.Errorf("%w")` (`viralefy_core@eb636b6`)
  2. Handler `PublicListPaymentMethods`: `errors.Is(err, paymentsclient.ErrNotFound)` → `writeError(w, domain.ErrNotFound)` → 404 (`viralefy_core@eb636b6`)
  3. `writeError` ganha defensive `pgx.ErrNoRows` → 404 (caso outras rotas tenham bug similar) + 2 unit tests novos (`viralefy_core@f523e08`)
- **Validado prod:** restart manual do core necessário (binary trocado mas systemd não restart). Após restart: `GET /v1/plans/00000000-.../payment-methods` → **404** ✓ (era 500)

### Track HH — 13 testes pré-existentes failing consertados (skill §37)
- **Baseline:** 487/500 passes, 13 fails. Veta silenciar.
- **Resultado:** 501/501 passes, 0 fails, 0 skip/xit/xfail/todo.
- **Causas identificadas:**
  - **11 testes errados** (refletiam contrato antigo):
    - `theme.test.mjs` (4): round 16 mudou default `dark`→`system`
    - `schemas.test.mjs` (2): auth usa `access_token`/UserView PascalCase/user opcional (2FA gate)
    - `categories/plan-slugs/jsonld-home` (3): CATEGORY_CODES 15→12 (marketplace fora)
    - `categories.test.mjs` (1): BUG-179 FAQ overrides por plataforma — IG e TT divergem na FAQ
    - `plan-slugs.test.mjs` (1): COPY map en/pt diretos; es/ru via copyFor fallback
  - **2 testes corretos**: código `tr()` em `src/i18n/languages.ts` quebrava identidade (`{...pack, checkout: en.checkout}` em hot path). Fix: mutação in-place na init do módulo. `tr(x) === PACKS[x]` sempre.

### Track II — 4 ADRs retroativos (skill §27)
- `viralefy_archive/adr/0011-cookies-cross-subdomain.md` — round 16, BUG-79/111
- `viralefy_archive/adr/0012-json-ld-graph-canonical.md` — rounds 17-18-19, BUG-191/192
- `viralefy_archive/adr/0013-rtl-logical-properties.md` — round 17 i18n AR
- `viralefy_archive/adr/0014-i18n-accept-language.md` — round 13 i18n
- `viralefy_archive/adr/README.md` atualizado (índice 0001-0014)
- Formato MADR (mesmo do ADR-0010): Status / Data / Decisores / Diretriz / Reavaliação / Contexto / Drivers / Options / Outcome / Triggers / Consequences / Links

## Deploy + smoke
- `viralefy-update` rodou completo
- 7 services active (após restart manual do core pra pegar binary novo)
- `viralefy-smoke` 13/13 verde
- Bug Medium GG corrigido em prod (404 ✓)

## Commits da sessão
- `viralefy_core@f523e08` — pgx.ErrNoRows → 404 + 2 unit tests
- `viralefy_core@eb636b6` — paymentsclient.ErrNotFound + handler mapeia
- `viralefy_front@4952c7d` — 13 testes consertados + tr() identity fix + pentest forms.sh
- `viralefy_ops@5f476b4` — simulated inventário ampliado
- `viralefy_archive@10d7d64` — 4 ADRs + route registry + simulated archive

## EM ABERTO

### Sentinel ErrNotFound pattern pra outros clients
- `paymentsclient.ErrNotFound` deveria virar padrão também em `senderclient` e outros futuros internal clients. Hoje só payments.

### viralefy-update não restarta serviços
- Bug recorrente: viralefy-update faz swap (mv binary) mas systemd não detecta automaticamente. Restart manual necessário. Adicionar `systemctl restart` no fim do swap, ou usar `systemd-notify` no binary.

### simulated full matrix tem 156 REVIEW
- Análise manual feita: todos falsos-positivos. Mas pra rodar sem REVIEW noise: ajustar runner pra categorizar `429` como expected quando rate limiter detectado, e expectar `400` em UUIDs/JSON malformados em vez de marcar 200/404 como anomalia.

### Vary stripped pelo Next App Router
- Continua débito conhecido. Custo > benefício atual.

## Total acumulado após round 20
- Rounds 13-20: ~30 tracks paralelos
- Bugs do QA fechados: ~197/213 (92%)
- **Bug Medium descoberto pelo simulated + corrigido em 3 camadas**
- Tests: 405 → 501 (+96 verdes, 0 silenciados)
- Smoke prod: 8 → 13 asserts (+5)
- Pentest: 0 → 358 asserts (novo pillar)
- Simulated: 0 → 142 rotas cobertas (novo pillar)
- JSON-LD: 1 → 13 pages com Org+WebSite canônicos
- i18n: 1 → 19 idiomas em rotas-chave + RTL infra
- ADRs: 10 → 14 (+4 retroativos)
- CLAUDE.md em 10 repos (pinando padrões v5.3)
- Hooks `context-monitor` + `precompact-backup` ativos
- viralefy-update débito de migrations resolvido

## DoD checklist (skill §35)
- ✓ Testes + cobertura: 501/501 verdes
- ✓ Simulated com cobertura total: 142/142 (100%)
- ✓ Pentest de entrada limpo: 358/0 em 7 rotas críticas
- ✓ Nenhum anti-padrão §37: 0 skip/xfail, sem catch/pass, sem any/@ts-ignore introduzido
- ✓ Migration reversível: nenhuma migration neste round
- ✓ Archive commitado: este arquivo + ADRs + route registry
- △ OpenAPI atualizada: não aplicável (mudanças no core foram em error mapping, não em endpoints novos)
- ✓ CI verde: TS exit 0, Go build exit 0, npm test 501/501
