# Viralefy — INDEX.md (Índice de Documentação)

**Última atualização:** 2026-06-12

Mapa completo de todos os documentos do `viralefy_archive`. Para começar: leia `CONTEXT.md`, depois `CHECKLIST.md`.

---

## 📍 Entry points (leia primeiro)

| Doc | Propósito |
|---|---|
| **[CONTEXT.md](CONTEXT.md)** | Snapshot factual do estado atual da plataforma |
| **[CHECKLIST.md](CHECKLIST.md)** | Done + pending priorizado |
| **[SESSION-2026-06-11.md](SESSION-2026-06-11.md)** | Detalhes da sessão de 11/06 (auth UI / tracking / soft-delete / honeypot) |
| **[README.md](README.md)** | Overview do archive |
| **[diretrizes.md](diretrizes.md)** | Padrões de engenharia (normativo) v4.0 |

---

## 🏗️ Arquitetura e fases

| Doc | Conteúdo |
|---|---|
| **[PHASE-7-PLAN.md](PHASE-7-PLAN.md)** | Storage MinIO + 2FA + dashboards |
| **[PHASE-8-MICROSERVICES.md](PHASE-8-MICROSERVICES.md)** | Split api → core/auth/payments/sender |
| **[PHASE-9-ARCHITECTURE.md](PHASE-9-ARCHITECTURE.md)** | Dispatcher Rust + cutover plan (1056 linhas) |
| **[PHASE-9-BUCKET-2-PLAN.md](PHASE-9-BUCKET-2-PLAN.md)** | Split 2a/2b/2c do user-auth cutover |
| **[MICROSERVICES-OPS.md](MICROSERVICES-OPS.md)** | Operação dos microservices |
| **[ROADMAP.md](ROADMAP.md)** | Roadmap macro |
| **[STATUS-CHECKLIST.md](STATUS-CHECKLIST.md)** | Histórico de ~250 items |

---

## 📋 Runbooks operacionais (11)

| Doc | Quando usar |
|---|---|
| **[RUNBOOK.md](RUNBOOK.md)** | Operação geral (legacy) |
| **[RUNBOOK-DR.md](RUNBOOK-DR.md)** | Disaster recovery (drill executado 9s warm) |
| **[RUNBOOK-INCIDENT-RESPONSE.md](RUNBOOK-INCIDENT-RESPONSE.md)** | Resposta a incidentes (955 linhas, 8 playbooks SEV1-4) |
| **[RUNBOOK-BACKUP-VERIFY.md](RUNBOOK-BACKUP-VERIFY.md)** | Backup verify + restore drill |
| **[RUNBOOK-USER-DELETION.md](RUNBOOK-USER-DELETION.md)** | LGPD hard-delete cron |
| **[RUNBOOK-COOKIE-CONSENT.md](RUNBOOK-COOKIE-CONSENT.md)** | Cookie consent gate (LGPD Art. 8) |
| **[RUNBOOK-PROOF-MIGRATION.md](RUNBOOK-PROOF-MIGRATION.md)** | Migração proofs base64 → MinIO |
| **[RUNBOOK-SMOKE-ADMIN.md](RUNBOOK-SMOKE-ADMIN.md)** | Smoke admin via SQL-mint (sem TOTP) |
| **[RUNBOOK-EXTERNAL-SMOKE.md](RUNBOOK-EXTERNAL-SMOKE.md)** | GitHub Actions cron 15min |
| **[RUNBOOK-RENOVATE.md](RUNBOOK-RENOVATE.md)** | Auto-merge + triagem de vulns |
| **[RUNBOOK-CLOUDFLARE-MIGRATION.md](RUNBOOK-CLOUDFLARE-MIGRATION.md)** | Migration Coraza → Cloudflare (1031 linhas, decisão: NÃO migrar agora) |

---

## 🔒 Segurança e compliance

