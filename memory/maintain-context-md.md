---
name: maintain-context-md
description: "Ao finalizar cada task no Viralefy, atualizar/criar context MD + checklist extensivo no viralefy_archive."
metadata: 
  node_type: memory
  type: feedback
  originSessionId: 156ce2c8-a44d-4b68-83b1-2ec311c4d144
---

Ao final de CADA task substantiva no projeto Viralefy, atualizar dois arquivos no
`viralefy_archive/`:

1. **CONTEXT.md** — snapshot geral do estado da plataforma. Cobre infra, arquitetura,
   credenciais de acesso, features ativas, decisões importantes. Substitui o snapshot
   anterior pra qualquer sessão futura pegar contexto em uma única leitura.

2. **CHECKLIST.md** — checklist extensivo do que foi pedido pelo user nas conversas:
   marca `[x] feito` / `[ ] pendente` linha por linha. Quando o user pede algo novo,
   adiciona como `[ ]`; quando entrega, marca `[x]` com link pro commit.

**Why:** o user disse verbatim "sempre faça isso. ao finalizar uma task adicione o
contexto importante num md e faça um checklist extensivo com tudo que te pedi.
aloque isso na deepmemory." A intenção é compactar contexto entre sessões — em vez
de re-derivar o estado, qualquer próxima sessão lê os dois MDs e parte de onde a
anterior parou.

**How to apply:**
- Ao concluir um deploy / E2E verde / task fechada, antes de fechar a resposta:
  1. Atualizar `CONTEXT.md` (replace por completo se mudou significativamente)
  2. Atualizar `CHECKLIST.md` (incrementar com novas entries e marcar concluídos)
  3. Commit + push no `viralefy_archive`
- Manter ambos legíveis: tabelas, headings claros, sem narrativa rasa. Cada linha
  é alvo de busca.
- Linkar entre [[viralefy-features-v2]], [[viralefy-ops-and-github]] etc. quando relevante.
- ROADMAP.md continua existindo como visão de futuro (RECOMMENDATIONS.md → ROADMAP);
  CONTEXT é o snapshot atual; CHECKLIST é o histórico de pedidos do user.
- RUNBOOK.md continua sendo o playbook de ops, separado.
