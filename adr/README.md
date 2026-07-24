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
| [ADR-0011](0011-cookies-cross-subdomain.md) | Cookies cross-subdomain para persistência de theme/currency | accepted |
| [ADR-0012](0012-json-ld-graph-canonical.md) | JSON-LD via `@graph` canonical com Org + WebSite globais | accepted |
| [ADR-0013](0013-rtl-logical-properties.md) | RTL via CSS logical properties | accepted |
| [ADR-0014](0014-i18n-accept-language.md) | i18n por `Accept-Language` em rotas globais (sem country prefix) | accepted |
| [ADR-0015](0015-front-locale-segment-isr.md) | Segmento `[locale]` + CSP estática para destravar o ISR do front | accepted |
| [ADR-0016](0016-front-strict-dynamic-removal.md) | CSP estática (`'unsafe-inline'`) e remoção do `'strict-dynamic'` — trade-off do ISR | accepted |

## Quando criar uma nova ADR

Conforme diretrizes §27, criar ADR para:

- Escolha de banco, broker, linguagem
- Padrão arquitetural (DDD, hexagonal, etc.)
- Mudança de contrato público
- **Qualquer desvio formal das diretrizes**

Numeração sequential (`NNNN-kebab-case-title.md`). Cada arquivo segue o template MADR.
