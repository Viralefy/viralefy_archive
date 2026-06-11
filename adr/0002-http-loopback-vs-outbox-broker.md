# ADR-0002 — HTTP loopback sync em vez de Outbox Pattern + NATS/Kafka

- **Status:** accepted
- **Data:** 2026-06-11
- **Decisores:** Equipe Viralefy
- **Diretriz violada:** §9 (Transactional Outbox obrigatório, brokers NATS/Kafka)
- **Reavaliação:** 2026-12 ou no trigger documentado abaixo

## Contexto e Problem Statement

A diretriz §9 estabelece:

- "Transactional Outbox para publicação de eventos. Dual-write (banco + broker no mesmo fluxo) é proibido."
- "Brokers: NATS (eventos leves) / Kafka (alto throughput)."
- "Consumidores idempotentes, DLQ configurada, retry com limite."

Estado atual (2026-06-11):

- Comunicação inter-service via **HTTP loopback síncrono** em `127.0.0.1` com `INTERNAL_SHARED_SECRET`:
  - `viralefy_core` → `viralefy_payments` (porta 8081) — criar checkout sessions, capturar webhooks
  - `viralefy_core` → `viralefy_sender` (porta 8082) — enviar emails transacionais
  - `viralefy_core` → `viralefy_auth` (porta 8083) — validar tokens
- Existe **uma tabela outbox**: `sender_outbox` em `viralefy_sender`, usada como work-queue interna do próprio sender (não como evento pub/sub).
- Existe **trilha de auditoria imutável**: tabela `audit_log` (migration 012), append-only.
- Nenhum broker (NATS/Kafka) está rodando.
- Stripe webhook é assíncrono inerentemente — entrega via HTTPS pública, processado em `viralefy_payments`.

## Decision Drivers

- Volume de eventos críticos: poucos por minuto (checkout iniciado, payment confirmed, user deleted, password reset email).
- Consumidores por evento: 1 (não há fan-out).
- Latência loopback: ~1ms; broker introduziria 5-20ms.
- Custo operacional de adicionar NATS/Kafka: novo processo, monitoramento, backup, alertas, RBAC, segredos.
- Footprint de RAM já alto (~260MB apps + 1.2GB observability) em VPS única.

## Considered Options

### Option A — Implementar Outbox + NATS imediatamente

Padrão da casa. Cumprir §9 100%.

**Prós:** conforme diretriz, desacoplamento real, retry/DLQ nativo.
**Contras:** +1 processo crítico (NATS server), ~+100MB RAM, complexidade de bootstrap (auth+stream config), latência adicional para fluxos onde resposta síncrona já é aceitável.

### Option B — Manter HTTP loopback sync + outbox pontual para o que já existe (status quo)

**Prós:** simples, baixíssima latência, zero infra adicional.
**Contras:** dual-write implícito (DB + HTTP) em alguns fluxos, falha de um serviço bloqueia o caller, sem replay/DLQ universal.

### Option C — Outbox table genérica + worker poller, sem broker

Tabela `event_outbox` com `outbox_publisher` poller que faz HTTP POST nos consumidores.

**Prós:** padrão Outbox cumprido sem broker, retry persistente, replay possível, zero novo processo (vira goroutine).
**Contras:** ainda HTTP no consumo, eventual fan-out manual.

## Decision Outcome

**Escolhida: Option B no curto prazo, Option C planejada para fase 2.**

Razões para B agora:

1. **Volume não justifica broker.** Stripe webhook (o único async crítico) já é entregue por HTTPS externo com retry do próprio Stripe.
2. **Loopback síncrono é simples e auditável.** `paymentsclient` e `senderclient` são ~100 linhas cada, com timeouts explícitos e logs estruturados.
3. **`sender_outbox` já cobre o caso mais sensível** (emails): worker persiste antes de tentar entrega, com retry e estado.
4. **`audit_log` cobre trilha imutável** para mudanças críticas (RBAC, financeiro, admin actions) conforme §16.6.

## Triggers para Reavaliação (Option A/C se torna obrigatória)

- > 100 events/sec sustained.
- 2+ consumers por evento (fan-out real).
- Necessidade de replay histórico (compliance, debugging em produção).
- Adoção de event sourcing em qualquer bounded context.
- Incidente de perda de evento por crash entre DB commit e HTTP call.

## Action items

- [ ] **Curto prazo:** documentar em CONTEXT.md a lista de eventos cross-service atuais (checkout, payment, sender, auth) e a semântica de cada chamada loopback.
- [ ] **Curto prazo:** garantir que toda chamada loopback tem timeout explícito + circuit breaker leve (já implementado parcialmente).
- [ ] **Médio prazo (Option C):** generalizar pattern do `sender_outbox` em uma tabela `event_outbox` no `viralefy_core` para eventos críticos identificados como candidatos a perda (payment_confirmed, user_deleted).
- [ ] **Longo prazo:** quando trigger acionar, plano: NATS standalone no mesmo VPS → consumer migration por evento → desativar HTTP loopback síncrono onde aplicável.

## Consequences

### Positivas

- Latência mínima nos fluxos críticos (checkout → payment ~1-5ms).
- Stack simples de operar em VPS única.
- Stripe webhook resilience já garantido pelo provider externo.

### Negativas

- **Acoplamento temporal:** se `viralefy_sender` está down, emails não saem e cliente não tem confirmação imediata (mitigado por `sender_outbox` que persiste e retenta).
- Sem replay universal — debug retroativo de eventos perdidos exige análise de logs estruturados.
- Dual-write parcial em fluxos como "criar order + enviar email": se o email falha após commit, fica órfão (mitigado parcialmente por outbox do sender; ainda não cobre payments).

### Mitigações

- Cada client loopback tem **timeout + retry com backoff** + log estruturado com `correlation_id`.
- Métricas `RED` por endpoint inter-service expostas em `/internal/metrics`.
- `audit_log` registra ações críticas independente de o consumer downstream estar saudável.

## Links

- Diretrizes §9, §16.6
- `viralefy_core/internal/infrastructure/external/paymentsclient/`
- `viralefy_core/internal/infrastructure/external/senderclient/`
- `viralefy_sender/internal/application/outbox.go`
- ADR-0001 (shared DB) — relacionada
