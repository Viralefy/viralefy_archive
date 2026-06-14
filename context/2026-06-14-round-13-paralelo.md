---
date: 2026-06-14
session: round 13 (paralelo de 4 tracks)
---

# Round 13 — 4 tracks em paralelo

Executado em 4 agents Claude paralelos. Cada track tocou arquivos
distintos pra evitar race. Commits serializados pelo orquestrador.

## FEITO

### Track A — BUG /v1/admin/plans 500 → 409
- **Arquivo:** `viralefy_core/internal/interface/http/response.go`
- **Mudança:** `writeError` agora trata `*pgconn.PgError` com `Code == "23505"`
  (unique_violation) → `409 CONFLICT` com mensagem genérica
  `"resource already exists"`. Sem expor nome da constraint.
- **Build:** `go build ./...` OK. Sem dependência nova
  (pgconn é submódulo do pgx/v5 já em go.mod).
- **Commit:** `viralefy_core@ae0b266`
- **Débito:** sem teste unitário; idealmente o repositório de planos deveria
  traduzir 23505 → `domain.ErrConflict` na camada de persistência (DDD strict).

### Track B — BUG-69 checkout review step
- **Arquivos:** `viralefy_front/src/components/CheckoutModal.tsx`,
  `src/i18n/languages.ts`
- **Mudança:** novo step `"review"` entre `form` e `method`. Mostra handle,
  plano, total na display currency, método escolhido. Botões Confirmar+Pagar /
  Voltar. ESC no review volta (não fecha modal — consistente com BUG-60).
- **i18n:** `review.title/handleLabel/totalLabel/confirmAndPay/back` em EN/PT/ES.
  FR/DE/IT/NL/RU/AR/ZH/JA caem em EN via `tr()` fallback.
- **Commit:** parte do `viralefy_front@7ea066d`

### Track C — BUG-50/75/89/104 PT-BR em /pricing /vs /cities
- **Arquivos:** `src/app/pricing/page.tsx`, `src/app/vs/[competitor]/page.tsx`,
  `src/app/cities/[city]/page.tsx`
- **Mudança:** lê `headers()` pra obter `x-locale`, resolve em `"pt" | "en"`.
  Packs `PRICING`, `VS`, `CITY_T` inline com PT+EN completos. JSON-LD
  `inLanguage`, `openGraph.locale`, `alternates.languages` refletem lang.
- **Trade-off:** 3 rotas migraram de SSG estático (`○`/`●`) para
  server-rendered (`ƒ`) — uso de `headers()` é dynamic API.
- **Commit:** parte do `viralefy_front@7ea066d`
- **Débito:** apenas PT+EN. ES/FR/DE/JA continuam caindo em EN. Para adicionar
  bastam mais entradas nos packs locais + entrada em `resolveLang`.

### Track C+ — BUG hidden: middleware não honrava Accept-Language
- **Problema descoberto após deploy:** Track C funcionava só via `headers()`,
  mas o middleware só lia o country prefix do path. Em `/pricing` (sem
  country) sempre devolvia `en`, tornando o suporte PT unreachable.
- **Arquivo:** `viralefy_front/src/middleware.ts`
- **Mudança:** `detectAcceptLanguage()` parseia `Accept-Language` com weight
  (`q=...`), prioridade country prefix > Accept-Language > "en". Emite
  `Vary: Accept-Language` em rotas globais.
- **Smoke prod confirmou:**
  - `/pricing` Accept-Language pt-BR → `<html lang="pt-BR">` + "Preços transparentes em USDT"
  - `/vs/socialplug` pt-BR → "Viralefy vs SocialPlug — comparação lado a lado"
  - `/cities/london` pt-BR → "Comprar seguidores no Instagram em London"
  - `/br` (country-scoped) intacto → `lang="pt-BR"`
  - `/pricing` Accept-Language en-US → `<html lang="en">` + "Transparent pricing"
- **Commit:** `viralefy_front@625886f`

### Track D — BUG-94/95 preços TikTok 50k/100k
- **Investigação:** rodou análise + recompute SQL na prod (`/tmp/track-d-tiktok-recompute.sql`).
- **Fonte da fórmula:** `viralefy_core/internal/application/plan_price_drift_cron.go:78-89`
  ```
  plan_prices.amount = ROUND( (plans.price_cents/100.0) * currencies.rate,
                              currencies.decimals )
  ```
- **Resultado em prod:** `UPDATE 0` — todos os 46 rows de TikTok 50k/100k
  já estavam on-formula. `plan_prices` está consistente com a fórmula
  do BUG-15.
- **Conclusão:** o que QA reportou como "preço anormal" vem dos
  `plans.price_cents` em si, não de drift no `plan_prices`. Exemplos:
  - `curtidas_tiktok` 50k = $549.90 (price_cents=54990)
  - `curtidas_tiktok` 100k = $899.90 (price_cents=89990)
  - `visualizacoes_tiktok` 50k = $85, 100k = $160 (normais)
- **Bloqueio:** decisão de produto se os preços de likes TikTok são
  intencionais ou precisam recalibragem. Não há fix de código.

## Deploy + smoke prod
- `viralefy-update front` rodou 2 vezes (uma com Track A+B+C, outra com
  middleware patch). Ambas falharam na etapa de migrations
  (`/etc/viralefy/.env: Permission denied` — bug conhecido, débito antigo).
- Após cada deploy, restart manual de `viralefy-{front,backoffice,payments,sender}`
  porque o swap interrompido deixou os 4 inactive.
- `viralefy-smoke` 8/8 verde ao final.

## EM ABERTO

### Decisão de produto (não é fix de código)
- **BUG-94/95 preços likes TikTok**: revisar com produto se $549/$899 são
  intencionais. Sugestão: comparar com benchmarks do mercado ou fórmula
  unit-cost × markup.

### Débito de infra recorrente
- **viralefy-update**: migrations step falha por `/etc/viralefy/.env`
  Permission denied. Workaround atual: rodar deploy, restartar manualmente
  os 4 services. **Fix sugerido**: rodar o passo de migration como root
  ou ajustar perm do .env pra +r do user de service.
- **Caddy/CDN strip Vary**: o `Vary: Accept-Language` que o middleware
  emite não aparece no header de resposta visto pelo browser
  (vary contém apenas `rsc, next-router-*, Accept-Encoding`). Pode
  causar cache mix-up se houver CDN intermediário. Investigar config Caddy.
- **`viralefy-reconcile.service` failed**: visto durante smoke. Cron de
  drift que não roda — débito de observabilidade.

### Débitos de qualidade
- ES/FR/DE/JA em /pricing /vs /cities (fallback EN).
- LOCAL_FLAVOR PT pra ~5 cidades sem entrada específica.
- Teste unitário `response_test.go` cobrindo o caminho 23505.

## NÃO REFAZER
- Não tentar conectar no DB local pra checar `plan_prices` — está vazio
  (`SELECT count(*) FROM plans = 1`). Toda análise de preço deve sair da
  prod via SSH.
- Não tentar rodar o viralefy-update inteiro esperando migrations passar
  até o `.env` permission bug ser resolvido. Workaround: deploy + restart manual.

## Como retomar
- SSH: `ssh -i /tmp/vf-ssh.key root@62.238.41.231`
- SQL Track D: `/tmp/track-d-tiktok-recompute.sql` na prod (já aplicado,
  idempotente — pode rodar de novo sem efeito).
- Front commits novos pós-handoff: `b6c4adb..625886f` (3 commits).
- Core commits novos: `e8d2620..ae0b266` (1 commit).
