# Viralefy — Engineering Conformance Audit

**Versão:** 1.0
**Data:** 2026-06-11
**Auditor:** revisão sistemática vs. `viralefy_archive/diretrizes.md` v4.0
**Escopo:** todos os repos do workspace (`viralefy_api`, `viralefy_core`, `viralefy_auth`, `viralefy_payments`, `viralefy_sender`, `viralefy_dispatcher`, `viralefy_front`, `viralefy_backoffice`, `viralefy_ops`, `viralefy_archive`)
**Reavaliação:** trimestral (próxima: 2026-09-11)

---

## Sumário Executivo

A plataforma **cumpre majoritariamente as diretrizes** em segurança, observabilidade, auth, healthchecks e estrutura DDD básica. Os principais desvios são **conscientes, documentados em ADRs**, e justificados pela escala atual (VPS única, B2C, faturamento crescente mas pequeno).

### Top 5 Gaps Críticos

1. **`handlers.go` de 3000+ linhas** em `viralefy_core` e `viralefy_api` (3323 e 3125 linhas respectivamente). §6 obriga revisão crítica acima de 300. **Refactor prioritário — Q3 2026.**
2. **Shared database** (§10 violado) — formalizado em ADR-0001, mas sem linter/test que **previna** queries cross-context. Risco silencioso.
3. **Sem outbox universal** (§9 parcialmente violado) — apenas `sender_outbox` existe. Eventos críticos como `payment_confirmed` dependem de HTTP loopback síncrono. ADR-0002 documenta plano fase 2.
4. **Test Kit `viralefy_ops` incompleto** (§22.3) — pentest/authz/hardening/chaos/simulated planejados, parcialmente implementados.
5. **LGPD parcial:** C3 (consent banner) + C5 (anonimização) prontos; C1 (DPIA), C2 (política retenção), C4 (DPO contato/processo de direitos) **pendentes**.

### O que recomendamos refatorar próximo trimestre (Q3 2026)

| Prio | Item | Impacto | Esforço |
|---|---|---|---|
| 1 | Quebrar `handlers.go` em handlers por bounded context | Manutenibilidade | Alto (~3-5 dias) |
| 2 | Linter custom para imports cross-context (ADR-0001 mitigação) | Risco silencioso | Médio (~1-2 dias) |
| 3 | Centralizar `bcryptCost = 12` em `shared/crypto` (ADR-0003 action item) | Consistência | Baixo (~2h) |
| 4 | Generalizar `sender_outbox` pattern como `event_outbox` em core (ADR-0002 fase 2) | Resiliência | Médio (~2-3 dias) |
| 5 | Completar Test Kit ops (pentest + authz + hardening) | Cobertura segurança | Alto (semanas) |

---

## Tabela de Conformidade vs Diretrizes

