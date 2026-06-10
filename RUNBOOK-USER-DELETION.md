# Runbook — Hard Delete LGPD (User Deletion Cron)

Implementação do Art. 18 IV da LGPD: execução física do direito ao
apagamento. Resolve o tech-debt declarado em
`viralefy_core/internal/application/user_data_service.go:20-21`.

## 1. Visão geral

```
POST /v1/me/data/deletion   →  grava pending + executes_at = NOW()+30d
DELETE /v1/me/data/deletion →  cancela dentro da grace window
GET /v1/me/data/deletion    →  consulta status + categorias afetadas

[systemd timer 03:45 UTC daily]
  viralefy-user-deletion.timer
        ↓
  viralefy-user-deletion.service
        ↓
  /usr/local/sbin/viralefy-user-deletion
        ↓
  SELECT … WHERE status='pending' AND executes_at <= NOW()
  → BEGIN TX por user
    → anonimiza orders (preserva fiscal 5y)
    → anonimiza audit_log (preserva imutabilidade)
    → DELETE cascading
    → status='executed', executed_at=NOW()
  → COMMIT (atômico)
```

## 2. Grace period

- Padrão: **30 dias** entre o request e a execução física.
- Constante: `deletionWindow = 30 * 24 * time.Hour` em
  `internal/application/user_data_service.go`.
- Mudar isso EXIGE: (a) update da Política de Privacidade publicada,
  (b) atualizar `TestDeletionWindowIs30Days`, (c) comunicar usuários
  com pedido pendente (vão ter janela diferente do contratado).
- Durante a grace window o usuário pode:
  - `DELETE /v1/me/data/deletion` → status vira `cancelled`, dados ficam.
  - `POST /v1/me/data/deletion` de novo → re-arma timer (UPSERT).
- Após `executed`: sem rollback. Não há recuperação (hard delete por
  design). Backups existem mas RESTAURAR um usuário deletado por LGPD é
  re-introdução de dados que o titular pediu pra remover — só com nova
  base legal explícita.

## 3. Categorias de dados — hard delete vs anonimização vs retenção

### Hard delete (rows somem)

| Tabela | Coluna de match | Motivo da exclusão |
|---|---|---|
| `users` | `id` | Identidade primária |
| `refresh_tokens` | `user_id` | Credenciais |
| `password_resets` | `user_id` | Credenciais |
| `user_2fa` | `user_id` | Credenciais |
| `api_keys` | `owner_user_id` | Credenciais |
| `profiles` | `user_id` | Dado pessoal |
| `subscriptions` | `user_id` | Relacionamento contratual |
| `user_events` | `user_id` | Comportamento |
| `user_journeys` | `user_id` | Comportamento |
| `email_events` | `email` (via snapshot) | Histórico de entrega |
| `fraud_signals` | `actor` (email) | Anti-fraude |
| `tickets` + `ticket_messages` | `user_id` / `ticket_id` | Atendimento |
| `reviews` | `user_id` | Conteúdo gerado |
| `credit_accounts` + `credit_transactions` | `user_id` | Saldo (não-fiscal) |
| `referral_rewards` (referrer/referred) | `*_user_id` | Programa de indicação |
| `users.referred_by_user_id` | apontando pro deletado | Quebra a ref pra preservar pais |

### Anonimização (rows ficam, PII removida)

| Tabela | Tratamento | Motivo |
|---|---|---|
| `orders` | `user_id = NULL`, `email_at_purchase` + `name_at_purchase` preservados | Retenção fiscal 5 anos (Receita Federal) |
| `audit_log` | `metadata.actor_email` / `target_email` / `*_name` → `"[DELETED]"` | Imutabilidade da trilha de auditoria |

### Preservado integralmente (não tocado pelo cron)

| Tabela | Motivo |
|---|---|
| `invoices` | Obrigação contábil |
| `order_refunds` | Obrigação contábil |
| `stripe_events_processed` | Idempotência de webhook (sem PII direta) |
| `user_consent_log` | Auditoria de consent — anonimizar removeria a prova de que houve consent. Mantém visitor_id; user_id fica órfão |

## 4. Métricas (textfile collector)

O cron emite `/var/lib/node_exporter/textfile_collector/viralefy_user_deletion.prom`
ao final de cada execução. node_exporter coleta automaticamente.

```
viralefy_user_deletion_executed_total            # counter — execuções OK na última passagem
viralefy_user_deletion_failed_total              # counter — execuções falhas na última passagem
viralefy_user_deletion_pending_count             # gauge   — total de pending (qualquer data)
viralefy_user_deletion_last_run_timestamp_seconds # gauge   — unix ts da última passagem
```

**Alertas recomendados (Prometheus):**

