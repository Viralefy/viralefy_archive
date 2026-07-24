# Task — Otimizar viralefy_front para tráfego orgânico e pago (ISR real)

- **Data:** 2026-07-24
- **Repos tocados:** `viralefy_front`, `viralefy_archive`
- **Branch:** `perf/front-locale-isr`
- **ADRs:** [ADR-0015](../adr/0015-front-locale-segment-isr.md), [ADR-0016](../adr/0016-front-strict-dynamic-removal.md)

## Pedido

> "otimize essa merda toda pra rodar o fino no tráfego orgânico e pago."

## Problema (diagnóstico)

`src/app/layout.tsx` (único a renderizar `<html>`) lia `headers()` (x-locale +
nonce) e `cookies()` (tema/moeda). No Next 15 isso torna **toda** a árvore dinâmica:
todo `revalidate=1800` estava morto (SSR por request, `no-store`, sem bf-cache), a
metadata ia pro `<body>` em vez do `<head>`, e o `@sentry/nextjs` pesava o bundle
mesmo com DSN vazio. Ou seja: o gargalo de orgânico **e** pago era o mesmo arquivo.

## O que foi feito

1. **CSP estática + remover nonce** — `'strict-dynamic'` removido (incompatível com
   ISR); GTM vira script externo. `src/lib/theme-bootstrap.ts` novo; `src/lib/csp.ts`
   deletado; `JsonLdScript` sem nonce. **`script-src` precisa de `'unsafe-inline'`**:
   o App Router emite inline `__next_f` por página que hash estático não cobre e nonce
   forçaria dinâmico — custo inevitável do ISR (ver ADR-0016; downgrade honesto vs
   round 25). Mantém allowlist de host + demais diretivas.
2. **Sentry gated** — `withSentryConfig` só com `SENTRY_AUTH_TOKEN`/DSN; SDK fora do
   bundle (0 chunks mencionam "sentry").
3. **Restructure `app/[locale]/`** — novo root layout lê `params.locale` (sem
   headers/cookies); `app/layout.tsx` deletado; middleware faz **rewrite** preservando
   URL pública; `src/i18n/locales.ts` novo (mapa segmento→`<html lang>`).
4. **generateStaticParams bottom-up** — country (130), category (todas, 650), slug
   (featured×planos quando API no build). Home + leaves globais por locale.
5. **Páginas x-locale → params.locale** — pricing, cities, cities/[city], vs,
   vs/[competitor]. not-found virou estático EN (débito documentado).
6. **Suspense** em CategoryCardGrid (useSearchParams) — exigido pelo prerender.
7. **security.test.mjs** reescrito pro novo contrato (hash, sem nonce/strict-dynamic/
   unsafe-inline) + guarda de deriva do hash.

## Verificação (build local + `next start`)

- Build verde, **4861 páginas pré-renderizadas**.
- ISR `x-nextjs-cache: HIT` (`s-maxage=1800`) em: `/`, `/en`, `/us`, `/br`, `/jp`,
  `/pricing`, e **todas** as categorias testadas (us, br, de, jp, kr, ng). Antes: `no-store`.
- `<html lang>` correto por URL: `/`=en, `/us`=en-US, `/br`=pt-BR, `/jp`=ja-JP.
- `<meta description>` agora **dentro do `<head>`** (antes ia pro body).
- CSP: `script-src 'self' 'unsafe-inline' <hosts>` — sem nonce/strict-dynamic/wildcard.
- Testes: unit 507/507; emulated i18n 7/0; a11y 5/0 (`<html lang>` ok); pentest
  frontend tudo verde (9 fails são `000` para a API ausente no ambiente local).

## CI (PR #1, branch `perf/front-locale-isr`)

- **CI (build-test + gitleaks): VERDE** — o gate obrigatório. (`main` sem branch protection.)
- **lighthouse: vermelho, mas PRÉ-EXISTENTE e MELHORADO.** `main` já falhava (3/3 runs
  de 2026-07-21). Antes do meu commit as páginas nem carregavam sob CSP-sem-unsafe-inline
  (todas as categorias NULAS); agora pontuam. O que resta é `errors-in-console`, causado
  pela CI buscar a API de PROD (`https://api.viralefy.com`) a partir de `localhost` →
  **CORS** (TODO do próprio `lighthouse.yml`: trocar por `test:api-stub`; o stub regrediu
  por motivo não isolado — fora de escopo deste PR).
- **npm-audit: vermelho, PRÉ-EXISTENTE.** Advisory MODERATE de `@opentelemetry/core`
  (transitivo via `@sentry/nextjs`); deps inalteradas por este PR; não falha o workflow CI.

## Aberto / débito

- `[slug]` (plano) só faz ISR completo com API acessível no build (senão on-demand).
- 404 estático EN (sem localização de copy; noindex/low-value).
- **Cutover prod (ADR-0016):** se o GTM injeta pixels de terceiros (Meta/TikTok/Ads),
  adicionar os hosts ao `script-src`/`img-src`/`connect-src` antes de habilitar.
- Lighthouse não rodado localmente (chrome/porta); os itens que ele flagava
  (bf-cache=no-store, meta-description no body, SEO 0.92) foram corrigidos na origem e
  verificados por header/HTML.
