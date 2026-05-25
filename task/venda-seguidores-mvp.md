# Task: MVP venda de seguidores

**Status:** concluído (estrutura inicial)  
**Data:** 2026-05-22

## Objetivo

Página de venda de seguidores com front, backoffice e API em repositórios separados, seguindo diretrizes v4.0.

## Entregues

- [x] `viralefy_archive/diretrizes.md` + links para agents (`AGENTS.md`, `.cursor/rules`)
- [x] `viralefy_api` — Go, DDD em camadas, PostgreSQL, checkout com cadastro
- [x] `viralefy_front` — planos + modal checkout
- [x] `viralefy_backoffice` — login, planos, gateways, pedidos
- [x] `docker-compose.yml` — PostgreSQL 16

## Próximos passos sugeridos

- Integração real com gateway (Stripe, Mercado Pago, etc.) via ACL
- JWT RS256 + refresh para admin (substituir HS256 dev)
- Repo `viralefy_ops` com smoke tests
- CI GitHub Actions por repositório
