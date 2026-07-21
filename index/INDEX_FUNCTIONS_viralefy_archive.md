# INDEX_FUNCTIONS — `viralefy_archive`

> **Gerado** por `viralefy_ops/lib/index/build-index.mjs` (§39). Não editar à mão:
> corrija o doc-comment na origem e regenere com `/eng-index`.

| Métrica | Valor |
|---|---|
| Arquivos com função indexada | 2 (de 13 varridos) |
| **N — funções declaradas no código** | **25** |
| **M — entradas neste índice** | **25** |
| Invariante `M == N` | ✅ OK |
| Funções sem doc-comment (§3) | 20 (80.0%) |

Colunas: `de onde vem → pra onde vai` é derivada (camada dos chamadores → efeitos detectados);
`chama (out)` / `é chamada por (in)` vêm do grafo resolvido por nome. As listas inline são
limitadas a 10 nomes com sufixo `+N`; a adjacência COMPLETA está na última seção.

## Grafo de chamadas (por módulo)

```mermaid
flowchart LR
```

## Funções


### `scripts/external-smoke/lib.sh` — camada `ops`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `_bump` | func | ⚠ SEM DOC | — → retorno | — | — | — | 40 |
| `log` | func | ----- logging ----- | — → retorno | — | — | — | 43 |
| `warn` | func | ⚠ SEM DOC | — → retorno | — | — | — | 44 |
| `err` | func | ⚠ SEM DOC | — → retorno | — | — | — | 45 |
| `ok` | func | ⚠ SEM DOC | — → retorno | — | — | — | 46 |
| `sanitize` | func | Sanitize a string for logs — strip bearer tokens + cookies + obvious secret fields. | — → retorno | — | — | — | 50 |
| `set_group` | func | ⚠ SEM DOC | — → retorno | — | — | — | 62 |
| `begin_test` | func | ⚠ SEM DOC | — → retorno | — | — | — | 64 |
| `pass_test` | func | ⚠ SEM DOC | — → retorno | — | — | — | 70 |
| `fail_test` | func | ⚠ SEM DOC | — → retorno | — | — | — | 77 |
| `http_get` | func | ----- curl wrappers ----- http_get URL [extra_curl_args...] Echos "<status_code>\t<latency_ms>\t<body_file>\t<headers_file>" | — → retorno | — | — | — | 91 |
| `http_post_json` | func | ⚠ SEM DOC | — → retorno | — | — | — | 96 |
| `http_options` | func | ⚠ SEM DOC | — → retorno | — | — | — | 101 |
| `_http` | func | ⚠ SEM DOC | — → retorno | — | — | — | 106 |
| `assert_status` | func | ----- assertions ----- | — → retorno | — | — | — | 130 |
| `assert_status_in` | func | ⚠ SEM DOC | — → retorno | — | — | — | 137 |
| `assert_json_array_nonempty` | func | ⚠ SEM DOC | — → retorno | — | — | — | 147 |
| `assert_latency_under` | func | ⚠ SEM DOC | — → retorno | — | — | — | 156 |
| `assert_header_present` | func | ⚠ SEM DOC | — → retorno | — | — | — | 165 |
| `assert_header_absent` | func | ⚠ SEM DOC | — → retorno | — | — | — | 172 |
| `finalize` | func | ----- summary ----- | — → retorno | — | — | — | 182 |

### `scripts/smoke_admin.py` — camada `ops`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `mint` | func | ⚠ SEM DOC | ops → cripto | — | truncate | cripto | 39 |
| `http` | func | ⚠ SEM DOC | ops → retorno | — | truncate | — | 54 |
| `psql` | func | ⚠ SEM DOC | ops → retorno | — | truncate | — | 70 |
| `truncate` | func | ⚠ SEM DOC | — → db | mint, http, psql | — | db | 80 |

## Adjacência completa (grep-able)

```text
truncate -> mint   (scripts/smoke_admin.py:80 -> scripts/smoke_admin.py:39)
truncate -> http   (scripts/smoke_admin.py:80 -> scripts/smoke_admin.py:54)
truncate -> psql   (scripts/smoke_admin.py:80 -> scripts/smoke_admin.py:70)
```
