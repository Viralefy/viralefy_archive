# Conformidade vs `diretrizes.md` v4.0

**Data:** 2026-05-31
**Fase:** HML / POC (15-day result test)
**Status:** Snapshot inicial — usar como baseline.

> Auditoria seção-a-seção. Cada item: ✅ conforme | ⚠️ parcial | ❌ não-conforme |
> N/A não-aplicável-no-momento. Itens marcados ❌ MUST viram débitos rastreáveis.

---

## §2 Estrutura de Repositórios

| Item | Status | Nota |
|---|---|---|
| Um repositório = uma aplicação ou bounded context | ✅ | 5 repos: `viralefy_api`, `viralefy_front`, `viralefy_backoffice`, `viralefy_ops`, `viralefy_archive` |
| Comunicação entre serviços via HTTP/gRPC/eventos | ✅ | Front e backoffice consomem API via HTTP |
| Cada serviço dono do seu schema | ⚠️ | API e backoffice compartilham mesmo Postgres + schema (acoplamento via DB). Backoffice deveria consumir API. **Débito.** |

---

## §3 Linguagens

| Item | Status | Nota |
|---|---|---|
| Versão exata no Anexo A | ⚠️ | Anexo diz Go 1.25; usamos 1.26.3 (mais nova). Sem ADR mas alinhado direcionalmente. |
| Não misturar linguagens no mesmo bounded context | ✅ | API só Go; front/backoffice só TS |
| Empate Go vs Node → Go vence | ✅ | API em Go |

---

## §4 Arquitetura

| Item | Status | Nota |
|---|---|---|
| 4 camadas explícitas (domain/application/infrastructure/interface) | ✅ | `viralefy_api/internal/{domain,application,infrastructure,interface}/` |
| Inversão de dependência | ✅ | Domain não importa frameworks |
| Domain não importa ORM/IO | ⚠️ | Verificar individualmente; alguns serviços ainda misturam |
| DDD tático (agregados, VOs, eventos) | ⚠️ | Tem entidades, faltam eventos de domínio |
| Anti-Corruption Layer pra integrações | ✅ | `infrastructure/external/{email,payment}` adapter-style |

---

## §5 Estrutura de Pastas

✅ **API** segue o layout Go canônico (`cmd/api/`, `internal/{domain,application,infrastructure,interface,config}`).
N/A Front/backoffice (Next.js tem layout próprio).

---

## §6 Complexidade

| Item | Status | Nota |
|---|---|---|
| Arquivos > 300 linhas com revisão | ⚠️ | Front: `categories.ts` 1055 linhas, `languages.ts` 700+, `legal.ts` 1087, `countries.ts` 1450+. Todos data-files de catálogo; coesão alta, refactor não justifica. |
| Funções ≤ 50 linhas | ⚠️ | Não auditado sistematicamente. |
| Cyclomatic complexity ≤ 15 | ❌ | Sem linter rodando. **Débito CI.** |
| Aninhamento ≤ 4 | ✅ (impressão) | |

---

## §7 Shared Libraries

✅ Não criamos `commons`. Cada repo é independente.

---

## §8 CQRS

N/A — projeto pequeno, sem necessidade.

---

## §9 Eventos e Mensageria

❌ **Sem broker, sem outbox.** Checkout + email são dual-write (gravar pedido + enviar email no mesmo handler). Risco: API cair entre INSERT e Resend → cliente paga e não recebe confirmação. **§9 MUST: Outbox Pattern.** Débito Tier 3.

---

## §10 Banco de Dados

