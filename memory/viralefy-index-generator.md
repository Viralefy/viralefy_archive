---
name: viralefy-index-generator
description: "O índice §39 do viralefy é GERADO por viralefy_ops/bin/viralefy-index, nunca escrito à mão"
metadata: 
  node_type: memory
  type: project
  originSessionId: e8575e7f-461b-425a-8284-3421de280d16
  modified: 2026-07-21T11:38:51.620Z
---

O índice de funcionalidades (§39) do workspace viralefy é **gerado**, não mantido à mão:
`viralefy_ops/bin/viralefy-index` (implementação em `viralefy_ops/lib/index/`, 19 módulos)
varre os 10 repos e escreve `viralefy_archive/index/` (MAPA.md, INDEX_GLOBAL.md e um
INDEX_FUNCTIONS_<serviço>.md por repo). Criado em 2026-07-21.

**Why:** são ~3.700 funções em 5 linguagens (Go, Rust, TS, shell, Python) — índice à mão
apodrece em dias, e a §39 exige `nº entradas == nº funções` conferível por contagem.

**How to apply:**
- Depois de mexer em código, rode `viralefy_ops/bin/viralefy-index` e commite o `index/`
  junto — o CI do `viralefy_archive` regenera e falha se divergir.
- A única parte escrita à mão é `lib/index/service-registry.mjs` (propósito dos repos,
  pastas top-level, contratos entre serviços). Repo/contrato novo entra ali.
- `--strict-doc` liga o gate de doc-comment (§6). Hoje reprovaria: 2286 das 3728 funções
  não têm doc-comment de contexto — dívida conhecida, ver [[viralefy-doc-comment-debt]].
- O gerador mora no `_ops` (não no archive) porque o `viralefy_archive/CLAUDE.md` fixa
  "markdown-only, nada de código".
