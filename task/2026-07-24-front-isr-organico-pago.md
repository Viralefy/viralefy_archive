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

- **build-test + gitleaks + lighthouse: VERDES.**
- **lighthouse foi consertado nesta task** (main falhava 3/3 em 2026-07-21). Dois passos:
  1. `lighthouse.yml` passou a subir o `test:api-stub` (localhost:4010) em vez de
     buscar a API de prod a partir de localhost (matava o CORS no console). O stub já
     existia pra isso; a ressalva do TODO era o e2e de checkout, que o LH não audita.
  2. `connect-src` da CSP passou a derivar a origem da API do `NEXT_PUBLIC_API_URL`
     (antes fixava os hosts de prod → bloqueava o fetch ao stub na CI). Prod inalterado.
  Antes do fix as páginas nem carregavam sob a CSP (categorias nulas); agora pontuam e
  passam. Nota: `best-practices` fica ~0.93-0.95 porque o audit `csp-xss` do Lighthouse
  penaliza o `'unsafe-inline'` (tradeoff aceito do ISR, ADR-0016) — passou mesmo assim.
- **npm-audit: vermelho, PRÉ-EXISTENTE e NÃO-BLOQUEANTE (`continue-on-error`).** deps
  inalteradas por este PR. Achados: `body-parser` (high) é transitivo do **`@lhci/cli`**
  (ferramenta de CI, nunca roda em prod) e `@opentelemetry/core` (moderate) via
  `@sentry/nextjs` (gated off no HML/POC). O único fix é `npm audit fix --force`, que
  DOWNGRADA o lhci (0.14→0.6.1) e MAJORA o storybook — quebra tooling pra fugir de
  advisory de dev/CI sem risco em runtime. Deixado pra uma pass de higiene de deps à parte.

## Aberto / débito

- `[slug]` (plano) só faz ISR completo com API acessível no build (senão on-demand).
- 404 estático EN (sem localização de copy; noindex/low-value).
- **Cutover prod (ADR-0016):** se o GTM injeta pixels de terceiros (Meta/TikTok/Ads),
  adicionar os hosts ao `script-src`/`img-src`/`connect-src` antes de habilitar.
- Lighthouse não rodado localmente (chrome/porta); os itens que ele flagava
  (bf-cache=no-store, meta-description no body, SEO 0.92) foram corrigidos na origem e
  verificados por header/HTML.