| Seção | Item | Status | Notes |
|---|---|---|---|
| §0 | ADRs registrados | ✅ | 10 ADRs criados em `adr/` (2026-06-11) |
| §1 | Filosofia (clareza, simplicidade) | ✅ | Evidência por code review em PRs |
| §2 | Um repo = um bounded context | ✅ | 10 repos, ADR-0009 formaliza |
| §2 | Comunicação inter-service não via DB | ⚠️ | HTTP loopback síncrono, mas DB **é compartilhado** — ADR-0001 |
| §3 | Linguagens (Go/Rust/Node) | ✅ | Conforme. Frontend em ADR-0008 |
| §4 | DDD layered architecture | ✅ | 5 Go repos com `domain/application/infrastructure/interface` |
| §4 | Domain não importa frameworks/infra | ✅ | grep confirma 0 imports proibidos em domain |
| §4 | Application não importa interface | ✅ | grep confirma 0 hits |
| §4 | Application não importa infrastructure (hexagonal) | ⚠️ | 33 hits em core, 34 em api (legacy) — DDD híbrido §4.X aplicado |
| §4 | Anti-Corruption Layer em providers externos | ✅ | Adapters dedicados em `external/payment/` (ADR-0010) |
| §6 | Arquivos ≤ 300 linhas (revisão crítica) | ❌ | `handlers.go` 3325 em core. Refactor pendente |
| §6 | Complexidade ciclomática ≤ 15 | ❓ | Sem CI gate; revisar com `gocyclo` |
| §7 | Sem `commons`/`core-lib` genérico | ✅ | Cada repo é dono do seu domínio; helpers locais |
| §8 | CQRS | ➖ | Aplicado pragmaticamente em queries vs commands; sem framework |
| §9 | Eventos imutáveis + versionados | ⚠️ | `sender_outbox` cumpre parcialmente; loopback síncrono não — ADR-0002 |
| §9 | Transactional Outbox obrigatório | ❌ | Apenas em `sender`; demais via HTTP — ADR-0002 |
| §9 | DLQ configurada | ⚠️ | `sender_outbox` tem retry+max; sem DLQ formal noutros lugares |
| §10 | Postgres como DB principal | ✅ | Postgres 16 conforme |
| §10 | Migrations reversíveis | ✅ | 43 migrations com `.up.sql` + `.down.sql` |
| §10 | Schema próprio por serviço | ❌ | Shared DB — ADR-0001 |
| §10 | Timestamps UTC | ✅ | `TIMESTAMPTZ` em migrations, `time.UTC()` em código |
| §10 | UUIDv7 ou ULID | ⚠️ | Mix: uuid v4 em legacy, ULID em novos. Padronizar |
| §11 | Cache TTL explícito | ✅ | `jwks` cache + `revocation_cache` com TTL; sem TTL infinito identificado |
| §11 | Mitigação cache stampede | ⚠️ | Single-flight não verificado em todos pontos |
| §12 | OpenAPI 3.1 em `/docs/openapi.yaml` | ⚠️ | Existe parcial; não é fonte 100% da verdade |
| §12 | Versionamento na URL (`/v1`) | ✅ | Conforme |
| §12 | Erro padrão RFC 7807 | ⚠️ | Maioria sim; padronizar todos |
| §12 | Idempotency-Key em writes | ⚠️ | `idempotency_keys` table existe (migration 012); aplicar broadly |
| §13 | SAST + SCA + Container scan + Secret scan | ✅ | Pipeline ativo, Renovate, govulncheck |
| §13 | bcrypt cost ≥ 12 | ✅ | Cost 12 universal — ADR-0003. Backup codes em cost 10 (exceção documentada) |
| §13 | Containers não-root, multi-stage | ✅ | Distroless final stage |
| §13 | Segredos fora de código | ✅ | `INTERNAL_SHARED_SECRET` via env; `credentials` no workspace gitignored |
| §13 | Commit signing | ⚠️ | Não enforced ainda |
| §13 | SBOM no build | ❓ | Verificar CI |
| §14 | OAuth2/OIDC | ➖ | Não aplicável (auth interna) |
| §14 | JWT RS256 (não HS256) | ✅ | RS256 + JWKS; HS256 legado em remoção (Fase 4.1) |
| §14 | Refresh token rotativo + detecção de reuse | ✅ | `refresh_tokens` table + revoke family on reuse |
| §14 | RBAC granular | ✅ | superadmin/manager/viewer/user |
| §15 | Multi-tenancy | ➖ | Não aplicável (marketplace B2C) — ADR-0005 |
| §16 | Logs JSON estruturados | ✅ | Loki + log levels |
| §16 | trace_id, correlation_id | ✅ | Propagação via dispatcher |
| §16 | Proibido logar PII | ⚠️ | Smoke `pii-log-scan` cobre; revisar broadly |
| §16 | RED por endpoint | ✅ | Prometheus + `/internal/metrics` por service |
| §16 | Tracing W3C | ✅ | OpenTelemetry + Tempo |
| §16 | SLO documentado em `/docs/slo.md` | ❌ | Pendente |
| §16.6 | Audit log imutável | ✅ | `audit_log` table append-only (migration 012) |
| §17 | `/health` + `/ready` + `/metrics` | ✅ | Padronizado PHASE-10 |
| §18 | Timeout + retry + circuit breaker em externos | ⚠️ | Timeout sim; circuit breaker parcial |
| §19 | Jobs idempotentes + timeout + DLQ | ⚠️ | `sender_outbox` sim; cron jobs (`reconcile`, `user-deletion`) com timeout systemd |
| §20 | Config via env, validação no startup | ✅ | `config.go` valida |
| §21 | Kubernetes + Helm | ❌ | **VPS única + systemd** — não aplicável agora. Sem ADR (gap) |
| §21 | IaC | ❌ | Bash installer em `viralefy_ops/`. Sem Terraform/OpenTofu |
| §21 | CI/CD GitHub Actions | ✅ | Conforme |
| §21 | Promoção por artefato imutável | ⚠️ | `viralefy-update` build local in-place; futuro: containers |
| §22 | Coverage mínimo por camada | ❓ | Sem gate CI; medir com `go test -cover` por repo |
| §22 | Caminhos críticos (auth/payment) testados | ✅ | auth_service_test, checkout_service_test, payment provider tests |
| §22.3 | Test Kit (smoke/security/pentest/authz/hardening/chaos/simulated) | 🚧 | Smoke ativo (external + internal). Demais em construção (agents J-O) |
| §23 | Makefile padrão | ⚠️ | `viralefy_core/Makefile`, `viralefy_api/Makefile` parcial |
| §24 | Conventional Commits | ✅ | Inspeção de `git log` confirma |
| §24 | Trunk-based + squash merge | ✅ | Main protegida; PR linear |
| §24 | CODEOWNERS | ❌ | Não configurado |
| §25 | Owner explícito + oncall | ⚠️ | Único maintainer = sem necessidade hoje; documentar |
| §26 | Runbooks em `/docs/runbook.md` | ✅ | `RUNBOOK-*.md` no archive |
| §26 | Postmortem blameless | ✅ | `INCIDENT-ORDER-450F0E6F.md` exemplo |
| §27 | ADRs em formato MADR | ✅ | 10 ADRs criados nesta auditoria |
| §28 | Archive de tasks/chats | ✅ | `viralefy_archive` ativo |
| §29 | Templates | ❌ | Sem `/templates` ainda |
| §30 | Performance targets | ❓ | Não medido sistematicamente |
| §31 | Feature flags | ❌ | Sem ferramenta; flags ad-hoc via env |
| §32 | LGPD | ⚠️ | C3+C5 done; C1+C2+C4 pendente — `LGPD-BASELINE-2026-06-10.md` |
| §33 | FinOps | ➖ | VPS única, custo fixo conhecido |
| §34 | IA assistida | ✅ | PRs revisados; chat archive deste audit existe |
| §35 | Definition of Done | ⚠️ | Parcial — CI verde sim, ADR/runbook nem sempre |

