---
name: viralefy-stack-initial-build-fixes
description: The viralefy apps never compiled as first committed; what was broken and fixed on 2026-05-27
metadata: 
  node_type: memory
  type: project
  originSessionId: 156ce2c8-a44d-4b68-83b1-2ec311c4d144
---

O commit inicial do stack viralefy (api/front/backoffice) **nunca compilou**. Em 2026-05-27 corrigi para rodar:

- **viralefy_api (Go)**: (1) faltava `go.sum` → `go mod tidy`; (2) `interface/http/handlers.go` tinha campo `Checkout` e método `Checkout` no mesmo struct `Handlers` (proibido em Go) → método renomeado para `CreateCheckout` (router atualizado); (3) **todas** as 5 interfaces de repositório em `internal/domain/*.go` declaravam `ctx interface{}` em vez de `ctx context.Context`, então os repos concretos não satisfaziam as interfaces → trocado para `context.Context` + `import "context"`.
- **viralefy_front (Next.js)**: `src/app/page.tsx` tinha `let plans = []` (implicit any[] sob noImplicitAny) → tipado `let plans: Plan[] = []`.
- **viralefy_backoffice (Next.js)**: só faltava `npm install`; código limpo.

Verificado em runtime: fluxo completo OK (GET /v1/plans, login admin, 401 sem token, POST /v1/checkout 201, orders, validação 422). Ver [[run-viralefy-stack-local]].

**Débitos MVP conhecidos (NÃO bugs, já anotados em `viralefy_archive/task/venda-seguidores-mvp.md`)**: JWT HS256 em vez de RS256 (viola §14 das diretrizes), IDs UUIDv4 em vez de UUIDv7/ULID (§10), sem tabela de versão de migrations.
