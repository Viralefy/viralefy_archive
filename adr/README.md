# Architecture Decision Records — Viralefy

Registro de decisões arquiteturais relevantes e desvios formais vs. `viralefy_archive/diretrizes.md` (v4.0).

Formato: [MADR](https://adr.github.io/madr/) — Markdown Any Decision Record.

## Status possíveis

- `proposed` — proposta sob revisão
- `accepted` — aceita, em vigor
- `deprecated` — não mais aplicável
- `superseded by NNNN` — substituída por outra ADR

## Índice

| ID | Título | Status |
|---|---|---|
| [ADR-0001](0001-shared-database-vs-schema-per-service.md) | Shared database em vez de schema-per-service | accepted |
| [ADR-0002](0002-http-loopback-vs-outbox-broker.md) | HTTP loopback sync em vez de Outbox + NATS/Kafka | accepted |
| [ADR-0003](0003-bcrypt-cost-12.md) | bcrypt cost 12 para senhas (não argon2id) | accepted |
| [ADR-0004](0004-viralefy-api-legacy-soak.md) | viralefy_api LEGACY em soak até 2026-06-24 | accepted |
| [ADR-0005](0005-single-tenant-marketplace.md) | Single tenant (marketplace, não SaaS multi-tenant) | accepted |
| [ADR-0006](0006-coraza-waf-vs-cloudflare.md) | Coraza WAF on-prem em vez de Cloudflare WAF | accepted |
| [ADR-0007](0007-migration-tracker-sequential.md) | Migration tracker sequential + checksum em vez de timestamp-based | accepted |
| [ADR-0008](0008-frontend-nextjs-stack.md) | Next.js 14 + React + Tailwind como stack frontend padrão | accepted |
| [ADR-0009](0009-multi-repo-vs-monorepo.md) | Multi-repo (10 repos) em vez de monorepo | accepted |
| [ADR-0010](0010-payment-providers-acl.md) | Stripe + Heleket + AbacatePay com ACL parcial | accepted |

## Quando criar uma nova ADR

Conforme diretrizes §27, criar ADR para:

- Escolha de banco, broker, linguagem
- Padrão arquitetural (DDD, hexagonal, etc.)
- Mudança de contrato público
- **Qualquer desvio formal das diretrizes**

Numeração sequential (`NNNN-kebab-case-title.md`). Cada arquivo segue o template MADR.
