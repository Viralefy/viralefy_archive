---
date: 2026-06-14
session: round 16 (4 tracks paralelos)
---

# Round 16 — 4 tracks paralelos

Sequência rounds 13/14/15. Refactors médios + sweep round 2.

## FEITO

### Track O — BUG-13 navbar duplicada no scroll
- **Causa raiz:** NÃO é duplicação estrutural (`grep -c "<header"` = 1 em todas as rotas). É `flex-wrap: wrap` em `.site-header__row` e `.site-header__nav`. Em viewports 900-1100px o nav crescia após o `mounted` gate (BUG-105/109) — de 1 placeholder (SupportButton) pra 5 elementos (ThemeToggle + CurrencyPicker + Support + Login + Register) — e quebrava pra segunda linha visual abaixo do logo.
- **Fix:** `flex-wrap: nowrap` + `min-width: 0` em `.site-header__row`, `flex-wrap: nowrap` + `flex-shrink: 0` em `.site-header__nav`. Mobile (<760px) segue com hamburger via `display:none`.
- **Arquivo:** `src/app/globals.css`
- **Validado prod:** 5 rotas testadas, `<header>` count = 1 em todas (/, /br, /pricing, /cities/london, /vs/socialplug).

### Track P — BUG-29 highlight de campo no checkout
- **Arquivo:** `src/components/CheckoutModal.tsx`, `src/i18n/languages.ts`, `src/app/globals.css`
- **Mudança:**
  - `fieldErrors: Record<string, string>` state + `fieldRefs` map
  - `<form noValidate>` + validação controlada explícita (HANDLE_RE, EMAIL_RE, URL parser)
  - `aria-invalid` + `aria-describedby` + `<p role="alert">` por campo errado
  - Foco automático no primeiro campo com erro pós-submit
  - `clearFieldError(field)` no onChange limpa erro do campo
  - i18n `checkout.fieldError` em EN/PT/ES (required, nameInvalid, emailInvalid, handleInvalid, publicationUrlInvalid, formSummary)
  - CSS `.input-invalid` + `.field-error` theme-aware via `--danger`
  - `ProfileSection` e `PublicationSection` estendidos com props field-level

### Track Q — BUG-79/111 theme + currency persist
- **Arquivos novos/editados:**
  - `src/lib/theme.ts` (refactor cookie-first)
  - `src/lib/currency.ts` (NOVO — análogo)
  - `src/components/ThemeToggle.tsx`
  - `src/components/Providers.tsx`
  - `src/app/layout.tsx` (SSR cookie read)
  - `src/app/legal/cookies/page.tsx` (docs)
- **Estratégia:**
  - Cookies `vf_theme=dark|light|system` e `vf_currency=USD|USDT|...`
  - Path=/; Max-Age=31536000; SameSite=Lax; Domain=.viralefy.com (cross-subdomain via helper espelhado de `gdpr.ts`)
  - Precedência (CSR): cookie → localStorage → default
  - Precedência (SSR): `cookies()` em `layout.tsx` injeta `data-theme={effective}` + `data-theme-pref={pref}` no `<html>`, e passa `initialCurrency` pro `<Providers>` → sem FOUC, sem salto USD→USDT
  - Default theme = `system` (respeita `prefers-color-scheme` + `matchMedia change`)
  - Default currency derivado por `/api/geo` (CF + Accept-Language) só se NÃO houver cookie
  - Evento `vf-currency-changed` sincroniza componentes em outras abas
- **Validado prod:**
  - `vf_theme=dark` → `<html data-theme="dark" data-theme-pref="dark">`
  - `vf_theme=light` → `<html data-theme="light" data-theme-pref="light">`
  - `vf_theme=system` → `<html data-theme="dark" data-theme-pref="system">` (server defaulta dark; CSR ajusta se necessário)

### Track R — Sweep round 2 (7 bugs mecânicos)
| BUG | Descrição | Fix |
|---|---|---|
| 204 | `/jp` e `/kr` mostravam "Premium services" em EN | 9 idiomas faltantes (ja/ko/ar/hi/id/vi/th/tr/uk) no `CATEGORY_LABEL.servicos` |
| 184 (HU typo) | "szolgáltatações" — cedilha PT-BR vazada | → "szolgáltatások" |
| 151 | PT "Comprar views" / "views" | → "Comprar visualizações" / "visualizações" |
| 170 | Help payment-methods não nomeava Heleket/Stripe/Abacate Pay | Headings explicitam providers |
| 190 (residual) | Help 2 artigos ainda diziam "magic-link" | Reescrito: dashboard `viralefy.com/account` com email+senha, reset via ticket |
| 184 (British) | "catalogue"/"tokenisation"/"finalises" residual round 9 | → American |
| 179 | FAQ Instagram-only mencionava TikTok e vice-versa | `CopyOverride` com novo campo `faq` em `SEGUIDORES_INSTAGRAM/TIKTOK_OVERRIDES` |

**Arquivos:** `src/i18n/categories.ts`, `src/lib/help.ts`, `src/lib/case-studies.ts`.

## Deploy + smoke
- `viralefy-update` rodou completo (fix do round 14 persiste)
- 7 services active
- `viralefy-smoke` 8/8 verde
- BUG-13: header count = 1 em 5 rotas ✓
- BUG-79: theme cookie SSR 3/3 variantes ✓

## Commit
- `viralefy_front@bf7a77f` — round 16 inteiro (12 arquivos, +684/-95)

## EM ABERTO

### Sweep limpou — sobraram principalmente decisões de produto
- BUG-94/95 likes TikTok preço alto
- BUG-200 geo-redirect raiz
- BUG-114/115 CN/JP script nativo
- BUG-191/192 JSON-LD dup / lowPrice — exige investigação runtime
- BUG-161/162/182/185 perf — refactor

### Pendentes Q&A
- BUG-178 prefetch /tickets — precisa URL exata
- BUG-22 `/legal/about?lang=pt` — verificado OK, marcar como resolvido

### Débitos de infraestrutura
- Vary: Accept-Language stripped pelo Next App Router (round 15 nota)
- i18n longtail (ar/zh/hi/tr/pl/sv/...) — template pronto
- ar/he/fa exigem RTL no `<html dir>` — infra não tem
- Caddy emite `vary: rsc, next-router-*, Accept-Encoding` mas não preserva Accept-Language do upstream Next (que também não emite)

### Possíveis próximos rounds
- Round 17: i18n longtail expansion (ar/zh/hi/tr/pl)
- Round 18: BUG-191/192 JSON-LD investigation + cleanup
- Round 19: perf (BUG-161/162/182/185)
- Round 20: RTL para ar/he/fa (custo: estética + componentes)

## Total da maratona após round 16
- Round 13: 4 tracks (16 commits acumulado)
- Round 14: 5 tracks
- Round 15: 5 tracks (+ 10 CLAUDE.md commits, hooks ativados)
- Round 16: 4 tracks
- Bugs fechados acumulado: ~157 / 213 (74%)
