---
date: 2026-06-15
session: round 25 — hardening dos Altos + Médios do code review
---

# Round 25 — Hardening security batch (4 tracks paralelos)

Sequência do round 24 (review profunda). Atacou 5 Altos + 5 Médios documentados.

## FEITO

### Track AA — JWT validation hardening (HIGH)
- **`viralefy_auth/internal/application/token_service.go`**
- `parseDualSign` agora usa `jwt.NewParser` com:
  - `WithValidMethods(["RS256", "HS256"])` — bloqueia `alg=none`
  - `WithIssuer("viralefy-auth")` 
  - `WithAudience(expectedAudience)` por consumer
  - `WithExpirationRequired()`
- Mint emite `iss` + `aud` array (RFC 7519 §4.1.3)
- Constants: `AudienceAPI/Core/Payments/Sender`, `AudiencePartial2FA`
- `VerifyAccess(raw, expectedAudience)` recebe aud do consumer
- `ParsePartialToken` isolado (só aceita aud=viralefy-auth)
- `errors.Is` contra sentinels golang-jwt/v5
- **6 tests novos:** alg=none, iss errado, aud errado, exp missing, partial vs access
- **Tokens legacy** (sem iss/aud) rejeitados como malformed — refresh re-mintar (HML/POC OK)

### Track BB — Refresh token preserva role + Stripe idempotency atomic (HIGH)

**Refresh role preservation:**
- `viralefy_auth/internal/application/token_service.go::Refresh`
- Re-busca user/admin do repo após validar refresh_token
- Mintar novo access_token com role + email REAIS (era role default)
- Falha fechada: admin não existe, soft-deleted, repos nil
- main.go wiring: passa Users + Admins
- **4 tests:** superadmin preservado, admin deleted → 401, user email preservado, soft-deleted → 401

**Stripe webhook idempotency atomic:**
- `viralefy_core/internal/interface/http/handlers.go::StripeWebhook`
- Novo helper `classifyStripeIdempotencyResult(rows, err)` retorna `Proceed | Duplicate | TransientError`
- ANTES: erro de DB caía em `logger.Warn` e SEGUIA pro MarkOrderPaid → double-fire possível
- AGORA:
  - Proceed → segue
  - Duplicate (rows=0 ou pg 23505 cru/wrapped) → 200 sem MarkOrderPaid
  - TransientError (40001/23503/timeout/genérico) → 500 sem MarkOrderPaid → Stripe re-entrega
- **8 tests table-driven** + self-check anti-verde-mentiroso

### Track CC — Frontend CSP nonce + backoffice empty catch (HIGH)

**Frontend nonce (espelha round 22 Track OO no backoffice):**
- `viralefy_front/src/middleware.ts`: gera nonce CSPRNG via `crypto.randomUUID()` base64
- Propaga via `x-nonce` no request header
- CSP per-request com `script-src 'self' 'nonce-{N}' 'strict-dynamic'`
- Mantém geo-redirect, locale, Vary, matcher exclui /monitoring (Sentry tunnel)
- `src/lib/csp.ts`: novo helper `getNonce()` 
- `src/components/JsonLdScript.tsx`: server component reusável com nonce + safeJsonStringify
- `src/app/layout.tsx`: lê nonce, passa em `<script nonce={nonce}>` do anti-flash
- `src/app/legal/cookie-preferences/page.tsx`: virou server, UI client em `CookiePreferencesClient.tsx`
- `next.config.ts`: CSP removida (movida pro middleware)
- **16 pages JSON-LD** migradas para `<JsonLdScript>`
- `tests/unit/security.test.mjs` atualizada: assert nonce + strict-dynamic, proíbe `'unsafe-inline'` em script-src
- **Validado prod:** CSP header tem `nonce-NzdmNzhiMzAt...`, nonce no script HTML, sem `'unsafe-inline'` em script-src ✓

**Backoffice empty catch:**
- `viralefy_backoffice/src/middleware.ts:129`
- `try{...metrics...} catch{}` → `catch (err) { console.error("[middleware] metric record failed", err); }`
- Skill §V4 cumprido (erro não engolido)

### Track DD — bcrypt cost + HTTP Transport (MED)

**Bcrypt cost backup codes 10 → 12:**
- `viralefy_auth/.../password.go`: const `BackupCodeCost = 12`
- `viralefy_auth/.../auth_service.go:310`: usa BackupCodeCost
- `viralefy_core/.../twofa_service.go:63`: const + uso
- Backup codes existentes continuam validando (cost embedded no hash)

**HTTP Transport hardening em payment providers:**
- Novo helper `viralefy_core/.../payment/httpclient.go::DefaultHTTPClient(timeout)`:
  - DialContext.Timeout: 3s
  - TLSHandshakeTimeout: 3s
  - ResponseHeaderTimeout: 5s
  - ExpectContinueTimeout: 1s
  - MaxIdleConns: 100, MaxIdleConnsPerHost: 10
  - IdleConnTimeout: 90s
