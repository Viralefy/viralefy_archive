# Task — Paginação no backoffice + vazamento de usuários de teste

**Data:** 2026-07-22
**Origem:** "o backoffice não tem paginação" + "na página de usuário tem vários critical flow test"

## Problema 1 — "Critical Flow Bot" na lista de clientes

**Causa raiz (incompatibilidade de domínio):**

| Componente | Domínio |
|---|---|
| `viralefy-critical-flows` (cria) | `@test.viralefy.com` |
| `test-cleanup-cron` (apaga) | `%@viralefy.test` |

Os dois nunca casaram. O monitor roda de hora em hora e **cada execução deixava
um usuário órfão pra sempre** — daí o acúmulo visível no painel.

**Correção:** o `critical-flows` passou a usar `@viralefy.test`, o domínio
reservado (TLD `.test`, RFC 2606) que o resto da suíte já usa. O cron passa a
limpar sozinho.

**Decisão deliberada:** NÃO ampliei o pattern do cron pra incluir
`@test.viralefy.com`. Esse é subdomínio de um domínio real — garantia mais fraca
que um TLD reservado — e o cron documenta a constante como defense-in-depth
("não parametrizar, constante on purpose"). Ampliar enfraqueceria a proteção
permanentemente. O passado é drenado por um comando pontual e auditado:
`viralefy_ops/bin/viralefy-purge-legacy-test-users` (dry-run por padrão,
transação única, preserva pedido pago).

**Camada extra:** a listagem admin agora esconde fixtures `@viralefy.test` por
padrão (`include_test=1` traz de volta). Isso também tira da frente as personas
dos testes de authz (`superadmin@viralefy.test`, `user-b@viralefy.test`), que
nunca foram clientes.

## Problema 2 — sem paginação

`GET /v1/admin/users` fazia `ListWithCreditBalance(ctx, 200)`: **teto fixo de 200
sem paginação e sem aviso**. Acima disso o cliente não existia pro admin. Pior: a
busca do backoffice filtrava em memória, ou seja, só enxergava o que já tinha
vindo — procurar cliente antigo não achava nada.

**Implementado:**
- Contrato reutilizável em `internal/interface/http/pagination.go`:
  `limit`/`cursor`/`q` → `{data, meta{next_cursor, has_more, total, limit}}`.
- **Cursor keyset (§12), não OFFSET**: com OFFSET, um cadastro durante a
  navegação empurra a lista e a mesma linha aparece duas vezes (ou some).
- Busca ILIKE no servidor, em email e nome, com `total` calculado sob os MESMOS
  filtros da página.
- UI: Anterior/Próxima com pilha de cursores, debounce de 300ms, descarte de
  resposta obsoleta por sequência, contador "1–50 of 137", estado de carregando.
- "Selecionar todos" passou a marcar só a página atual — a ação em massa é soft
  delete e não pode alcançar linha que o admin não viu.

## Bugs achados pelos testes hostis (§22.8)

1. **Null byte na busca virava 500.** `\x00` chega no Postgres e estoura
   `invalid byte sequence for encoding "UTF8"`. 500 por input hostil é falha de
   pentest — agora 400 na borda, com contraprova de que acento e unicode astral
   legítimos continuam passando.
2. **`%` na busca casava a base inteira.** O termo ia parametrizado (sem
   concatenação), mas `%` e `_` são curingas do LIKE. Agora escapados, com
   `ESCAPE '\'` explícito.

`limit` distingue erro de FAIXA (clampa — quem digita 99999 quer o máximo) de
erro de SINTAXE (400 — `abc`, `12.5`, `1e3`, sem coerção silenciosa).

## Verificação

- 6 testes unitários de borda + 4 de integração contra Postgres real.
- Ponta a ponta contra a API rodando, com 120 clientes + 7 fixtures semeados:
  **18 páginas percorridas, 120 únicos, zero duplicata, zero perda**;
  total 120 sem fixtures / 127 com; busca `%` → 0; cursor lixo, limit texto e
  null byte todos em **400 INVALID_PAGINATION** (nenhum 500).
- `go test ./...` e build do backoffice verdes.

## Em aberto

- As outras listas admin (**orders, invoices, tickets, reviews**) seguem sem
  paginação — `ListAllView` devolve tudo. O contrato de `pagination.go` foi feito
  pra ser reusado; falta aplicar. Orders é a mais urgente (cresce mais rápido).
- Endpoints admin não estão na OpenAPI (lacuna pré-existente, não introduzida
  aqui) — documentar junto quando as outras listas forem paginadas.
- `viralefy-purge-legacy-test-users` precisa ser rodado no servidor (via ops)
  pra drenar os bots já acumulados.