| Item | Status | Nota |
|---|---|---|
| Postgres | ✅ | 17 |
| Migrations versionadas reversíveis | ⚠️ | Migrations em `internal/infrastructure/persistence/postgres/migrations/` mas sem `down`. Reversibilidade quebrada. |
| Schema próprio por serviço | ❌ | API + backoffice no mesmo schema. **§2 + §10 violation.** |
| Sem joins cross-service | N/A | Backoffice usa SQL direto no schema da API (acoplamento). |
| Timestamps em UTC | ✅ | `timestamp with time zone now()` em todas as tabelas |
| IDs UUIDv7/ULID | ❌ | Usa `gen_random_uuid()` (UUIDv4). Não há ordenação natural exigida no domínio então toleráve. |
| Read replicas em alta escala | N/A | Tráfego baixo. |

---

## §11 Cache

❌ **Sem Redis, sem cache layer.** Currency rates lidos do Postgres a cada request. Plans/categories também. Aceitável no POC; débito quando volume crescer.

---

## §12 APIs

| Item | Status | Nota |
|---|---|---|
| OpenAPI 3.1 em `/docs/openapi.yaml` | ✅ | Existe em `viralefy_api/docs/openapi.yaml` (auditar fidelidade ao código) |
| Versionamento URL `/v1` | ✅ | Todos os endpoints sob `/v1` |
| Validação de payload na borda | ✅ | Handlers fazem validação |
| Erro padrão RFC 7807-compatível | ⚠️ | Tem envelope `{error: {code, message}}` mas falta `trace_id` e `details: []`. Quase. |
| Operações de escrita aceitam `Idempotency-Key` | ❌ | Checkout / orders não suportam. Risco real de double-charge. Débito Tier 2. |
| Timestamps ISO-8601 com tz | ✅ | Go `time.Time` serializa pra RFC 3339 |
| Cursor pagination | ⚠️ | Listas atuais (admins, plans, etc.) usam offset. Tolerável pra volumes baixos. |
| Rate limiting distribuído | ❌ | **Sem rate limit nenhum.** Vulnerável a brute force, scraping, DDoS de baixo custo. **Débito Tier 1.** |

---

## §13 Segurança

| Item | Status | Nota |
|---|---|---|
| Dependabot / Renovate | ❌ | |
| SAST | ❌ | |
| SCA + licenças | ❌ | |
| Container scan | N/A (sem containers) |
| Secret scan (Gitleaks) | ❌ | Chave SSH e Resend foram coladas em chat (CONTEXT débito) |
| Commit signing | ❌ | |
| SBOM | ❌ | |
| Containers não-root, read-only | N/A | Stack roda direto via systemd com hardening (NoNewPrivileges, ProtectSystem=strict, etc.) — substituição razoável. |
| Distroless | N/A |
| Secrets em Vault/Secret Manager | ❌ | Tudo em `/etc/viralefy/.env` (0640 root:viralefy). Aceitável HML, não PRD. |

**Bloco inteiro = débito CI/CD.**

---

## §14 Autenticação e Autorização

| Item | Status | Nota |
|---|---|---|
| OAuth2 / OIDC | N/A | Auth simples por bcrypt + JWT |
| JWT RS256/EdDSA, nunca HS256 | ❌ | **VIOLAÇÃO MUST.** Usamos HS256 em `internal/application/{auth_service,user_auth_service}.go`. Risco real: vazamento de `JWT_SECRET` permite forjar tokens. **Débito Tier 1.** |
| Refresh token rotativo com detecção de reuso | ❌ | Sessão é JWT longo (30d) sem refresh. |
| RBAC granular | ✅ | `application/abac.go` + permissions table |
| ABAC quando necessário | ✅ | Custom permissions check (`can("admins:manage")` etc.) |

---

## §15 Multi-tenancy

N/A — single tenant.

---

## §16 Observabilidade

