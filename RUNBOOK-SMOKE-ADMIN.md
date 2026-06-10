# RUNBOOK — Smoke admin Bucket 3 (`/v1/admin/*`)

Smoke E2E sem TOTP: minta um JWT RS256 de admin diretamente com a chave
privada no servidor, percorre 25+ endpoints do Bucket 3, valida RBAC com um
token de `viewer`, exercita a revogação hot-set via NOTIFY e confirma que
o `audit_log` recebe a entrada do core.

A motivação é cobrir o Bucket 3 em ciclos curtos (smoke periódico, CI noturna,
verificação pós-deploy) sem precisar de um aplicativo TOTP montado pra rodar
o fluxo de 2FA normal.

## Pré-condições

- SSH na máquina HML: `ssh -i /tmp/vf-ssh.key root@62.238.41.231`.
- `/etc/viralefy/jwt-rs256.pem` presente (chave RSA do mint RS256).
- Postgres local rodando com a env `DATABASE_URL` em `/etc/viralefy/.env`.
- `viralefy-core` ativo em `127.0.0.1:8084`, `viralefy-dispatcher` em
  `127.0.0.1:8090`. Caddy faz TLS + Coraza WAF em `:443`.
- `viralefy-api` (legacy) `inactive (dead)` — isso é o invariante que
  permite atribuir cada nova linha de `audit_log` ao core sem ambiguidade.
- Python 3 com `PyJWT` (`>=2.10`) e `cryptography` (`>=43`).

## Restrições do ambiente que o script respeita

- **Coraza WAF (CRS 4.10, rule 911100)** bloqueia métodos fora do default
  (`GET HEAD POST OPTIONS`) com HTTP 403 antes mesmo de chegar no core. Por
  isso o teste de RBAC usa **só POST** pra writes — `PUT`/`PATCH`/`DELETE`
  retornam 403 do WAF, contaminando a verificação RBAC. Se quisermos cobrir
  `PUT currencies/{code}`, etc., precisa adicionar `PUT PATCH DELETE` ao
  `tx.allowed_methods` em `crs-setup.conf`. Ver: ROADMAP / `WAF tuning`.
- **tower_governor** no dispatcher: 1 req/s sustentado, burst 30, per-IP.
  O script intercala `time.sleep` entre rajadas pra não contaminar com 429.

## Procedimento — uma execução

```bash
# 1) Copia o script e roda
scp -i /tmp/vf-ssh.key scripts/smoke_admin.py root@62.238.41.231:/tmp/
ssh -i /tmp/vf-ssh.key root@62.238.41.231 'python3 /tmp/smoke_admin.py' | tee /tmp/smoke_admin_$(date -u +%FT%TZ).json
```

Saída em JSON; campos críticos:

| Campo | Esperado |
| --- | --- |
| `smoke_count` | 27 |
| `smoke_2xx` | 27 |
| `rbac.viewer_reads[*].ok` | `true` para todos |
| `rbac.viewer_writes[*].ok` | `true` para todos (todos 403) |
| `rbac_writes_all_403` | `true` |
| `hotset.pre_status` | 200 |
| `hotset.post_status` | 401 |
| `hotset.revoked_ok` | `true` |
| `audit.mutation_status` | 201 |
| `audit.new_entries_after_mutation[0].action` | `admin.create` |
| `audit.new_entries_after_mutation[0].metadata` contém `role` e `email` | sim |

## Identificação da origem do audit_log

`audit_log` é compartilhado entre legacy e core (mesmo DB, mesmo schema —
`viralefy_core` é fork 1:1 do `viralefy_api`). Identificamos a origem
pelo invariante operacional:

```bash
systemctl is-active viralefy-api   # → inactive
ss -tlnp | grep -E ":8084|:8090"   # → core e dispatcher escutam
```

Como o legacy está parado, qualquer linha nova em `audit_log` foi gravada
pelo core. Sinal adicional: o `AdminCreateAdmin` em
`viralefy_core/internal/interface/http/handlers.go:657` emite `metadata =
{"email": <created.Email>, "role": <created.Role>}` (sem
`ip/path/method/user_agent`) — distinto do wrapper `logAudit` genérico,
útil pra grep visual.

## Última execução (2026-06-10)

- Bucket 3 smoke: **27/27 endpoints @ 200**.
- RBAC: viewer leu 4/4 endpoints @ 200, foi negado em 5/5 writes (POST
  admins/plans/coupons/vendors/ab) @ 403.
- Hot-set: pre=200, post=401, latência insert→observed = **1.75s**
  (NOTIFY recebido + cache atualizado dentro do polling do core).
- Audit: POST `/v1/admin/admins` → 201, gravou entry `admin.create`
  com metadata `{role:viewer, email:smoke-…@viralefy.local}` —
  assinatura do handler core (confirmado em `handlers.go:657`).

## Cleanup automático

O script remove:

- `revoked_jtis` row do teste hot-set (`DELETE WHERE jti = $1`).
- O admin criado no teste de audit (`DELETE FROM admins WHERE id = $1`).

O `audit_log` é imutável por design (vide
`viralefy_core/.../migrations/012_idempotency_audit.up.sql`) e a linha de
`admin.create` fica como rastro do smoke — isso é desejado.

## Segurança operacional

- O token mintado tem TTL 15min. O script só loga fingerprint
  `<first10>...<last10>`, nunca o token completo.
- Não cria/persiste admin "viewer". O role `viewer` já existe em `roles`
  (`PermCurrenciesRead`, `PermGatewaysRead`, `PermOrdersRead`,
  `PermPlansRead`, `PermReviewsRead`, `PermTicketsRead`). O mint só usa
  o `sub = admin_id` do superadmin existente com `role: "viewer"`.
  `ValidateAdmin` re-deriva permissões do papel no DB a cada request, então
  o token de viewer recebe perms de viewer mesmo apontando pro mesmo
  `admin_id` — isso é defensivo do design RBAC.
- A chave privada `jwt-rs256.pem` nunca sai do servidor; o mint roda em
  Python 3 no host (`/etc/viralefy/jwt-rs256.pem` lido com `root`).

## Script

Versão atual em `viralefy_archive/scripts/smoke_admin.py`. Para mudanças
no smoke, editar lá e re-rodar o copy do procedimento acima.
