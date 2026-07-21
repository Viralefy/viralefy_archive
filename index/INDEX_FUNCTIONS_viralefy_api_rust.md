# INDEX_FUNCTIONS — `viralefy_api_rust`

> **Gerado** por `viralefy_ops/lib/index/build-index.mjs` (§39). Não editar à mão:
> corrija o doc-comment na origem e regenere com `/eng-index`.

| Métrica | Valor |
|---|---|
| Arquivos com função indexada | 10 (de 11 varridos) |
| **N — funções declaradas no código** | **39** |
| **M — entradas neste índice** | **39** |
| Invariante `M == N` | ✅ OK |
| Funções sem doc-comment (§3) | 16 (41.0%) |

Colunas: `de onde vem → pra onde vai` é derivada (camada dos chamadores → efeitos detectados);
`chama (out)` / `é chamada por (in)` vêm do grafo resolvido por nome. As listas inline são
limitadas a 10 nomes com sufixo `+N`; a adjacência COMPLETA está na última seção.

## Grafo de chamadas (por módulo)

```mermaid
flowchart LR
```

## Funções


### `src/auth.rs` — camada `infrastructure`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `new` | method | ⚠ SEM DOC | — → http-out | — | — | http-out | 81 |
| `get` | method | Devolve o JwkSet, refresh se TTL estourou. | cmd+infrastructure+interface → retorno | — | main, verify, extract_bearer | — | 91 |
| `verify` | method | Verifica token RS256 com cache atual. | interface → db | get, bootstrap | enforce_hot_set, optional_auth, require_auth | db | 122 |
| `new` | method | Cria uma instância e roda bootstrap inicial. | — → db | bootstrap, listen_loop | — | db | 172 |
| `is_revoked` | method | True se jti está no hot-set. | interface → interno | load | claim_is_revoked | — | 213 |
| `bootstrap` | method | Recarrega o set inteiro do DB (active rows). | infrastructure → db+log | — | verify, new | db, log | 223 |
| `listen_loop` | func | ⚠ SEM DOC | infrastructure → db | — | new | db | 243 |

### `src/config.rs` — camada `infrastructure`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `load` | method | ⚠ SEM DOC | cmd+infrastructure → interno | getenv, env_u64 | main, is_revoked | — | 26 |
| `getenv` | func | ⚠ SEM DOC | infrastructure → retorno | — | load | — | 48 |
| `env_u64` | func | ⚠ SEM DOC | infrastructure → retorno | — | load | — | 52 |

### `src/error.rs` — camada `infrastructure`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `into_response` | method | ⚠ SEM DOC | interface → retorno | — | enforce_path_safety, unauthorized, forward | — | 44 |

### `src/main.rs` — camada `cmd`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `main` | func | [tokio::main] | — → http-out | get, shutdown_signal, init, init_tracing, load | — | http-out | 53 |
| `shutdown_signal` | func | ⚠ SEM DOC | cmd → retorno | — | main | — | 216 |

### `src/metrics.rs` — camada `infrastructure`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `init` | func | Inicializa o recorder global de métricas. | cmd+infrastructure → retorno | — | main, init_tracing | — | 48 |
| `track` | func | Middleware que mede latência por request. | — → interno | route_label | — | — | 71 |
| `route_label` | func | ⚠ SEM DOC | infrastructure → retorno | — | track | — | 102 |

### `src/middleware.rs` — camada `interface`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `enforce_hot_set` | func | `enforce_hot_set` — checa revogação de JTI em TODA request que carrega Bearer. | externo (borda) → interno | verify, extract_bearer, claim_is_revoked, unauthorized | — | — | 31 |
| `enforce_path_safety` | func | `enforce_path_safety` — primeiro middleware. | externo (borda) → interno | into_response, path_is_safe | — | — | 52 |
| `optional_auth` | func | `optional_auth` — valida JWT se presente; passthrough se ausente. | externo (borda) → interno | verify, extract_bearer, claim_is_revoked | — | — | 68 |
| `require_auth` | func | `require_auth` — exige JWT válido. 401 caso contrário. | externo (borda) → interno | verify, extract_bearer, claim_is_revoked, unauthorized | — | — | 92 |
| `extract_bearer` | func | ⚠ SEM DOC | interface → interno | get | enforce_hot_set, optional_auth, require_auth | — | 120 |
| `claim_is_revoked` | func | ⚠ SEM DOC | interface → interno | is_revoked | enforce_hot_set, optional_auth, require_auth | — | 127 |
| `unauthorized` | func | ⚠ SEM DOC | interface → interno | into_response | enforce_hot_set, require_auth | — | 137 |
| `jwks_cache` | func | Wrappers acessíveis pros handlers que precisam consultar JWKS/RevocSet (rotas internas tipo /_revoked/check, /_jwks/refresh — não públicas). [allow(dead_code)] | externo (borda) → retorno | — | — | — | 150 |
| `revocation_set` | func | [allow(dead_code)] | externo (borda) → retorno | — | — | — | 155 |

### `src/observability.rs` — camada `infrastructure`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `init_tracing` | func | ⚠ SEM DOC | cmd → interno | init | main | — | 7 |

