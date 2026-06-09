# Viralefy — Fase 8: Microsserviços, mensageria e pagamentos isolados

Data **2026-06-09**. Drive: o monólito `viralefy_api` cresceu pra ~30 services + 50+ handlers e cada feature nova mexe em pontos não-relacionados (ex.: bug de Stripe no checkout vazou pra cron de retenção). Carve-out de 2 microsserviços:

1. **`viralefy_payments`** — toda a integração de gateway, providers, charges, webhooks.
2. **`viralefy_sender`** — toda a entrega de mensagem ao cliente (email, Telegram bot, futuro WhatsApp/SMS/push).

Cada um expõe API HTTP interna na rede loopback da VPS (`127.0.0.1:8081` payments, `127.0.0.1:8082` sender). API principal vira "orchestrator": orquestra fluxo de domínio, delega pagamento e mensagem.

---

## Princípios

1. **Loopback-only**. Caddy não expõe payments/sender ao mundo. API principal é o único cliente.
2. **HTTP/JSON**. Simples, debugável, mesma stack Go que o resto. gRPC fica pra Fase 9 se justificar latência.
3. **Sem DB próprio inicial**. Ambos compartilham o Postgres atual em schemas isolados (`payments.*`, `sender.*`). Migração pra DBs separados depois.
4. **Failure-friendly**. API principal continua respondendo se sender está down — mensagem cai numa fila local + retry. Pagamento é mais sensível: API exige payments healthy pra fechar pedido.
5. **Observabilidade homogênea**. Mesmo Loki, Tempo, Prometheus. Tags `service=viralefy_payments` etc.

---

## 1. `viralefy_payments`

### Responsabilidades absorvidas
- `internal/infrastructure/external/payment/{stripe,heleket,woovi,manual_pix,manual_crypto,manual_usdt}.go`
- `internal/application/payment.go` (PaymentRegistry + PaymentProvider)
- `internal/application/payment_methods.go` (listing + multi-currency expansion)
- `internal/application/gateway_service.go` (CRUD)
- `internal/domain/gateway.go` + repo postgres
- Webhook handlers (Stripe, Heleket, Woovi)
- migrations 032 + 034 (proof) + 035 (stripe events)
- Stripe key validation
- USDT-universal filtering rules
- PIX hard-block rules

### API HTTP interna (consumida pelo `viralefy_api`)

```
GET    /internal/health
GET    /internal/methods?plan_id={id}&display_currency={c}&country={cc}
       -> []PaymentMethodOption (mesma shape atual)

POST   /internal/charge
       body: { order_id, plan_id, plan_name, display_amount, display_currency,
               settlement_amount, settlement_currency,
               pay_currency, gateway_id, customer: {name, email},
               siteURL, return_paths }
       -> { provider, payment_url, payment_extra: {...}, external_ref }

POST   /internal/webhooks/stripe   (público, montado pela API via reverse-proxy)
POST   /internal/webhooks/heleket  (idem)
POST   /internal/webhooks/woovi    (idem)
  -> Após validar assinatura + idempotency, chama callback POST do API:
     POST {API_URL}/internal/payment-confirmed
     body: { external_ref, order_id, gateway_provider }
     header: X-Internal-Token: {shared secret}

CRUD admin (proxied through API):
GET    /internal/gateways
POST   /internal/gateways
PUT    /internal/gateways/{id}
DELETE /internal/gateways/{id}
```

### Schemas Postgres
- `payment_gateways` (já existe)
- `stripe_events_processed` (já existe)
- futuro: `payment_attempts` (cada CreateCharge log) pra debugging Stripe 4xx

### Estrutura de pastas
```
viralefy_payments/
├── cmd/payments/main.go
├── internal/
│   ├── config/           # endpoint, db url, internal token, providers config
│   ├── domain/           # gateway, payment_method
│   ├── application/
│   │   ├── methods.go    # ListMethodsForPlan
│   │   ├── charge.go     # CreateCharge orquestrando provider
│   │   ├── gateway.go    # CRUD
│   │   └── eligibility.go # gatewayEligible, brOnly, USDT universal
│   ├── infrastructure/
│   │   ├── external/payment/   # stripe.go, heleket.go, etc (movidos)
│   │   └── persistence/postgres/ # gateway_repo, migrations
│   └── interface/http/   # handlers internos + webhooks
├── go.mod
├── Dockerfile (futuro)
└── README.md
```