### Legenda

- ✅ Conforme
- ⚠️ Parcial / com ressalvas
- ❌ Não conforme (gap claro)
- ❓ Não verificado / a medir
- ➖ Não aplicável

---

## DDD Audit por Repo (Go services)

Critérios verificados via `grep` em 2026-06-11:

### viralefy_core (motor principal)

| Critério | Resultado | Esperado |
|---|---|---|
| `domain/` importa `infrastructure/` | 0 | 0 ✅ |
| `domain/` importa `application/` | 0 | 0 ✅ |
| `domain/` importa `interface/` | 0 | 0 ✅ |
| `application/` importa `interface/` | 0 | 0 ✅ |
| `application/` importa `infrastructure/` | **34** | 0 (puro hexagonal) ou aceitar híbrido §4.X |
| Arquivo > 500 linhas | **3** | revisar |

**Top arquivos grandes (>500 linhas):**

| Arquivo | Linhas |
|---|---|
| `internal/interface/http/handlers.go` | **3323** |
| `internal/application/checkout_service.go` | 639 |
| `internal/interface/http/security_test.go` | 567 (teste, exceção §6) |
| `internal/application/delivery_capture_cron_test.go` | 469 (teste) |
| `internal/infrastructure/persistence/postgres/order_repo.go` | 466 |
| `internal/infrastructure/persistence/postgres/seed.go` | 465 (seed, exceção §6) |
| `internal/application/payment_receiver.go` | 462 |

**Diagnóstico:** estrutura DDD presente, mas `handlers.go` precisa ser quebrado por bounded context (auth, checkout, orders, admin, plans...). 34 imports de `infrastructure/` em `application/` indicam **DDD híbrido §4.X** — use cases instanciam repositórios concretos em vez de aceitar ports. Plano: introduzir interfaces de repositório em `domain/repositories/` e usar DI no construtor.

### viralefy_api (LEGACY — em soak)

Espelho próximo do core:

