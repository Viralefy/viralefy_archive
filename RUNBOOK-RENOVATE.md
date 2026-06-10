# RUNBOOK — Renovate (dependency automation)

Status: configurado em todos os 10 repos do Viralefy via preset central em
`viralefy_ops/renovate-config.json`. Pendente: instalação do **Renovate
GitHub App** na org (passo manual do owner da org).

## Por que Renovate (e não Dependabot)

- Schedule customizável (Mondays 09:00–12:00 America/Sao_Paulo).
- Grouping por manager (todos os go.mod em 1 PR, todos os crates em 1 PR).
- Auto-merge granular por updateType + currentVersion (skipa 0.x).
- Vulnerability alerts integrados (GHSA + OSV).
- Preset central — 1 arquivo controla 10 repos (DRY).
- Dependency dashboard issue (visibilidade do backlog num lugar só).

## Onde está cada arquivo

| Arquivo | Repo | Função |
| --- | --- | --- |
| `renovate-config.json` | `viralefy_ops` | preset central — única fonte de verdade |
| `renovate.json` | todos os 10 repos | extends do preset central |
| `.github/workflows/security.yml` | `viralefy_auth`, `_payments`, `_sender`, `_api_rust` | govulncheck / cargo audit (defesa-em-profundidade) |
| `.github/workflows/ci.yml` (jobs `govulncheck` / `npm-audit`) | `viralefy_api`, `_core`, `_front`, `_backoffice` | adicionados aos CI existentes |

Mudanças no preset central propagam pra todos os 10 repos no próximo run
do Renovate — não precisa abrir 10 PRs pra ajustar schedule, label, etc.

## Pré-requisito: instalar o Renovate GitHub App

Passos (uma vez por org, owner-only):

1. Acessar https://github.com/apps/renovate
2. Clicar em **Install** → escolher a org `Viralefy`
3. Selecionar **All repositories** (ou os 10 explicitamente)
4. Confirmar permissões: contents (read/write), pull requests (read/write),
   issues (read/write), checks (read), metadata (read), workflows (write
   — pinning de actions)
5. Aguardar ~10 min: Renovate cria a **onboarding PR** em cada repo. Como
   já temos `renovate.json` committed, ele detecta e pula a onboarding —
   começa a abrir PRs reais na próxima janela schedule.

Self-hosted alternativo (caso owner não queira o app): rodar
`renovate-bot` em GitHub Actions com `RENOVATE_TOKEN`. Não recomendado
agora — adiciona ops sem ganho.

## O que automerga vs o que não

Regras em `viralefy_ops/renovate-config.json` (resumo):

| Tipo de update | Comportamento |
| --- | --- |
| patch / minor em deps >= 1.0 | **automerge via branch** (não cria PR — só merge direto se CI passar) |
| patch / minor em deps 0.x | abre PR pra revisão (SemVer não garante BC) |
| major | abre PR com label `major-update`, **revisão obrigatória** |
| devDependencies (qualquer tipo) | automerge |
| GitHub Actions | grupo único, **pin por digest** |
| Vulnerability alert | PR com labels `security`, `urgent`, automerge **off** |
| lockFileMaintenance | rota mensal (1º dia do mês) |

CI tem que passar pro automerge acontecer — Renovate respeita branch
protection. Se um patch quebrar build/teste, vira um PR pra revisão.

## Volume esperado de PRs

Com grouping + schedule limit (`prHourlyLimit: 4`, `prConcurrentLimit: 8`):

- Segunda 09:00–12:00 BRT: 1 PR de `go modules` (agrega todos os go.mod
  do repo), 1 PR de `node modules`, 1 PR de `rust crates`, 1 PR de
  `github actions`. Total: ~4 PRs por repo por semana, mas a maioria
  automerga sozinha.
- O que chega no cliente pra revisar: majors + 0.x bumps + vulns. Algo
  como 2–5 PRs/semana no total (estimado pra fase POC).

## Como mexer no schedule

Editar `viralefy_ops/renovate-config.json`:

```json
"schedule": ["before 12:00 on Monday"]
```

Outros exemplos úteis:

- `"every weekend"` — só fim de semana
- `"after 22:00 every weekday"` — fora de horário comercial
- `"before 05:00 on Monday"` — madrugada de segunda

Commit + push em `main`. Próximo run do Renovate (~1h) usa a nova config.

## Como lidar com major updates

PR de major chega com label `major-update`. Fluxo:

1. Ler o CHANGELOG do upstream (link no PR description).
2. Rodar localmente: `git fetch origin pull/<N>/head:rev-<N> && git checkout rev-<N>`.
3. Build + test full: `go test ./... && go vet ./...` (ou equivalente Rust/Node).
4. Se OK → merge. Se quebrou → comentar `@renovatebot close` ou ajustar
   `packageRules` pra ignorar até nova versão.

Pra ignorar um major específico:

```json
{
  "matchPackageNames": ["github.com/lib/pq"],
  "matchUpdateTypes": ["major"],
  "enabled": false
}
```

## Vulnerability alerts — triagem

Quando Renovate detecta vuln (via GHSA/OSV), abre PR **fora do schedule**
(`"schedule": ["at any time"]`) com labels `security` + `urgent`.

SLA proposto (revisar com cliente):

- **Critical / High**: review + merge em ≤ 24h
- **Medium**: ≤ 7 dias
- **Low**: incluir no próximo ciclo regular

Sinal complementar nos CIs:
- `govulncheck` (Go repos) — Go-specific, pega vulns em chamadas reais
- `cargo audit` (Rust) — RustSec advisories
- `npm audit --audit-level=high` (Node) — high+ apenas

Os jobs estão `continue-on-error: true` agora (não bloqueiam merge). Plano:
promover pra blocking após o pentest baseline de 2026-06-10 estar zerado
e o time ter SLA definido.

## Dependency Dashboard

Renovate cria uma issue chamada **"Renovate Dependency Dashboard"** em
cada repo, listando:

- PRs abertos pelo bot
- Updates pendentes (rate-limited)
- Updates ignorados (com motivo)
- Botões pra forçar re-run

Bookmark essa issue por repo — é o checkin semanal de saúde de deps.

## Validar config localmente

```bash
npx --yes --package renovate -- renovate-config-validator \
  /caminho/pro/renovate.json
```

Roda offline, sem token — apenas valida JSON + schema.

Pra dry-run de verdade (sem abrir PRs, mas chama GitHub API):

```bash
RENOVATE_TOKEN=<gh_token_com_repo_scope> \
LOG_LEVEL=debug \
npx --yes --package renovate -- renovate \
  --dry-run=full \
  --platform=github \
  Viralefy/viralefy_core
```

## Troubleshooting

- **PR não foi aberto na janela**: checar Dependency Dashboard — rate
  limit pode ter sido atingido. Aumentar `prHourlyLimit` se necessário.
- **Automerge não rolou**: checar branch protection (precisa de status
  checks marcados como required). Renovate só dá merge se CI passar.
- **Preset não está sendo aplicado**: `extends` precisa de `Viralefy/`
  com case correto. Confirmar no log da Renovate App.
- **Vuln alert sem PR**: confirmar que **Dependabot alerts** está
  habilitado no repo (Settings → Code security → Dependabot). Renovate
  consome esse feed.

## Referências

- Preset central: `viralefy_ops/renovate-config.json`
- Per-repo configs: `<repo>/renovate.json`
- Docs Renovate: https://docs.renovatebot.com/
- Schema: https://docs.renovatebot.com/renovate-schema.json