### Migração das chamadas no `viralefy_api`
- Substituir `payments.Get(provider).CreateCharge(...)` por `paymentsClient.Charge(...)`.
- Substituir `application.ListPaymentMethods(...)` por `paymentsClient.Methods(...)`.
- Substituir handlers de webhook por reverse-proxy via Caddy (`api.viralefy.com/v1/webhooks/stripe` → `127.0.0.1:8081/internal/webhooks/stripe`).
- Manter `PaymentReceiver.MarkOrderPaid` no monolito — é regra de domínio do pedido.

---

## 2. `viralefy_sender`

### Responsabilidades absorvidas
- `internal/infrastructure/external/email/*` (Resend + SMTP)
- `internal/application/email.go` + `email_template.go`
- `notify.WebhookClient` (admin webhook)
- Templates de email (checkout, refund, proof rejection)
- Futuro: Telegram bot, WhatsApp Cloud API, SMS

### Novas funcionalidades
- **Email "compra confirmada"** — disparado por `PaymentReceiver.MarkOrderPaid`. Template novo, separado do "checkout created".
- **Telegram bot notifications** — admin tem chat_id do bot configurado; receber notificação a cada paid order. Cliente que tiver telegram cadastrado recebe template separado.

### API HTTP interna

```
GET    /internal/health
POST   /internal/send
       body: { channel: "email"|"telegram"|"webhook",
               template: "checkout_paid"|"proof_rejected"|"refund_issued"|...,
               to: {email, telegram_handle, webhook_url},
               vars: {...},
               attempt_id: uuid (idempotency),
               priority: "high"|"normal" }
       -> { status: "queued"|"sent"|"failed", attempt_id }

POST   /internal/telegram/webhook  (push do Telegram Bot API)
       -> Captura interação inbound (cliente respondeu, comando /start, etc).
```

### Telegram Bot Architecture

1. Admin cria bot via @BotFather na Telegram, copia token.
2. Cadastra em `/sender/admin/telegram-config` (backoffice):
   - `bot_token` (segredo)
   - `admin_chat_id` (canal de notificação interna)
   - Configurações de templates por evento.
3. Sender expõe `/internal/telegram/webhook` que registra com `setWebhook` da Telegram API.
4. Cliente vincula handle no register; quando bot recebe `/start` de qualquer handle, salva chat_id em `user_telegram_chats`.
5. Envio: `POST /internal/send {channel: telegram, to: {telegram_handle: "@user"}, template: ..., vars: ...}`. Sender resolve chat_id pela tabela e dispara via Bot API.

### Schemas Postgres
- `sender_outbox` — fila persistente. Cada send vira row, status enqueued → in_flight → sent / failed.
- `sender_attempts` — log de tentativas (retry + observability).
- `telegram_chats` — vincula telegram handle ↔ chat_id (capturado no /start).
- `telegram_config` — bot tokens, admin chat ids.
- Templates ficam em arquivos `*.gohtml` no repo, não no DB (versão atrelada ao deploy).

### Fluxo retry
- enqueued → tick a cada 30s pra rodar batch.
- Falha: incrementar attempt_count, exponential backoff (30s → 5min → 1h → 6h → 24h, max 5 tentativas).
- Status final: sent ou failed-final. Failed-final gera alerta no admin_webhook + Sentry.

---

## 3. Microservice contracts

### Shared types (sync via codegen ou copy-paste pragmático inicialmente)

```
type PaymentMethodOption struct { ... } // exato como hoje, ambos serializam
type ChargeRequest struct { OrderID, GatewayID, PayCurrency, Amount, Currency, ... }
type ChargeResponse struct { PaymentURL, PaymentExtra, ExternalRef, Provider }
type SendRequest struct { Channel, Template, To, Vars, AttemptID, Priority }
type SendResponse struct { Status, AttemptID }
```

