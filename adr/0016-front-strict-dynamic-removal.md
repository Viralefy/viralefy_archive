# ADR-0016 — CSP estática (`'unsafe-inline'`) e remoção do `'strict-dynamic'` no front — trade-off do ISR

- **Status:** accepted
- **Data:** 2026-07-24
- **Decisores:** Equipe Viralefy
- **Diretriz relacionada:** §1 (segredo/segurança), §21 (performance)
- **Relacionada:** [ADR-0015](0015-front-locale-segment-isr.md), supersede parcialmente [track-oo-round-22-csp-nonce-backoffice](../track-oo-round-22-csp-nonce-backoffice-2026-06-15.md) (nonce+strict-dynamic no front)
- **Reavaliação:** 2027-01

## Contexto

Para destravar o ISR ([ADR-0015]) o front não pode mais usar **nonce per-request** na
CSP: o nonce é um valor por-request lido no render (`headers()`), e qualquer `headers()`
no root layout torna a árvore inteira **dinâmica**. **Nonce e ISR são mutuamente
exclusivos**, e o ISR é o objetivo (tráfego orgânico/pago).

Testado na prática: o App Router do Next 15 **emite scripts INLINE por página**
(`<script>self.__next_f.push(...)` — streaming do RSC + hidratação). O conteúdo varia
por página, então **hash estático (`'sha256-'`) NÃO os cobre**, e sem nonce (que
forçaria dinâmico) **a única forma de não bloqueá-los é `'unsafe-inline'`**. Verificado
via Lighthouse CI: com hash-sem-unsafe-inline, todos os `__next_f` eram bloqueados →
console errors + página quebrada + todas as categorias do Lighthouse nulas.

`'strict-dynamic'` também é **incompatível** com scripts parser-inserted sem nonce
(bloquearia o bundle `<script src="/_next/…">`). Logo **sai**.

## Decisão

CSP **estática** (`CSP_STATIC` no middleware, sem valor per-request):

- `script-src 'self' 'unsafe-inline' <hosts>` — `'unsafe-inline'` é o **custo
  inevitável** de servir estático/ISR no App Router (cobre os `__next_f` inline e o
  bootstrap de tema/moeda). **Reintroduz o `'unsafe-inline'` que a round 25 removeu.**
- **Sem `'strict-dynamic'`** e **sem nonce** (ambos incompatíveis com ISR).
- **Mantém a allowlist de host** (`'self'` + gtm/jsdelivr/cloudflare): script EXTERNO
  de host arbitrário continua bloqueado (não é wildcard).
- JSON-LD é `type="application/ld+json"` (dado, não executável) → fora de `script-src`.
- GTM: loader inline trocado por `gtm.js` **externo** (googletagmanager, allowlist).
- `style-src` mantém `'unsafe-inline'` (inalterado desde antes).

## Consequência de segurança (assumida)

**Downgrade real:** `script-src` volta a ter `'unsafe-inline'`, então XSS inline
injetado (ex.: em conteúdo de ticket/review) não é mais barrado pela CSP. É o preço do
ISR no App Router — nonce (a alternativa forte) obrigaria render dinâmico e negaria o
objetivo do trabalho.

**Compensações que se mantêm:** `default-src 'self'`, `object-src 'none'`,
`frame-ancestors 'none'`, `base-uri 'self'`, `form-action 'self'`; allowlist de host em
script/img/connect; React escapa por padrão; JSON-LD via `safeJsonStringify`; sem
`dangerouslySetInnerHTML` com dado de usuário. Sem `'strict-dynamic'`, pixels de
terceiros injetados pelo GTM (Meta/TikTok/Ads) **não herdam confiança** — cada host
precisa entrar na allowlist antes de prod.

**Reversível:** trocar `'unsafe-inline'` por nonce+`'strict-dynamic'` recupera a CSP
forte, ao custo de tornar as landing pages dinâmicas (perde ISR). É a decisão
ISR-vs-CSP-forte; escolhemos ISR (objetivo declarado: tráfego orgânico/pago).

## Checklist de cutover prod

- [ ] Se o GTM injeta Meta/TikTok/Google Ads: adicionar os hosts ao `script-src`
      (`connect.facebook.net`, `analytics.tiktok.com`, `googleadservices.com`, …) e
      aos `img-src`/`connect-src` correspondentes.
- [ ] Validar no navegador (console CSP violations = 0) com consent aceito.

## Alternativa considerada

- **Manter nonce+strict-dynamic:** obrigaria render dinâmico (nega o ISR). Rejeitado —
  o ISR do tráfego orgânico/pago é o objetivo declarado.
