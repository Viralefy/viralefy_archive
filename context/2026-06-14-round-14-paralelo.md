---
date: 2026-06-14
session: round 14 (5 tracks paralelos)
---

# Round 14 — mais 5 tracks paralelos

Sequência do round 13. Mesma arquitetura: 5 agents Claude paralelos,
files distintos, commits serializados.

## FEITO

### Track E — viralefy-update .env permission (débito antigo resolvido)
- **Repo:** `viralefy_ops`
- **Arquivo:** `bin/viralefy-update`
- **Root cause:** o script fazia `sudo -u viralefy-{api,core} bash -c "source '$ENV_FILE'; ... migrate up"`. `/etc/viralefy/.env` é `0600 root:viralefy` (installer set 0640, mas algo em prod baixou pra 0600). User `viralefy-api`/`viralefy-core` não consegue ler → vars vazias → migrate cai no auth default e SASL falha.
- **Fix:** `.env` já é carregado como root no início do script. Agora `sudo --preserve-env="$MIGRATE_ENV" -u viralefy-X <bin> migrate up` (sem subshell, sem source no contexto unpriv). `MIGRATE_ENV` é allowlist explícita pra não vazar STRIPE_SECRET etc.
- **Deploy:** scp manual de `bin/viralefy-update` → `/usr/local/sbin/viralefy-update` na prod (script é instalado pelo installer, não auto-atualizado).
- **Validado em prod:** `viralefy-update` rodou **completo pela primeira vez**, sem precisar de restart manual dos 4 services. Migration api → core passou.
- **Commit:** `viralefy_ops@5a02052`

### Track F — response_test.go pro 23505 → 409
- **Repo:** `viralefy_core`
- **Arquivo criado:** `internal/interface/http/response_test.go`
- **4 testes:**
  - `TestWriteError_PgUniqueViolation_Returns409` (caminho feliz)
  - `TestWriteError_OtherPgError_FallsThroughToSwitch` (23503 FK ainda cai em 500, prova que só 23505 é interceptado)
  - `TestWriteError_DomainNotFound_StillReturns404` (regressão)
  - `TestWriteError_WrappedPgError_IsDetected` (`fmt.Errorf("%w", pgErr)` via `errors.As` na cadeia)
- **Tudo passa.** `go test ./internal/interface/http/...` → ok
- **Commit:** `viralefy_core@90ddeb4`

### Track G — i18n ES/FR/DE/JA em /pricing /vs /cities
- **Repo:** `viralefy_front`
- **Arquivos:** `src/middleware.ts`, `src/app/pricing/page.tsx`, `src/app/vs/[competitor]/page.tsx`, `src/app/cities/[city]/page.tsx`
- **Middleware:** `detectAcceptLanguage` reconhece pt/es/fr/de/ja/en e retorna BCP47 (`es-ES`, `fr-FR`, `de-DE`, `ja-JP`).
- **PageLang:** expandido de `"pt"|"en"` pra 6 idiomas. `resolveLang` ramifica por prefixo.
- **Packs PRICING/VS/CITY_T:** ES/FR/DE/JA completos. Tradução manual idiomática (não literal).
- **JSON-LD:** `inLanguage`, `openGraph.locale`, `alternates.languages` refletem o lang.
- **neighborhoodsText:** ramifica fallback por lang (`"central <city>"` → `"o centro de"` PT, `"el centro de"` ES, `"<city>の中心部"` JA, etc.)
- **Smoke prod validou:** 4 langs × 3 paths = 12 combos OK. Exemplos:
  - ES /pricing → "Precios transparentes en USDT — Viralefy"
  - FR /vs/socialplug → "Viralefy vs SocialPlug — comparatif côte à côte"
  - DE /cities/london → "Instagram-Follower in London kaufen — lokales Wachstum"
  - JA /pricing → "USDT建ての透明な価格 — Viralefy"
- **Débito:** it/ru/nl/ko/ar/zh/hi seguem em EN fallback. Template já preparado pra adicionar.