| Item | Status | Nota |
|---|---|---|
| Grafana, Alloy, Loki, Tempo, Prometheus, OTel | ❌ | **ZERO. Logs vão pra journalctl, sem métricas, sem traces.** |
| Logs JSON estruturado | ⚠️ | API usa `log.Printf`. Front Next.js usa console. **Não-estruturado.** |
| `trace_id` / `correlation_id` | ❌ | |
| Mascaramento de PII | ❌ | Logs podem vazar email/etc. Não auditado. |
| RED metrics por endpoint | ❌ | Sem métricas. |
| USE metrics infra | ❌ | |
| W3C Trace Context | ❌ | |
| SLOs em `/docs/slo.md` | ❌ | |
| Métricas de negócio | ❌ | |
| Trilha de auditoria imutável | ⚠️ | Tem `audit_logs` em alguns pontos? Verificar. |

**Bloco inteiro = trabalho desta sessão.**

---

## §17 Healthchecks

| Item | Status |
|---|---|
| `/health` (liveness) | ✅ |
| `/ready` (readiness com deps) | ❌ |
| `/metrics` (Prometheus) | ❌ |

---

## §18 Resiliência

❌ Chamadas externas (Resend, Woovi, Heleket) sem timeout/retry/circuit-breaker estruturados. Usam stdlib `http.Client` default. **Débito Tier 2.**

---

## §19 Jobs e Workers

❌ Sem workers. Sem DLQ. Há cron? Apenas Caddy auto-renova certs. Webhook receiver é síncrono. **Débito quando entrar abandoned-cart, etc.**

---

## §20 Configuração

✅ 12-factor — tudo via env vars validado em `config.LoadFromEnv()`. Fail-fast em valores ausentes.

---

## §21 Infraestrutura e Deploy

| Item | Status | Nota |
|---|---|---|
| Kubernetes + Helm | ❌ | Bare metal + systemd. **ADR necessário** documentando trade-off (1 servidor, custo, velocidade vs k8s). |
| IaC (Terraform/OpenTofu) | ❌ | Installer bash em `viralefy_ops`. Substituição razoável pra single-host. |
| CI/CD GitHub Actions | ❌ | Deploy manual via `viralefy-update`. **Débito Tier 1.** |
| Ambientes isolados (dev/staging/production) | ❌ | Single env, é HML/POC. |
| Artefato imutável | ❌ | Update destrutivo pulla `main` HEAD — não há versionamento de artefato. |
| Rollback automatizado em falha de healthcheck | ❌ | Se healthcheck falha pós-deploy nada acontece (`viralefy-update` apenas falha no shell). |

---

## §22 Testes

| Item | Status | Nota |
|---|---|---|
| Testes em dois eixos (unit + system) | ⚠️ | Temos: 255 unit no front, smoke/pentest/emulated. Falta backend Go (`go test`). |
| Caminhos críticos com testes | ⚠️ | Cobre i18n/sitemap/search. **API não testada.** |
| Cobertura mínima por camada (domain 80%, app 70%, infra 40%, global 60%) | ❌ | API: 0%. Front: 85% mas mistura camadas. |
| Mutation testing em domínio crítico | ❌ | |
| Test kit em `<project>_ops` com CLI `viralefy test smoke/integration/...` | ❌ | Suíte mora em `viralefy_front/tests/` em vez de `viralefy_ops/tests/`. Estrutura inicial existe mas não está unificada. |
| `summary.json` machine-readable | ❌ | |
| Personas multi-tenant em `tests/seeds/` | N/A (single tenant) |
| OWASP ZAP, Nuclei, Trivy em CI noturno | ❌ | |

**Débito Tier 3.**

---

## §24 Qualidade e Git

| Item | Status |
|---|---|
| Conventional Commits | ✅ |
| SemVer | ⚠️ Sem tags release ainda |
| Trunk-based (main) | ✅ |
| PR size ≤ 400 linhas | ⚠️ Alguns PRs maiores no POC |
| ≥ 1 reviewer | ❌ Single dev |
| CODEOWNERS | ❌ |
| CI verde obrigatório | ❌ Sem CI |
| Squash merge | ⚠️ Usamos commit direto |
| Branch protection na main | ❌ |

---

## §25-26 Ownership / Runbooks / Incidentes

