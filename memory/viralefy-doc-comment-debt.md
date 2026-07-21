---
name: viralefy-doc-comment-debt
description: "2286 das 3728 funções do viralefy não têm doc-comment de contexto (§6) — dívida aberta, não corrigir em massa por IA"
metadata: 
  node_type: memory
  type: project
  originSessionId: e8575e7f-461b-425a-8284-3421de280d16
  modified: 2026-07-21T11:39:06.410Z
---

Medido em 2026-07-21 pelo [[viralefy-index-generator]]: **2286 de 3728 funções (61%)**
sem doc-comment de contexto (§3/§6). Concentração: `front` 77%, `backoffice` 84%,
`core` 57%, `api` 59%. Números atuais sempre em `viralefy_archive/index/INDEX_GLOBAL.md`.

**Why:** o gate existe (`viralefy-index --strict-doc`) mas está desligado no exit code
padrão porque ligá-lo hoje trava tudo. A correção é **na origem**, função por função —
gerar 2286 comentários por IA produziria exatamente o "comentário que só repete a
assinatura" que a §3 rejeita, e daria falsa sensação de conformidade.

**How to apply:** atacar por serviço, começando pelo `core` (domínio); quando um serviço
zerar, considerar ligar `--strict-doc` no CI só para ele. Ao escrever o doc-comment,
seguir o contrato da §3: o quê, onde é usada, entradas, saídas, efeitos e o fluxo do dado
(de onde vem → pra onde vai) — e **contíguo à declaração**, senão o extrator não associa.
