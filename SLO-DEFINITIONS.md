# Viralefy — SLO Definitions & Runbook

**Última atualização:** 2026-06-10 (criação inicial — bucket SLO/alerting)

Este documento é o complemento operacional do
`viralefy_ops/observability/slo.yml` e do
`viralefy_ops/config/prometheus-alerts.yml`. Aqui ficam:

1. O que cada SLO mede, **por que** definimos nesse target.
2. Como o burn-rate é calculado (matemática + thresholds escolhidos).
3. **Como responder** a cada alerta (runbook por alert).
4. Trade-offs e por que escolhemos números não-perfeitos.

---

## 1. Princípios

- **Stack single-VPS, sem HA.** Janela de manutenção = downtime real, então
  99.99% (52min/ano) é inviável sem replica + LB. Escolhemos 99.5%/mês
  como floor — dá ~3.6h de "espaço" para deploy ruim + 1 incident curto.
- **Realismo > teatro.** Preferimos um SLO que dá pra cumprir e que dispara
  alarme só quando realmente importa. Alert fatigue mata operação.
- **Métrica real ou não existe.** Não criamos SLO sobre métrica TODO/
  hipotética; quando a métrica não está exposta, o alerta vai em
  `severity: info` com `absent()` no expr, sem rodada.
- **Multi-window burn-rate (Google SRE workbook).** Cada SLO crítico tem
  2 alertas: *fast burn* (page em 2h) e *slow burn* (ticket em ~5d).

---

## 2. Tabela canônica

| SLO | Target | Window | Severity de quebra | Métrica fonte |
|---|---|---|---|---|
| `api_availability` | 99.5% | 30d | critical (fast burn) / warning (slow) | `http_requests_total{service=viralefy-api}` |
| `api_latency_p95` | <500ms | 30d | warning | `http_request_duration_seconds_bucket` |
| `api_latency_p99` | <1500ms | 30d | critical | idem |
| `core_db_query_p95` | <100ms | 30d | warning | `db_query_duration_seconds_bucket{service=viralefy-core}` |
| `dispatcher_overhead_p95` | <50ms | 30d | warning | `http_request_duration_seconds_bucket{service=viralefy-dispatcher}` |
| `payments_webhook_ingestion` | 99.9% | 30d | critical (fast burn) | `http_requests_total{service=viralefy-payments,path=~/v1/webhooks/.*}` |
| `payments_provider_calls` | 99% | 30d | warning | `gateway_callbacks_total` |
| `stripe_reconcile_freshness` | <10min stale | — | info (métrica TODO) | `viralefy_stripe_reconcile_last_success_timestamp_seconds` (não exposta) |
| `revocation_propagation_p99` | <5s | 30d | info (métrica TODO) | `viralefy_revocation_propagation_seconds_bucket` (não exposta) |
| `coraza_inspection_rate` | 99% | 30d | warning | `caddy_http_requests_total{handler=~.*coraza.*}` |
| `backup_daily_success` | 100% | 30d | critical | `viralefy_backup_verify_ok` + `viralefy_backup_last_success_timestamp` (textfile) |

---

## 3. Math do burn-rate

Para SLO de **99.5% / 30 dias**:

```
error_budget = 1 - 0.995 = 0.005 (0.5% do total)
budget em tempo absoluto ≈ 0.005 × 30 × 24h ≈ 3.6h/mês
```

**Fast burn (page imediato):**

```
threshold_fast = (1 - 0.995) × 14.4 = 0.072  (7.2% error rate)
```

Mantendo essa taxa por 2h consecutivas, consome 100% do budget mensal em 2h.
Window de detecção: 1h rolling rate (suaviza ruído de 1 burst).

**Slow burn (ticket / não-page):**

```
threshold_slow = (1 - 0.995) × 6 = 0.03  (3% error rate)
```

Mantendo essa taxa por 6h, consome 100% do budget em ~5d.

Para SLO de **99.9%** (webhook ingestion):

```
threshold_fast = (1 - 0.999) × 14.4 = 0.0144  (1.44% error rate)
threshold_slow = (1 - 0.999) × 6    = 0.006   (0.6%)
```

Implementado em `prometheus-alerts.yml` com filtro AND short-window
(5min) para reduzir falsos positivos no detection window longo.

---

## 4. Runbooks por alerta

### `SLOApiAvailabilityFastBurn` (critical)

**O que significa:** 5xx ratio em 1h excedeu 7.2%. Estamos perdendo budget
mensal num ritmo que esgota tudo em ~2h.

**Resposta (em ordem):**

