# Task — Otimizar o viralefy_front para performar melhor no orgânico (sweep SEO + AIO)

- **Data:** 2026-07-26
- **Repos tocados:** `viralefy_front`, `viralefy_archive`
- **Branch:** `perf/front-locale-isr` (continuação; mesmo PR #1)
- **ADR:** [ADR-0017](../adr/0017-front-organic-seo-aio-sweep.md)

## Pedido

> "otimize BEM esse site para performar ainda melhor no organico."

## Diagnóstico (3 auditorias paralelas)

Fan-out de 3 subagents (metadata por página, structured-data/AIO, técnico/CWV).
Base já forte após ADR-0015/0016 (ISR, `<html lang>` por URL, canonical limpo,
1 `<h1>`, fontes de sistema = custo zero, Product/Offer/Article/Merchant Listing).
Lacunas encontradas, por impacto:

- **Alto:** FAQPage ausente nas money pages (country/slug) apesar do FAQ já
  existir localizado; `lastmod` do sitemap sempre "agora" (sinal morto); tier de
  planos sem link interno em HTML servido (quase-órfão); og:image faltando em 7
  landings tier-4 (card social em branco).
- **Médio:** `dateModified`/`article:modified_time` via `new Date()` (frescor
  falso sob ISR); `/llms.txt` em sintaxe robots (não llmstxt.org); sem feed;
  `legal/[doc]` sem OG próprio; hreflang tier-4 "27 langs → 1 URL"; HowTo/Review
  não usados; sem TL;DR.
- **Baixo:** OG route `force-dynamic`/`no-store`; `NEXT_PUBLIC_SITE_URL` cai em
  localhost silenciosamente; vs-page Organization inline em vez de @id.

Usuário aprovou **sweep completo** (High+Medium+Low).

## O que foi feito (12 frentes) — detalhe no ADR-0017

1. **FAQPage** em country + product-detail (reusa `copy.faq()` localizado) +
   visível. **HowTo** em help procedural (how-to-buy, choose-the-right-plan) com
   `#step-N`; Q&A continua FAQPage. **Review** nodes reais no Product. **vs**
   migrado pra `withGlobalGraph` + @id. Helpers novos em `lib/jsonld.ts`
   (`buildFaqPageNode`, `buildHowToNode`, `buildReviewNodes`).
2. **`dateModified` estável**: constante `SITE_CONTENT_VERSION` (fonte única em
   `seo-meta.ts`) no lugar de `new Date()` — em `jsonld.ts` e `seo-meta.ts`.
3. **Sitemap `lastmod` real**: `site-urls.ts` seta `lastModified` por entrada
   (versão do conteúdo p/ catálogo; data real p/ help/case-studies); `/status`
   omite; `sitemap.ts` omite quando desconhecido (nunca `new Date()`);
   `sitemap.xml/route.ts` cacheado (1h) com max-lastmod por shard.
4. **og:image + twitter** restauradas em pricing/cities(+city)/vs(+competitor)/
   help(+slug) via `ogFallbackImages`/`OG_FALLBACK_IMAGE` (`/og/global`);
   `legal/[doc]` ganhou OG/Twitter próprios.
5. **hreflang honesto**: pricing/cities[city]/vs[competitor] colapsados de 27
   langs→1 URL pra `x-default`+`en` (conteúdo EN-only).
6. **Tier de planos rastreável**: lista `<a>` server-side (dedup por URL) na
   página de categoria — o grid client (Suspense null) não expunha os links.
7. **`/llms.txt`** gerado no formato llmstxt.org (route handler, das mesmas
   fontes). **`/feed.xml`** RSS 2.0 novo (case studies + guias) + autodiscovery
   na home/hubs.
8. **OG route** → ISR 1h/path. **Guard de build** exige `NEXT_PUBLIC_SITE_URL`
   em produção.

**TL;DR separado: decisão consciente de NÃO adicionar** — o lead paragraph +
bullets + FAQ já cobrem o answer-first; um bloco duplicado seria conteúdo
redundante (vetado pela reference de AIO). Registrado no ADR.

## Verificação

- **520 unit tests** (13 novos em `tests/unit/seo-aio.test.mjs`) — verde. Cobrem
  os 3 builders, `dateModified` estável (anti-churn por render), og fallback,
  lastmod real+estável por entidade.
- **Build de produção verde** (com guard de env ativo).
- **Render conferido** (`next start` + stub API): FAQPage em country/category,
  Product+FAQPage no slug, 5 links de plano server-side na categoria, HowTo +
  `#step-N` no help, FAQPage (não HowTo) no refill-guarantee, og:image nos
  tier-4, `rel=alternate` do feed na home, `/llms.txt` Markdown, `/feed.xml` RSS,
  sitemap com datas reais por entidade (2026-02-14 etc.).
- Review nodes corretamente ausentes quando não há review (stub sem reviews) —
  não fabrica; builder coberto por unit test.
- **Índice §39 regenerado** (`viralefy-index`, N=M, exit 0).

## Aberto / débito (não bug — decisão/infra)

- `SITE_CONTENT_VERSION` é bumpada à mão quando o copy editorial muda.
- Localizar de verdade as URLs tier-4 (pricing/cities/vs) por idioma é trabalho
  de conteúdo futuro (hoje EN-only, hreflang self-referencial honesto).
- Slug FAQPage/Review e lista de planos server-side dependem da API no
  build/runtime (mesma dependência de infra do ADR-0015).
- Suítes smoke/pentest/emulated são prod-oriented (SITE_URL deployado); não
  rodadas localmente aqui pra evitar falso-negativo de base divergente do build.
