# MICROSERVICES-OPS — runbook curto da Fase 8

Snapshot **2026-06-09**. Companheiro de [PHASE-8-MICROSERVICES.md](PHASE-8-MICROSERVICES.md)
(plano arquitetural) e [RUNBOOK.md](RUNBOOK.md) (ops geral). Aqui só o
"como faço pra X" do dia-a-dia com os 3 binários.

## Topologia rápida

| Service | Porta | Bin path | systemd unit |
|---|---|---|---|
| viralefy-api       | 127.0.0.1:8080 | `/viralefy/api/bin/viralefy-api`   | `viralefy-api.service` |
| viralefy-payments  | 127.0.0.1:8081 | `/usr/local/sbin/viralefy-payments` | `viralefy-payments.service` |
| viralefy-sender    | 127.0.0.1:8082 | `/usr/local/sbin/viralefy-sender`   | `viralefy-sender.service` |

Caddy só expõe `viralefy-api` (`api.viralefy.com`). Webhooks externos
(Stripe etc.) entram via Caddy `handle_path /v1/webhooks/* → 127.0.0.1:8081`.
Auth interna: header `X-Internal-Token: $INTERNAL_SHARED_SECRET` em todo
request entre services.

---

## 1. Como adicionar uma nova migration (payments OU sender)

Regra de ouro: **migrations dos microservices são 100% idempotentes**.
Em prod o Postgres é compartilhado com o monólito; nada pode quebrar se a
tabela/coluna já existe.

### Payments

```bash
cd viralefy_payments/internal/infrastructure/persistence/postgres/migrations/
# Next number depois do último (atualmente 001_payments_init)
$EDITOR 002_<short_name>.up.sql
$EDITOR 002_<short_name>.down.sql
```

Template up:

```sql
-- 002_<short_name>.up.sql
-- O que faz, por quê. Sempre idempotente.
BEGIN;

-- Nova tabela exclusiva do payments:
CREATE TABLE IF NOT EXISTS payment_attempts (
    id          TEXT PRIMARY KEY,
    order_id    TEXT NOT NULL,
    provider    TEXT NOT NULL,
    payload     JSONB NOT NULL,
    status      TEXT NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
CREATE INDEX IF NOT EXISTS idx_pay_attempts_order
    ON payment_attempts(order_id, created_at DESC);

-- Coluna em tabela compartilhada (CUIDADO: tabela é dona do monólito):
-- ALTER TABLE payment_gateways ADD COLUMN IF NOT EXISTS soft_deleted_at TIMESTAMPTZ;

COMMIT;
```

**Não toque** o monólito a partir do payments. Se precisa mudar shape de
tabela compartilhada (payment_gateways, orders, etc.), abra a migration no
**viralefy_api** e no payments só leia.

### Sender

Mesmo padrão; numeração começa em `001_sender_outbox` / `002_telegram_chats`.
Tabelas do sender (`sender_outbox`, `sender_attempts`, `telegram_chats`,
`telegram_config`) são exclusivas — pode usar `CREATE TABLE IF NOT EXISTS`
sem medo.

### Aplicar / testar

Cada binário roda suas migrations no boot (golang-migrate embedded). Para
testar localmente:

```bash
# Postgres local na 15432 (stack viralefy local)
DATABASE_URL='postgres://viralefy:viralefy@127.0.0.1:15432/viralefy?sslmode=disable' \
  /viralefy/payments/bin/viralefy-payments --migrate-only
```

Em prod, o `viralefy-update` re-builda + reinicia → o boot do payments roda
as migrations automaticamente. Falha de migration aborta o boot, healthcheck
da Wave de update falha, rollback automático.

---

## 2. Como debugar uma payment failure

Sintoma típico: cliente vê erro no checkout step "instructions" OU
order fica em `pending` eternamente apesar do cliente ter pago.

### Passo 1 — qual service?

```bash
journalctl -u viralefy-api -n 200 --no-pager | grep -iE 'payment|charge|webhook'
journalctl -u viralefy-payments -n 200 --no-pager
journalctl -u viralefy-sender -n 50 --no-pager  # confirma email saiu
```

Cada log tem `service=viralefy-<x>` graças ao Alloy scrape config.

### Passo 2 — onde quebrou?

| Sintoma na API | Onde olhar | Causa típica |
|---|---|---|
| `payments client: 500` | journalctl payments | provider API quebrada, secret inválido |
| `payments client: 401` | `/etc/viralefy/.env` | `INTERNAL_SHARED_SECRET` dessincronizado entre services (re-restart os 3) |
| `payments client: connection refused` | `systemctl status viralefy-payments` | service down — `systemctl start viralefy-payments` |
| `MarkOrderPaid` nunca dispara | journalctl payments | webhook Stripe não bateu OU assinatura inválida; ver `gateway_callbacks_total` em Prometheus |
| order paid mas sem email | journalctl sender | outbox row em `failed_final`; consultar `SELECT * FROM sender_outbox WHERE order_id=...` |

### Passo 3 — replay seguro

