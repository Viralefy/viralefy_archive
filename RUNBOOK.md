# Viralefy — Ops Runbook

Snapshot 2026-06-08. Resposta a incidentes + procedimentos operacionais.

## Acesso

```bash
# SSH
ssh -i /media/sonne/Archives/projects/viralefy/credentials root@62.238.41.231

# Postgres (via env)
PGPASSWORD=$(grep DATABASE_URL /etc/viralefy/.env | sed 's/.*:\(.*\)@.*/\1/') \
  psql -U viralefy -h localhost -d viralefy

# Grafana
https://obs.viralefy.com  (admin / GRAFANA_ADMIN_PASSWORD em /etc/viralefy/.env)
```

## Deploy

```bash
# Padrão (zero-downtime, ~5s):
viralefy-update --yes

# Emergência (rebuild destrutivo, ~5min downtime):
viralefy-update --legacy
```

Healthcheck automático pós-deploy; rollback se /health ou :3000 falham em 30s.

## Status geral

```bash
viralefy-status              # systemd + binários
curl -sS https://api.viralefy.com/v1/status
systemctl list-timers        # crons systemd
journalctl -u viralefy-api -f --since '5 min ago'
```

## Incidente: API down

1. `systemctl status viralefy-api`
2. `journalctl -u viralefy-api --since '10 min ago' --no-pager | tail -50`
3. Se OOM: `dmesg | grep -i kill | tail -5`. Reiniciar: `systemctl restart viralefy-api`
4. Se segfault: rollback via `mv /viralefy.prev/api /viralefy/api && systemctl restart viralefy-api`
5. Logs estruturados: `journalctl -u viralefy-api -o json | jq 'select(.level=="ERROR")'`

## Incidente: Pagamento não confirma

1. Verificar gateway ativo: `psql … -c 'SELECT * FROM payment_gateways WHERE active'`
2. Webhook URL configurado no provider? Provider envia tokens válidos?
3. Logs: `journalctl -u viralefy-api | grep -i 'webhook\|payment_receiver'`
4. Forçar marca manual: backoffice `/orders/<id>` → "Mark paid" (requer `admins:manage`)
5. Reprocessar webhook: provider geralmente tem retry; ou via curl manual com mesmo payload.

## Incidente: Backup atrasado (alert `BackupStale`)

1. `systemctl list-timers viralefy-backup.timer` → última execução?
2. `journalctl -u viralefy-backup.service --since yesterday`
3. Manual: `viralefy-backup` (roda imediato)
4. Espaço em disco: `df -h /var/backups/viralefy/`

## Incidente: Drift `plan_prices` (alert `PlanPriceDriftHigh`)

1. Identificar moeda no alert label `currency_code`
2. SQL:
   ```sql
   SELECT p.name, pp.amount AS stored,
          ROUND((p.price_cents::numeric / 100.0) * c.rate::numeric, c.decimals) AS expected
   FROM plan_prices pp
   JOIN plans p ON p.id=pp.plan_id
   JOIN currencies c ON c.code=pp.currency_code
   WHERE c.code = 'XXX'
     AND pp.amount::numeric IS DISTINCT FROM ROUND((p.price_cents::numeric / 100.0) * c.rate::numeric, c.decimals);
   ```
3. Causa comum: admin updated plan.price_cents direto via SQL sem refresh do cascade. Fix:
   ```sql
   -- Trigger manual do cascade
   UPDATE currencies SET rate = rate WHERE code = 'XXX';  -- no-op pra disparar service
   ```
   ou recompute pelo service via PUT no backoffice `/currencies/XXX`.

## Incidente: Rate-limit disparando (alert `AuthBruteforce`)

1. `journalctl -u viralefy-api | grep '429' | tail -50` → IPs
2. Identificar IP atacante: `awk '/429/{print $remote_ip}' | sort | uniq -c | sort -rn | head`
3. Bloquear via iptables se persistente:
   ```bash
   iptables -A INPUT -s <IP> -j DROP
   ```
4. Tabela `fraud_blocks` registra automaticamente se 10+/h:
   `SELECT * FROM fraud_blocks ORDER BY blocked_until DESC LIMIT 10`

## Restore de backup

Drill validado 2026-06-08: dump 25KB restaura em 1s, 0 erros.

```bash
# Em DB clone (TEST):
LATEST=$(ls -t /var/backups/viralefy/dump-*.sql.gz | head -1)
sudo -u postgres createdb viralefy_restore_test -O viralefy
gunzip -c "$LATEST" | sudo -u postgres psql -d viralefy_restore_test -q
# Validar:
sudo -u postgres psql -d viralefy_restore_test -c 'SELECT count(*) FROM plans;'
# Cleanup:
sudo -u postgres dropdb viralefy_restore_test
```