❌ Sem CODEOWNERS, sem runbook, sem postmortem template. HML aceita. **Débito Tier 2 quando escalar.**

---

## §27 ADR

❌ **Zero ADRs.** Decisões importantes (bare-metal vs k8s, HS256 acceptable temporário, monorepo schema compartilhado API↔backoffice, IndexNow key hardcoded etc.) não registradas. **Débito Tier 2.**

---

## §28 Archive

Existe `viralefy_archive/CONTEXT.md` (contexto operacional). Chat/task archive seletivos não montados.

---

## §30 Performance

Alvo p95 < 300ms — não medido. Falta `/metrics` e dashboard. **Débito junto com §16.**

---

## §31 Feature Flags

❌ Sem flag system. Releases são "tudo on, todo mundo, agora". **Débito Tier 2.**

---

## §32 LGPD

| Item | Status |
|---|---|
| Classificação de dados documentada | ❌ |
| PII fora dos logs | ⚠️ Não auditado |
| Política de retenção | ⚠️ Termos mencionam mas sem processo |
| Direitos do titular (acesso/correção/eliminação) | ❌ Sem endpoint |
| TLS 1.2+ em trânsito | ✅ Caddy (TLS 1.2/1.3) |
| Criptografia em repouso | ❌ Postgres não-cifrado em disco |
| DPIA pra tratamentos de alto risco | ❌ |

---

## §33 FinOps

N/A — single server $X/mês.

---

## §34 IA Assistida

✅ Co-Author trailer em commits. Disclaimer claro.

---

## §35 Definition of Done

⚠️ Parcial. Falta CI, OpenAPI sync auto, runbook, ADR pra cada decisão.

---

# Resumo executivo

## Débitos Tier 1 (resolver antes de PRD ou em paralelo a este sprint)

1. **§16 Observabilidade — Grafana + Loki + Tempo + Prometheus + OTel.** Resolvendo NESTE PR.
2. **§14 JWT RS256.** Trocar HS256 por RS256. Risco real de forjar tokens.
3. **§12 Rate limiting.** Adicionar middleware token-bucket em chi.
4. **§12 Idempotency-Key em writes.** Evita double-charge em retries de cliente/gateway.
5. **§21 CI/CD via GitHub Actions.** Mínimo: build + tests on PR.

## Débitos Tier 2 (1-2 semanas)

6. **§9 Outbox Pattern** pra checkout+email atômicos.
7. **§18 Resiliência** — timeouts/retry/circuit-breaker em external calls (Resend/Woovi/Heleket).
8. **§13 Pipeline de segurança** — Dependabot, Semgrep, Gitleaks, Trivy.
9. **§31 Feature flags** — começar com algo simples (GrowthBook self-host ou Unleash).
10. **§32 LGPD** — endpoint de export/delete + classificação de dados.

## Débitos Tier 3 (escalação ou pós-validação POC)

11. **§22 Test kit unificado** em `viralefy_ops/tests/` seguindo §22.1-§22.7.
12. **§16.6 Auditoria imutável** em `audit_logs` append-only.
13. **§10 Migrations reversíveis** com `down`.
14. **§2 Schema separation** API ↔ backoffice (backoffice consome API).
15. **§11 Redis** pra cache de plans/categories/currencies.
16. **§14 Refresh tokens rotativos.**
17. **§27 ADRs** — documentar bare-metal vs k8s, HS256 temporário, monorepo schema, etc.
18. **§21 Artefato imutável** — versionar releases com tag + manter imagens.

---

## ADRs imediatos a redigir

- `0001-bare-metal-systemd-vs-kubernetes.md` (justifica desvio §21)
- `0002-hs256-jwt-poc-window.md` (aceite temporário do desvio §14, plano de migração pra RS256)
- `0003-shared-postgres-schema-api-backoffice.md` (desvio §2/§10)
- `0004-grafana-stack-self-hosted-single-host.md` (escolha desta sessão)