- `handlers.go` = **3125 linhas**.
- 33 imports de `infrastructure/` em `application/`.
- Status: ADR-0004 — arquivar pós 2026-06-24.

**Recomendação:** **não refatorar** — apenas arquivar.

### viralefy_auth

| Critério | Resultado |
|---|---|
| Imports proibidos em `domain/` | 0 ✅ |
| `application/` importa `interface/` | 0 ✅ |
| `application/` importa `infrastructure/` | **2** |
| Arquivos > 500 | 0 ✅ |

**Top arquivos:**

- `internal/application/auth_service.go` — 470 linhas (perto do limite, monitorar)
- `internal/interface/http/handlers.go` — 409 (aceitável)
- `internal/application/token_service.go` — 355

**Diagnóstico:** **boa saúde DDD**. Service novo, layout limpo. 2 imports infra→application são reduzíveis.

### viralefy_payments

| Critério | Resultado |
|---|---|
| Imports proibidos em `domain/` | 0 ✅ |
| `application/` importa `interface/` | 0 ✅ |
| `application/` importa `infrastructure/` | **0** ✅ |
| Arquivos > 500 | 0 ✅ |

**Top arquivos:**

- `internal/application/payment_methods.go` — 363
- `internal/infrastructure/external/payment/stripe.go` — 292
- `internal/infrastructure/external/payment/abacatepay.go` — 289

**Diagnóstico:** **referência de arquitetura limpa**. Adapters em ACL conforme §4. Application não toca infra direto — usa ports. **Modelo a seguir nos outros services.**

### viralefy_sender

| Critério | Resultado |
|---|---|
| Imports proibidos em `domain/` | 0 ✅ |
| `application/` importa `interface/` | 0 ✅ |
| `application/` importa `infrastructure/` | **0** ✅ |
| Arquivos > 500 | 0 ✅ |

**Top arquivos:**

- `internal/application/outbox.go` — 395
- `internal/infrastructure/external/telegram/bot.go` — 225
- `internal/application/templates/checkout.go` — 204

**Diagnóstico:** **referência também**. Outbox pattern bem aplicado (deveria ser modelo para event_outbox no core — ADR-0002 fase 2).

---

## Gaps Críticos Detalhados

### Gap 1 — `handlers.go` monolítico (3000+ linhas)

**Severidade:** Alta
**Repo afetado:** `viralefy_core` (+ `viralefy_api` legacy)
**Diretriz:** §6 (300 linhas dispara revisão crítica)

**Diagnóstico:** Toda a API HTTP pública vive em um arquivo gigante. Faz código difícil de revisar, alta carga cognitiva, conflito de PRs frequente.

**Plano de refactor (Q3 2026):**

1. Quebrar por bounded context:
   ```
   internal/interface/http/
   ├── handlers.go         (router setup + middlewares globais, ≤200 linhas)
   ├── auth_handlers.go    (~400 linhas)
   ├── checkout_handlers.go
   ├── orders_handlers.go
   ├── admin_handlers.go
   ├── plans_handlers.go
   └── ...
   ```
2. Cada handler file < 500 linhas.
3. Refactor incremental (1 PR por contexto), não big-bang.

### Gap 2 — Sem barreira física contra queries cross-context (ADR-0001 risk)

**Severidade:** Média
**Plano:** Linter Go custom (ou go-arch-lint) que rejeite import de tabelas/repositórios fora do escopo do serviço.

**Action:**

```yaml
# .go-arch-lint.yml em cada repo
components:
  - name: payments
    in: internal/infrastructure/persistence/postgres/gateway_repo.go
  # ...
```

Reject pattern: `viralefy_auth` lendo `orders` table direto.

### Gap 3 — Outbox apenas em sender (ADR-0002 follow-up)

**Severidade:** Média
**Risco:** se `viralefy_core` crashar entre commit de order e chamada para `viralefy_payments`, evento perdido.
**Mitigação imediata:** já implementado retry + timeout em `paymentsclient`.
**Mitigação completa (fase 2):** tabela `event_outbox` em `viralefy_core` com poller worker.

### Gap 4 — Test Kit `viralefy_ops` incompleto

**Severidade:** Média (segurança)
**Status:** Smoke (external + internal) ativo. Demais (pentest, authz, hardening, chaos, simulated) em construção.
**Plano:** roadmap entrega trimestral, prioritizando authz + hardening + pentest.