- **Stripe webhook**: `stripe_events_processed` tem `event_id` PK. Para
  re-processar manualmente, `DELETE FROM stripe_events_processed WHERE event_id='evt_xxx'`
  e usar o dashboard Stripe pra reenviar. PaymentReceiver.MarkOrderPaid é
  idempotente.
- **Sender retry**: `UPDATE sender_outbox SET status='enqueued', next_attempt_at=NOW(), attempt_count=0 WHERE id='...'`. Próximo tick (30s) pega.

### Passo 4 — Prometheus

Métricas-chave:
- `viralefy_payments_charges_total{provider,status}`
- `viralefy_payments_webhook_total{provider,status}` (status: ok|invalid_sig|duplicate)
- `viralefy_sender_outbox_depth{status}`
- `viralefy_sender_send_total{channel,status}`

---

## 3. Como rotacionar `INTERNAL_SHARED_SECRET`

Os 3 services lêem o secret no boot e mantêm em memória. Trocar exige
restart sincronizado (sem isso, api fala com payments usando token novo e
toma 401 → checkout quebra por ~30s).

```bash
# 1. Gera novo secret (32 bytes hex)
NEW_SECRET="$(openssl rand -hex 32)"

# 2. Atualiza /etc/viralefy/.env (mode 0640 root:viralefy)
sudo sed -i.bak "s|^INTERNAL_SHARED_SECRET=.*|INTERNAL_SHARED_SECRET=$NEW_SECRET|" /etc/viralefy/.env
sudo chmod 0640 /etc/viralefy/.env
sudo chown root:viralefy /etc/viralefy/.env

# 3. Restart sincronizado — todos juntos, ordem não importa pois ficam ~2s down
sudo systemctl restart viralefy-payments viralefy-sender viralefy-api

# 4. Confirma health + smoke
sudo viralefy-smoke
```

Janela de erro: ~3-5s entre stop do api e up dos 3. Aceitável fora de horário
de pico. Para zero-downtime real precisaria dual-secret no middleware (Phase 9).

**Auditoria**: deixa `.bak` por 24h pra rollback rápido. Depois `shred -u`.

---

## 4. Como testar Telegram bot integration local

Pré-req: bot criado via @BotFather (token formato `123456:ABC-DEF...`),
`admin_chat_id` conhecido (envie qualquer msg pro bot e cheque
`https://api.telegram.org/bot<TOKEN>/getUpdates`).

### Setup local

```bash
cd viralefy_sender
export DATABASE_URL='postgres://viralefy:viralefy@127.0.0.1:15432/viralefy?sslmode=disable'
export INTERNAL_SHARED_SECRET='local-dev-token-not-prod'
export TWOFA_ENCRYPTION_KEY="$(openssl rand -hex 32)"
export TELEGRAM_BOT_TOKEN='123456:ABC-DEF...'
export PORT=8082
go run ./cmd/sender
```

### Webhook do Telegram → sender local (ngrok)

Telegram só fala HTTPS pública. Use ngrok:

```bash
ngrok http 8082
# anota URL https://xxxx.ngrok.io
curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -d "url=https://xxxx.ngrok.io/internal/telegram/webhook"
```

Agora mande `/start` pro bot no Telegram. Sender deve logar a captura do
`chat_id` e salvar em `telegram_chats`:

```sql
SELECT * FROM telegram_chats;
```

### Disparar envio de teste

```bash
curl -s -X POST http://127.0.0.1:8082/internal/v1/send \
  -H "X-Internal-Token: $INTERNAL_SHARED_SECRET" \
  -H 'Content-Type: application/json' \
  -d '{
    "channel": "telegram",
    "template": "checkout_paid_admin_telegram",
    "to": {"telegram_handle": "@seuhandle"},
    "vars": {
      "plan_name": "Test Plan",
      "settlement_amount": "10.00",
      "settlement_currency": "USDT",
      "customer_email": "test@example.com",
      "order_short_id": "abc123"
    },
    "attempt_id": "'"$(uuidgen)"'",
    "priority": "high"
  }'
```

Deve chegar no Telegram em <2s. Conferir `sender_outbox`:

```sql
SELECT id, channel, template, status, attempt_count, last_error
FROM sender_outbox ORDER BY created_at DESC LIMIT 5;
```

### Limpar e voltar pra config de prod

```bash
curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/deleteWebhook"
# Re-set webhook pra URL de prod:
curl -s "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/setWebhook" \
  -d "url=https://api.viralefy.com/internal/telegram/webhook"
```

---

## Quick reference

```bash
# Status global
viralefy-status

# Smoke check (3 healths + endpoints chave)
viralefy-smoke

# Logs por service
viralefy-logs api
viralefy-logs payments
viralefy-logs sender

# Deploy zero-downtime
viralefy-update --yes

# Restart individual sem afetar os outros
systemctl restart viralefy-payments

# Conferir versões em prod
/usr/local/sbin/viralefy-payments --version
/usr/local/sbin/viralefy-sender --version
/viralefy/api/bin/viralefy-api --version
```
