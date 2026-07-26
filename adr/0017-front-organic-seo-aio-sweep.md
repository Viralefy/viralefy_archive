# ADR-0017 — Sweep de SEO orgânico + AIO no viralefy_front

- **Status:** Aceito
- **Data:** 2026-07-26
- **Contexto:** continuação do ADR-0015 (locale-segment ISR) e ADR-0016
  (remoção do strict-dynamic). Aquele trabalho tornou as landings estáticas/ISR;
  este otimiza o que já é servido pra performar **melhor no orgânico** (busca +
  descoberta por IA), sem mudar URL pública.

## Decisão

Aplicado um sweep de otimização orgânica em 12 frentes, agrupadas em 4 temas.
Todas as mudanças são **code-only** (sem schema/migration), preservam 100% das
URLs públicas e mantêm o ISR.

### 1. Dados estruturados mais ricos (rich results + citação por IA)

- **FAQPage nas "money pages".** O FAQ localizado já existia em
  `i18n/categories.ts` (`copy.faq()`) mas só a página de categoria o usava. Agora
  **country root** e **product-detail (slug)** também emitem `FAQPage` no JSON-LD
  **e** renderizam o FAQ visível (`<details>`) — mesmo conteúdo, zero cópia nova.
  A country usa o FAQ da categoria-âncora (seguidores Instagram, já usada pro
  Service/AggregateOffer).
- **HowTo em conteúdo procedural.** Tópicos de ajuda cujas seções são passos
  sequenciais (`how-to-buy`, `choose-the-right-plan`) emitem `HowTo` com
  `HowToStep` ordenados + âncoras deep-link (`#step-N`). Tópicos em formato Q&A
  (`refill-guarantee`, `refund-policy-explained`) **continuam FAQPage** — não se
  marca conteúdo condicional/referência como passos (structured data tem que
  refletir o conteúdo). Um tópico nunca emite os dois.
- **Review nodes** individuais no `Product` (slug), a partir das reviews REAIS já
  visíveis — reforça o Product além do `aggregateRating`. Não fabrica.
- **vs/[competitor]** passou a usar `withGlobalGraph` + `@id` pro author/publisher
  (antes um `Organization` inline duplicado, órfão no grafo).
- Novos helpers centralizados em `lib/jsonld.ts`: `buildFaqPageNode`,
  `buildHowToNode`, `buildReviewNodes` — uma superfície testada, sem shape
  duplicado por página.

### 2. `dateModified` estável (fim do frescor falso)

`lib/jsonld.ts` (buildCountryJsonLd) e `lib/seo-meta.ts` computavam
`dateModified`/`article:modified_time` via `new Date()`. Sob ISR (revalidate=1800,
não mais `force-dynamic` — ver ADR-0016) isso **avançava a cada regeneração** (a
cada 30 min), um sinal de "modificado" falso que Google desconta. Substituído por
uma **constante `SITE_CONTENT_VERSION`** (fonte única em `seo-meta.ts`), bumpada à
mão quando a cópia editorial muda. Páginas com data real por entidade
(`help.updatedAt`, `caseStudy.updatedAt`) continuam passando `modifiedAt`
explícito.

### 3. Sitemap com `lastmod` real e estável

`lib/site-urls.ts` declarava `lastModified?` mas **nunca o setava** → `sitemap.ts`
caía em `new Date()` pra ~10k URLs, reportando "mudou agora" a cada regeneração →
Google aprende a **ignorar** o lastmod. Corrigido:

- Cada URL agora declara `lastModified`: catálogo/editorial estático usa
  `SITE_CONTENT_VERSION`; help/case-studies usam a data real por entidade.
- `/status` (force-dynamic, muda a toda hora) **omite** o lastmod — honesto.
- `sitemap.ts` **omite** o campo quando desconhecido, nunca `new Date()`.
- `sitemap.xml/route.ts` (índice) deixou de ser `force-dynamic` com `new Date()`;
  agora é cacheado (1h) e cada shard reporta o **max lastModified** das suas URLs.

### 4. Cobertura de metadata, linking e superfícies de IA