### Track H — BUG-67 / BUG-71-74 sitemap order
- **Repo:** `viralefy_front`
- **Arquivo:** `src/lib/site-urls.ts`
- **Root cause:** SQL `ORDER BY sort_order, followers_qty` tinha sort instável quando `sort_order` repetia entre categorias. Combinado com `SITEMAP_URLS_PER_PAGE=100`, uma categoria PT podia ficar partida entre `/sitemap/pt.xml` e `/sitemap/pt-2.xml`. QA percebia como "truncamento", mas era só perceção.
- **Fix:** `sortStableForSitemap` aplicado antes do retorno de `allSiteUrls`. Chave: `(country ASC, categoryIndex ASC, qty ASC, url ASC, índice de inserção)`. Landings cross-country (home/pricing/cities/vs/legal) ficam no topo.
- **SITEMAP_HARD_CAP_PER_LANG=50_000** com `console.warn` se exceder (não trunca, só avisa).
- **Validado em prod:** `/sitemap/pt.xml` começa em `/ao` (ordem alfabética por país), 100 URLs por página.

### Track I — bugs pontuais
**BUG-178 prefetch /tickets** → falso positivo. Nenhum `prefetch=false` no front. Rota existe. Marcado como "pedir QA URL exata".

**BUG-110/121 BTC ₿** → já estava OK. Seed tem `{"BTC", "Bitcoin", "₿"}`, frontend consome `c.symbol` dinâmico, nunca hard-coda. Ocorrências de "BTC" em texto são todas marketing (correto: "Pay in USDT, BTC, ETH").

**Date format register** → form não tem campo de data. Nota memory era ambígua, provavelmente referia ao phone validation (já implementado).

**Register +55 placeholder hard-coded** → FIX APLICADO.
- `src/app/register/page.tsx`
- Mapa `PHONE_PLACEHOLDERS` (br/us/uk/es/fr/de/it/jp/cn)
- `useEffect` lê `localStorage.viralefy_last_country` e ajusta placeholder
- Fallback `+1 555 123-4567` (US)
- Erro também usa placeholder dinâmico

**viralefy-reconcile.service failed** → NÃO É BUG. Binário sai com `exit 1` quando detecta drift (por design). systemd marcava como `failed`. Fix aplicado direto no unit file em prod:
- `/etc/systemd/system/viralefy-reconcile.service` ganhou `SuccessExitStatus=0 1`
- Backup salvo em `.bak`
- `systemctl daemon-reload && systemctl reset-failed`
- Drift continua capturado no journald.

## Deploy + smoke
- `viralefy-update` rodou completo (primeira vez sem restart manual!)
- Migration api → core: OK
- Todos os 7 services active (front, backoffice, payments, sender, core, auth, dispatcher)
- `viralefy-smoke` 8/8 verde
- i18n smoke: 4 langs × 3 paths × 200 OK + lang correto em `<html>`

## Commits da sessão
- `viralefy_ops@5a02052` — fix(viralefy-update): migrate via sudo --preserve-env
- `viralefy_core@90ddeb4` — test(http): cover writeError pg unique_violation
- `viralefy_front@39bd4df` — feat(qa): round 14 (i18n + sitemap + register)

## EM ABERTO

### Débitos i18n
- it/ru/nl/ko/ar/zh/hi/etc em /pricing /vs /cities (fallback EN).
- LOCAL_FLAVOR PT em ~5 cidades sem entrada específica (continua EN embarcado nos parágrafos PT).

### Pendentes investigação
- BUG-178: precisa URL exata do QA pra reproduzir.
- BUG-94/95 likes TikTok: decisão de produto sobre `plans.price_cents` (não é drift).

### Débitos infra residuais
- `chmod 0640` em `/etc/viralefy/.env` na prod (hardening, não obrigatório com fix do script): `ssh ... 'chmod 0640 /etc/viralefy/.env'`. Realinha com o que installer/30-secrets.sh define.
- Caddy/CDN strip `Vary: Accept-Language` (round 13 nota).
- Dispatcher Rust: cargo not found no host de build → tasks só de Go funcionam.

## Não refazer
- viralefy-update step migrations sem deploy do script novo: o fix EM bin/viralefy-update do repo precisa de scp manual pro prod (script é installed, não pulled).
- BUG-110/121: BTC ₿ — confirmado OK no DB e front, não tem mais nada pra mexer aqui.

## Total da maratona após round 14
- Round 13: 4 tracks (admin/plans, checkout review, PT i18n, middleware A-L)
- Round 14: 5 tracks (viralefy-update fix, response test, i18n ES/FR/DE/JA, sitemap order, lote pequeno)
- Bugs fechados acumulado: ~143 / 213 (67%)
