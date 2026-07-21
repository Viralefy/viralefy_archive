# Task — Índice de funcionalidades exaustivo (§39) + MAPA (§4)

**Data:** 2026-07-21
**Comando:** `/eng-index`
**Escopo:** workspace inteiro (10 repos)

## Contexto

O workspace não tinha `viralefy_archive/index/` — nem `MAPA.md`, nem `INDEX_GLOBAL.md`,
nem índice de microfunções. A §39 exige índice **exaustivo por contagem**
(`nº entradas == nº funções`) e **em grafo**, e a §4 exige o MAPA no archive,
nunca no root. Com ~3,7k funções em 5 linguagens, manter isso à mão é inviável e
apodrece em uma semana: o índice tinha que ser **gerado**.

## Objetivo

1. Enumerar e contar TODA função de cada repo (N).
2. Produzir uma entrada por função (M), com fluxo, adjacência e efeitos.
3. Construir o grafo de serviços e o grafo de chamadas.
4. Conciliar `M == N` por serviço, com contagem independente.

## Decisões

- **Gerador, não escrita à mão.** `viralefy_ops/lib/index/` (19 módulos, uma
  função por arquivo, doc-comment em todas) + CLI `viralefy_ops/bin/viralefy-index`.
- **Casa no `viralefy_ops`, não no `viralefy_archive`.** O `CLAUDE.md` do archive
  fixa "markdown-only, nada de código"; e ferramenta que opera todos os repos é,
  por definição, control plane (§2, `references/ops.md` §4: "não tem comando pra
  aquilo? cria no ops"). A **saída** (MDs) vai para o archive.
- **Grafo em dois níveis.** Mermaid agregado por módulo (um flowchart com 1.200 nós
  não renderiza nem se lê) + adjacência função a função completa, em bloco de texto
  grep-able. É o que a §39 pede: "o Mermaid é o desenho; a adjacência é a fonte
  pesquisável".
- **Sem AST.** Parsers por regex, um por linguagem, com os limites declarados no
  doc-comment de cada arquivo. A honestidade do índice vem da **conciliação por
  contagem independente**, não da promessa do parser.
- **Camada global à mão.** `service-registry.mjs` (propósito, pastas, contratos)
  é a única parte não derivada — revisada junto do ADR a cada mudança arquitetural.

## Resultado

| Serviço | N (código) | M (índice) | M==N | Sem doc |
|---|---|---|---|---|
| viralefy_core | 1206 | 1206 | ✅ | 690 |
| viralefy_api (legado) | 1077 | 1077 | ✅ | 635 |
| viralefy_front | 583 | 583 | ✅ | 450 |
| viralefy_ops | 234 | 234 | ✅ | 119 |
| viralefy_backoffice | 181 | 181 | ✅ | 152 |
| viralefy_auth | 169 | 169 | ✅ | 98 |
| viralefy_payments | 151 | 151 | ✅ | 96 |
| viralefy_sender | 63 | 63 | ✅ | 17 |
| viralefy_api_rust | 39 | 39 | ✅ | 16 |
| viralefy_archive | 25 | 25 | ✅ | 20 |
| **TOTAL** | **3728** | **3728** | ✅ | **2287** |

Grafo de serviços: 10 nós, 18 arestas com contrato nomeado.

## Achados durante a conciliação (bugs de enumeração, corrigidos)

1. **Método Go com receiver anônimo ficava de fora** — `func (ManualPIX) Provider()`
   e `func (*Stripe) Provider()` não casavam (o regex exigia nome de receiver).
   Faltavam 25 funções em `payments`, `core` e `api`.
2. **Os CLIs do ops não eram varridos** — `bin/viralefy-install`, `viralefy-update`,
   `viralefy-test` e outros 8 **não têm extensão** e caíam no filtro. **48 funções
   do control plane** ficavam invisíveis ao índice. Corrigido com detecção por
   shebang.

Sem essas duas correções o índice teria fechado "verde" com 73 funções a menos —
exatamente o "índice de 90 linhas para 100+ funções" que a §39 reprova.

## Dívida registrada (não silenciada)

- **2287 de 3728 funções (61,3%) sem doc-comment de contexto (§3/§6).** Concentração:
  `front` 77%, `backoffice` 84%, `core` 57%, `api` 59%. O gate existe e está ligado:
  `viralefy-index --strict-doc` reprova. Não foi corrigido nesta task porque a
  correção é **na origem** (2287 funções), não no índice — precisa de plano próprio.
- O `viralefy_api` legado (1077 funções) está no índice como `legado`. Regra dos
  30/50% (§3.1) continua valendo: ele não cresce.

### O gate pegou o próprio gerador

Na primeira geração, 17 funções do `lib/index/` apareceram como SEM DOC. Duas
causas reais, não falso-positivo: (1) o doc-comment estava no topo do arquivo,
separado da função por um bloco de constantes — a §3 pede comentário **contíguo**
à declaração; (2) auxiliares privadas (`field`, `cell`, `flowOf`, `byShebang`…)
não tinham doc. Corrigido: o gerador fecha com **0 função sem doc-comment**.

## Feito nesta entrega

1. ✅ `viralefy_ops` commitado: gerador (`lib/index/`), CLI (`bin/viralefy-index`),
   alvo `make index`, README.
2. ✅ `viralefy_archive/index/` commitado (12 MDs) + este archive + ponteiro no `INDEX.md`.
3. ✅ Gate no CI dos dois repos: `viralefy_ops` concilia `M == N` a cada push;
   `viralefy_archive` regenera e exige `git diff --exit-code` em `index/` —
   índice desatualizado trava o merge (§39).
4. ✅ `AGENTS.md` da raiz atualizado (estava em 4 repos e apontando pra diretrizes
   v4.0; agora 10 repos e aponta pro `CLAUDE.md` + índice).
5. ✅ Arquivo `credentials` (chave SSH privada de root do servidor) removido do
   índice do git na raiz e adicionado ao `.gitignore` — estava *staged* pra commit
   (§37 item 3). Nunca chegou a entrar em nenhum commit.

## Em aberto

1. **Dívida de doc-comment: 2287 funções.** Precisa de plano próprio, por serviço,
   começando pelo `core` (domínio). Gerar comentário em massa por IA seria
   exatamente o "comentário que repete a assinatura" que a §3 rejeita.
2. **Mapa de endpoints (§39, superfície de ataque)** — peça que falta ao lado deste
   índice; `route-registry-2026-06-15.md` é o insumo, `/pentest-endpoints` o gerador.
3. **Repo raiz do workspace** segue sem remote, com arquivos nunca commitados
   (`PROJETO_archive/`, `skill/`, imagens, PDFs). Decidir se vira repo de verdade
   ou se deixa de ser repo.