| Doc | Conteúdo |
|---|---|
| **[PENTEST-BASELINE-2026-06-10.md](PENTEST-BASELINE-2026-06-10.md)** | Self-pentest baseline (0 CRITICAL, 3 HIGH resolved + 4 MEDIUM fixed) |
| **[CORAZA-SOAK-STATUS.md](CORAZA-SOAK-STATUS.md)** | Re-audit Coraza WAF + decisão flip |
| **[REVIEW-XSS-AUDIT.md](REVIEW-XSS-AUDIT.md)** | /v1/me/reviews 12 payloads + rule 900300 fix |
| **[LGPD-BASELINE-2026-06-10.md](LGPD-BASELINE-2026-06-10.md)** | Self-audit LGPD (score BAIXA-MÉDIA, 5 gaps + roadmap 18d) |
| **[COMPLIANCE.md](COMPLIANCE.md)** | Compliance overview |

---

## 📊 Observability + SLO

| Doc | Conteúdo |
|---|---|
| **[SLO-DEFINITIONS.md](SLO-DEFINITIONS.md)** | 11 SLOs + error budgets + burn rate |

---

## 📐 ADRs (Architecture Decision Records)

Pasta: `adr/`

| ADR | Tópico | Status |
|---|---|---|
| **[0001](adr/0001-shared-database-vs-schema-per-service.md)** | Shared DB vs schema-per-service | ACCEPTED (desvio §10 documentado) |
| **[0002](adr/0002-http-loopback-vs-outbox-broker.md)** | HTTP loopback vs Outbox/NATS/Kafka | ACCEPTED (desvio §9 documentado) |
| **[0003](adr/0003-bcrypt-cost-12.md)** | bcrypt cost 12 | ACCEPTED |
| **[0004](adr/0004-viralefy-api-legacy-soak.md)** | Legacy soak 14d | ACCEPTED |
| **[0005](adr/0005-single-tenant-marketplace.md)** | Single tenant (§15 N/A) | ACCEPTED |
| **[0006](adr/0006-coraza-waf-vs-cloudflare.md)** | Coraza vs Cloudflare WAF | ACCEPTED Coraza |
| **[0007](adr/0007-migration-tracker-sequential.md)** | Migration tracker sequential | ACCEPTED |
| **[0008](adr/0008-frontend-nextjs-stack.md)** | Next.js + React + Tailwind | ACCEPTED |
| **[0009](adr/0009-multi-repo-vs-monorepo.md)** | Multi-repo | ACCEPTED |
| **[0010](adr/0010-payment-providers-acl.md)** | Payment providers ACL | ACCEPTED |
| **[ENGINEERING-CONFORMANCE-AUDIT.md](ENGINEERING-CONFORMANCE-AUDIT.md)** | Conformance vs diretrizes v4.0 + top 5 gaps | - |

---

## 📝 Incidentes documentados

| Doc | Evento |
|---|---|
| **[INCIDENT-ORDER-450F0E6F.md](INCIDENT-ORDER-450F0E6F.md)** | Order manual_pix FP no reconcile cron |

---

## 🎯 Tasks + recomendações

