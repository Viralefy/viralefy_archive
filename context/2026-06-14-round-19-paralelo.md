---
date: 2026-06-14
session: round 19 (4 tracks paralelos)
---

# Round 19 — 4 tracks paralelos

Sequência rounds 13-18. i18n nórdico + JSON-LD Org expansion + sweep round 4 + +73 tests.

## FEITO

### Track BB — i18n DA/NO/FI (19 langs totais)
- **PageLang em /pricing /vs /cities:** 16 → 19 langs (adicionado da|no|fi)
- **Middleware:** `detectAcceptLanguage` mapeia da→da-DK, nb/no→nb-NO, fi→fi-FI
- **Packs:** PRICING/VS/CITY_T completos
- **neighborhoodsText:** DA `"<city> centrum"`, NO `"<city> sentrum"`, FI `"<city>n keskusta"` (genitivo). Conector: DA/NO `" og "`, FI `" ja "`.
- **localeFmtByLang** populado pra Intl.NumberFormat
- **Validado prod:** 9/9 combos OK
  - DA /pricing → "Gennemsigtige priser i USDT" ✓
  - NO /vs/socialplug → "side ved side-sammenligning" ✓
  - FI /cities/london → "Osta Instagram-seuraajia kaupungissa London" ✓

### Track CC — JSON-LD Org+WebSite em 7 pages adicionais
- **Aplicado `withGlobalGraph` em:**
  - /status
  - /[country]/[category] (com `Service.provider` agora referenciando `#organization` por @id, era inline anônimo)
  - /[country]/[category]/[slug]
  - /help/[slug] (Article.author/publisher → @id)
  - /case-studies/[slug] (Article.author/publisher → @id)
  - /legal/cookies
  - /legal/cookie-preferences
- **Total:** 11 pages agora têm Org+WebSite canônicos no @graph (era 4 pós-Track Y round 18)
- **Validado prod:** 13/13 rotas reais com JSON-LD count = 1 ✓ (incluindo /help/how-to-buy, /case-studies/small-business-instagram-growth, /br/seguidores-instagram, etc.)

### Track DD — Sweep round 4 (9 bugs mecânicos)
Forms em /account + /tickets — áreas pouco varridas até aqui.

| BUG | Descrição | Fix |
|---|---|---|
| DD-401 | `Setup2FAPrompt` aria-modal sem valor + sem aria-labelledby | `aria-modal="true"` + `id` no heading + `aria-labelledby` no dialog |
| DD-402 | `account/profiles` handle input sem maxLength/pattern | `maxLength={30}` + `pattern="[A-Za-z0-9._]{1,30}"` |
| DD-403 | `account/profiles` display_name input sem maxLength | `maxLength={60}` |
| DD-404 | `account/notifications` WhatsApp input sem id/pattern | `autoComplete="tel"`, `maxLength={20}`, `pattern="\+?[\d\s().-]{8,20}"` |
| DD-405 | `tickets/new` sem minLength (anti-spam) | `minLength={4}` subject, `minLength={10}` body |
| DD-406 | `tickets/[id]` reply textarea sem minLength | `minLength={2}` |
| DD-407 | `account/credits` ledger `<th>` sem `scope="col"` | adicionado em 5 headers |
| DD-408 | `account/credits` CustomAmount sem aria-label | `aria-label="Custom top-up amount in USD"` |
| DD-409 | `account/api-keys` create-key modal label/input mismatch | htmlFor/id pairing + name + minLength |

### Track EE — +73 unit tests novos
- **`tests/unit/round-18-helpers.test.mjs`** (41 testes):
  - `buildOrganizationNode` (3), `buildWebSiteNode` (5), `withGlobalGraph` (5)
  - `localizedPlanName` (10), `localizedPlanDescription` (8)
  - `cookieDomain` (9) — localhost/.local/apex/subdomain/.com.br
- **`tests/unit/checkout-validation.test.mjs`** (32 testes):
  - `HANDLE_RE` (12), `EMAIL_RE` (10), `validatePublicationUrl` (11)
- **Export adicionado:** `cookieDomain()` em `src/lib/gdpr.ts` (era helper interno)
- **Baseline:** 414/427 → 487/500 + 73 novos. Zero regressão.

## Deploy + smoke
- `viralefy-update` rodou completo
- 7 services active
- `viralefy-smoke` **13/13 verde** (continua expandido pós round 18)

## Commits da sessão
- `viralefy_front@31c8dac` — round 19 inteiro (21 arquivos, +904/-115)

## EM ABERTO

### Vary stripped, decisões de produto — sem mudança vs round 18.

### i18n longtail residual (diminishing returns)
- Restam: he/fa/ur (RTL semitas), cs/sk/hu/ro/bg/el/uk (CEE), th/vi/id/ms/tl/bn/sw/am (Ásia + África)
- Cada custo ~200 LOC. Decisão: parar até demand real de mercado.

### tr() global packs
- DA/NO/FI/PL/SV agora caem em EN no `tr()` global (Footer, etc.) — só os 3 pages têm pack completo. Adicionar pack global é refactor maior; deixar como débito.

## Total acumulado após round 19
- Rounds 13-19: ~26 tracks paralelos
- Commits front: ~10 grandes + 19 commits CLAUDE.md em todos repos
- Bugs fechados: ~196 / 213 (92%)
- i18n: 1 lang → 19 langs em pages-chave
- Smoke: 8 → 13 asserts (+62%)
- Unit tests: 405 → 500 (+95 novos)
- JSON-LD: 1 → 13 pages com Org+WebSite canônicos no @graph
- viralefy-update: débito antigo de migrations resolvido (round 14)
