# PHASE-9 Bucket 2 — User Auth Cutover Plan

**Status:** planejado · pré-cutover · aguarda 24-48h soak do Bucket 1
**Última revisão:** 2026-06-10

---

## 1. Pré-condições (descoberta nesta sessão)

| Constraint | Status | Implicação |
|---|---|---|
| Legacy api dual-sign verify (RS256 + HS256) | ✅ tem (`parseDualSign`) | Tokens interchangeable entre legacy/core/auth |
| RSA key (`/etc/viralefy/jwt-rs256.pem`) compartilhada | ✅ todos 3 services lêem mesma key | RS256 minted em qualquer service = válido em qualquer service |
| Migration 039 (refresh_tokens + revoked_jtis + password_resets) | ✅ aplicada em prod | Tabelas existem, viralefy_auth usa, legacy/core ignoram |
| Legacy api NÃO tem `/v1/refresh` ou `/v1/logout` | ⚠️ rotas só existem no viralefy_auth | Frontend só conhece auth se já chamava elas |
| Core (`viralefy_core`) é fork 1:1 do legacy | ✅ tem mesmas rotas user-auth que legacy | `/v1/me/*` funciona em core idêntico ao legacy |

**Conclusão**: canary É seguro porque tokens são interchangeable. Refresh-token rotation só importa pra rotas que o legacy nunca expôs — não há regressão possível.

---

## 2. Split do Bucket 2 em sub-buckets

### Bucket 2a — `/v1/me/*` GET (read-only)

**Risco**: mínimo. Mesma JWT verify, mesmo DB, sem mutação.

Rotas (18 endpoints):
- `/v1/me/orders`, `/v1/me/orders/{id}`, `/v1/me/orders/{id}/proof-url`
- `/v1/me/referral`, `/v1/me/journey`
- `/v1/me/2fa/status`
- `/v1/me/subscriptions` (GET)
- `/v1/me/whatsapp` (GET)
- `/v1/me/api-keys` (GET)
- `/v1/me/notif-prefs` (GET)
- `/v1/me/profiles` (GET)
- `/v1/me/credits`, `/v1/me/transactions`, `/v1/me/invoices`
- `/v1/me/tickets`, `/v1/me/tickets/open-count`, `/v1/me/tickets/{id}`
- `/v1/me/reviews/by-order/{order_id}`
- `/v1/me/data/export`

**Estratégia**: full cutover (não canary) — read-only + dual-sign garante safety. Smoke: requisição sem Bearer → 401, com Bearer válido → 200.

### Bucket 2b — `/v1/me/*` Mutating (POST/PUT/DELETE)

**Risco**: baixo (mesmo DB). Mas POST/DELETE são side-effect; rollback parcial é mais delicado.

Rotas (20 endpoints):
- `POST /v1/me/orders/{id}/proof` (upload + mutationLimiter + idem)
- `POST /v1/me/subscriptions`, `DELETE /v1/me/subscriptions/{id}`
- `PUT /v1/me/whatsapp`
- `POST /v1/me/api-keys`, `DELETE /v1/me/api-keys/{id}`
- `PUT /v1/me/notif-prefs`
- `POST /v1/me/2fa/{enroll,verify,disable,dismiss-prompt}`
- `POST /v1/me/data/deletion`, `DELETE /v1/me/data/deletion`
- `POST /v1/me/profiles`, `DELETE /v1/me/profiles/{id}`
- `POST /v1/me/recharge`
- `POST /v1/me/tickets`, `POST /v1/me/tickets/{id}/messages`
- `POST /v1/me/reviews`

**Estratégia**: full cutover após Bucket 2a estável 24h. Canary não traz benefício (DB é o mesmo).

**Risco residual**: idempotency-key e mutationLimiter rodam no core também (fork 1:1). Confirmar antes do swap: `grep mutationLimiter viralefy_core/internal/interface/http/router.go`.

### Bucket 2c — Auth user flows

**Risco**: médio. Estes endpoints existem em DUAS implementações (legacy/core vs auth) e mintam tokens.

