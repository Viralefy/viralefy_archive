# ADR-0012 — JSON-LD via `@graph` canonical com Organization + WebSite globais

- **Status:** accepted
- **Data:** 2026-06-15
- **Decisores:** Equipe Viralefy (Track T Round 17, Track Y Round 18)
- **Diretriz relacionada:** §15 (SEO técnico), §22 (consistência cross-page)
- **Reavaliação:** 2026-12

## Contexto e Problem Statement

Round 17 (Track T) e Round 18 (Track Y) revelaram problemas estruturais no markup
estruturado:

- Páginas emitiam **2-3 `<script type="application/ld+json">` separados** (Organization
  + WebSite + Service, por exemplo), cada um com sua cópia da Org.
- `Service.provider`, `Article.author`, `Article.publisher`, `Product.brand`
  apareciam **inline anônimos** — referenciando a empresa por nome em vez do
  identificador canônico.
- `AggregateOffer.lowPrice` calculava errado quando havia ofertas com `amount === 0`
  (free tier) ou `amount === "on_request"` (enterprise) — Google Rich Results marcava
  como inválido.
- Sem `@id` canônico, validadores tratavam cada Organization como entidade nova,
  diluindo sinais de SEO.

Atingiu **BUG-191** e **BUG-192**.

## Decision Drivers

- Google Rich Results e Bing Webmaster esperam **um único grafo coerente** por página.
- `@id` canônico permite cross-page e cross-script referenciar a mesma entidade.
- AggregateOffer precisa filtrar ofertas inválidas pra não publicar `lowPrice=0`
  enganoso.
- 11 páginas afetadas — refactor pontual viável.

## Considered Options

### Option A — Um `<script>` por página com `{ "@context": "schema.org", "@graph": [...] }`

Organization e WebSite globais com `@id` canônico (`/#organization`, `/#website`)
no topo do `@graph`. Páginas com Service/Article referenciam por `@id` (sem inline).

**Prós:** payload menor; entidades canônicas; validadores felizes; código DRY
(helper `buildGraph(pageEntities)`).
**Contras:** refactor de 11 páginas; quebra se algum dev adicionar `<script>` solto.

### Option B — Múltiplos scripts (status quo)

**Prós:** zero refactor. Schema.org tecnicamente permite.
**Contras:** Google Rich Results trata cada script como ilha; duplicação de Org;
risco de inconsistência (versão A de Org em pricing, versão B em about).

### Option C — Microdata HTML (`itemscope` / `itemtype`)

**Prós:** inline no markup, sem JSON.
**Contras:** verbose, mistura semântica com layout, dificulta a11y, e Google
favorece JSON-LD desde 2017.

### Option D — RDFa

**Prós:** padrão W3C.
**Contras:** mesmo problema da microdata + tooling pior.

## Decision Outcome

**Aceito Option A.** Padronizar todo JSON-LD do site sob um único `<script>` por
página, no formato:

```json
{
  "@context": "https://schema.org",
  "@graph": [
    { "@type": "Organization", "@id": "https://viralefy.com/#organization", "name": "Viralefy", ... },
    { "@type": "WebSite",      "@id": "https://viralefy.com/#website",      "publisher": { "@id": "https://viralefy.com/#organization" }, ... },
    { "@type": "Service",      "provider": { "@id": "https://viralefy.com/#organization" }, ... }
  ]
}
```

### Compromissos

1. **Helper único** (`apps/web/src/lib/seo/jsonld.ts`) exporta `buildGraph(entities)`
   que injeta Org + WebSite automaticamente no topo.
2. **`@id` canônico obrigatório** para Organization (`/#organization`) e
   WebSite (`/#website`).
3. **Service/Article/Product** referenciam Org por `@id`, nunca inline anônimo.
4. **AggregateOffer** filtra ofertas onde `amount === 0` ou
   `amount === "on_request"` antes de calcular `lowPrice`/`highPrice`. Se restar
   zero ofertas válidas, omite o AggregateOffer inteiro.
5. **Lint**: regex CI grep `'application/ld\\+json'` deve casar exatamente 1 vez
   por route file no `apps/web/src/app/`.

## Triggers para Reabrir

- Google passar a tratar `@graph` mal em algum vertical.
- Páginas com >2 entidades complexas exigirem split (ex.: AMP).
- Adoção de framework de SEO que gere JSON-LD próprio.

## Consequences

### Positivas

- 1 `<script>` por página (era 2-3) → payload menor.
- Org e WebSite canônicos → sinais consolidados em Knowledge Graph.
- Rich Results consistente em 11 páginas refatoradas.
- Helper centralizado → próxima página herda padrão de graça.

### Negativas

- Refactor de 11 páginas (custo único, já pago).
- Dev que adicionar JSON-LD à mão fora do helper quebra a invariante — depende
  de revisão/lint pra não regredir.
- AggregateOffer some quando todas as ofertas são free/on_request — perde rich
  card no Google (trade-off intencional vs. publicar `lowPrice=0` enganoso).

## Links

- BUG-191 (Round 17): Organization duplicado entre scripts.
- BUG-192 (Round 18): AggregateOffer.lowPrice incorreto em planos free.
- `apps/web/src/lib/seo/jsonld.ts` — helper canônico.
- Schema.org `@graph` reference: https://schema.org/docs/datamodel.html
- ADR-0008 (Next.js stack).