- **og:image + twitter image** restauradas em 7 landings tier-4 (pricing, cities
  hub + cidade, vs hub + competitor, help hub + tópico) que definiam `openGraph`
  próprio **sem `images`** — no Next isso substitui o default do layout inteiro,
  deixando o card social **em branco**. Helper `ogFallbackImages`/`OG_FALLBACK_IMAGE`
  (`/og/global`, branded 1200×630) em `seo-meta.ts`. `legal/[doc]`, que não tinha
  openGraph nenhum (herdava a URL da HOME), ganhou OG/Twitter próprios.
- **hreflang honesto no tier-4.** pricing, cities/[city] e vs/[competitor]
  declaravam ~27 alternates de idioma **apontando pra mesma URL** (conteúdo é
  EN-only) — mentira pro Google. Colapsado pra `x-default` + `en`
  self-referencial, consistente com os hubs. (Localizar de verdade essas URLs
  fica como iniciativa futura, com URL real por idioma.)
- **Tier de planos des-orfanizado.** Os links das páginas de plano só existiam
  dentro do `CategoryCardGrid` (client, `Suspense fallback={null}`) → **ausentes
  do HTML servido**. Adicionada uma lista de planos **server-side** (`<a>` reais,
  dedup por URL) na página de categoria — o crawler passa a alcançar o tier mais
  profundo.
- **`/llms.txt`** reescrito do formato robots (errado) pro **llmstxt.org**
  (Markdown curado), agora **gerado** via route handler das mesmas fontes
  (categorias, países-âncora, guias, case studies) — nunca desatualiza.
- **`/feed.xml`** (RSS 2.0) novo, do conteúdo serial (case studies + guias),
  com autodiscovery `rel="alternate"` na home + hubs.
- **OG route** deixou de ser `force-dynamic`/`no-store` → ISR 1h por path
  (preview de share mais rápido, menos carga no backend).
- **Guard de build**: `next.config.ts` falha o build de PRODUÇÃO se
  `NEXT_PUBLIC_SITE_URL` faltar (senão metadataBase/canonical/sitemap/OG caem em
  localhost silenciosamente). `next dev` usa o fallback localhost.

## Decisão consciente: sem bloco "TL;DR" separado

As páginas de country/category já lideram com um parágrafo-resumo localizado
(`c.intro` / `copy.paragraphs()[0]`), têm bullets de proposta de valor
(`copy.bullets()` — fatos auto-contidos que a IA extrai bem) e agora FAQ. Estampar
um bloco "TL;DR" adicional com a mesma cópia seria **conteúdo visível duplicado** —
o que a reference de AIO veta ("escreva pro humano, não minta"). O intento
answer-first foi atendido pela estrutura existente + o FAQ novo, sem redundância.

## Consequências

- **Positivas:** FAQ/HowTo/Review elegíveis a rich results e mais citáveis por IA;
  lastmod/dateModified confiáveis → recrawl mais rápido do que muda de fato; cards
  sociais não-brancos nas páginas de link-building; tier de planos rastreável;
  llms.txt/feed como superfícies de descoberta por IA; guard evita desastre de
  canonical em prod.
- **Custo/tradeoff:** `SITE_CONTENT_VERSION` é manual (bumpar quando a cópia muda)
  — aceitável: o catálogo é editorial e estável. O tier-4 hreflang recolhido a en
  reflete a realidade EN-only; localizar de verdade é trabalho de conteúdo, não de
  tag. Slug FAQPage/Review e a lista de planos server-side dependem da API no
  build/runtime (mesma dependência de infra do ADR-0015).
- **Verificação:** 520 unit tests (13 novos em `tests/unit/seo-aio.test.mjs`);
  build de produção verde; render conferido via `next start` (FAQPage em
  country/category, HowTo em help, og:image nos tier-4, llms.txt Markdown,
  feed.xml RSS, sitemap com datas reais por entidade).

## Alternativas descartadas

- **Nonce/`new Date()` "por frescor"** — rejeitado: frescor falso churna e o
  Google desconta; a constante é a verdade.
- **og:image page-específica via param de título no route** — descartado por ora:
  complica o cache do route; o card branded genérico já resolve o card em branco.
  Fica como enhancement.
- **Deletar `sitemap.xml/route.ts` em favor do índice auto do Next** — não: o
  build prova que o handler manual serve `/sitemap.xml` e os shards vivem em
  `/sitemap/[id].xml` sem colisão; manter dá controle de cache.