Rotas (4 endpoints):
- `POST /v1/auth/user/register` (legacy + auth, ambos mintam RS256)
- `POST /v1/auth/user/login` (legacy + auth)
- `POST /v1/auth/user/login/2fa` (legacy + auth)

**Diferenças**:
- Legacy stateless: mint RS256 + retorna `{token, ttl}`, esquece
- Auth stateful: mint RS256 + refresh_token (rotated), grava em `refresh_tokens`, suporta logout/revoke
- Frontend atual: não chama `/v1/refresh` (legacy não tem) → só usa access token

**Estratégia**:
1. Cut para auth (full) — frontend ganha refresh capability automaticamente quando suportar
2. Migrar frontend pra usar `/v1/auth/user/refresh` + `/v1/auth/user/logout` (próximo PR)
3. Hot-set revoke já funciona (dispatcher LISTEN/NOTIFY)

**Cuidado**: backoffice usa `/v1/auth/login` (admin), NÃO está no Bucket 2c. Esse fica no Bucket 3 (admin).

---

## 3. Ordem de execução

```
[t=0]    Bucket 1 (DONE)
[+24h]   Soak Bucket 1 OK → Bucket 2a cut
[+24h]   Soak Bucket 2a OK → Bucket 2b cut
[+24h]   Soak Bucket 2b OK → Bucket 2c cut
[+48h]   Soak Bucket 2c OK → Bucket 3 (admin) plan
```

Cada swap usa o mesmo padrão do Bucket 1:
1. Edit Caddyfile com `handle` blocks
2. `caddy validate` + `systemctl reload` (zero-downtime)
3. Smoke E2E HTTPS confirma 401/200 conforme esperado
4. Logs dispatcher confirmam request chegou
5. Rollback test: swap back, validar 0 downtime

---

## 4. Smoke E2E pós-cutover (Bucket 2 específico)

Adicionar ao `viralefy-smoke` (ou script separado `viralefy-smoke-auth`):

```bash
# Bucket 2a smoke — /v1/me/* sem Bearer → 401
for p in /v1/me/orders /v1/me/2fa/status /v1/me/referral; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "https://api.viralefy.com$p")
  [[ "$code" == "401" ]] && ok "$p → 401" || bad "$p → $code"
done

# Bucket 2c smoke — register/login disponíveis (sem credentials inválidos = 400/401)
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST \
  -H 'Content-Type: application/json' -d '{}' \
  "https://api.viralefy.com/v1/auth/user/login")
[[ "$code" == "400" || "$code" == "401" ]] && ok || bad
```

---

## 5. Rollback (mesmo procedimento do Bucket 1)

```bash
# Backup atual antes do swap:
cp /etc/caddy/Caddyfile /etc/caddy/Caddyfile.bak.$(date +%s)

# Em caso de regressão:
cp /etc/caddy/Caddyfile.bak.LATEST /etc/caddy/Caddyfile
systemctl reload caddy  # zero-downtime
```

**Não-rollbackable**: mutações de Bucket 2b já gravadas no DB. Mas como o DB é compartilhado, mutação via dispatcher e via legacy resultam no MESMO state — sem inconsistência por path.

---

## 6. Critério de "Bucket 2 done"

- [ ] 42 rotas user-auth (18 GET + 20 mutating + 4 auth) servidas pelo dispatcher
- [ ] Smoke E2E HTTPS valida 401 sem Bearer em todas
- [ ] Smoke E2E com Bearer válido valida 200 em pelo menos 5 GETs amostradas
- [ ] 48h sem regressão de error rate
- [ ] Front + backoffice (lado user) consumindo via `:8090` sem incidente
- [ ] Hot-set revocation testado E2E (revoke JTI → dispatcher rejeita em ≤5s)
- [ ] Logs Coraza não acusam novos falsos positivos por causa do path

---

## 7. Bucket 2 NÃO inclui

- Admin routes (`/v1/admin/*`) → Bucket 3
- Checkout (`/v1/checkout/*`) → Bucket 4
- Webhooks (`/v1/webhooks/*`) → já roteado pra payments (Bucket 1)
- `/internal/*` → bloqueado na borda, never cuts