```yaml
# Pendente sem rodar → cron parado
- alert: ViralefyUserDeletionStale
  expr: time() - viralefy_user_deletion_last_run_timestamp_seconds > 28 * 3600
  for: 5m
  annotations:
    summary: "cron de hard-delete LGPD não rodou nas últimas 28h"

# Fila crescendo → cron quebrando ou DB lento
- alert: ViralefyUserDeletionBacklog
  expr: viralefy_user_deletion_pending_count > 50
  for: 24h
  annotations:
    summary: "backlog LGPD > 50 pedidos pendentes — investigar"

# Falhas na última passagem
- alert: ViralefyUserDeletionFailures
  expr: viralefy_user_deletion_failed_total > 0
  annotations:
    summary: "ao menos um hard-delete falhou — checar journal"
```

## 5. Operação manual

### Forçar execução fora do cron (pedido judicial, suporte)

```bash
# 1) Confirmar request existe e por que está pending
PGPASSWORD=... psql ... -c "
  SELECT id, user_id, status, executes_at, error_message
    FROM user_deletion_requests
   WHERE user_id = '<USER_ID>';"

# 2) Antecipa executes_at pro passado
PGPASSWORD=... psql ... -c "
  UPDATE user_deletion_requests
     SET executes_at = NOW() - INTERVAL '1 minute',
         status = 'pending', error_message = NULL
   WHERE user_id = '<USER_ID>';"

# 3) Roda o cron manualmente
sudo -u viralefy-core /usr/local/sbin/viralefy-user-deletion
```

### Dry-run (não escreve nada)

```bash
sudo -u viralefy-core DRY_RUN=1 /usr/local/sbin/viralefy-user-deletion
```

### Inspecionar histórico

```sql
-- Últimas execuções
SELECT user_id, status, requested_at, executed_at, error_message
  FROM user_deletion_requests
 ORDER BY COALESCE(executed_at, requested_at) DESC
 LIMIT 20;

-- Falhas
SELECT user_id, error_message, requested_at
  FROM user_deletion_requests
 WHERE status = 'failed'
 ORDER BY requested_at DESC;
```

### Retry de falha

Uma row `failed` pode voltar a `pending`:

```sql
UPDATE user_deletion_requests
   SET status='pending', error_message=NULL,
       executes_at=NOW() - INTERVAL '1 minute'
 WHERE id = '<REQ_ID>';
```

O cron vai pegar na próxima passagem. Se a causa raiz não foi resolvida
(ex.: schema novo sem coluna esperada), vai falhar de novo. Investigar
`journal -u viralefy-user-deletion.service` primeiro.

## 6. Idempotência

- Rodar o cron 2x não duplica nada:
  - DELETE…WHERE … é no-op quando nada bate.
  - UPDATE…SET status='executed' já no estado final.
  - User órfão (rerun pós-restore parcial) → marca request como executed
    e segue.
- A row `user_deletion_requests` SOBREVIVE ao hard-delete do user
  (a FK foi dropada em migration 043) — preserva auditoria "este UUID
  foi excluído em <data>".

## 7. Falhas comuns

| Sintoma | Diagnóstico |
|---|---|
| `error_message: ERROR ... does not exist` | Tabela ainda não migrada no host → cron ignora (defesa contra ambiente sem migration recente). Aplicar migrations e re-tentar. |
| `error_message: violates foreign key constraint` | Nova FK foi adicionada e o cron não conhece. Adicionar a tabela à lista de deletes no `cmd/user-deletion-cron/main.go`. |
| `pending_count` cresce sem parar | Timer parado (`systemctl status viralefy-user-deletion.timer`) ou cron crashando antes de processar (checar journal). |
| Falha em "users" final | FK órfã não anonimizada antes — ver lista de tabelas, adicionar deleção/anonymize correspondente. |

## 8. Recuperação se deletado errado

**Não há.** O hard-delete é definitivo by design — é o que a LGPD pede.
Único caminho:

1. Restaurar backup pgsql (RTO normal, ver `RUNBOOK-DR.md`).
2. SQL manual extraindo apenas as rows do user específico.
3. Re-inserir com `INSERT … ON CONFLICT DO NOTHING`.
4. Documentar como incidente — o titular EXPRESSAMENTE pediu o apagamento.

Se o usuário pediu por engano e ainda estiver na grace window, basta
`DELETE /v1/me/data/deletion`. Após `executed`, o pedido legítimo do
titular já foi cumprido — restaurar requer NOVA base legal explícita.

## 9. Mudar a lista de tabelas

Toda nova tabela com FK pra `users` precisa entrar em uma de 3 listas:

- **Hard delete**: adicionar entry em `deletes` no `cmd/user-deletion-cron/main.go`.
- **Anonimizar**: adicionar `UPDATE … SET … WHERE …` no bloco antes
  do loop de delete.
- **Preservar**: documentar aqui o motivo (fiscal/audit/etc.).

Após mudar a lista, rodar o test
`internal/application/user_data_service_test.go::TestDataCategoriesDeleted_*`
pra garantir que a UI fica honesta (`dataCategoriesDeleted` /
`dataCategoriesRetained` no `user_data_service.go`).
