# Track OO · Round 22 · CSP nonce migration (backoffice) — 2026-06-15

## Objetivo

Eliminar `'unsafe-inline'` de `script-src` do CSP do `viralefy_backoffice`.
Round 21 (Track NN) adicionou CSP estática com débito conhecido: `script-src
'self' 'unsafe-inline' 'unsafe-eval'`. Round 22 migra para nonce por-request
via middleware do Next 15 — padrão `'self' 'nonce-...' 'strict-dynamic'`.

Padrão alvo (skill `padroes-engenharia` v5.3 §16, §38, §13.4):
- Sem `'unsafe-inline'` em script-src — anula XSS de injeção HTML mesmo com
  bypass de sanitização.
- Nonce CSPRNG único por request (crypto.randomUUID, base64).
- Defense-in-depth (RBAC + 2FA já existem; CSP é camada extra).

## Arquivos editados

### 1. `viralefy_backoffice/next.config.ts`

- Removido constante `CSP` estática e a entrada
  `{ key: "Content-Security-Policy", value: CSP }` de `headers()`.
- Mantidos os outros 6 headers de segurança (X-Frame-Options, X-Content-Type-
  Options, Referrer-Policy, Permissions-Policy, X-Robots-Tag, HSTS).
- Comentário cabeçalho atualizado explicando que CSP agora é dinâmica do
  middleware e por que duplicar quebraria o nonce (browser aplica interseção
  de headers CSP duplicados).

### 2. `viralefy_backoffice/src/middleware.ts`

- Mantida toda lógica de métricas RED (prom-client, sanitizePath) intacta.
- Adicionada geração de nonce CSPRNG por request:
  `Buffer.from(crypto.randomUUID()).toString("base64")`.
- Adicionada função `buildCsp(nonce)` que monta a directive com
  `script-src 'self' 'nonce-${nonce}' 'strict-dynamic'` (+ `'unsafe-eval'`
  apenas em `NODE_ENV=development`, requirement do React dev runtime para
  reconstruir stacks SSR).
- Propagação correta para o Next App Router: nonce e CSP setados no
  `requestHeaders` (`x-nonce` + `Content-Security-Policy`) que é repassado
  via `NextResponse.next({ request: { headers } })`. Next 15 lê o CSP do
  request, extrai o nonce e injeta automaticamente em scripts da framework,
  bundles e `<Script nonce>`.
- CSP também escrito no `response.headers` — é como o browser aplica.
- Matcher atualizado para ignorar prefetches de `next/link` (headers
  `next-router-prefetch` / `purpose: prefetch`), evitando desperdício de
  CPU gerando nonce que não vai ser usado e invalidação inútil de cache.
- `runtime: "nodejs"` preservado (prom-client exige Node APIs).

### 3. `viralefy_backoffice/src/app/layout.tsx`

- Layout agora é `async`.
- Importa `headers` de `next/headers` e lê `x-nonce` — força dynamic
  rendering (compatível: backoffice já é all-dynamic, auth-gated).
- Backoffice atualmente não tem `<Script>` próprio; a leitura existe para
  servir de hook futuro e para sinalizar dynamic rendering ao Next.

## CSP final

Produção:

```
default-src 'self'; script-src 'self' 'nonce-{NONCE}' 'strict-dynamic'; style-src 'self' 'unsafe-inline'; img-src 'self' data: blob:; font-src 'self' data:; connect-src 'self'; frame-ancestors 'none'; form-action 'self'; base-uri 'self'; object-src 'none'; upgrade-insecure-requests
```

Dev (acrescenta `'unsafe-eval'` em script-src):

```
script-src 'self' 'nonce-{NONCE}' 'strict-dynamic' 'unsafe-eval'
```

## Tradeoffs / débitos remanescentes