- Aplicado em: heleket (15s), woovi (15s), stripe (20s)
- Rationale: timeouts por camada cortam slowloris/DNS lento antes do timeout total

## Deploy + smoke
- `viralefy-update` rodou completo
- 7 services com age 0s
- `viralefy-smoke` 13/13 verde

## Validações em prod

### CSP nonce funcionando
```
content-security-policy: default-src 'self'; 
script-src 'self' 'nonce-NzdmNzhiMzAtN2RhMS00ZjI5LTk1MzQtMzI5NzUwZDY0ZTFi' 'strict-dynamic' ...
```
Script tags têm `nonce="Nzg2MmUzZjYt..."` ✓

### Sem 'unsafe-inline' em script-src ✓
(style-src ainda tem como débito documentado)

### Testes end-to-end:
- **full-route-suite WAN: 208/208 PASS, 0 5xx**
- **simulated: 2808/2808 AUTO (30 rotas × 6 personas × 15+ injections + controls)**
- viralefy-smoke 13/13

## Commits da sessão
- `viralefy_auth@ac7e29c` — JWT validation + Refresh role + bcrypt cost
- `viralefy_core@f59c50a` — Stripe idempotency + HTTP Transport + bcrypt
- `viralefy_front@971c53b` — CSP nonce no front
- `viralefy_backoffice@09b2287` — empty catch fix

## Estado FINAL de segurança após rounds 22-25

### CSP
- Backoffice: `script-src 'self' 'nonce-...' 'strict-dynamic'` ✓ (round 22 OO)
- Front: `script-src 'self' 'nonce-...' 'strict-dynamic'` ✓ (round 25 CC)
- Style-src 'unsafe-inline' mantido em ambos (Next 15 limitation)

### Token storage
- Backoffice admin: cookie HttpOnly SameSite=Strict ✓ (round 23 UU)
- Front user: localStorage (débito conhecido — refactor futuro)

### CORS
- Allowlist explícita: `www|api|auth|admin.viralefy.com` ✓ (round 24)

### JWT validation
- WithValidMethods + iss + aud + exp required ✓ (round 25 AA)
- Refresh preserva role/email reais ✓ (round 25 BB)

### Webhooks
- Stripe idempotency atomic (no double-fire) ✓ (round 25 BB)
- Heleket constant-time HMAC: débito (não tocado neste round)

### bcrypt cost
- Senha: 12 ✓
- 2FA backup codes: 12 ✓ (round 25 DD)

### Race conditions
- Checkout com créditos: eliminado ✓ (round 24)

### Timing oracle
- Login enum: bloqueado ✓ (round 24)

### HTTP Transport
- Payment providers: dial/TLS/response timeouts ✓ (round 25 DD)

### Anti-padrões §37 ativos
- ✗ Token user em localStorage (débito documentado, refactor amplo)
- ✗ style-src 'unsafe-inline' (Next 15 limitation, débito)
- Resto: 0 anti-padrões

## EM ABERTO (futuro opt-in)

### Médios
- `viralefy_core/.../handlers.go` 3863 linhas — split por bounded context
- N+1 em `ListPublicPlans` — single query com JOIN
- Rate limiter in-memory → Redis (POC declarado mas em prod)
- `viralefy_api` (legacy) e `viralefy_core` têm parseDualSign similar ao auth — aplicar mesmo hardening AA (Track AA bullet)

### Baixos
- `var _ = errors.New` sanity-check gambiarra (auth_service.go:499)
- Funções duplicadas (strPtrAuth/strPtr)
- Style-src nonce migration (Next 15 limitation)
- Comentários PT/EN misturados

## DoD §35 — status final
- ✓ Testes: 501/501 unit + 13/13 smoke + 208/208 full-suite + 2808/2808 simulated + pentest = ~3500+ checks verdes
- ✓ Pentest entrada limpo
- ✓ Simulated: 142/142 rotas (100%) com cobertura completa por persona
- ✓ Anti-padrões §37: 2 conhecidos documentados (localStorage user, style-src)
- ✓ Archive commitado
- ✓ ADRs: 14
- ✓ CI verde

## Total acumulado após round 25

- **12 rounds** (13 a 25), ~42 tracks paralelos
- **213/213 bugs QA** (100%)
- **+5 críticos descobertos via review** (round 24+25)
- **CSP nonce em front E backoffice** (sem unsafe-inline em script-src)
- **JWT validation completa** (alg/iss/aud/exp)
- **Stripe idempotency atomic**
- **Race condition checkout eliminado**
- **Timing oracle eliminado**
- **Refresh token preserva role real**
- **HTTP Transport hardened**
- **bcrypt consistente cost 12**
- **CORS allowlist**
- **/metrics 404 no edge**
- **/llms.txt 200**
- **26 idiomas** suportados
- **RTL infra**
- **Cookie HttpOnly admin** (BFF pattern)
- **viralefy-update débito eliminado**
- **Rust toolchain em prod**