| Doc | Conteúdo |
|---|---|
| **[RECOMMENDATIONS.md](RECOMMENDATIONS.md)** | Recomendações abertas |
| **task/** | Pasta de task archives |

---

## 🔧 Infra do repo

| Item | Função |
|---|---|
| `.github/workflows/external-smoke.yml` | GH Actions cron 15min (36 assertions, off-prod) |
| `.github/workflows/security.yml` | govulncheck + gitleaks |
| `.gitleaksignore` | Allowlist de strings que parecem secrets |
| `renovate.json` | Renovate config (centralized preset) |
| `scripts/external-smoke/` | Scripts do workflow externo |
| `scripts/smoke_admin.py` | Smoke admin via SQL-mint |
| `brand/` | Brand assets |
| `memory/` | Auto-memory storage (Claude) |
| `task/` | Task archives históricos |
| `AGENTS.md` | Instruções pra agents (orquestração) |

---

## 📦 Estrutura de pastas

```
viralefy_archive/
├── README.md
├── INDEX.md                              ← este arquivo
├── CONTEXT.md                            ← snapshot atual
├── CHECKLIST.md                          ← done + pending
├── diretrizes.md                         ← padrões normativos v4.0
├── ENGINEERING-CONFORMANCE-AUDIT.md      ← gap analysis vs diretrizes
├── adr/                                  ← 10 ADRs
│   ├── README.md
│   └── 000N-*.md
├── PHASE-*.md                            ← arquitetura por fase
├── RUNBOOK-*.md                          ← operação (11 runbooks)
├── PENTEST-BASELINE-*.md                 ← pentest auditado
├── LGPD-BASELINE-*.md                    ← LGPD auditado
├── CORAZA-SOAK-STATUS.md                 ← WAF tuning
├── REVIEW-XSS-AUDIT.md                   ← reviews XSS audit
├── COMPLIANCE.md                         ← compliance overview
├── SLO-DEFINITIONS.md                    ← 11 SLOs + alerting
├── INCIDENT-*.md                         ← postmortems
├── ROADMAP.md                            ← roadmap macro
├── RECOMMENDATIONS.md                    ← backlog priorizado
├── STATUS-CHECKLIST.md                   ← histórico ~250 items
├── MICROSERVICES-OPS.md                  ← ops micros
├── scripts/                              ← test scripts
│   ├── external-smoke/
│   └── smoke_admin.py
├── brand/                                ← brand assets
├── memory/                               ← auto-memory
├── task/                                 ← task archives
└── .github/workflows/                    ← external-smoke + security
```

---

## 🚀 Como navegar (por necessidade)

### "Acabei de chegar, quero entender o stack"
1. `CONTEXT.md` — snapshot factual
2. `PHASE-9-ARCHITECTURE.md` — desenho do sistema atual
3. `diretrizes.md` — padrões obrigatórios

### "Preciso resolver um incidente AGORA"
1. `RUNBOOK-INCIDENT-RESPONSE.md` — 8 playbooks
2. `RUNBOOK-DR.md` — se for disaster recovery
3. `INCIDENT-*.md` — postmortems similares

### "Quero contribuir / desenvolver"
1. `diretrizes.md` — padrões obrigatórios
2. `ENGINEERING-CONFORMANCE-AUDIT.md` — gaps conhecidos
3. `adr/` — decisões arquiteturais
4. `CHECKLIST.md` — o que está aberto

### "Quero rodar testes"
- CLI em prod: `viralefy-test [smoke|pentest|security|hardening|authz|integration|chaos|simulated]`
- `RUNBOOK-EXTERNAL-SMOKE.md` — workflow externo
- `RUNBOOK-SMOKE-ADMIN.md` — smoke admin sem 2FA

### "Auditar segurança / compliance"
1. `PENTEST-BASELINE-2026-06-10.md`
2. `CORAZA-SOAK-STATUS.md`
3. `REVIEW-XSS-AUDIT.md`
4. `LGPD-BASELINE-2026-06-10.md`
5. `COMPLIANCE.md`

### "Preciso de SLO / observability"
1. `SLO-DEFINITIONS.md`
2. `RUNBOOK-BACKUP-VERIFY.md`
3. Grafana: https://obs.viralefy.com (dashboards: revenue, payments, behavior, reliability, slo, phase9)

---

## 📈 Métricas do archive

- **Total docs MD:** 33+
- **ADRs:** 10 + README
- **Runbooks:** 11
- **Tamanho total:** ~500KB de documentação
- **Última auditoria de conformidade:** 2026-06-11
- **Test Kit:** §22 completo (smoke/pentest/security/hardening/authz/integration/chaos/simulated)

---

## 🔗 Repositórios relacionados

| Repo | URL |
|---|---|
| viralefy_api (legacy STOPPED) | https://github.com/Viralefy/viralefy_api |
| viralefy_payments | https://github.com/Viralefy/viralefy_payments |
| viralefy_sender | https://github.com/Viralefy/viralefy_sender |
| viralefy_front | https://github.com/Viralefy/viralefy_front |
| viralefy_backoffice | https://github.com/Viralefy/viralefy_backoffice |
| viralefy_ops | https://github.com/Viralefy/viralefy_ops |
| **viralefy_archive** | https://github.com/Viralefy/viralefy_archive |
| **viralefy_core** | https://github.com/Viralefy/viralefy_core |
| **viralefy_auth** | https://github.com/Viralefy/viralefy_auth |
| **viralefy_dispatcher** | https://github.com/Viralefy/viralefy_dispatcher |