1. `journalctl -u viralefy-api -u viralefy-core -u viralefy-dispatcher -n 200 --no-pager`
2. Olhar Grafana → Reliability dashboard, "5xx por serviço" (5m).
3. Conferir último deploy: `cd /viralefy/viralefy_ops && git log --oneline -5`
4. Se mudança recente correlacionada: rollback via `viralefy-update <commit-anterior>`.
5. Se DB envolvida: `psql -c "SELECT * FROM pg_stat_activity WHERE state != 'idle' ORDER BY query_start;"`.
6. Se nada óbvio: page eng on-call (quando webhook configurado).

### `SLOApiAvailabilitySlowBurn` (warning)

**O que significa:** Error rate constante de ~3% por 6h. Não é fogo, mas
o budget mensal será consumido em ~5d se nada mudar.

**Resposta:** investigar no próximo turno; criar ticket; conferir se
não é uma rota específica (filtrar `http_requests_total` por path).

### `SLOApiLatencyP95High` (warning) / `SLOApiLatencyP99Critical` (critical)

**Causas comuns:**
- N+1 query (cheque slow query log).
- Connection pool saturado (`DBConnectionExhausted` provavelmente também dispara).
- Caddy upstream timeout configurado errado.

**Resposta:** Tempo traces → encontrar span lento → SQL ofensor → adicionar índice ou refatorar.

### `SLOCoreDBQueryP95High` (warning)

**O que significa:** Postgres respondendo > 100ms p95 numa query_type.

**Resposta:**
1. Identificar `query_type` no label do alert.
2. `EXPLAIN ANALYZE` da query no `pg_stat_statements`.
3. Se faltando índice: criar migration.
4. Se lock contention: cheque `pg_locks`.

### `SLODispatcherOverheadP95High` (warning)

**Causa típica:** `revoked_jtis` cresceu demais e `is_revoked()` lookup
ficou lento. Cheque `SELECT count(*) FROM revoked_jtis WHERE expires_at > now()`.
Se > 1000, validar o cleanup cron.

### `SLOPaymentsWebhookIngestFastBurn` (critical)

**MUITO CRÍTICO:** pagamentos podem estar sendo perdidos.

1. Verificar logs `viralefy-payments`.
2. Conferir tabela `idempotency_keys` — está acessível?
3. Conferir DB conn pool do payments.
4. Replay webhook do Stripe dashboard pra confirmar fix.

### `SLOPaymentsProviderConfirmRate` (warning)

**Causa típica:** flakiness do gateway externo. Conferir status pages do
Stripe/Heleket. Se persistir > 30min, investigar nossa assinatura/parser.

### `ServiceDown` (critical)

**Resposta:** `systemctl status <unit>` + `systemctl restart <unit>`. Se
não sobe: `journalctl -u <unit> -n 100`.

### `DBConnectionExhausted` (critical)

1. `SELECT pid, usename, state, query_start, query FROM pg_stat_activity ORDER BY query_start;`
2. Identificar conn leak no serviço (`application_name`).
3. Terminar conn vazada: `SELECT pg_terminate_backend(pid)`.
4. Restart o serviço causador.
5. Médio prazo: ajustar pool size ou `max_connections`.

### `DiskSpaceLow` / `DiskSpaceCritical` (critical)

1. `df -h` + `du -sh /var/lib/* /var/log/*` pra achar o culpado.
2. Suspeitos comuns: Loki logs, Tempo blocks, Postgres WAL, journal.
3. Se Loki: `loki -config.file=/etc/loki/loki.yaml -log.level=error -compactor.working-directory=...`.
4. Se journal: `journalctl --vacuum-time=7d`.

### `BackupFailed` / `RestoreDrillFailed` (critical)

Veja `RUNBOOK-BACKUP-VERIFY.md` e `RUNBOOK-DR.md`. Resumo:
- `BackupFailed`: dump corrompido ou pg_dump errou. `journalctl -u viralefy-backup-verify`.
- `RestoreDrillFailed`: restore num DB temporário falhou. `journalctl -u viralefy-restore-drill`.

### `CorazaBlockSpike` (warning)

> 5/s 403s do WAF. Possíveis causas:
- Ataque massa (bot / scanner). Conferir IPs em access log; banir via Caddy.
- False positive de regra CRS recém-promovida. Ajustar `coraza-crs-exclusions.conf`.

### `AuthBruteforce` (warning)

> 1/s 429s em `/v1/auth/*`. Cheque IPs no access log; considerar ban.

### `ReconcileCronFailed` / `PlanPriceDriftSpike` (warning)

Drifts > 5 high ou > 20 rows em plan_prices.
1. `journalctl -u viralefy-reconcile -n 50` pra ver findings.
2. Resolver root cause no SQL ou code.
3. Re-rodar manualmente: `systemctl start viralefy-reconcile`.

---

## 5. Trade-offs documentados

### Por que 99.5% e não 99.9%?

Stack single-VPS. Cada reload do Caddy, restart do Postgres pra patch,
deploy do front (rebuild Next.js) tira o serviço por 5-30s. 99.9% deixa
budget de 43min/mês — não dá.

