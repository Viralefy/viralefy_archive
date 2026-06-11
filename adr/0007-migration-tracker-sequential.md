# ADR-0007 — Migration tracker sequential + checksum em vez de timestamp-based

- **Status:** accepted
- **Data:** 2026-06-11
- **Decisores:** Equipe Viralefy
- **Diretriz relacionada:** §10 (migrations versionadas, reversíveis)
- **Reavaliação:** 2027-01 ou no trigger documentado

## Contexto e Problem Statement

A diretriz §10 obriga:
- Migrations versionadas, reversíveis (com `down`), automatizadas no deploy.
- Sugere `golang-migrate`, `node-pg-migrate`, `sqlx-cli`, `flyway`.

Estado atual:

- Migrations em `viralefy_core/internal/infrastructure/persistence/postgres/migrations/` com 43 arquivos.
- Naming **sequential**: `001_init.up.sql`, `002_features.up.sql`, ..., `043_*.up.sql`.
- Cada migration tem par `.down.sql` (reversível).
- Tracker estilo Laravel: tabela `schema_migrations` com `version` (int) + `checksum` (hash do conteúdo) + `applied_at`.
- Auto-backfill em produção legacy (CHECKLIST: "Migration tracker estilo Laravel — schema_migrations + checksum + auto-backfill prod legado").
- **Bug recente (~ 2026-06):** dois agentes paralelos criaram migration `041_*` simultaneamente → conflito de número sequencial detectado na hora do merge.

## Decision Drivers

- **Conflict resilience:** numeração sequencial causa conflito quando branches paralelas adicionam migrations. Timestamp-based (`20260611103000_xyz.up.sql`) evita conflito de nome mas pode causar **ordem inconsistente** entre devs.
- **Determinismo:** sequencial garante ordem absoluta; checksum impede que migration aplicada seja modificada silenciosamente.
- **Compatibilidade com `golang-migrate`:** suporta ambos sequencial e timestamp.
- **Frequência de paralelismo:** equipe pequena (1 dev humano + agentes IA pontuais), conflitos são raros e detectáveis no PR.

## Considered Options

### Option A — Manter sequencial + checksum (status quo)

**Prós:** ordem determinística, simples de raciocinar, checksum protege contra modificações silenciosas, alinhado com convenções de muitos times Go.
**Contras:** conflito de número quando 2+ branches criam migration no mesmo intervalo.

### Option B — Migrar para timestamp-based

**Prós:** zero conflito de nome em branches paralelas.
**Contras:** ordem entre devs pode divergir (Alice cria `20260611_a` em paralelo a Bob `20260610_b`; merge invertido aplica `_b` antes de `_a` que já estava no DB do Alice). Migração trabalhosa: renomear 43 arquivos + atualizar `schema_migrations` em produção.

### Option C — Sequencial + reservation script

Script `make migrate-new NAME=xyz` que abre o próximo número, faz lock leve via gist/issue.

**Prós:** evita o conflito source, baixo custo.
**Contras:** overhead operacional.

## Decision Outcome

**Escolhida: Option A — manter sequencial + checksum.**

Justificativa:

1. **Conflito é detectável e trivial de resolver:** PR review pega; renumerar é `mv`.
2. **Determinismo > conveniência:** ordem absoluta facilita debug em produção (sabemos exatamente qual migration estava aplicada em qual data).
3. **Checksum cobre o cenário mais perigoso** (alguém edita migration já aplicada → boot falha com mensagem clara).
4. **Auto-backfill em prod legacy** já é resolvido — não queremos invalidar esse caminho.

## Trade-off explícito (vs Option B)

| Cenário | Sequencial | Timestamp |
|---|---|---|
| 2 PRs paralelos criam migration | Conflito detectado no merge | Sem conflito, mas possível ordem inconsistente entre DBs de devs |
| Verificar "qual era a migration N" | `cat NNN_*.up.sql` | Precisa olhar ordem por timestamp |
| Rollback "última aplicada" | trivial (N-1) | trivial (último timestamp aplicado) |
| Auditoria pós-incidente | "aplicamos 041 em 2026-06-09" | "aplicamos 20260609103000_x" |

Sequencial vence em legibilidade humana; timestamp vence em throughput de PRs paralelos. Para nossa escala, sequencial é melhor.

## Triggers para Reavaliação (Option B se torna candidata)

- Equipe cresce para 3+ devs concorrentes adicionando migrations.
- Frequência de conflito > 1/semana.
- CI passa a falhar regularmente em PRs por colisão de número.

## Action items

- [ ] Documentar em `viralefy_core/README.md` a convenção de naming e como resolver conflito.
- [ ] Adicionar `make migrate-new NAME=xyz` que escolhe próximo número automaticamente (reduz erro humano).
- [ ] Adicionar CI check que valida: (a) números sequenciais sem buraco, (b) cada `.up.sql` tem `.down.sql` correspondente.

## Consequences

### Positivas

- Ordem determinística trivial de raciocinar.
- Checksum protege contra modificação silenciosa de migration aplicada.
- Compatível com `golang-migrate` (caminho de saída fácil se Option B virar necessária).

### Negativas

- Conflitos esporádicos de numeração quando agentes paralelos colaboram (mitigável com `make migrate-new`).
- Necessidade de coordenação humana mínima para escolher próximo número.

## Links

- Diretrizes §10
- `viralefy_core/internal/infrastructure/persistence/postgres/migrate.go`
- `viralefy_core/internal/infrastructure/persistence/postgres/migrations/`
- ADR-0001 (shared DB) — define onde as migrations vivem