### Internal auth
- Variável `INTERNAL_SHARED_SECRET` no `/etc/viralefy/.env`, gerada pelo installer.
- Cada request entre services carrega `X-Internal-Token: $INTERNAL_SHARED_SECRET`.
- Middleware rejeita 401 quando ausente ou diff.
- Loopback-only mitiga a maior parte; token é defense-in-depth.

### Versioning
- Path `/internal/v1/...` desde dia 1. Mudança de contrato bumpa `/internal/v2/...`. Old service rola junto durante migração.

---

## 4. Infraestrutura

### systemd units novas
- `/etc/systemd/system/viralefy-payments.service` (binário em `/usr/local/sbin/viralefy-payments`).
- `/etc/systemd/system/viralefy-sender.service` idem.
- Mesmas hardening flags do `viralefy-api.service` (NoNewPrivileges, ProtectSystem, etc).
- Logs vão pro journald → Alloy → Loki, com tag `service`.

### Caddy
- Adicionar `handle_path` no `Caddyfile` pra reverse-proxy de webhooks externos:
  ```
  handle_path /v1/webhooks/stripe* {
    reverse_proxy 127.0.0.1:8081
  }
  ```
- Resto do tráfego externo continua em api.viralefy.com → 8080.

### Build no `viralefy_ops/installer/50-build.sh`
- Adicionar build de `viralefy_payments` e `viralefy_sender`.
- Versionamento: mesmo APP_VERSION pra todos.

### Migrations
- `viralefy_payments` é dono das migrations 032/034/035.
- `viralefy_sender` ganha migrations próprias 001-XXX (numeração isolada).
- API monolito perde essas tabelas do escopo de migration (move pra outros repos).
- Postgres roles separadas? Por ora um único role `viralefy`. Schema-level ownership.

---

## 5. viralefy_api (monolito refatorado)

### Sobra no monolito
- Domínio: User, Order, Plan, Profile, Coupon, Referral, A/B, Subscription, Vendor, APIKey, Review, Ticket, Audit, UserEvent, TaxRate, CountryPPP, Credit.
- Services: tudo que não é payment/email.
- `PaymentReceiver.MarkOrderPaid` (domínio do pedido) chama:
  - `payments.MarkAsPaid` (registro local)
  - `sender.Send({template: "checkout_paid", channel: "email"})`
  - `sender.Send({template: "purchase_admin_alert", channel: "telegram", to: admin_chat_id})`
  - Se cliente tem telegram: `sender.Send({template: "purchase_customer_confirmation", channel: "telegram", to: customer_handle})`

### Cliente HTTP dos microservices
- `internal/infrastructure/external/payments/client.go` (wrapper http.Client)
- `internal/infrastructure/external/sender/client.go` (idem)
- Implementam a porta application.PaymentProvider/EmailSender (já existem) — substituem in-memory por HTTP.

---

## 6. Novos templates de mensagem

### Email
- `checkout_paid` (cliente) — substitui o atual de "order created" quando MarkOrderPaid finaliza.
- `checkout_paid_admin` (admin) — notificação interna que alguém comprou.
- `proof_rejected` (já existe — migra para o sender).
- `refund_issued` (já existe — migra para o sender).
- Futuro: `subscription_renewed`, `password_changed`, `2fa_enabled`.

### Telegram
- Bot config: nome, descrição, comandos (/start, /pedidos, /suporte).
- Templates Markdown V2:
  - `checkout_paid_admin_telegram`:
    > 💰 *Nova venda*
    > Plano: {plan_name}
    > Valor: {settlement_amount} {settlement_currency}
    > Cliente: {customer_email}
    > Order: {order_short_id}
  - `checkout_paid_customer_telegram`:
    > ✅ *Pagamento confirmado*
    > Pedido #{order_short_id} — {plan_name}
    > Estamos processando — atualização em até 30min.
  - `proof_rejected_customer_telegram`:
    > ⚠ *Comprovante precisa ser revisado*
    > Order #{order_short_id}
    > Motivo: {note}
    > Reenvie pelo app.