1. **`style-src 'unsafe-inline'` mantido.** Next 15 injeta styles inline
   (CSS modules dev mode, next/font, runtime style insertion) sem propagar
   nonce de forma consistente. Substituir por `'nonce-${nonce}'` em
   style-src quebra hydration em ambientes que dependem desses injects.
   A docs oficial do Next também mantém `'unsafe-inline'` em style-src no
   exemplo dev. Débito **separado**: revisar quando Next padronizar nonce
   em todos os style injectors.
2. **`'unsafe-eval'` em dev.** React dev runtime usa `eval` para
   reconstruir stacks SSR no browser. Documentado oficialmente. Apenas
   em `NODE_ENV=development` — produção fica sem.
3. **`experimental.nodeMiddleware`** ainda gera warning de `Unrecognized
   key` no Next 15.5.18 (a flag funciona em runtime mas não está nos
   types/schema do config). Preexistente, não introduzido por esta task.
4. **Dynamic rendering universal.** Nonces forçam todas as páginas a
   dynamic. Sem impacto prático aqui: backoffice já era 100% dinâmico
   (RBAC server-side, sem ISR/SSG). Confirmado no output do `next build`:
   todas as 24 rotas marcadas `ƒ (Dynamic) server-rendered on demand`.

## Resultado do build

`npm run build` — **verde**.

```
✓ Compiled successfully in 68s
✓ Generating static pages (19/19)
ƒ (Dynamic)  server-rendered on demand
```

Warnings preexistentes (Sentry deprecations, `nodeMiddleware`
Unrecognized key) inalterados — não introduzidos pelo round 22.

## Testes

`npm test` — 3 pass, 1 fail. A falha (`no-pt-regression` em
`src/app/admins/page.tsx:375 → "Cancelar"`) é **preexistente** e fora do
escopo da Track OO (Track OO só toca `next.config.ts`, `middleware.ts`,
`layout.tsx`). String PT a ser corrigida em outro track.

Sem testes de CSP/nonce ainda no `tests/unit/`. Track futuro pode
adicionar:
- Boot do app, request a `/login`, asserir header
  `Content-Security-Policy` contém `nonce-` e NÃO contém `'unsafe-inline'`
  em script-src.
- Asserir que dois requests consecutivos retornam nonces diferentes.

## Verificação browser

Não executada nesta sessão (sem stack rodando localmente). Smoke manual
recomendado:

1. `npm run dev` → abrir `/login` → DevTools → Network → ver header
   `Content-Security-Policy` no response do documento HTML, conferir
   `script-src 'self' 'nonce-XYZ...' 'strict-dynamic' 'unsafe-eval'`.
2. DevTools → Elements → confirmar que `<script>` tags injetados pelo
   Next (`_next/static/chunks/...`) carregam: o atributo `nonce="XYZ..."`
   bate com o do header.
3. Console: sem `Refused to execute inline script because it violates the
   following Content Security Policy directive`.
4. Reload: novo nonce a cada request.

## Conformidade com padrões da casa

- §13.4 (frontend / segredos): nenhum segredo em bundle — task só toca
  CSP, sem mexer em segredos.
- §16 / §22.3 (hardening de headers): CSP sem `'unsafe-inline'` em
  script-src é o piso recomendado; nonce + strict-dynamic é o padrão moderno.
- §14 (CSPRNG): nonce via `crypto.randomUUID()` — não `Math.random()`.
- §28 (archive): este arquivo.
- DoD (§35): build verde, sem regressão de testes (a falha é preexistente),
  archive commitado. **Sem commit** por instrução explícita da task.

## Próximos passos sugeridos

1. Track de testes: adicionar `tests/unit/csp-nonce.test.mjs` (smoke
   afirmativo + self-check de falha conhecida).
2. Track de débito CSS: investigar se Next 15.5+ permite remover
   `'unsafe-inline'` de style-src com nonce em todos os style injectors.
3. Aplicar mesma migração nos outros frontends (`viralefy_front`) com a
   adaptação para o public site (provavelmente terceiros adicionais em
   script-src).
