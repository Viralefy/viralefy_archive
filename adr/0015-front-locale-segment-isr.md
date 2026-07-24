# ADR-0015 — Segmento de rota `[locale]` + CSP estática para destravar o ISR do front

- **Status:** accepted
- **Data:** 2026-07-24
- **Decisores:** Equipe Viralefy
- **Diretriz relacionada:** §15 (SEO/i18n), §21 (performance/CWV), §22 (UX)
- **Relacionada:** [ADR-0014](0014-i18n-accept-language.md) (Accept-Language em rotas globais — **preservada**), [ADR-0016](0016-front-strict-dynamic-removal.md)
- **Reavaliação:** 2027-01

## Contexto e Problem Statement

Todas as landing pages de tráfego **orgânico e pago** (`/`, `/[country]`,
`/[country]/[category]`, `/pricing`, …) estavam sendo renderizadas **dinâmicas
(SSR por request)**, apesar de cada página declarar `export const revalidate = 1800`.

Causa raiz única: `src/app/layout.tsx` — o **único** arquivo que renderiza `<html>` —
chamava `await headers()` (para `x-locale` e o `x-nonce` da CSP) e `await cookies()`
(tema e moeda). No App Router do Next 15, **qualquer** `headers()`/`cookies()` no root
layout opta a árvore **inteira** para render dinâmico. Consequências medidas:

1. Todo `revalidate` estava **morto** — `Cache-Control: private, no-store`, sem
   back/forward cache. O ISR do "round 23" nunca teve efeito real.
2. `<title>`/`<meta name="description">` eram **streamados para o `<body>`**, não o
   `<head>` — crawler sem JS não lia; categoria SEO travava em 0.92.
3. `@sentry/nextjs` entrava em todo bundle client mesmo com DSN vazio (HML/POC) —
   JS morto (flag `unused-javascript`).

## Decision Drivers

- `<html lang>` correto **por URL** no HTML cru (SEO + WCAG 3.1.1), gerado de forma
  **estática** (ISR), não SSR.
- **Preservar 100% das URLs públicas** já indexadas — mudar URL nuke o SEO
  (canonical/hreflang/sitemap/redirects).
- Manter o comportamento de [ADR-0014] (rotas globais localizam por Accept-Language).

## Decisão

O `<html>` só é renderizado pelo root layout, e para variar `lang` por URL de forma
**estática** o locale precisa ser um route param **acima** desse layout. Logo:

1. **`app/[locale]/layout.tsx` vira o root layout** (renderiza `<html lang>`/`dir` a
   partir de `params.locale`; sem `headers()`/`cookies()`). `app/layout.tsx` removido.
   Toda a árvore de páginas move para `app/[locale]/`; route handlers (`api`, `og`,
   `sitemap*`, `robots`, `monitoring`) ficam no top-level.
2. **Middleware faz REWRITE (não redirect)** de `/us/instagram-followers` →
   `/{locale}/us/instagram-followers`, preservando a URL pública. O valor do segmento
   é a mesma string BCP47 que o middleware já computava para `x-locale`, lowercased
   (`pt-br`, `en`, `ja-jp`). hreflang/canonical/sitemap seguem emitindo URLs **sem
   prefixo** — nada muda no SEO indexado. Guard: se o path já começa com um locale
   (path físico interno), não reescreve de novo.
3. **As 3 outras dependências dinâmicas saem do root:** nonce → CSP **estática**
   (o Next emite inline `__next_f` por página que só `'unsafe-inline'` cobre sem nonce;
   trade-off em [ADR-0016]); tema → bootstrap inline lê cookie/localStorage antes do
   paint (`suppressHydrationWarning`); moeda → client (Providers já lê
   `getStoredCurrency`).
4. **`generateStaticParams` é BOTTOM-UP** nas rotas dinâmicas aninhadas: cada rota
   devolve o par COMPLETO (`{locale, country, …}`). O Next 15 **não propaga** de forma
   confiável o param do `[locale]` pai (layout) para o `generateStaticParams` do filho
   (testado: chega `undefined`) — top-down não funciona aqui.
5. **Sentry só entra no build quando há token/DSN** (`SENTRY_ENABLED`); sem isso o SDK
   fica fora do bundle client.

### Nuance crítica de ISR: middleware rewrite × cache

Com o middleware fazendo rewrite, o **ISR-fallback não cacheia** params não-listados
(on-demand via rewrite → `no-store`). **Só caminhos EXPLICITAMENTE pré-renderizados**
viram cache HIT. Por isso pré-renderizamos **todas** as (país × categoria) — 650
páginas, `categorySlug` é função pura, custo baixo — e **todos** os country roots (130).
As páginas de plano (`[slug]`) dependem de quantidades da API: seedam os FEATURED com
planos reais quando a API está acessível no build; senão ficam on-demand (débito de
infra: build com API habilita o ISR completo do slug).

## Consequências

**Positivas:** toda landing (home/country/category/pricing/locales) serve ISR
(`s-maxage=1800, stale-while-revalidate`, `x-nextjs-cache: HIT`); `<html lang>` correto
por URL no HTML cru; metadata no `<head>`; bf-cache habilitado; Sentry fora do bundle;
URLs públicas e SEO intactos. Build: 4861 páginas pré-renderizadas.

**Negativas / débitos:**
- 404 (`[locale]/not-found`) é estático EN (não recebe `params`; ler `headers()`
  reintroduziria dinâmico) — perde localização da copy nas 25 línguas e o país no
  "Browse all". 404 é noindex/low-value.
- `[slug]` (plano) só faz ISR completo se a API estiver acessível no build.
- Trade-off de segurança da CSP: ver [ADR-0016].

## Alternativas consideradas

- **Static shell + lang client-side (sem restructure):** mais rápido, mas `<html lang>`
  fica `en` no HTML cru para não-EN (regressão WCAG/SEO real nas páginas que faturam).
  Rejeitado pelo usuário em favor do restructure completo.
- **URLs prefixadas (`/en/...`, `/pt-br/...`):** destruiria o SEO indexado. Rejeitado —
  o rewrite preserva as URLs.
