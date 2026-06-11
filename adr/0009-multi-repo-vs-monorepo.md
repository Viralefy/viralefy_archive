# ADR-0009 — Multi-repo (10 repos) em vez de monorepo

- **Status:** accepted
- **Data:** 2026-06-11
- **Decisores:** Equipe Viralefy
- **Diretriz relacionada:** §2 (um repo = uma aplicação ou bounded context)
- **Reavaliação:** 2027-06 ou em reorganização da equipe

## Contexto e Problem Statement

A diretriz §2 diz: "Um repositório = uma aplicação ou um bounded context." Não obriga monorepo, mas também não veda. Estado atual:

10 repos públicos em `github.com/Viralefy/`:

| Repo | Função | Linguagem |
|---|---|---|
| viralefy_api | Legacy backend (em soak) | Go |
| viralefy_core | Backend principal (motor) | Go |
| viralefy_auth | Auth service | Go |
| viralefy_payments | Pagamentos (Stripe/Heleket/AbacatePay) | Go |
| viralefy_sender | Email/Telegram outbox | Go |
| viralefy_dispatcher | API gateway / routing | Rust |
| viralefy_front | Storefront público | Next.js |
| viralefy_backoffice | Admin panel | Next.js |
| viralefy_ops | Installer, systemd, tests, observability | Bash + Python |
| viralefy_archive | Documentação, ADRs, runbooks | Markdown |

## Decision Drivers

- **CI isolation:** falha em build do front não bloqueia merge no auth.
- **Versionamento independente:** cada serviço evolui no seu ritmo.
- **CODEOWNERS por escopo:** §25 mais fácil de aplicar.
- **Cross-repo PRs:** custo real quando mudança afeta 2+ repos (ex.: contrato API que envolve front + core + dispatcher).
- **Deploy:** `viralefy-update` (em `viralefy_ops`) coordena build de todos os serviços por commit hash.

## Considered Options

### Option A — Multi-repo (status quo)

**Prós:** CI isolation, versionamento independente, CODEOWNERS naturais, blast radius pequeno por bug, GitHub Actions custos pequenos por repo.
**Contras:** cross-repo PRs trabalhosos, mais difícil garantir consistência de versões de libs comuns, onboarding de dev novo precisa clonar 10 repos.

### Option B — Monorepo único (`viralefy/`)

**Prós:** atomic commits cross-service, refactor cross-cutting trivial, uma única CI config.
**Contras:** CI mais lenta (precisa build matrix ou paths-filter), git history gigante, blast radius de force-push, ferramentas (Bazel, Nx, Turborepo) introduzem complexidade.

### Option C — Híbrido: monorepo Go (`viralefy_backend/`) + repos separados para front, ops, archive

**Prós:** atomic refactor entre os 5 services Go que compartilham conceitos; isola frontend.
**Contras:** migration cost, contradiz §2 "um repo = um bounded context".

## Decision Outcome

**Escolhida: Option A — Multi-repo.**

Justificativa:

1. **Cada serviço Go tem fronteira clara** (auth, payments, sender, core/api) — bounded contexts reais conforme §2.
2. **Independent versioning** alinha com SemVer per-service: bug em `viralefy_payments` v1.2.4 → tag e deploy só desse repo.
3. **CI rápido por repo:** PR em `viralefy_front` não roda testes de Go.
4. **`viralefy_ops` coordena deploy:** o "metarepo" workspace local (`viralefy/`) é a unidade de orquestração, não git submodules.
5. **Custo de cross-repo PR é aceito:** acontece raramente (mudança de contrato), e dispatcher Rust serve como ponto de articulação entre back e front.

## Compromissos para mitigar contras

- **CODEOWNERS** em cada repo (algumas pessoas em vários).
- **`renovate.json` compartilhado** via "config:base" + override per-repo.
- **`viralefy_archive` é fonte de verdade documental** cross-repo (ADRs, runbooks, CONTEXT).
- **Workspace local viralefy/** com submodules ou checkout manual coordenado é o "monorepo virtual" para dev.

## Triggers para Reavaliação (Option B candidata)

- Equipe cresce para 10+ devs, cross-repo PR frequência > 30% dos PRs.
- Refactor cross-cutting frequente exige atomic commits cross-service (ex.: adicionar `tenant_id` em todo schema — não acontecerá conforme ADR-0005).
- Ferramentas tipo Nx/Turborepo amadurecem ao ponto de "monorepo grátis".

## Action items

- [ ] Documentar em CONTEXT.md a árvore de dependência inter-repo (quem chama quem, contratos).
- [ ] Padronizar `AGENTS.md` em cada repo apontando para `viralefy_archive/` como referência canônica.
- [ ] CI workflow compartilhado (`.github/workflows/`) gerado a partir de template em `viralefy_archive/templates/` (planejado).

## Consequences

### Positivas

- Blast radius pequeno por bug.
- CI por repo rápido (~3-5min para Go services).
- Versionamento independente facilita rollback granular.
- CODEOWNERS naturais.

### Negativas

- Cross-repo PR trabalhoso (ex.: criar 3 PRs simultâneos com mesma intenção).
- Onboarding precisa do script `viralefy_ops/installer/clone-all.sh` (planejado).
- Drift de versões de libs comuns (Go modules, npm) — Renovate ajuda.

## Links

- Diretrizes §2, §7, §25
- `viralefy_archive/CHECKLIST.md` — lista de repos
- `viralefy_ops/installer/`
