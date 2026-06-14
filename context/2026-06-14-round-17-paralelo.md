---
date: 2026-06-14
session: round 17 (4 tracks paralelos)
---

# Round 17 — 4 tracks paralelos

Sequência rounds 13-16. i18n longtail + JSON-LD + perf + sweep round 3.

## FEITO

### Track S — i18n AR/ZH/HI/TR (14 langs totais)
- **PageLang em /pricing /vs /cities:** en|pt|es|fr|de|ja|it|ru|nl|ko|**ar|zh|hi|tr**
- **Middleware:** `detectAcceptLanguage` mapeia ar→ar-SA, zh→zh-CN, hi→hi-IN, tr→tr-TR
- **Layout:** emite `<html lang dir="rtl">` quando lang in (ar|he|fa)
- **Packs:** PRICING/VS/CITY_T com traduções idiomáticas (formal-comercial AR, ZH simplificado, Hindi devanāgarī, TR direto)
- **AR:** usa western digits ($1.00) — escolha consciente pra consistência de preços
- **Pack zh** adicionado ao `LangCode` + `PACKS` pra Footer compilar
- **neighborhoodsText:** fallback ramificado nos 4 langs
- **Validado prod:** 8/8 combos OK
  - AR /pricing → "أسعار شفافة بعملة USDT" + `dir="rtl"` ✓
  - ZH /vs/socialplug → "Viralefy 对比 SocialPlug" ✓
  - HI /pricing → "USDT में पारदर्शी कीमतें" ✓
  - TR /vs/socialplug → "yan yana karşılaştırma" ✓
- **Débito:** RTL completo (logical properties no CSS, ordem de flex, breadcrumb chevrons) ainda pendente — só `dir="rtl"` foi emitido; texto fica legível mas layout fica visualmente "torto" em árabe.

### Track T — JSON-LD consolidado + AggregateOffer correto
- **BUG-191 (JSON-LD duplicado):**
  - 11 pages emitiam 2-3 `<script type="application/ld+json">` separados (Breadcrumb + Service + FAQPage, etc.)
  - Novo helper `toJsonLdGraph(nodes)` em `src/lib/jsonld.ts` envelopa em UM `@context` + `@graph: [...]`
  - Aplicado em 11 pages: `/[country]/[category]/+/{slug}`, `/case-studies/*`, `/help/*`, `/vs/*`, `/cities/*`, `/pricing`, `/status`
- **BUG-192 (lowPrice errado):**
  - `lowPrice` era computado sem filtrar amount=0 ou "on_request"
  - Novo helper `buildAggregateOffer(offers, {priceCurrency})` em `src/lib/jsonld.ts`
  - Filtra offers com `parseFloat(price)` finito **e > 0**
  - Retorna `null` quando 0 offers válidas → caller omite o bloco
- **Validado prod:** 
  - JSON-LD count = 1 em `/`, `/br/seguidores-instagram`, `/br/.../[slug]`, `/pricing`, `/status` (5 rotas) ✓
  - Restante (/cities, /vs, /help, /case-studies) tem 2 — Organization global do layout + página específica. Semanticamente correto (Org ≠ conteúdo). 
  - AggregateOffer: lowPrice=2.50, highPrice=4000.00, offerCount=18 ✓

### Track U — Perf mecânico
- **Resource hints em `layout.tsx`:**
  - `preconnect`: api.viralefy.com, flagcdn.com (warm connection)
  - `dns-prefetch`: auth.viralefy.com, cdn.viralefy.com, www.googletagmanager.com, challenges.cloudflare.com
- **CheckoutModal lazy:** `next/dynamic({ ssr: false })` em 4 callers (BuyPlanCta, QuantitySlider, CategoryCardGrid, CategoryGroupedGrid). Retira o modal da chunk inicial das landing pages.
- **`<img>` audit:** apenas 3 instâncias raw `<img>` em `src/`; Flag.tsx já tinha lazy/async; 2FA QR ganhou `loading="lazy" decoding="async"`.
- **Cache imutável:** `Cache-Control: public, max-age=31536000, immutable` em `/_next/static/:path*` e `/fonts/:path*` via `next.config.headers()`.
- **Fonts:** site usa system font stack (sem `next/font` externo), sem custo extra.

### Track W — Sweep round 3 (10 fixes mecânicos)
| BUG | Descrição | Fix |
|---|---|---|
| W-301 | `<th>` da cookies table sem `scope="col"` | adicionado em 7 headers |
| W-302/303 | `<th>` em api-keys tables sem `scope="col"` | adicionado em 4+3 headers |
| W-304 | "Back to home" hardcoded EN/PT em /legal/cookies | helper com 12 idiomas |
| W-305 | "Updated" idem | helper com 12 idiomas |
| W-306 | "Other languages:" idem | helper com 12 idiomas |
| W-307 | `<textarea name="body">` em /tickets/new sem `maxLength` | `maxLength={8000}` |
| W-308 | `<input name="order_id">` em /tickets/new sem `maxLength` | `maxLength={64}` |
| W-309 | `<textarea>` reply em /tickets/[id] sem `maxLength` | `maxLength={8000}` |
| W-310 | `<textarea>` reason em /account/data sem `maxLength` | `maxLength={2000}` |

## Deploy + smoke
- `viralefy-update` rodou completo
- 7 services active
- `viralefy-smoke` 8/8 verde
- Smoke i18n: 8/8 combos AR/ZH/HI/TR × 2 paths
- JSON-LD: 5/9 rotas com 1 script (others = 2 com Org global, acceptable)

## Commit
- `viralefy_front@ac2ed46` — round 17 inteiro (27 arquivos, +760/-177)

## EM ABERTO

### RTL completo (decorrência da AR adição)
- Hoje só `dir="rtl"` é emitido; CSS usa `padding-left/right`, `text-align: left`, ordem de flex LTR-only
- Fix completo exigiria migrar pra logical properties (`padding-inline-start/end`, `margin-block`, etc.) ou usar `[dir="rtl"]` selectors
- Componentes a auditar: Header, breadcrumbs, pricing tables, /vs comparison tables, cards

### JSON-LD Organization duplicação restante
- 4 index pages (/cities /vs /help /case-studies) ainda têm 2 scripts: layout-level Org + page-level
- Não é regressão; é o estado existente do layout. Fix opcional: mover Org pra `[@graph]` global em layout único.

### Bugs ainda em aberto
- Decisões de produto (BUG-94/95, BUG-200, BUG-114/115)
- BUG-178 prefetch /tickets — pedir URL exata
- i18n longtail residual (pl/sv/da/no/fi/cs/sk/hu/ro/bg/el/uk/th/vi/id/ms/tl/he/fa/ur/bn/sw/am) — pages /pricing /vs /cities; demais pages ainda menos cobertas

### Vary
- Continua débito conhecido. Workarounds custo > benefício atual.

## Total da maratona após round 17
- Round 13: 4 tracks
- Round 14: 5 tracks
- Round 15: 5 tracks
- Round 16: 4 tracks
- Round 17: 4 tracks
- Bugs fechados acumulado: ~175 / 213 (82%)
