# ADR-0010 — Stripe + Heleket + AbacatePay com Anti-Corruption Layer parcial

- **Status:** accepted
- **Data:** 2026-06-11
- **Decisores:** Equipe Viralefy
- **Diretriz relacionada:** §4 (Anti-Corruption Layer obrigatório em integrações externas)
- **Reavaliação:** 2026-12

## Contexto e Problem Statement

A diretriz §4 estabelece:

> **MUST em integrações com sistemas externos:** adapter dedicado em `infrastructure/external/` que traduz o modelo externo para o modelo de domínio. **Nunca** expor DTOs externos diretamente no domínio.

Estado atual (2026-06-11):

**Providers ativos:**

- **Stripe** — `rk_live_*`, cartão internacional, webhook em `api.viralefy.com/v1/webhooks/stripe`.
- **Heleket** — crypto, USDT settlement.
- **AbacatePay** — PIX dinâmico (BR).
- **manual_pix** — desativado (preserva orders legados).
- **woovi** — inativo.

**Estrutura de código** (em `viralefy_payments/internal/infrastructure/external/payment/` e espelhado em `viralefy_core` legacy path):

```
external/payment/
├── stripe.go          (292 linhas)
├── stripe_test.go     (204 linhas)
├── abacatepay.go      (289 linhas)
├── abacatepay_test.go (130 linhas)
├── heleket.go
├── woovi.go
├── manual.go
├── manual_crypto.go
├── manual_usdt.go
└── webhooks.go
```

Cada arquivo é um adapter dedicado por provedor. Bom sinal. Porém, verificação rápida levanta dúvidas:

- **Não confirmado em revisão profunda** se DTOs do Stripe (ex.: `stripe.CheckoutSession`) atravessam até `domain/`.
- **Webhook handlers** (`webhooks.go`) podem manipular shape externo diretamente antes de mapear.

## Decision Drivers

- Cada provider tem ciclo de quebras de API próprio (Stripe muda formato sutilmente; AbacatePay pode renomear campos).
- Domínio não deve "saber" se pagamento veio de Stripe ou Heleket — apenas que existe um `Payment` com estado, valor, gateway, identificador externo.
- Testes existem para Stripe e AbacatePay (good).

## Considered Options

### Option A — Auditar e corrigir leaks de DTOs externos, manter adapters atuais

**Prós:** baixa fricção, mantém estrutura.
**Contras:** trabalho de revisão file-by-file.

### Option B — Refactor para interface `PaymentProvider` explícita no `domain/` + adapters implementam

Já parcialmente feito (existe `application/gateway_service.go`). Formalizar.

**Prós:** §4 cumprida estritamente.
**Contras:** custo de refactor médio.

### Option C — Aceitar status quo (não auditar)

**Prós:** zero esforço.
**Contras:** dívida silenciosa, futuro provider novo herda o problema.

## Decision Outcome

**Aceito padrão atual com plano de auditoria.** O layout de `internal/infrastructure/external/payment/` **já segue ACL** estruturalmente. O que falta é validação formal de que **nenhum DTO externo vaza para `application/` ou `domain/`**.

### Compromissos

1. **Estrutura física** já cumpre §4 (adapters em `infrastructure/external/`).
2. **Webhook handlers** ficam em `interface/http/` ou `infrastructure/external/payment/webhooks.go` — devem traduzir para tipo de domínio antes de chamar `application/`.
3. **Novo provider** SEMPRE entra como adapter dedicado, com testes de mapping bidirecionais.

### Action items (auditoria pendente)

- [ ] **Audit Stripe:** verificar se `domain/` ou `application/` importam `github.com/stripe/stripe-go`. Esperado: zero — só `infrastructure/external/payment/stripe.go`.
- [ ] **Audit AbacatePay/Heleket:** mesma verificação.
- [ ] **Webhook flow:** garantir que `webhooks.go` desserializa para tipo do provedor, mapeia para domain event (ex.: `PaymentConfirmed{OrderID, Amount, Provider}`), e chama `application.PaymentReceiver.Handle(ctx, evt)` — não passa DTO externo adiante.
- [ ] **Linter custom** (ou go-arch-lint): blacklist de imports de `stripe-go`, `abacatepay-*` em `internal/domain/` e `internal/application/`.
- [ ] **Documentar contract** de cada provider em `viralefy_payments/docs/providers/<name>.md`.

### Verificação rápida (executar antes de fechar action items)

```bash
# Em viralefy_payments/ e viralefy_core/:
grep -rE "stripe-go|abacatepay" internal/domain/ internal/application/
# Esperado: zero hits
```

## Triggers para Reabrir

- Novo provider adicionado sem adapter dedicado.
- Audit revela DTO externo em `domain/` (= breaking refactor obrigatório).
- Provider muda API e quebra integração porque mapping não estava isolado.

## Consequences

### Positivas

- Estrutura física já correta — risco baixo de regressão.
- Adapter por provider permite swap (ex.: substituir Heleket por outro crypto gateway sem tocar core).

### Negativas

- Auditoria pendente é dívida.
- Sem linter, regressão depende de code review humano.

## Links

- Diretrizes §4 (ACL)
- `viralefy_payments/internal/infrastructure/external/payment/`
- `viralefy_payments/internal/application/gateway_service.go`
- `viralefy_core/internal/infrastructure/external/payment/`
- ADR-0002 (HTTP loopback) — relacionada à comunicação core→payments
