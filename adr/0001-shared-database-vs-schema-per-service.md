# ADR-0001 — Shared database em vez de schema-per-service

- **Status:** accepted
- **Data:** 2026-06-11
- **Decisores:** Equipe Viralefy
- **Diretriz violada:** §2 (banco compartilhado proibido), §10 (schema próprio por serviço)
- **Reavaliação:** 2026-12 ou no trigger documentado abaixo

## Contexto e Problem Statement

A diretriz §10 estabelece "Schema próprio por serviço. Sem joins cross-service no banco." e §2 reforça "Comunicação entre serviços via HTTP, gRPC, eventos ou mensageria — nunca via banco compartilhado."

Estado atual (2026-06-11):

- **Todos os 5 serviços Go** (`viralefy_api` legacy, `viralefy_core`, `viralefy_auth`, `viralefy_payments`, `viralefy_sender`) apontam para a **mesma database `viralefy`** no mesmo cluster Postgres 16.
- 43 migrations sequenciais no diretório do `viralefy_core` cobrem ~49 tabelas; `viralefy_auth`, `viralefy_payments` e `viralefy_sender` reaproveitam tabelas existentes (`users`, `orders`, `revoked_jtis`, `sender_outbox`, etc.).
- `viralefy_auth` declara explicitamente no `config.go` que `DATABASE_URL` é **compartilhado com core**.
- Não há joins cross-context declarados, mas **não há barreira física** que impeça um serviço de ler tabela de outro.

## Decision Drivers

- Escala atual: VPS única (8c/16GB), <100k req/dia, faturamento confirmado mas pequeno.
- Custo operacional: migrar para schemas separados exige (a) refatorar 43 migrations, (b) duplicar lookup tables (users, currencies, países), (c) migrar dados em produção live.
- Reversibilidade: cada serviço pode ser isolado em schema próprio quando justificado pelo crescimento.
- Defense-in-depth atual: cada serviço só expõe seus endpoints; isolamento aplicado em camada HTTP via dispatcher + tokens compartilhados (`INTERNAL_SHARED_SECRET`).

## Considered Options

### Option A — Migrar para schemas separados (`viralefy_core`, `viralefy_auth`, `viralefy_payments`, `viralefy_sender`)

**Prós:** conforme §10, isolamento físico, menor blast radius por bug.
**Contras:** custo de migration em produção live, downtime ou janela de cutover complexa, necessidade de réplicas read-only para queries cross-context.

### Option B — Aceitar desvio com plano de migration futuro acionado por trigger

**Prós:** zero custo de migration, mantém velocidade de delivery do MVP.
**Contras:** dívida arquitetural, possível acoplamento implícito por dados.

### Option C — Bancos separados (databases distintos no mesmo cluster)

**Prós:** isolamento mais forte que schema, ainda viável em VPS única.
**Contras:** mesmo custo de migração que Option A, sem o ganho de futuras réplicas leitoras unificadas.

## Decision Outcome

**Escolhida: Option B — Aceitar desvio justificado.**

Razões:

1. **Scale atual não justifica complexidade.** A regra existe para evitar acoplamento via banco em arquiteturas de alta escala/equipes paralelas. Hoje a Viralefy roda em VPS única com 1 squad.
2. **Defense-in-depth aplicado em camada HTTP.** Dispatcher Rust + RBAC + INTERNAL_SHARED_SECRET + Coraza WAF garantem que vazamento entre contextos exige bug deliberado em código de serviço, não em rede.
3. **Migrations centralizadas reduzem drift** durante fase de evolução rápida do MVP.

## Triggers para Reavaliação (Option A volta a ser candidata)

Re-abrir esta ADR quando **qualquer** dos itens for verdadeiro:

- Volume > 5M req/dia sustentado por 30+ dias.
- Compliance enterprise exige isolamento físico (cliente B2B SOC2/ISO).
- Equipe cresce para 3+ squads independentes (squad por bounded context).
- Incidente confirmado por acoplamento de dados cross-context (bug que leu tabela de outro serviço por engano).
- Necessidade de réplicas read-only por bounded context para escala de leitura.

## Consequences

### Positivas

- Custo de manutenção baixo no momento.
- Migrations versionadas centralmente, mais simples de raciocinar.
- Joins ad-hoc para análise (reconcile, debug) viáveis sem ETL.

### Negativas

- Risco de regressão por engano: dev pode adicionar query cross-context sem perceber.
- Mitigação parcial: **revisão de PR vigilante para imports de repos de outro contexto** (`code-review` skill cobre isso). Idealmente migrar para um **linter custom** (gosec/staticcheck rule) que rejeite import de `internal/infrastructure/persistence/postgres/` de outro bounded context.
- Backup/restore atômico por contexto inviável (todos sobem juntos do mesmo dump).

### Mitigações de risco

- **Action 1 (curto prazo):** documentar em `viralefy_archive/CONTEXT.md` a lista de tabelas "ownership" por serviço para code review.
- **Action 2 (médio prazo):** introduzir teste de fumaça que valida queries por serviço só tocam tabelas declaradas em allowlist.
- **Action 3 (longo prazo):** quando trigger acionar, plano de migração: criar schemas vazios, mover tabelas com `ALTER TABLE ... SET SCHEMA`, atualizar search_path por role.

## Links

- Diretrizes §2, §10
- `viralefy_archive/CONTEXT.md` — visão de stack
- ADR-0002 (HTTP loopback) — decisão relacionada de comunicação inter-service