---

## 7. Sequência de implementação (Workflow multi-agent)

### Wave 1 — scaffolding (paralelo)
- Agent A: cria estrutura `viralefy_payments` (dirs, go.mod, main.go skeleton, README, Dockerfile placeholder).
- Agent B: cria estrutura `viralefy_sender` (idem).
- Agent C: ajusta `viralefy_ops` (systemd units, installer build steps, env.template, Caddyfile reverse-proxy).
- Agent D: cria stubs de cliente HTTP no `viralefy_api`.

### Wave 2 — extração (paralelo)
- Agent E: move providers + payment_methods + gateway_service pro `viralefy_payments` + cria handlers internos. Smoke test local.
- Agent F: move email + templates pro `viralefy_sender` + cria handlers internos. Adapta sender.outbox + retry.
- Agent G: adiciona migration `sender_outbox` + telegram_config + telegram_chats no `viralefy_sender`.
- Agent H: implementa template `checkout_paid` (email + telegram) + integração com bot Telegram.

### Wave 3 — integração (paralelo)
- Agent I: substitui chamadas in-memory por HTTP client nos handlers/services do monolito.
- Agent J: monta novos handlers em monolito pra audit dos novos `/internal/payment-confirmed` callbacks.
- Agent K: smoke test E2E (subir 3 services, simular checkout Stripe, verificar email + telegram).
- Agent L: atualiza CONTEXT.md / CHECKLIST.md / ROADMAP.md.

### Wave 4 — observabilidade
- Agent M: Grafana dashboard novo: "Payments throughput" + "Sender outbox depth". Alerts.

---

## 8. Riscos & mitigações

| Risco | Mitigação |
|---|---|
| Bug em microservice derruba a venda | Health check antes de checkout submit; fallback in-memory pra Sender (não bloqueia). |
| Latência extra (3 services chamando-se) | Loopback HTTP < 1ms. Aceitável. |
| Migration sequence quebrada | Cada service roda suas migrations no boot, ordem deterministica via numeração. |
| Webhook reentrega antes do callback monolito | Sender retry + idempotency_key. Payments idempotency em stripe_events_processed. |
| Deploy ordem importa (sender precisa estar up antes do API) | systemd Wants/After deps no `viralefy-api.service`. |
| Senha do bot Telegram vazada | Token criptografado AES-256 com `TWOFA_ENCRYPTION_KEY` (mesma key, escopo diferente). |
| Telegram API rate limit | Sender outbox tick respeita 30 req/s; backoff em 429. |

---

## 9. Cronograma & marcos

| Marco | Quem | Duração |
|---|---|---|
| Wave 1 scaffolding | Agents A-D paralelos | 1 sprint (1d) |
| Wave 2 extração | Agents E-H paralelos | 2 sprints (3d) |
| Wave 3 integração + smoke | Agents I-L paralelos | 1 sprint (1d) |
| Wave 4 dashboards | Agent M | 0.5 sprint |
| Deploy em prod (rolling) | Manual | 1h |

Total: ~5-7 dias úteis, paralelizado entre agents.

---

## 10. Métricas de done

- [ ] `viralefy_payments` rodando em prod, processando checkout Stripe end-to-end
- [ ] `viralefy_sender` rodando em prod, despachando emails + Telegram
- [ ] `viralefy_api` perde dependência direta de Stripe SDK / Resend SDK
- [ ] Health check trifásico em `viralefy-status` (api, payments, sender)
- [ ] Email + Telegram disparado em cada paid order
- [ ] Bug de Stripe 422 não pode reaparecer — coberto por integration test
- [ ] CONTEXT.md atualizado refletindo arquitetura nova
- [ ] CHECKLIST PHASE-7 + PHASE-8 reconciliado

---

## Links

- [CONTEXT.md](CONTEXT.md) — snapshot atual
- [PHASE-7-PLAN.md](PHASE-7-PLAN.md) — sprints 1-6 anteriores
- [ROADMAP.md](ROADMAP.md) — visão histórica
- [RUNBOOK.md](RUNBOOK.md) — operação prod
