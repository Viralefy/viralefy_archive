# ADR-0005 — Single tenant (marketplace), §15 multi-tenancy não se aplica

- **Status:** accepted
- **Data:** 2026-06-11
- **Decisores:** Equipe Viralefy
- **Diretriz relacionada:** §15 (Multi-tenancy obrigatório quando aplicável)
- **Reavaliação:** apenas se modelo de negócio mudar para SaaS B2B

## Contexto e Problem Statement

A diretriz §15 lista obrigatoriedades para multi-tenancy:

- `tenant_id` em contexto, logs, traces.
- Queries com `tenant_id` no `WHERE`.
- Row Level Security no Postgres.
- Testes de cross-tenant leak em CI.

Estado atual:

- **Viralefy é marketplace consumer (B2C)**, não plataforma SaaS B2B multi-tenant.
- Modelo: usuários finais compram serviços de engajamento (followers, likes) por categoria → não há "tenants" no sentido de §15.
- RBAC implementado: roles `superadmin`, `manager`, `viewer`, `user` (escopo platform, não tenant).
- BOLA (Broken Object Level Authorization) cross-user: testado em `tests/authz/` (planejado §22.3) e `tests/pentest/idor.sh`.
- Não existe coluna `tenant_id` em nenhuma tabela do schema — e **não deveria existir**.

## Decision Drivers

- §15 abre com "**MUST — quando aplicável (SaaS, plataformas)**". A regra é condicional.
- Forçar `tenant_id` sintético (ex.: todos = `'viralefy'`) adicionaria complexidade sem benefício.
- Modelo de negócio explícito: 1 plataforma, N usuários finais, M provedores de engajamento internos. Não há cliente B2B comprando "instância isolada".

## Decision Outcome

**§15 NÃO se aplica diretamente ao Viralefy.** ADR esclarece scope:

### O que aplicamos da família "isolation"

- **RBAC granular:** `superadmin`, `manager`, `viewer`, `user`. Implementado em `viralefy_core` + dispatcher.
- **BOLA cross-user testing:** scripts `tests/pentest/idor.sh`, `tests/pentest/user-bola.sh`, `tests/authz/cross-tenant-idor.sh` (último a ser renomeado para `cross-user-idor.sh` para refletir o modelo real).
- **Authorização server-side:** todo endpoint admin valida claim do JWT contra recurso, nunca confia em `user_id` enviado pelo cliente.
- **Audit log:** mudanças sensíveis (RBAC, financeiro, admin actions) gravadas em `audit_log` com `actor_id`, `action`, `target_type`, `target_id`.

### O que NÃO aplicamos

- ❌ Coluna `tenant_id`.
- ❌ Row Level Security por tenant.
- ❌ Métricas/logs particionáveis por tenant.
- ❌ Personas `tenant_admin_A` e `tenant_admin_B` (§22.5) — substituídas por `superadmin`, `manager`, `normal_user`.

## Triggers para Reavaliação (§15 passa a se aplicar)

Re-abrir esta ADR somente se houver pivot de negócio:

- Lançamento de modelo "Viralefy White-Label" para agências (cada agência = tenant).
- Aquisição de cliente B2B que exige instância dedicada lógica (não física).
- Compliance impõe isolamento por organização cliente.

## Action items

- [ ] Renomear `tests/authz/cross-tenant-idor.sh` para `cross-user-idor.sh` quando o test kit (agents J-O) for entregue. Documentar no ops README que "tenant" no nome de tests é histórico (semantic = user).
- [ ] Garantir que **nenhum endpoint** aceita `tenant_id` em path/query/body (se aceitar, é mass-assignment vulnerability — deve ser ignorado).

## Consequences

### Positivas

- Schema enxuto (sem coluna inútil em 49+ tabelas).
- RBAC mais simples de raciocinar.
- Sem custo de testes de cross-tenant leak inexistentes.

### Negativas

- Pivot futuro para multi-tenant exigiria migration significativa (add `tenant_id`, backfill, RLS, refactor de queries). Aceito como custo de futuro.

## Links

- Diretrizes §15
- `viralefy_archive/CONTEXT.md` — modelo de negócio
- ADR-0001 (shared DB) — relacionada
