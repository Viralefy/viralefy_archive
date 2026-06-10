# RUNBOOK-BACKUP-VERIFY — Verificação contínua + restore drill automatizado

**Alvo**: provar continuamente que cada dump em `/var/backups/viralefy/` é restaurável e bate com prod — não só que o arquivo existe.

Complementa [RUNBOOK-DR.md](RUNBOOK-DR.md), que documenta o restore manual em VPS nova. Este runbook cobre os controles automáticos que pegam dump corrompido / regressão de schema / shrink anômalo antes que viraem incidente real.

---

## 1. O que roda quando

| Unit | Quando | Duração típica | Alvo |
|---|---|---|---|
| `viralefy-backup.service` | diário 03:00 UTC (+ até 30min jitter) | <5s | dump compactado + retenção 7d+4w+6m |
| `viralefy-backup-verify.service` | diário 04:00 UTC (+ até 15min jitter) | <2s | sanity dos últimos 10 dumps |
| `viralefy-restore-drill.service` | domingo 05:00 UTC (+ até 30min jitter) | ~8s | restore real + smoke em container docker |

Listar:
```bash
ssh root@$IP 'systemctl list-timers --all | grep viralefy'
```

---

## 2. Backup verify — o que checa

Para cada dump em `/var/backups/viralefy/` (limite `MAX_INSPECT=10`, mais recentes):

1. **gzip integridade** (`gzip -t`) — **hard**: falha aqui → exit 1 (OnFailure).
2. **sha256** registrado (16 chars) — forensics futura.
3. **Schema completo** — `zcat | grep -c '^CREATE TABLE'`; abaixo de `MIN_TABLES=30` → flag `schema_too_small` (**soft**, só métrica).
4. **Anomalia de tamanho** vs o vizinho anterior:
   - cresceu > 2x → `size_anomaly_grew` (soft)
   - encolheu < 0.5x → `size_anomaly_shrunk` (soft — possível truncated dump)

**Hard issues** disparam OnFailure no systemd. **Soft issues** viram métrica Prometheus pra alertmanager decidir gravidade.

### Métricas exportadas (`/var/lib/prometheus/node_exporter/viralefy_backup_verify.prom`)

```
viralefy_backup_verify_last_run_timestamp <epoch>
viralefy_backup_verify_ok 0|1
viralefy_backup_verify_checked_total <int>
viralefy_backup_verify_issues_total <int>      # soft+hard
viralefy_backup_verify_hard_issues_total <int> # alvo do alerta crítico
```

**Alerta sugerido (Prometheus):**
```yaml
- alert: ViralefyBackupCorrupt
  expr: viralefy_backup_verify_hard_issues_total > 0
  for: 5m
  annotations:
    summary: "Backup verify achou dump corrompido"
- alert: ViralefyBackupVerifyStale
  expr: time() - viralefy_backup_verify_last_run_timestamp > 48*3600
  for: 1h
```

### Saída JSON exemplo

```json
{"ok":true,"timestamp":1781108984,"checked":7,"issues":0,"hard_issues":0,
 "items":[{"file":"dump-20260610T162451Z.sql.gz","size":78468,
           "sha256_16":"652c9da597ff1bac","tables":49,"indexes":70,
           "ok":true,"reasons":[""]}]}
```

---

## 3. Restore drill — o que faz

Roda semanal pra provar end-to-end que o backup É restaurável (verify só checa estrutura, drill restaura de verdade).

**Sequência:**
1. Pega o dump mais recente em `/var/backups/viralefy/`.
2. Sobe container `postgres:17-alpine` em `127.0.0.1:15433` (escolhe próxima porta livre se ocupada). Volume = tmpfs 512MB. Container nome `viralefy-restore-drill-<PID>`.
3. `pg_isready` aguardando até 30s.
4. `zcat dump.sql.gz | psql sandbox` — registra `restore_secs`.
5. Conta `pg_tables`/`pg_indexes` em sandbox vs prod. **Schema fail** se sandbox <30 tables.
6. Row count de 5 tabelas (`profiles`, `plans`, `orders`, `payment_gateways`, `email_events`) — sandbox vs prod com tolerância ±5% (configurável via `ROWCOUNT_TOLERANCE`).
7. 5 queries smoke representativas. Cada uma cronometrada via `date +%s%N`. SLO 250ms (inclui overhead psql/TCP/auth).
8. `trap EXIT` derruba o container.

### Métricas exportadas

```
viralefy_restore_drill_last_run_timestamp <epoch>
viralefy_restore_drill_ok 0|1
viralefy_restore_drill_duration_seconds <int>
viralefy_restore_drill_restore_seconds <int>
viralefy_restore_drill_smoke_max_ms <int>
```

**Alerta sugerido:**
```yaml
- alert: ViralefyRestoreDrillFailed
  expr: viralefy_restore_drill_ok == 0
  for: 10m
- alert: ViralefyRestoreDrillStale
  expr: time() - viralefy_restore_drill_last_run_timestamp > 14*86400
```