### `src/proxy.rs` — camada `interface`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `base_url` | method | ⚠ SEM DOC | interface → retorno | — | forward | — | 32 |
| `resolve_upstream` | func | Lookup table path → upstream. | interface → http-out | — | forward, resolve_upstream_opt | http-out | 44 |
| `forward` | func | `forward` faz o reverse proxy de um axum::Request pro upstream resolvido. | interface → http-out | into_response, base_url, resolve_upstream, upstream_label | proxy_handler | http-out | 113 |
| `upstream_label` | func | ⚠ SEM DOC | interface → retorno | — | forward | — | 222 |
| `proxy_handler` | func | Captura tudo (any path/any method) e despacha pro upstream resolvido. | externo (borda) → interno | forward, path_is_safe | — | — | 233 |
| `resolve_upstream_opt` | func | Compatibilidade com chamadas existentes nos commits anteriores. [allow(dead_code)] | externo (borda) → interno | resolve_upstream | — | — | 243 |
| `_u_compat` | func | [allow(dead_code)] | externo (borda) → retorno | — | — | — | 248 |

### `src/routes.rs` — camada `interface`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `health` | func | ⚠ SEM DOC | externo (borda) → retorno | — | — | — | 10 |
| `ready` | func | ⚠ SEM DOC | externo (borda) → retorno | — | — | — | 19 |

### `src/security.rs` — camada `infrastructure`

| Função | Tipo | O quê | de onde vem → pra onde vai | chama (out) | é chamada por (in) | Efeitos | Linha |
|---|---|---|---|---|---|---|---|
| `path_is_safe` | func | True se o path contém qualquer pattern proibido. | interface+infrastructure → retorno | — | enforce_path_safety, proxy_handler, path_denies_traversal | — | 44 |
| `sanitize_html` | func | Sanitiza string de input removendo HTML executável. | infrastructure → retorno | — | sanitize_strips_html | — | 50 |
| `path_denies_traversal` | method | [test] | — → interno | path_is_safe | — | — | 62 |
| `sanitize_strips_html` | method | [test] | — → interno | sanitize_html | — | — | 80 |

## Adjacência completa (grep-able)

```text
verify -> get   (src/auth.rs:122 -> src/auth.rs:91)
verify -> bootstrap   (src/auth.rs:122 -> src/auth.rs:223)
new -> bootstrap   (src/auth.rs:172 -> src/auth.rs:223)
new -> listen_loop   (src/auth.rs:172 -> src/auth.rs:243)
is_revoked -> load   (src/auth.rs:213 -> src/config.rs:26)
load -> getenv   (src/config.rs:26 -> src/config.rs:48)
load -> env_u64   (src/config.rs:26 -> src/config.rs:52)
main -> get   (src/main.rs:53 -> src/auth.rs:91)
main -> shutdown_signal   (src/main.rs:53 -> src/main.rs:216)
main -> init   (src/main.rs:53 -> src/metrics.rs:48)
main -> init_tracing   (src/main.rs:53 -> src/observability.rs:7)
main -> load   (src/main.rs:53 -> src/config.rs:26)
track -> route_label   (src/metrics.rs:71 -> src/metrics.rs:102)
enforce_hot_set -> verify   (src/middleware.rs:31 -> src/auth.rs:122)
enforce_hot_set -> extract_bearer   (src/middleware.rs:31 -> src/middleware.rs:120)
enforce_hot_set -> claim_is_revoked   (src/middleware.rs:31 -> src/middleware.rs:127)
enforce_hot_set -> unauthorized   (src/middleware.rs:31 -> src/middleware.rs:137)
enforce_path_safety -> into_response   (src/middleware.rs:52 -> src/error.rs:44)
enforce_path_safety -> path_is_safe   (src/middleware.rs:52 -> src/security.rs:44)
optional_auth -> verify   (src/middleware.rs:68 -> src/auth.rs:122)
optional_auth -> extract_bearer   (src/middleware.rs:68 -> src/middleware.rs:120)
optional_auth -> claim_is_revoked   (src/middleware.rs:68 -> src/middleware.rs:127)
require_auth -> verify   (src/middleware.rs:92 -> src/auth.rs:122)
require_auth -> extract_bearer   (src/middleware.rs:92 -> src/middleware.rs:120)
require_auth -> claim_is_revoked   (src/middleware.rs:92 -> src/middleware.rs:127)
require_auth -> unauthorized   (src/middleware.rs:92 -> src/middleware.rs:137)
extract_bearer -> get   (src/middleware.rs:120 -> src/auth.rs:91)
claim_is_revoked -> is_revoked   (src/middleware.rs:127 -> src/auth.rs:213)
unauthorized -> into_response   (src/middleware.rs:137 -> src/error.rs:44)
init_tracing -> init   (src/observability.rs:7 -> src/metrics.rs:48)
forward -> into_response   (src/proxy.rs:113 -> src/error.rs:44)
forward -> base_url   (src/proxy.rs:113 -> src/proxy.rs:32)
forward -> resolve_upstream   (src/proxy.rs:113 -> src/proxy.rs:44)
forward -> upstream_label   (src/proxy.rs:113 -> src/proxy.rs:222)
proxy_handler -> forward   (src/proxy.rs:233 -> src/proxy.rs:113)
proxy_handler -> path_is_safe   (src/proxy.rs:233 -> src/security.rs:44)
resolve_upstream_opt -> resolve_upstream   (src/proxy.rs:243 -> src/proxy.rs:44)
path_denies_traversal -> path_is_safe   (src/security.rs:62 -> src/security.rs:44)
sanitize_strips_html -> sanitize_html   (src/security.rs:80 -> src/security.rs:50)
```
