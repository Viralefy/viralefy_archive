# ADR-0014 — i18n por `Accept-Language` em rotas globais (sem country prefix)

- **Status:** accepted
- **Data:** 2026-06-15
- **Decisores:** Equipe Viralefy (Track C, Round 13)
- **Diretriz relacionada:** §15 (SEO e i18n), §22 (UX cross-locale)
- **Reavaliação:** 2026-12

## Contexto e Problem Statement

Round 13 expôs uma assimetria entre rotas:

- **Rotas country-scoped:** `/br/*`, `/us/*`, `/de/*` — prefixo na URL determina
  locale.
- **Rotas globais:** `/pricing`, `/vs/*`, `/cities`, `/case-studies` — **sem
  prefixo de país**.

Middleware antigo (`src/middleware.ts`) setava locale **só pelo path**. Resultado:
rotas globais caíam **sempre em EN**, mesmo para usuário pt-BR.

Track C tinha criado packs de tradução **PT** para essas páginas, mas eram
*unreachable* — código existia, conteúdo nunca renderizava em produção.

Atingiu **BUG-50, BUG-75, BUG-89, BUG-104**.

## Decision Drivers

- Não duplicar URL por idioma (não criar `/pt/pricing`, `/es/pricing`, ...) →
  sitemap explodiria + canonical SEO ficaria ambíguo.
- Manter `/br/*` intacto (country = país, não idioma).
- Suportar **19 idiomas** com 1 URL por página global.
- Primeira visita precisa funcionar (cookie de lang não cobre).
- Privacidade: evitar geo-IP no edge.

## Considered Options

### Option A — Middleware lê `Accept-Language` em rotas globais

`src/middleware.ts` detecta ausência de country prefix, faz parse de
`Accept-Language` (com `q=weight`), e seta header `x-locale` no request. Pages
leem via `headers()` async (Next 15 RSC) e resolvem pra `PageLang` interno via
`resolveLang(locale)`.

```ts
// middleware.ts
const accept = req.headers.get("accept-language") ?? "";
const locale = pickBestLocale(accept, SUPPORTED);  // q-weighted
req.headers.set("x-locale", locale);
```

Country-scoped (`/br/*`) **intacto**: prefix vence Accept-Language.
`<html lang>` reflete o locale resolvido. Header `Vary: Accept-Language` emitido
(débito conhecido: Next App Router sobrescreve em alguns paths — ver
"Consequences negativas").

**Prós:** 1 URL por página; 19 idiomas servidos; primeira visita resolve direito.
**Contras:** cache CDN precisa segmentar por `Accept-Language` (alta cardinalidade).

### Option B — URLs `/{lang}/pricing` etc.

**Prós:** cacheável trivialmente; explícito.
**Contras:** sitemap × 19; canonical/hreflang complexo; refactor enorme; quebra
links externos existentes.

### Option C — Cookie de lang

**Prós:** simples client-side.
**Contras:** **não funciona pra primeiro visitante** (não há cookie ainda) — cai
em EN no primeiro paint, FOUC de idioma; bots não enviam cookie.

### Option D — Geo-IP no Caddy

**Prós:** preciso para país.
**Contras:** viola privacidade (LGPD/GDPR exige base legal); **mistura "país"
com "idioma falado"** (alemão na Suíça, japonês no Brasil); custo de manter
GeoIP DB.

### Option E — `?lang=pt` query param

**Prós:** stateless.
**Contras:** SEO ruim (canonical ambíguo); polui analytics; pessoa que compartilha
URL nua perde idioma.

## Decision Outcome

**Aceito Option A.** Implementação:

1. **`src/middleware.ts`**:
   - Detecta se path começa com country prefix conhecido (`/br/`, `/us/`, ...).
   - Se **sim**, locale = mapa de país → idioma padrão; ignora `Accept-Language`.
   - Se **não**, parse de `Accept-Language` q-weighted, escolhe melhor match em
     `SUPPORTED_LOCALES`; fallback `en`.
   - Seta `x-locale` no request header; emite `Vary: Accept-Language` no response.

2. **Pages (RSC)**:
   ```ts
   const lang = resolveLang((await headers()).get("x-locale") ?? "en");
   const pack = await loadPack(route, lang);
   ```

3. **`<html lang>`** reflete o locale resolvido em `layout.tsx`.

4. **SEO**: `alternates.languages` em metadata aponta canonical pra **mesma URL**
   em todos os 19 idiomas (Google interpreta como variação por content-negotiation).

## Triggers para Reabrir

- Cache hit rate cair abaixo de aceitável por causa do `Vary: Accept-Language`
  → considerar split URL pra top 3 idiomas.
- Google passar a punir content-negotiation sem URL distinta.
- LGPD/GDPR exigir consentimento pra leitura de `Accept-Language` (improvável,
  é header de protocolo).

## Consequences

### Positivas

- `/pricing` serve 19 idiomas com 1 URL — sitemap limpo.
- Country-scoped (`/br/*`) preservado — prefix vence sempre.
- Primeira visita pt-BR vê PT direto, sem flicker de idioma.
- Bots com `Accept-Language: en` recebem EN canonical.
- Rotas continuam `ƒ` (server-rendered) — sem ISR, sem cache stale.

### Negativas

- **Cache CDN segmenta por `Accept-Language`** — cardinalidade alta; hit rate
  cai. Hoje aceitável (volume baixo), pode virar problema em escala.
- **Débito conhecido:** Next App Router às vezes **sobrescreve `Vary`** em
  responses de erro/redirect; cache pode entregar idioma errado em edge cases.
  Rastreado.
- SEO via `hreflang` apontando pra mesma URL é menos explícito que
  `/pt/pricing` — funciona, mas exige confiança no signal Google.
- Debug fica mais difícil (precisa setar Accept-Language pra repro).

## Links

- BUG-50, BUG-75, BUG-89, BUG-104 (Round 13).
- `apps/web/src/middleware.ts` — parser q-weighted.
- `apps/web/src/lib/i18n/resolveLang.ts` — locale → PageLang.
- ADR-0013 (RTL via logical properties) — relacionada (idiomas RTL chegam
  por essa mesma rota).
- RFC 9110 §12.5.4 (Accept-Language).