---

## 4. Rodar manualmente

```bash
# Backup ad-hoc
ssh root@$IP 'systemctl start viralefy-backup.service && journalctl -u viralefy-backup.service -n 20'

# Verify ad-hoc — JSON em stdout
ssh root@$IP '/usr/local/sbin/viralefy-backup-verify | jq .'

# Restore drill ad-hoc — leva ~8s
ssh root@$IP '/usr/local/sbin/viralefy-restore-drill | jq .'
```

Variáveis úteis pra debug:
```bash
MAX_INSPECT=20         # verify: inspeciona mais dumps históricos
MIN_TABLES=40          # verify: limiar schema-too-small
ANOMALY_GROW_RATIO=3   # verify: tolera crescimento até 3x
PG_IMAGE=postgres:16-alpine  # drill: imagem alternativa
SLO_QUERY_MS=500       # drill: smoke SLO mais frouxo
ROWCOUNT_TOLERANCE=0.10  # drill: ±10% por tabela
```

---

## 5. O que checar quando o alerta dispara

### `ViralefyBackupCorrupt` (hard_issues > 0)

```bash
ssh root@$IP 'journalctl -u viralefy-backup-verify.service -n 50 --no-pager'
# stdout JSON tem `items[].reasons` apontando o arquivo.
ssh root@$IP 'cd /var/backups/viralefy && gzip -t dump-XXX.sql.gz'
# Se gzip não bate, dump é lixo. Apague E confirme o próximo backup escreve ok:
ssh root@$IP 'rm /var/backups/viralefy/dump-XXX.sql.gz && systemctl start viralefy-backup.service'
```

### `ViralefyRestoreDrillFailed`

```bash
# Olha o JSON do último run:
ssh root@$IP 'journalctl -u viralefy-restore-drill.service -n 50 --no-pager | grep "{\"ok\""'

# Possíveis causas e fix:
#  - schema.ok=false: dump tem <30 tables. Backup foi feito de DB errado.
#  - rowcounts.issues>0: divergência grande sandbox vs prod (>5%). Pode ser
#    backup antigo ou prod cresceu muito. Recheck `ROWCOUNT_TOLERANCE`.
#  - smoke.issues>0 e max_ms>SLO: lentidão. Pode ser CPU contention na VPS
#    no horário do drill. Olhar carga.
#  - restore_err != "": pg_restore quebrou. Provavelmente migration drift
#    entre versão do pg_dump e schema atual.
```

### Container sobrou (raríssimo, trap EXIT é robusto)

```bash
ssh root@$IP 'docker ps -a | grep restore-drill'
ssh root@$IP 'docker rm -f viralefy-restore-drill-<PID>'
```

---

## 6. Ler journal logs

Todos os timers logam via `SyslogIdentifier=` próprio.

```bash
# Últimos 10 runs de cada
ssh root@$IP 'journalctl -u viralefy-backup.service --since "7 days ago" --no-pager'
ssh root@$IP 'journalctl -u viralefy-backup-verify.service --since "7 days ago" --no-pager'
ssh root@$IP 'journalctl -u viralefy-restore-drill.service --since "30 days ago" --no-pager'

# Só os JSON outputs do verify (uma linha por run):
ssh root@$IP 'journalctl -u viralefy-backup-verify.service --no-pager | grep "{\"ok\""'

# Diff de tamanho dos dumps últimos 7 dias (sanity manual):
ssh root@$IP 'ls -la /var/backups/viralefy/dump-*.sql.gz | tail -7'
```

---

## 7. Restrições e armadilhas conhecidas

- **`viralefy-backup.service` rodou em loop de falha entre 2026-06-07 e 2026-06-10 16:24 UTC** por bug com `install -d` no `/var/lib/prometheus/node_exporter` (ProtectSystem=strict + CapabilityBoundingSet="" → root sem CAP_DAC_READ_SEARCH não conseguia stat o parent 0750). Fix: parent agora `0755` e a escrita do textfile virou best-effort. Dump em si nunca foi afetado (já estava salvo no disco quando o erro acontecia).
- **Drill SLO de 250ms é generoso**: cada query nova abre TCP+auth psql (~80ms piso). Não usar pra detectar regressão fina; pra isso use métricas in-app contra prod.
- **Drill compara contra prod em tempo real**: se prod evoluir muito entre o backup (03:00) e o drill semanal (Dom 05:00), `rowcount_issues` pode crescer dentro de uma janela aceitável. Ajustar `ROWCOUNT_TOLERANCE` se virar ruído.
- **Verify não faz restore real** — só estrutura. Dump válido em verify ainda pode falhar no restore por incompatibilidade de extensão postgres / role faltante / etc. Por isso o drill existe.
- **MinIO/storage não está no escopo deste runbook** — backup atual cobre só Postgres + secrets. MinIO snapshot semanal é débito conhecido em [PHASE-7-PLAN.md](PHASE-7-PLAN.md).