**Quando subir pra 99.9%:**
- Caddy → 2+ instâncias atrás de IPv6 anycast (cliente forneceria).
- Postgres → réplica streaming + failover automatizado.
- Sem isso, perseguir 99.9% gera fatigue.

### Por que excluir 4xx do availability SLI?

4xx representa erro do **cliente** (token inválido, payload mal formado,
recurso não encontrado). Nosso serviço respondeu corretamente; não é
indisponibilidade. Incluímos 5xx (servidor errou) e timeouts.

### Por que payments_provider 99% e não 99.9%?

Stripe/Heleket têm flakiness próprio: ~0.1-0.5% das chamadas falham por
motivos externos (rate limit deles, transient errors). Setar 99.9% gera
falso positivo constante. 99% absorve esse ruído.

### Por que multi-window e não single-window burn rate?

Single-window (ex: 5min rolling) → flap em picos curtos.
Multi-window (1h + 5min AND) → exige que ambos detectem o problema,
reduzindo falsos positivos em > 80% (Google SRE workbook ch.5).

### Por que dispatcher overhead 50ms (não 10ms)?

Dispatcher faz JWT validate (RS256 ~1ms) + hot-set lookup (1-3ms) +
proxy round-trip pro core (5-30ms). 50ms p95 cobre tudo isso com
margem. < 10ms só com tudo em hot path; primeiro lookup miss já estoura.

---

## 6. Métricas TODO

Os SLOs abaixo dependem de métricas ainda não expostas. Alertas
correspondentes estão em `severity: info` com `absent()` no expr.

| Métrica | Onde adicionar | SLO afetado |
|---|---|---|
| `viralefy_stripe_reconcile_last_success_timestamp_seconds` (gauge) | `viralefy_core/internal/application/stripe_reconcile_cron.go` ou wrapper textfile no `viralefy-ops/bin/` | stripe_reconcile_freshness |
| `viralefy_stripe_reconcile_runs_total{result}` (counter) | idem | (dashboard payments) |
| `viralefy_revocation_propagation_seconds_bucket` (histogram) | `viralefy_api_rust` quando processa NOTIFY | revocation_propagation_p99 |
| `viralefy_revoked_jtis_count` (gauge) | textfile collector via psql query, ou auth service | TooManyRevokedJTIs |
| `viralefy_reconcile_drifts_{high,medium,low}` (gauge) | wrapper bash em `viralefy-ops/bin/viralefy-reconcile-textfile` que parsa o JSON do cron | ReconcileCronFailed |
| `probe_ssl_earliest_cert_expiry` | instalar blackbox_exporter + scrape targets | CertExpiringSoon |
| `pg_settings_max_connections` | postgres-exporter (já instalado — confirmar custom query) | DBConnectionExhausted |

---

## 7. Alertmanager

**Status:** config skeleton em `viralefy_ops/config/alertmanager.yml`, mas
NÃO INSTALADO em prod. Razão: webhook `ADMIN_WEBHOOK_URL` ainda vazio
(cliente fornece quando puder).

Até lá:
- Alertas ficam visíveis em `curl http://127.0.0.1:9090/api/v1/alerts` na VPS.
- Dashboard `viralefy-slo` (UID `viralefy-slo`) mostra "Firing alerts by severity".
- Loki coleta journal do Prometheus → busca via "firing" no Grafana.

**Próximo passo (quando cliente fornecer URL):**
1. Substituir placeholders em `alertmanager.yml`.
2. Criar systemd unit `alertmanager.service` (template comentado abaixo).
3. Adicionar bloco em `prometheus.yml`:
   ```yaml
   alerting:
     alertmanagers:
       - static_configs:
           - targets: [127.0.0.1:9093]
   ```
4. Reload Prometheus + start alertmanager.

---

## 8. Como rodar testes locais de alerta

```bash
# 1. Verificar regras carregadas
curl -s http://127.0.0.1:9090/api/v1/rules | jq '.data.groups[].name'

# 2. Forçar erros 5xx (em prod, com cuidado — usar ambiente local de preferência)
for i in $(seq 1 200); do curl -s -o /dev/null https://api.viralefy.com/v1/forcar-500-inexistente; done

# 3. Confirmar alerta dispara
curl -s http://127.0.0.1:9090/api/v1/alerts | jq '.data.alerts[] | {name: .labels.alertname, state, value}'

# 4. Parar carga → confirmar volta a OK (after for: 2m)
sleep 180
curl -s http://127.0.0.1:9090/api/v1/alerts | jq '.data.alerts[] | .labels.alertname'
```

---

## 9. Histórico de revisão

- **2026-06-10** — Criação. SLOs definidos a partir de métricas reais
  existentes + flagged métricas TODO. Dashboard `viralefy-slo` adicionado.
  Alertmanager skeleton criado, não instalado (aguarda webhook).
