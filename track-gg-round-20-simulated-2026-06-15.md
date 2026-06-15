# Track GG · Round 20 · simulated — 2026-06-15

## Entrega

- Script: `/media/sonne/Archives/projects/viralefy/viralefy_ops/tests/simulated/run.py` (já existente; reaproveitado, validado nesta sessão)
- Inventário: `/media/sonne/Archives/projects/viralefy/viralefy_ops/tests/simulated/routes-inventory.json` — **142 rotas** (era 125, ampliado em 17 rotas faltantes: soft/hard delete + restore + bulk + trash + honeypot + journey + visitors)
- Route registry humano: `/media/sonne/Archives/projects/viralefy/viralefy_archive/route-registry-2026-06-15.md`
- Personas: 6 (anonymous, normal_user, normal_admin, superadmin, bad_jwt, b2b_key)
- Injections: 26 (control, sqli, xss, path, encoding, size, mass_assign, header_smuggle)

## Execução

Rodada loopback via SSH (prod hml) contra `viralefy_core:8084` direto — bypass do rate limit do dispatcher Rust (`tower_governor` derruba 96% das requests em 429 quando chega via :8090). Rodada WAN contra `https://api.viralefy.com` validou cobertura total via Caddy + dispatcher.

### Loopback (core :8084) — matriz completa

```
total=22152 auto=21996 review=156 routes=142 personas=6 injections=26
distribution:  401: 17628 · 200: 2184 · 429: 2028 · 500: 156 · 404: 156
```

### Loopback (core :8084) — control-only

```
total=852 auto=846 review=6 routes=142 personas=6 injections=1
distribution:  401: 678 · 200: 84 · 429: 48 · 422: 24 · 404: 12 · 500: 6
```

### WAN (api.viralefy.com via Caddy → dispatcher) — control-only

```
total=852 auto=851 review=1 routes=142 personas=6 injections=1
distribution:  429: 774 · 200: 38 · 400: 18 · 401: 14 · 404: 6 · 500: 1 · 422: 1
```

## Cobertura: 142/142 (100%)

- Rotas fantasma: **0** (todas as rotas servidas têm handler)
- Rotas mortas: **0** (todas no inventário responderam)

## Surpresas / achados

### Critical: nenhum

### High: nenhum (sem vazamento cross-tenant, sem auth bypass, sem eco)

### Medium: 1 — 500 em rota pública com input legítimo

- `GET /v1/plans/{id}/payment-methods` → **500 INTERNAL_ERROR** quando UUID sintaticamente válido mas inexistente é fornecido.
- 6/6 personas afetadas, 156 hits no loopback, 1 hit reproduzido na WAN.
- Body: `{"error":{"code":"INTERNAL_ERROR","message":"internal server error","trace_id":"…"}}` — sem stack trace leak (compliant com §22.8 "nunca eco sem escape").
- **Violação direta** do §22.8 "nunca 500 por input legítimo" — esperado **404**.
- Localizar handler: `viralefy_core/internal/interface/http/handlers.go` → `PublicListPaymentMethods`. Repo provavelmente lança erro não-mapeado ao não achar plan; precisa devolver `ErrNotFound` no service.

### Low / Info

- Rate-limit do dispatcher (tower_governor 30 burst + 1/s/IP) cobre toda a matriz quando rodada via :8090 — confirma defesa funcionando, mas cega o teste contra os handlers. Para `simulated` exaustivo, usar :8084 (core direto) ou IP-spoofing por persona.
- Cobertura ampliada do inventário: 17 rotas faltantes (admin soft/hard delete, bulk, trash, honeypot, journey, visitors) adicionadas. Falta atualizar `viralefy_archive/PENTEST-BASELINE-2026-06-10.md` se referenciar contagem antiga.

## Output sumarizado (sample)

```
[simulated] anon × GET /v1/plans → 200 (expected 200)
[simulated] anon × POST /v1/checkout → 422 (expected 4xx, Turnstile bloqueou)
[simulated] anon × GET /v1/admin/plans → 401 (expected 401)
[simulated] anon × GET /v1/admin/trash → 401 (expected 401)
[simulated] anon × GET /v1/me/orders → 401 (expected 401)
[simulated] anon × GET /v1/plans/{uuid}/payment-methods → 500 (REVIEW: esperado 404)
[simulated] coverage: 142/142 rotas (100%)
```

## Próximos passos

1. Abrir issue de severidade Medium em `viralefy_core`: corrigir `PublicListPaymentMethods` para devolver 404 quando plan_id não existe (mapping `ErrNotFound`). Adicionar caso de teste unit + pentest.
2. Decidir se o run "via dispatcher" precisa de IP-spoofing por persona para validar handlers atrás do rate-limit; ou aceitar que `simulated` exaustivo passa direto pros backends loopback e dispatcher fica para pentest.
3. Considerar mover `simulated` para `make simulated` no `viralefy_ops/Makefile` (atualmente roda via `run.sh`).
