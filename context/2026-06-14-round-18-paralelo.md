---
date: 2026-06-14
session: round 18 (4 tracks paralelos + fix smoke)
---

# Round 18 — 4 tracks paralelos + bugfix do smoke

Sequência rounds 13-17. RTL completo + JSON-LD Org dedup + i18n PL/SV + tests.

## FEITO

### Track X — RTL completo via logical properties
- **Refactor globals.css** + 14 componentes/pages com inline styles:
  - `padding/margin/border *-left/right` → `*-inline-start/end`
  - `text-align: left/right` → `start/end`
  - `left/right` (position) → `inset-inline-start/end`
- **Chevron/arrow flip em RTL:**
  ```css
  [dir="rtl"] ol > li[aria-hidden] { transform: scaleX(-1); }
  [dir="rtl"] svg[data-icon="arrowRight"|"chevronRight"|...] { transform: scaleX(-1); }
  ```
  Pega breadcrumbs `›` automaticamente (estrutura `<ol><li aria-hidden>›</li>...`).
- **Edge cases LTR-forced:** `.force-ltr`, `code`, `kbd`, `pre`, `.site-header__logo`. Números tabulares, IDs, chaves de API e logos têm direcionalidade técnica fixa.
- **Validado prod:** AR /pricing → `dir="rtl"` + breadcrumb invertido ✓ (chevron flip via CSS)

### Track Y — JSON-LD Organization no @graph das index pages
- **Diagnóstico inicial errado** (compartilhado com smoke): o "2" do grep era artefato do RSC payload do Next, que serializa `"type":"application/ld+json"` na hidratação. Cada page já tinha 1 script real.
- **Problema real identificado:** as 4 index pages (/cities /vs /help /case-studies) tinham `@graph` SEM Organization+WebSite, e `isPartOf` referenciava `/#website` inexistente (gráfico órfão).
- **Fix:** novos helpers em `src/lib/jsonld.ts`:
  - `buildOrganizationNode(siteUrl)`, `buildWebSiteNode(siteUrl, {inLanguage})` com @id canônico
  - `withGlobalGraph(pageNodes, {siteUrl, inLanguage})` prepende Org+WebSite ao @graph
- **Aplicado em:** /cities, /vs, /help, /case-studies (índices)
- **Validado prod (com grep correto):** 6/6 rotas testadas com 1 script JSON-LD ✓

### Track Z — i18n PL + SV (16 langs totais)
- **PageLang em /pricing /vs /cities:** 14 → 16 langs (adicionado pl|sv)
- **Middleware:** detectAcceptLanguage com `pl→pl-PL`, `sv→sv-SE`
- **Packs:** PRICING/VS/CITY_T completos PL/SV
- **neighborhoodsText:** PL `"centrum <city>"`, SV `"centrala <city>"`. Conector: PL `" i "`, SV `" och "`.
- **Validado prod:** 6/6 combos OK
  - PL /pricing → "Przejrzyste ceny w USDT" ✓
  - SV /vs/socialplug → "sida vid sida-jämförelse" ✓
  - PL /cities/london → "Kup obserwujących na Instagramie w London" ✓

### Track AA — Testes pros fixes 13-17
- **Smoke prod expandido** (`viralefy_ops/bin/viralefy-smoke`):
  - +6 asserts cobrindo i18n PT, i18n RTL AR, JSON-LD count, header count, cookie SSR vf_theme, self-check (gated)
  - Fail-soft via `VIRALEFY_FRONT_HOST` (skip se rollout)
  - Self-check (skill §22.8): força FAIL conhecido via `VIRALEFY_SMOKE_SELFCHECK=1` pra provar reporter funciona
- **Unit tests novo** (`viralefy_front/tests/unit/round-13-17-fixes.test.mjs`):
  - 22 tests, 4 helpers: `toJsonLdGraph`, `buildAggregateOffer`, `formatQty`, `detectAcceptLanguage`
  - Baseline: 414/427 → 414/427 + 22 novos. Zero regressão.

### Bugfix do smoke (descoberto na validação)
- O grep `'application/ld\+json'` casava também a string em RSC payload, gerando count = 2 quando há 1 tag real.
- **Fix:** anchora em `'<script[^>]+type="application/ld\+json"'`.
- **Bug paralelo:** `viralefy-smoke` apontava pra `/usr/local/sbin/viralefy-smoke` (não `/bin/`). SCP feito pros dois paths.
- Mesmo bug diagnosticado por Track Y. Self-validated.

## Deploy + smoke
- `viralefy-update` rodou completo (debt de migrations resolvido desde round 14)
- 7 services active
- `viralefy-smoke` **13/13 verdes** (era 8 antes do round 18)
- Validações ad-hoc: 6/6 rotas com 1 JSON-LD, 6/6 com 1 `<header>`, 6/6 i18n PL/SV correto

## Commits da sessão
- `viralefy_front@974e884` — round 18 (28 arquivos, +849/-186)
- `viralefy_ops@ed9b892` — smoke expandido
- `viralefy_ops@27fc70a` — fix grep JSON-LD (false positive RSC payload)

## EM ABERTO

### Vary continua débito (Next App Router strip)
### Decisões de produto (BUG-94/95, BUG-200, BUG-114/115)
### BUG-178 prefetch /tickets (precisa URL do QA)
### i18n longtail diminishing returns
- Restam: da/no/fi/cs/sk/hu/ro/bg/el/uk/th/vi/id/ms/tl/he/fa/ur/bn/sw/am
- Cada lang custa ~200 linhas de tradução. Template pronto.
### RTL parcial — texto/layout OK em árabe; debug visual ainda pode ter casos não cobertos
- Auditar com browser real em viewport árabe se houver demand de mercado MENA

## Total da maratona após round 18
- Rounds 13-18: 22 tracks paralelos, ~30 commits front + 6 commits ops + 10 commits CLAUDE.md
- Bugs fechados acumulado: ~187 / 213 (88%)
- Smoke: 8 → 13 asserts (+62%)
- Unit tests: +22 novos (cobertura helpers críticos JSON-LD, formatQty, Accept-Language)
- Cobertura i18n /pricing /vs /cities: 1 → 16 idiomas + RTL infra