### Gap 5 — LGPD C1/C2/C4 pendentes

**Severidade:** Alta (compliance)
**Status:**

- C3 — Consent banner ✅
- C5 — Anonimização orders após 5 anos ✅
- C1 — DPIA formal ❌
- C2 — Política de retenção documentada por tipo ❌
- C4 — DPO contato + processo de exercício de direitos ❌

**Plano:** ver `LGPD-BASELINE-2026-06-10.md`.

### Gap 6 — Sem SLO documentado (§16.4)

**Severidade:** Baixa-Média
**Plano:** criar `viralefy_core/docs/slo.md` com targets:

- API p95 < 300ms (conforme §30)
- API p99 < 1s
- 99.9% uptime mensal
- Erro budget: 0.1% mensal → freeze de features quando consumido

### Gap 7 — Sem CODEOWNERS (§25)

**Severidade:** Baixa (equipe atual = 1 humano)
**Plano:** quando equipe crescer, configurar `CODEOWNERS` por bounded context.

### Gap 8 — Sem feature flags formais (§31)

**Severidade:** Baixa
**Atual:** flags via env (`LEGACY_HS256_DISABLED`, etc.)
**Plano:** introduzir OpenFeature SDK quando feature rollouts graduais virem necessidade.

### Gap 9 — Templates ausentes (§29)

**Severidade:** Baixa
**Plano:** criar `viralefy_archive/templates/` com ADR.md, RUNBOOK.md, TASK.md, OPENAPI_TEMPLATE.yaml.

---

## Roadmap Recomendado — Q3 2026

| Sprint | Item | Owner | DoD |
|---|---|---|---|
| S1 | Quebrar `handlers.go` (core) por context | Backend | Cada handler file < 500 linhas, testes verdes |
| S1 | Centralizar `bcryptCost` (ADR-0003) | Backend | Constante exportada de `shared/crypto` |
| S2 | Linter custom imports cross-context | Backend | CI gate ativo |
| S2 | LGPD C2 (política retenção) | Compliance | Documento aprovado |
| S3 | LGPD C4 (DPO + direitos) | Compliance | Página + processo |
| S3 | SLO docs `/docs/slo.md` por service | DevOps | 1 doc por service |
| S4 | Templates em `viralefy_archive/templates/` | Docs | 5 templates base |
| S4 | Test Kit ops: authz + hardening completos | DevOps | Conforme §22.3 |
| S4 (esticado) | Event outbox no core (ADR-0002 fase 2) | Backend | Tabela + poller + 1 evento migrado |

---

## Apêndice — Comandos para reproduzir auditoria

```bash
# Imports proibidos em domain/
for repo in viralefy_api viralefy_core viralefy_auth viralefy_payments viralefy_sender; do
  base="$repo/internal"
  echo "=== $repo ==="
  grep -rE '"[^"]*/internal/infrastructure' $base/domain/ | wc -l
  grep -rE '"[^"]*/internal/application'    $base/domain/ | wc -l
  grep -rE '"[^"]*/internal/interface'      $base/domain/ | wc -l
done

# Arquivos > 500 linhas
for repo in viralefy_api viralefy_core viralefy_auth viralefy_payments viralefy_sender; do
  echo "=== $repo ==="
  find $repo/internal -name "*.go" -exec wc -l {} \; | sort -rn | head -10
done

# bcrypt cost audit
grep -rn "bcrypt.GenerateFromPassword" */internal/ | grep -v "_test\."

# ACL audit (Stripe DTOs em domain/application — esperado: zero)
for repo in viralefy_payments viralefy_core; do
  grep -rE "stripe-go" $repo/internal/domain/ $repo/internal/application/
done
```

---

## Links

- `viralefy_archive/diretrizes.md` — fonte de verdade normativa
- `viralefy_archive/adr/` — 10 ADRs criados nesta auditoria
- `viralefy_archive/CHECKLIST.md` — estado operacional
- `viralefy_archive/CONTEXT.md` — snapshot técnico
- `viralefy_archive/LGPD-BASELINE-2026-06-10.md`
- `viralefy_archive/PENTEST-BASELINE-2026-06-10.md`
- `viralefy_archive/CORAZA-SOAK-STATUS.md`
