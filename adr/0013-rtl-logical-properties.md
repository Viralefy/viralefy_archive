# ADR-0013 — RTL via CSS logical properties

- **Status:** accepted
- **Data:** 2026-06-15
- **Decisores:** Equipe Viralefy (Track S, Round 17)
- **Diretriz relacionada:** §15 (i18n e a11y), §22 (UI consistente)
- **Reavaliação:** 2026-12

## Contexto e Problem Statement

Round 17 (Track S) introduziu **árabe (ar)** no conjunto de idiomas suportados, com
hebraico (he) e persa (fa) planejados para Round 19+. O CSS legado era 100% LTR-only:

- `padding-left`, `padding-right`, `margin-left`, `margin-right`
- `text-align: left`
- `left: 0`, `right: auto`
- chevrons (`›`) e setas (`→`) hard-coded em JSX

Resultado: ao renderizar `ar`, layout ficava com paddings invertidos, chevrons
apontando para o lado errado, e read direction lutava contra a página.

## Decision Drivers

- 3 idiomas RTL no roadmap (ar, he, fa).
- CSS logical properties têm suporte universal desde 2022 (Chrome 87+, Firefox 66+,
  Safari 15+).
- Drift entre `[dir="ltr"]` e `[dir="rtl"]` é inevitável se cada propriedade for
  duplicada manualmente.
- Code/kbd/pre/logo têm **direcionalidade técnica fixa** (snippets de código nunca
  invertem) — precisam de override.

## Considered Options

### Option A — CSS logical properties

Substituir `padding-left` → `padding-inline-start`, `text-align: left` →
`text-align: start`, `left: 0` → `inset-inline-start: 0`, etc. Layout emite
`<html dir="rtl">` quando `lang ∈ {ar, he, fa}`.

**Prós:** uma propriedade serve LTR e RTL; mais robusto a idiomas RTL futuros;
ganho de qualidade do CSS em geral (semântica > física).
**Contras:** refactor amplo; falha silenciosa em propriedades novas que devs ainda
escrevam em forma física.

### Option B — `[dir="rtl"]` selectors duplicando propriedades

**Prós:** zero refactor inicial.
**Contras:** cada regra precisa de par; drift inevitável; dobra superfície de CSS;
revisão de PR vira caça-bug.

### Option C — Tailwind RTL plugin

**Prós:** atalho declarativo (`ps-4` etc.).
**Contras:** não usamos Tailwind no `apps/web` (CSS modules); adoção criaria
inconsistência stack-wide.

### Option D — i18n via redirect pra subdomínio (`ar.viralefy.com`) com CSS separado

**Prós:** isola RTL.
**Contras:** complica deploy/SEO/canonical; dobra superfície de teste; cookies
cross-subdomain (ADR-0011) precisam expandir; mata reuso de hreflang.

## Decision Outcome

**Aceito Option A.** Refactor de `globals.css` + componentes pra CSS logical
properties:

| Físico (antes)      | Lógico (depois)              |
|---------------------|------------------------------|
| `padding-left`      | `padding-inline-start`       |
| `padding-right`     | `padding-inline-end`         |
| `margin-left`       | `margin-inline-start`        |
| `text-align: left`  | `text-align: start`          |
| `left: 0`           | `inset-inline-start: 0`      |
| `border-left`       | `border-inline-start`        |

Layout (`apps/web/src/app/layout.tsx`) emite:

```tsx
<html lang={lang} dir={isRtl(lang) ? "rtl" : "ltr"}>
```

onde `isRtl(lang)` retorna `true` para `ar`, `he`, `fa` (extensível).

### Chevrons e setas

Glifos direcionais (`›`, `→`, `❯`) **flipam via CSS** em RTL, sem patch no JSX:

```css
[dir="rtl"] .chevron-forward { transform: scaleX(-1); }
```

### Exceções (LTR forçado em RTL)

```css
[dir="rtl"] code,
[dir="rtl"] kbd,
[dir="rtl"] pre,
[dir="rtl"] .site-header__logo {
  direction: ltr;
  text-align: left;
}
```

Justificativa: snippets de código, atalhos de teclado e o logotipo têm leitura
LTR universal — inverter os confunde.

### Lint

CI grep para detectar regressões:

```bash
grep -rE '\b(padding|margin|border)-(left|right)\b|\btext-align:\s*(left|right)\b' apps/web/src
# Esperado: zero hits em código novo (legado em allowlist temporária)
```

## Triggers para Reabrir

- Idioma vertical (CJK vertical) entrar no roadmap — logical properties não
  cobrem `writing-mode`.
- Browser baseline subir e Tailwind ser adotado → considerar plugin RTL.
- Drift detectado: bug RTL específico que logical properties não pegam.

## Consequences

### Positivas

- ar/he/fa renderizam direção visualmente correta sem CSS duplicado.
- CSS fica mais semântico em geral — robusto a idiomas RTL futuros.
- Chevron flip via CSS sem patchear JSX (separation of concerns).
- Refactor é one-shot e estabelece padrão pra novos componentes.

### Negativas

- Refactor amplo (custo único pago no Round 17).
- Dev que escrever `padding-left` em código novo passa silenciosamente — lint
  precisa pegar.
- Exceções (code/kbd/pre/logo) são `[dir="rtl"]` override clássico — pequena
  inconsistência com o resto do CSS lógico.

## Links

- Bugs i18n Round 17 (Track S).
- `apps/web/src/app/globals.css` — refactor principal.
- `apps/web/src/lib/i18n/rtl.ts` — `isRtl(lang)`.
- ADR-0014 (i18n por Accept-Language) — relacionada.
- MDN: CSS Logical Properties and Values.