DRP completo (worst case — DB perdido inteiro):

```bash
systemctl stop viralefy-api  # evita writes
sudo -u postgres pg_dump viralefy > /tmp/last-good.sql  # tenta o atual
sudo -u postgres dropdb viralefy
sudo -u postgres createdb viralefy -O viralefy
LATEST=$(ls -t /var/backups/viralefy/dump-*.sql.gz | head -1)
gunzip -c "$LATEST" | sudo -u postgres psql -d viralefy
systemctl start viralefy-api
```

## Rotação de admin

```sql
UPDATE admins
   SET password_hash = '$2b$12$…',   -- bcrypt cost 12
       updated_at = NOW()
 WHERE email = 'viralefy@gmail.com';
```

Gerar hash:
```bash
python3 -c "import bcrypt; print(bcrypt.hashpw(b'NEW_PASS', bcrypt.gensalt(12)).decode())"
```

## Adicionar segundo admin

Sem UI de criação ainda. SQL direto:
```sql
INSERT INTO admins (id, email, password_hash, name, role)
VALUES (
  gen_random_uuid()::text,
  'novo@email.com',
  '$2b$12$…',
  'Nome',
  'superadmin'  -- ou outro role definido em RBAC
);
```

## Métricas críticas

| Métrica | Pra quê | Onde |
|---|---|---|
| `viralefy_backup_last_success_timestamp` | Alert se > 36h | Prometheus |
| `viralefy_plan_price_drift_rows{currency_code}` | Alert se > 5 | Prometheus |
| `up{job="viralefy-api"}` | Alert se 0 por 2min | Prometheus |
| `gateway_callbacks_total{status}` | Confirmação de pagamento | Prometheus |
| `http_requests_total{status=~"5.."}` | Alert se > 5% | Prometheus |
| Sentry events | Erros em runtime | Sentry (após DSN configurado) |

## Crons rodando

| Cron | Interval | O que faz |
|---|---|---|
| viralefy-backup.timer | diário 03:00 UTC | Postgres dump + retenção 7d+4w+6m |
| IdempotencyCleanupCron | 1h | Remove idempotency_keys expirados |
| DeliveryCaptureCron | 15min | Snapshot 2ª fonte de verdade pós-paid (24h) |
| ReviewRequestCron | 1h | Email "how was your order?" 7d pós-paid |
| PlanPriceDriftCron | 1h | Detecta drift USD * rate ≠ stored |
| FraudVelocityCron | 5min | Agrega sinais → fraud_signals histórico |
| CartAbandonmentCron | 30min | Email "complete payment" 1-24h após order pending |
| SubscriptionCron | 1h | Renovação mensal de subs |

## Tabelas que crescem

| Tabela | Política | Cleanup |
|---|---|---|
| `idempotency_keys` | TTL 24h | IdempotencyCleanupCron |
| `user_events` | Append-only | TODO: cron mensal mantém últimos 90d |
| `ab_events` | Append-only | TODO: política a definir |
| `email_events` | Append-only | TODO: idem |
| `audit_log` | Append-only | Auditoria; nunca limpa |

## Comandos úteis

```bash
# Stop tudo (mantém DB + .env)
systemctl stop viralefy-{api,front,backoffice}

# Reload de Prometheus rules
systemctl restart prometheus  # SIGHUP não tá habilitado

# Conferir métrica específica
curl -sS http://127.0.0.1:9090/api/v1/query?query=up | jq .

# Loki (logs) query
curl -sS "http://127.0.0.1:3100/loki/api/v1/query_range?query={service=\"viralefy-api\"} |= \"ERROR\"&start=...&end=..."

# Tamanho do DB
sudo -u postgres psql -tA -c "SELECT pg_size_pretty(pg_database_size('viralefy'));"
```

## Sentry (não ativado)

Código wireado, DSN vazio. Pra ativar:
1. Criar projeto em sentry.io (free tier OK)
2. Copiar DSN
3. `/etc/viralefy/.env`:
   ```
   SENTRY_DSN=https://...@sentry.io/...
   NEXT_PUBLIC_SENTRY_DSN=https://...@sentry.io/...
   ```
4. `viralefy-update --yes` (zero downtime)

## Contatos / escalation

(preencher com o time)

| Severity | Quem | Como |
|---|---|---|
| Critical | Sonne | direto |
| Warning | qualquer admin | Grafana alerts → email/Slack quando configurado |
