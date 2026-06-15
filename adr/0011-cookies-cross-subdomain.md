# ADR-0011 — Cookies cross-subdomain para persistência de theme/currency

- **Status:** accepted
- **Data:** 2026-06-15
- **Decisores:** Equipe Viralefy (Track II, Round 16 QA)
- **Diretriz relacionada:** §15 (UX consistente cross-domínio), §22 (FOUC vetado em hidratação SSR)
- **Reavaliação:** 2026-12

## Contexto e Problem Statement

Durante o Round 16 de Q.A. (BUG-79, BUG-111) ficou claro que `localStorage` é
*scoped por origin* e não compartilha estado entre os subdomínios da plataforma:

- `www.viralefy.com` (marketing/checkout)
- `auth.viralefy.com` (login/cadastro)
- `api.viralefy.com` (BFF / OpenAPI)

Fluxo quebrado observado:

1. Usuário escolhia **USD** como moeda em `www.viralefy.com`.
2. Era redirecionado para `auth.viralefy.com` para login.
3. Ao voltar pra `www`, a moeda voltava ao default (**USDT**) porque o `localStorage`
   de `auth.*` é outro silo.

Sintoma adicional: **FOUC** no tema (flash de tema claro antes do JS hidratar o
escuro) porque a leitura de preferência só acontecia client-side.

## Decision Drivers

- Preferência de UI (`theme`, `currency`) precisa ser **estável entre subdomínios**.
- SSR (Next 15) precisa **decidir o tema antes** da resposta HTML — eliminar FOUC.
- Safari ITP rompe `postMessage` cross-subdomain de forma silenciosa.
- Não queremos depender de chamada a `api.viralefy.com` só pra hidratar preferência.

## Considered Options

### Option A — Cookies `Domain=.viralefy.com` lidos no SSR

`Set-Cookie: vf_theme=dark; Domain=.viralefy.com; Path=/; SameSite=Lax; Max-Age=31536000`
e `vf_currency` idem. SSR lê via `cookies()` em `layout.tsx` e injeta
`data-theme` no `<html>` antes da hidratação.

**Prós:** Sem FOUC; sync automático entre abas e subdomínios; SSR-friendly; suporte
universal (sem flag).
**Contras:** ~30 bytes a mais por request; cookie sai com "limpar cookies" (não com
"limpar localStorage").

### Option B — `localStorage` + sync via `postMessage` entre subdomínios

**Prós:** zero overhead em request.
**Contras:** complexo (iframe oculto por subdomínio); Safari ITP marca como
third-party storage e expira em 7 dias; FOUC persiste no primeiro paint.

### Option C — `sessionStorage`

**Prós:** trivial.
**Contras:** perde no reload e em nova aba — quebra o caso de uso.

### Option D — URL param (`?theme=dark&currency=USD`)

**Prós:** stateless.
**Contras:** polui URLs, vaza pra analytics/logs, ruim pra SEO, ruim pra share.

### Option E — `BroadcastChannel`

**Prós:** API moderna pra sync de abas.
**Contras:** mesma origin only — não resolve cross-subdomain; sem suporte SSR.

## Decision Outcome

**Aceito Option A.** Adotar cookies `vf_theme` e `vf_currency` com:

```
Domain=.viralefy.com
Path=/
SameSite=Lax
Max-Age=31536000   # 1 ano
Secure             # produção
```

SSR (`apps/web/src/app/layout.tsx`) lê via `cookies()` async (Next 15 RSC) e injeta
`data-theme="<dark|light>"` no `<html>` e `data-currency="<code>"` no `<body>` antes
da resposta sair. Hidratação client lê os mesmos atributos e mantém store local
sincronizada.

`HttpOnly` **não** é setado porque o client precisa atualizar o valor quando o
usuário troca via UI; risco XSS é mitigado por CSP estrita (`script-src 'self' 'nonce-*'`)
e pelo fato de o cookie não carregar dado sensível (preferência de UI).

## Triggers para Reabrir

- Cookie law/LGPD passar a exigir consent banner mesmo para preferência de UI
  (hoje enquadrado como *strictly necessary*).
- Subdomínio novo entrar fora de `.viralefy.com` (ex.: white-label).
- Volume de cookies do request crescer ao ponto de impactar TTFB.

## Consequences

### Positivas

- Zero FOUC no tema (decisão no servidor antes do primeiro paint).
- Sync automático entre `www`, `auth` e demais subdomínios sem JS extra.
- Funciona no Safari (sem mitigations ITP necessárias).
- Multi-aba sincronizado naturalmente.

### Negativas

- ~30 bytes a mais por request HTTP.
- "Limpar localStorage" não reseta preferência — usuário precisa limpar cookies.
- Cookie aparece em logs do edge — assumir que `theme=dark` não é dado sensível.

## Links

- BUG-79 (Round 16): theme FOUC em `www`.
- BUG-111 (Round 16): currency reset ao atravessar `auth.*`.
- `apps/web/src/app/layout.tsx` — leitura SSR.
- `apps/web/src/lib/preferences.ts` — store client.
- ADR-0008 (frontend Next.js) — stack subjacente.
