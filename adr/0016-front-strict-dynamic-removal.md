# ADR-0016 — CSP estática (hash) e remoção do `'strict-dynamic'` no front

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

Sem nonce, a única forma de autorizar o inline mantendo `script-src` **sem
`'unsafe-inline'`** é **hash** (`'sha256-…'`). Mas `'strict-dynamic'` é **incompatível**
com scripts *parser-inserted* sem nonce: sob strict-dynamic o browser ignora `'self'`
e host-allowlist e bloquearia o bundle `<script src="/_next/…">` do Next (que não
carrega nonce quando não há `x-nonce`). Logo `'strict-dynamic'` **sai**.

## Decisão

CSP **estática** (`CSP_STATIC` no middleware, sem valor per-request):

- `script-src 'self' 'sha256-<BOOTSTRAP>' <hosts>` — o **único** inline executável
  (`BOOTSTRAP_JS`, tema+moeda) é autorizado por hash; o bundle do Next por `'self'`.
- **Sem `'strict-dynamic'`**, **sem nonce**, **sem `'unsafe-inline'` em script-src.**
- JSON-LD é `type="application/ld+json"` (dado, **não executável**) → fora de
  `script-src`, perde o nonce sem violar CSP.
- GTM: o loader inline foi trocado por carregamento **externo** de `gtm.js`
  (googletagmanager, já na allowlist) — sem inline.
- `style-src` mantém `'unsafe-inline'` (Next 15 injeta styles inline sem nonce — débito
  pré-existente, inalterado).
- O hash `BOOTSTRAP_SHA256` é travado por teste (`security.test.mjs` recomputa e falha
  em deriva).

## Consequência de segurança (a avaliar antes de prod)

Sem `'strict-dynamic'`, a confiança volta a ser por **allowlist de host**. Tags que o
GTM injeta de **terceiros** (Meta Pixel, TikTok Pixel, Google Ads) **não herdam mais
confiança automática** — cada host precisa ser adicionado ao `script-src` (e
`img-src`/`connect-src`) **antes de habilitar esses pixels em prod**. Hoje (HML/POC,
DSN vazio) o GTM carrega só `gtm.js` + GA, ambos já na allowlist → nada quebra.

`script-src` continua **sem `'unsafe-inline'`** — a proteção anti-XSS inline se mantém.
A allowlist explícita é, inclusive, mais auditável que a herança cega do strict-dynamic.

## Checklist de cutover prod

- [ ] Se o GTM injeta Meta/TikTok/Google Ads: adicionar os hosts ao `script-src`
      (`connect.facebook.net`, `analytics.tiktok.com`, `googleadservices.com`, …) e
      aos `img-src`/`connect-src` correspondentes.
- [ ] Validar no navegador (console CSP violations = 0) com consent aceito.

## Alternativa considerada

- **Manter nonce+strict-dynamic:** obrigaria render dinâmico (nega o ISR). Rejeitado —
  o ISR do tráfego orgânico/pago é o objetivo declarado.
