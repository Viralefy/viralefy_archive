# Padrões e Diretrizes de Engenharia

**Versão:** 4.0
**Atualizado em:** 2026-05-15
**Status:** Documento normativo. Desvios exigem ADR aprovado.

---

## 0. Como Ler

- **MUST / Obrigatório** — regra. Desvio bloqueia merge ou exige ADR.
- **SHOULD / Recomendado** — padrão. Desvio precisa de justificativa no PR.
- **MAY / Opcional** — sugestão.

Quando este documento conflitar com a realidade do problema, **registre um ADR** explicando o desvio. Padrão sem exceção vira dogma; dogma vira dívida.

Versões concretas de stacks ficam no **Anexo A**, atualizado independentemente deste corpo.

---

## 1. Filosofia

Prioridades, em ordem de desempate:

1. Clareza > esperteza
2. Simplicidade > abstração antecipada
3. Manutenibilidade > velocidade pontual
4. Observabilidade > debugging manual
5. Segurança por padrão > segurança como camada final
6. Evolução incremental > big-bang

**Princípios:** Clean Code, SOLID, KISS, DRY (com bom senso — duplicação acidental ≠ duplicação semântica).

**Regra suprema:** se algo aumenta acoplamento, reduz observabilidade, cria dependência desnecessária ou adiciona complexidade sem benefício claro, **provavelmente está errado**.

---

## 2. Estrutura de Repositórios

**MUST**
- Um repositório = uma aplicação ou um bounded context.
- Comunicação entre serviços via HTTP, gRPC, eventos ou mensageria — nunca via banco compartilhado.
- Cada serviço é dono do seu schema.

**SHOULD**
- Evitar mais de um domínio de negócio no mesmo repositório.
- Leitura cross-service por réplica read-only só com ADR e contrato documentado.

---

## 3. Linguagens

| Cenário | Stack |
|---|---|
| APIs de produtividade, scripts, glue code | **Node.js** |
| Serviços backend, concorrência, padrão da casa | **Go** |
| Performance crítica, segurança de memória | **Rust** |

**MUST**
- Versão exata em uso fica no Anexo A.
- Não misturar linguagens dentro do **mesmo bounded context** sem ADR.

**SHOULD**
- Em empate técnico entre Go e Node, **Go vence** (padrão do time).
- Frameworks são bem-vindos; abstrações mágicas não. Critério: consigo entender o stack trace?

---

## 4. Arquitetura

**MUST — todos os projetos**
- Separação explícita de camadas: `domain`, `application`, `infrastructure`, `interface`.
- Inversão de dependência: domínio não conhece infra.
- Domínio não importa frameworks nem ORM.

**SHOULD — projetos com regra de negócio relevante**
- DDD tático (agregados, value objects, eventos de domínio).
- Arquitetura hexagonal (ports & adapters).

**MAY — CRUDs simples**
- Manter as 4 camadas, dispensar táticas DDD pesadas.

### Dependências permitidas

```
interface       → application
application     → domain
infrastructure  → domain, application
```

### Dependências proibidas

```
domain          → qualquer outra camada
domain          → frameworks, ORM, libs de IO
application     → interface
```

### Anti-Corruption Layer

**MUST** em integrações com sistemas externos: adapter dedicado em `infrastructure/external/` que traduz o modelo externo para o modelo de domínio. **Nunca** expor DTOs externos diretamente no domínio.

### 4.X DDD híbrido durante transição

Projetos legados onde código já existe sem separação de camadas **podem** adotar DDD progressivamente em vez de big-bang. Regras:

**MUST**
- Toda nova feature/refactor em código tocado segue o layout completo (`domain/`, `application/`, `infrastructure/`, `interface/`) — não introduzir mais código "flat".
- Ao mover/quebrar arquivo legado, organize já em folders DDD mesmo que internamente alguma classe ainda misture responsabilidades (ex.: service em `application/` ainda chamando SQL direto). Estrutura primeiro, inversão depois.
- Cada PR que toca arquivo híbrido **deve** mover ao menos um pedaço pra direção certa (ex.: extrair entidade pra `domain/`, mover query pra `infrastructure/repositories/`).
- ADR registrando o débito e o plano de remoção: `<project>/docs/adr/<n>-ddd-migration-<contexto>.md`.

**SHOULD**
- Manter teste de cobertura por camada (§22) durante a transição — domain começa com 0%, sobe a cada PR.
- Linter ou guard test que **rejeita imports proibidos** logo que possível (mesmo que com whitelist de exceções legadas):
  - `domain/` não importa `@nestjs/*`, `pg`, `axios`, `infrastructure/*`, `application/*`, `interface/*`.
  - `application/` não importa `interface/*`.

**MAY**
- Marcar arquivos híbridos com comment `// @ddd-hybrid` pra busca fácil e cleanup priorizado.

---

## 5. Estrutura de Pastas

### Node.js

```
src/
├── domain/           # entities, value-objects, services, events, repositories (interfaces)
├── application/      # use-cases, dto, commands, queries
├── infrastructure/   # persistence, messaging, external, observability
├── interface/        # http, grpc, cli
├── shared/
└── config/
tests/
```

### Go

```
cmd/<app-name>/
internal/
├── domain/
├── application/
├── infrastructure/
├── interface/
├── shared/
└── config/
tests/
```

### Rust

```
src/
├── domain/
├── application/
├── infrastructure/
├── interface/
├── shared/
└── config/
tests/
```

---

## 6. Complexidade e Tamanho

**Diretriz (revisão obrigatória, não bloqueio automático)**
- Arquivos acima de **300 linhas** disparam revisão crítica. Se há coesão real, pode ficar; se há responsabilidades múltiplas, refatora antes do merge.
- Funções: idealmente até 50 linhas.
- Use cases: uma responsabilidade.
- Exceções: testes, migrations, gerados, schemas.

**Bloqueio rígido em CI**
- Complexidade ciclomática > 15 em função de produção.
- Aninhamento > 4 níveis.

> Linha de código é proxy ruim para complexidade. Complexidade ciclomática é métrica honesta.

---

## 7. Dependências Internas e Shared Libraries

**MUST**
- Shared libraries são **mínimas** e com escopo claramente delimitado.
- Permitido como shared: observabilidade, autenticação/auth, primitives de infraestrutura, SDKs internos, logging, configuração.

**MUST NOT**
- Criar `commons` / `core-lib` / `platform-utils` genéricos.
- Compartilhar **lógica de domínio** entre bounded contexts.
- Compartilhar entidades de domínio. Cada contexto modela o seu.

> O caminho mais rápido pra um monólito distribuído é uma shared lib chamada `commons`.

**SHOULD**
- Shared libs versionadas com SemVer próprio.
- Breaking changes em shared lib exigem ADR.

---

## 8. CQRS e Padrões de Aplicação

- **Commands**: alteram estado, retornam id ou void.
- **Queries**: nunca alteram estado, otimizadas para leitura, podem usar projeções.
- CQRS **não exige** event sourcing.

---

## 9. Eventos e Mensageria

**MUST — produção e consumo**
- Eventos são imutáveis e versionados (`v1`, `v2`).
- Consumidores idempotentes (deduplicação por id de evento).
- Suporte a replay.

**MUST — compatibilidade evolutiva**
- Novos campos são **opcionais**, com default seguro.
- Nunca remover ou renomear campo sem **nova versão** do evento.
- Consumidores **ignoram campos desconhecidos** (forward compatible).
- Coexistência de versões durante janela de migração documentada.

**MUST — entrega**
- **Transactional Outbox** para publicação de eventos. Dual-write (banco + broker no mesmo fluxo) é proibido.
- DLQ (dead letter queue) configurada para todo consumidor.
- **Retry infinito proibido.** Política de retry explícita com limite e backoff.

**MUST — backpressure**
- Consumidores com limites explícitos de concorrência e prefetch.
- Throttling em produtores quando broker sinaliza pressão.

**Convenção de nome:** `<dominio>.<entidade>.<evento>` no passado.
Exemplos: `catalog.product.created`, `billing.invoice.paid`.

**Brokers**

| Cenário | Stack |
|---|---|
| Eventos leves, baixa latência, pub/sub simples | **NATS** |
| Alto throughput, retenção, replay, streaming | **Kafka** |
| Workflows com routing complexo (caso a caso) | RabbitMQ |

> NATS e Kafka são padrão. RabbitMQ exige justificativa pelo custo operacional.

---

## 10. Banco de Dados

| Caso | Stack |
|---|---|
| Relacional | PostgreSQL |
| Cache | Redis |
| Busca textual | OpenSearch |
| Analytics / eventos | ClickHouse |

**MUST**
- Migrations versionadas, **reversíveis** (com `down`), automatizadas no deploy.
- Schema próprio por serviço.
- Sem joins cross-service no banco.
- **Timestamps em UTC, sempre.** Conversão de timezone apenas na borda (UI/API response).
- **IDs:** UUIDv7 ou ULID por padrão. IDs sequenciais apenas com justificativa (ex: ordenação natural exigida pelo domínio).

**SHOULD — alta escala**
- Separação leitura/escrita (réplicas) quando volume justificar.
- Revisão periódica de índices.
- Análise de query plan em endpoints críticos.
- Particionamento para tabelas com crescimento previsível alto.

**Ferramentas sugeridas:** `golang-migrate`, `node-pg-migrate`, `sqlx-cli`, `flyway`.

---

## 11. Cache

**MUST**
- TTL **sempre explícito**. Sem TTL infinito sem ADR.
- Mitigação de cache stampede (single-flight, lock, jitter).
- Fallback seguro em cache miss — degradação graciosa, nunca falha total.
- Invalidação documentada por chave.

**MUST NOT**
- Cache como source of truth.
- Cache de dados pessoais sensíveis sem criptografia.

---

## 12. APIs

**MUST**
- **OpenAPI 3.1** em `/docs/openapi.yaml` — fonte da verdade.
- Versionamento na URL: `/v1`, `/v2`.
- Validação de payload na borda.
- Erro padrão (compatível com RFC 7807):

```json
{
  "error": {
    "code": "PRODUCT_NOT_FOUND",
    "message": "Product not found",
    "trace_id": "01HXYZ...",
    "details": []
  }
}
```

- Operações de escrita aceitam `Idempotency-Key`.
- Quebra de contrato exige nova versão + janela de deprecação ≥ 90 dias com headers `Deprecation` e `Sunset`.
- Timestamps em **ISO-8601 com timezone explícito** (preferencialmente `Z`).

**MUST — paginação**
- **Cursor pagination** é o padrão.
- Offset apenas em listas pequenas (< 10k itens) e estáticas.
- Resposta inclui `next_cursor` e `has_more`.

**MUST — rate limiting**
- Rate limiting **distribuído** (Redis, gateway, ou serviço dedicado).
- Chave por usuário, API key e tenant.
- Resposta 429 com header `Retry-After`.

**SHOULD**
- Contratos consumer-driven (Pact) entre serviços.
- gRPC para alta performance interna; HTTP/JSON para externa.

---

## 13. Segurança

**MUST — pipeline (fail on high/critical)**
- Dependabot ou Renovate
- SAST (Semgrep / CodeQL)
- SCA (dependências + licenças)
- Container scan (Trivy / Grype)
- Secret scan (Gitleaks)
- Commit signing (GPG / SSH / Sigstore)
- SBOM no build (CycloneDX ou SPDX)

**MUST — runtime**
- Containers não-root, read-only filesystem.
- Distroless ou chainguard quando viável.
- Multi-stage build.
- Healthcheck na imagem.

**MUST — segredos**
- Nunca em código, nunca em env file commitado.
- Storage: Vault, AWS/GCP Secret Manager, sealed-secrets.
- Rotação documentada.

**Licenças permitidas:** MIT, Apache 2.0, BSD, MPL 2.0, ISC.
**Bloqueadas sem ADR:** GPL/AGPL, SSPL, proprietárias.

---

## 14. Autenticação e Autorização

- OAuth2 / OIDC.
- JWT assinado (RS256 ou EdDSA; **nunca HS256** em fluxo público).
- Refresh token rotativo com detecção de reuso.
- RBAC com permissões granulares; ABAC quando necessário.

---

## 15. Multi-tenancy

**MUST — quando aplicável (SaaS, plataformas)**
- Isolamento de tenant explícito em todas as camadas.
- `tenant_id` propagado em contexto, logs e traces.
- Autorização validada **server-side** em toda operação. Nunca confiar em `tenant_id` enviado pelo cliente sem verificação contra o token.
- Queries com `tenant_id` no `WHERE`, sempre. Considerar Row Level Security no Postgres.

**SHOULD**
- Testes de cross-tenant leak em CI.
- Métricas e logs particionáveis por tenant.

---

## 16. Observabilidade

**Stack obrigatória:** Grafana, Alloy, Loki, Tempo, Prometheus, OpenTelemetry.

### 16.1 Logs

- JSON estruturado.
- `trace_id`, `correlation_id`, `tenant_id` (se aplicável) em toda request.
- Níveis: DEBUG, INFO, WARN, ERROR.
- **Proibido logar:** senhas, tokens, JWT, PII (CPF, email, telefone), dados financeiros, payloads de pagamento. Mascaramento obrigatório.

### 16.2 Métricas

- **RED por endpoint/handler:** Rate, Errors, Duration (histograma p50/p95/p99).
- **USE para infra:** Utilization, Saturation, Errors.

### 16.3 Tracing

- Toda chamada externa, fila, banco e fluxo crítico instrumentados.
- Propagação **W3C Trace Context**.

### 16.4 SLOs

- Cada serviço define SLI/SLO em `/docs/slo.md`.
- Error budget consumido → freeze de features até recuperação.

### 16.5 Business Observability

**SHOULD**
- Métricas de negócio expostas (pedidos/min, conversão, churn, etc).
- Dashboards de negócio separados dos técnicos.
- KPIs principais instrumentados desde o dia 1.

### 16.6 Auditoria

**MUST**
- Operações sensíveis (mudança de permissão, transações financeiras, alteração de configuração, ações administrativas) registradas em **trilha de auditoria imutável**.
- Campos mínimos: `actor_id`, `tenant_id`, `action`, `resource`, `timestamp`, `ip`, `user_agent`, `result`.
- Retenção mínima conforme regulação aplicável.
- Storage append-only (não usar a mesma tabela de domínio).

---

## 17. Healthchecks

Endpoints obrigatórios:
- `/health` — liveness (processo está vivo)
- `/ready` — readiness (dependências OK, pronto pra tráfego)
- `/metrics` — Prometheus

---

## 18. Resiliência

**MUST em chamadas externas:**
- Timeout explícito (nunca infinito).
- Retry com backoff exponencial + jitter, idempotência garantida.
- Circuit breaker.
- Rate limiting na borda.
- Bulkhead em integrações críticas.

---

## 19. Jobs e Workers

**MUST**
- Jobs **idempotentes** (pode executar 2x sem corromper).
- Timeout obrigatório por job.
- Política de retry explícita com limite.
- Progress/state persistido para jobs longos ou críticos.
- DLQ para jobs que falharem após max retries.

**SHOULD**
- Jobs longos divisíveis em chunks com checkpoint.
- Cancelamento gracioso (respeitar context/signal).

---

## 20. Configuração

- Via environment variables (12-factor).
- Validação tipada no startup — falha rápido.
- Sem hardcode.
- Defaults seguros (fail closed).

---

## 21. Infraestrutura e Deploy

**MUST**
- Kubernetes + Helm.
- IaC: Terraform ou OpenTofu.
- CI/CD: GitHub Actions.
- Ambientes isolados: `dev`, `staging`, `production`.
- Promoção entre ambientes por **artefato imutável** (mesma imagem).

### 21.1 Estratégia de Deploy

| Estratégia | Quando usar |
|---|---|
| Rolling update | Default para serviços comuns |
| Blue/green | Serviços críticos, rollback instantâneo necessário |
| Canary | Mudanças de alto impacto, rollouts graduais |

**MUST**
- Rollback automatizado quando healthcheck falhar pós-deploy.
- Healthcheck gating: tráfego só vai pra pod ready.
- Janela de validação antes de declarar deploy bem-sucedido.

### 21.2 Preview Environments

**SHOULD**
- PRs em serviços principais geram ambiente efêmero automaticamente.
- Destruído ao merge ou após X dias de inatividade.

---

## 22. Testes

**Obrigatório**
- Testes em **dois eixos**: por código (unit/integration, dentro de cada serviço) e por sistema vivo (smoke/security/pentest/authz/hardening/chaos/simulated, no repo `<project>_ops`).
- Caminhos críticos (auth, pagamento, autorização, billing, eventos de domínio, multi-tenancy) têm testes explícitos cobrindo sucesso, falha e edge cases — independentemente da cobertura agregada.

**Cobertura mínima (por código)**

| Camada | Mínimo |
|---|---|
| `domain` | 80% |
| `application` | 70% |
| `infrastructure` | 40% |
| Global | 60% |

**Mutation testing (SHOULD)** no domínio em serviços críticos: Stryker (JS/TS), `go-mutesting`, `cargo-mutants`.

---

### 22.1 Test Kit do `<project>_ops`

Toda a malha de testes "do sistema vivo" mora num repo dedicado (`<project>_ops`), invocada por um CLI único.

**Estrutura padrão**

```
<project>_ops/
├── bin/
│   └── <project>-test          # CLI: run modes, agrega saída
├── tests/
│   ├── lib.sh                  # helpers compartilhados (cores, assertions, http_call)
│   ├── README.md               # tabela de modos × scripts × duração
│   ├── smoke/                  # health, rotas-chave, shape de respostas
│   ├── integration/            # login real + CRUD ponta-a-ponta
│   ├── security/               # auth bypass, headers, rate-limit
│   ├── pentest/                # OWASP + extensão
│   ├── authz/                  # RBAC + multi-tenancy isolation
│   ├── hardening/              # TLS, cookies, CORS, exposed paths
│   ├── chaos/                  # fuzz, property-based, kill, db-disconnect
│   ├── simulated/              # matriz exaustiva: rotas × personas × injections
│   ├── seeds/                  # SQL de setup (personas de teste, superadmin)
│   ├── unit/                   # delega `go test` / `npm test` por serviço
│   └── workspace-code.sh       # smell-scan no monorepo (arquivos > N linhas, etc.)
├── Makefile
└── README.md
```

**CLI padrão**

```bash
<project> test                  # default: smoke
<project> test smoke
<project> test integration
<project> test security
<project> test pentest
<project> test authz
<project> test hardening
<project> test chaos
<project> test simulated
<project> test unit
<project> test all              # tudo exceto chaos+unit
<project> test full             # all + chaos + unit
<project> test seed-superadmin  # setup inicial (uma vez)
```

**MUST**
- Cada script é executável standalone: `bash tests/smoke/auth-endpoints.sh` deve rodar e sair `0/1`.
- Cada script declara `TEST_NAME` e usa helpers de `lib.sh` (`test_pass`, `test_fail`, `test_skip`, `test_section`, `test_summary`, `http_call`, `assert_http_in`).
- Banner ENORME em vermelho quando há falha — feedback visual impossível de ignorar em CI.
- Skip sem erro quando dependência opcional falta (ex.: openssl ausente em hardening/tls).

---

### 22.2 Saída estruturada (machine-readable)

Toda execução escreve em `/<project>/logs/test-<YYYY-MM-DD>-<HHMMSS-pid>/`:

| Arquivo | Conteúdo |
|---|---|
| `summary.txt` | PASS/FAIL por script, legível |
| `summary.json` | **fonte única pra dashboards/CI** — schema fixo abaixo |
| `run-totals.txt` | 7 linhas: mode, started, finished, duration, scripts, pass, fail, exit |
| `<mode>-<name>.log` | output completo de cada script |
| `cookies.txt` | sessão dos personas (só em `integration`) |
| `coverage-summary.{txt,json}` | cobertura por serviço (só em `unit`) |

**Schema `summary.json`**

```json
{
  "started_at": "2026-05-11T11:35:50Z",
  "finished_at": "2026-05-11T11:35:57Z",
  "duration_seconds": 7,
  "mode": "smoke",
  "log_dir": "/<project>/logs/test-2026-05-11-083550-448694",
  "scripts": [
    {"category": "smoke", "name": "auth-endpoints", "status": "pass"},
    {"category": "smoke", "name": "services-health", "status": "fail"}
  ],
  "totals": {"pass": 23, "fail": 1, "scripts": 24, "exit_code": 1}
}
```

**MUST**
- Exit code 0 se tudo passou; 1 se qualquer caso falhou.
- `summary.json` é contrato — não quebre os campos `mode`, `totals`, `scripts[]`.
- Logs zipados e enviados pra storage de longo prazo após cada CI run (90 dias mínimo).

---

### 22.3 Categorias de teste (por modo)

#### `smoke` — saúde do sistema, < 2min

Cobre: health/metrics de cada serviço, rotas-chave do dispatcher, frontends, observability stack, endpoints por domínio (auth, catalog, billing, etc.), DB connectivity, microservices-status, shape de health/metrics, response-time p95, CORS preflight, OpenAPI availability, log scan pra PII vazada.

Falha = bloqueio de deploy. Roda **antes e depois** de cada `update` em todo ambiente.

#### `integration` — fluxos end-to-end com credenciais reais, < 3min

Cobre: login do superadmin com cookie real, CRUD course/user/subscription via API admin, upload de imagem, reset de senha completo. Usa seed `tests/seeds/test-superadmin.sql` pra garantir user existente.

**Requer pré-seed**: rodar `<project> test seed-superadmin` na primeira vez no ambiente.

#### `security` — controles de segurança "óbvios", < 1min

Cobre: auth bypass tentando rotas admin sem cookie, headers de segurança (CSP, X-Content-Type, HSTS), rate limit no login (50 paralelas → expect 429), formato de password hash (bcrypt cost ≥ 12 / argon2id), `npm audit --audit-level=high`, JWT algorithm validation (RS256 only).

#### `pentest` — OWASP Top 10 + extensão, < 3min

Scripts cobrem (cada um isolado):
- `sql-injection.sh` — payloads SQLi clássicos em query/body. Esperado: 400/422 ou 401/403/404. **NUNCA 500** e nunca 200 com data revelando "OR 1=1".
- `xss.sh` — `<script>`, `<img onerror>`, `javascript:` em campos refletidos. Resposta não pode incluir payload sem escape.
- `idor.sh` / `user-bola.sh` — IDs de outro tenant/user nos paths.
- `ssrf.sh` — URLs apontando pra `127.0.0.1`, `169.254.169.254`, `file://`, redirect chains.
- `jwt-tampering.sh` / `jwt-claim-tampering.sh` / `jwt-algorithm.sh` — alg=none, alg=HS256-com-RS256-pubkey, exp futuro, sub trocado.
- `path-traversal.sh` — `../`, `..%2f`, null bytes.
- `mass-assignment.sh` — POST com campos extras (`is_admin`, `tenant_id`, `created_at`) que deveriam ser ignorados.
- `open-redirect.sh` — `?next=https://evil.com`.
- `host-header.sh` — Host header arbitrário pra envenenar links em emails.
- `csrf.sh` — POST sem origin/referer válido.
- `http-method-tampering.sh` — TRACE, OPTIONS, métodos não suportados.
- `request-smuggling.sh` — `Transfer-Encoding: chunked` + `Content-Length` conflitantes.
- `cache-poisoning.sh` — headers exóticos que envenenam CDN.
- `cookie-bomb.sh` — flood de cookies grandes → expect 4xx limpo, não 500.
- `session-fixation.sh` — session ID atribuído pré-login persiste pós-login.
- `timing-attack.sh` — diff de latência entre user existente vs inexistente no login (alvo: < 30% variance).
- `prototype-pollution.sh` — `__proto__`, `constructor.prototype` no body JSON.
- `redos.sh` — strings catastróficas pra regex (`aaaaaa...aaa!`).
- `billion-laughs.sh` — JSON/XML bomb (nested arrays profundos).
- `clickjacking.sh` — `X-Frame-Options` / CSP `frame-ancestors`.
- `refresh-token-reuse.sh` — usar mesmo refresh duas vezes → 2ª deve revogar família.
- `parameter-pollution.sh` — `?id=1&id=2`.
- `excessive-data-exposure.sh` — endpoint público vaza email/cpf/telefone.
- `header-spoof.sh` — `X-Forwarded-For`, `X-Real-IP`, `X-Original-User` injetados.
- `oversized-payload.sh` — body de 10MB+ → 413, não 500.

#### `authz` — autorização e isolamento, < 1min

- `cross-tenant-idor.sh` — tenant A não vê dados de tenant B (cobre §15: tenant_id sempre no WHERE).
- `rbac-negative.sh` — viewer não consegue write, editor não consegue admin.
- `privilege-escalation.sh` — tenant_admin não consegue virar platform superadmin.
- `permission-boundary.sh` — combinações de roles + recursos → matriz de allow/deny.
- `tenant-isolation.sh` — cookie/JWT de tenant A injetado em rota de tenant B → 403.

#### `hardening` — endurecimento da superfície de ataque, < 1min

- `tls-config.sh` — TLS 1.2/1.3 ok, 1.0/SSLv3 rejeitados, cert válido, HSTS no header, nome bate.
- `headers-full.sh` — CSP, COOP, CORP, Referrer-Policy, Permissions-Policy, X-Content-Type-Options.
- `cookies.sh` / `cookie-attributes.sh` — HttpOnly + Secure + SameSite=Lax|Strict em todos os cookies de sessão.
- `cors.sh` — origens permitidas explícitas, sem `*` em rotas autenticadas.
- `exposed-paths.sh` — `.git/HEAD`, `.env`, `/debug`, `/actuator`, `phpinfo.php` retornam 404 (não 200).
- `default-creds.sh` — login com `admin/admin`, `root/root`, `test/test` falha sempre.

#### `chaos` — comportamento sob stress / falha, < 5min

- `input-fuzz.sh` — strings longas (10MB), null bytes, unicode astral, JSON malformado.
- `property-based.sh` — idempotência (`POST` com `Idempotency-Key` igual 2x → mesmo resultado), p95 < SLO, JWKS sempre formado corretamente, enums com valores fora do range.
- `service-kill.sh` — `systemctl stop <service>`, mede recuperação (gated por `EDUCE_CHAOS_ALLOW=1` — perigoso).
- `db-disconnect.sh` — derruba conexão DB momentaneamente, valida que pool recupera.
- `concurrent-load.sh` — 50 GETs concorrentes em rotas públicas, mede taxa de sucesso e p50/p95/p99, hang > 10s = falha.

#### `simulated` — matriz exaustiva, ~5min

Engine Python (`tests/simulated/run.py`) que cruza **rotas × personas × injections**:

- **Personas (mínimo 3)** declaradas em `personas.json`:
  - `superadmin` (platform role)
  - `tenant_admin` (escopo de 1 tenant de teste)
  - `normal_user` (sem roles)
  Cada persona declara `expected_access` por categoria de rota (`public`, `auth`, `authenticated`, `admin`, `internal`, `import`).

- **Injections (mínimo 10)** em `injections.json`:
  - SQLi (`' OR 1=1 --`, `'; DROP TABLE users CASCADE; --`)
  - XSS (`<script>alert(1)</script>`)
  - Path traversal (`../../etc/passwd`, `..%2f..%2fetc%2fpasswd`)
  - Null byte, unicode RTL override, long string
  - Mass-assignment keys (`is_admin`, `tenant_id`, `created_at`, `password_hash`)

- **Rota catalog** — JSON gerado a partir do OpenAPI ou inventário de rotas do dispatcher (no Educe: `educe_api_go/docs/legacy_inventory.json`).

**Outputs**:
- `raw.jsonl` — uma linha por request, toda evidência.
- `report.md` — relatório humano com seções **AUTO** (passou claro) e **REVIEW** (status inesperado, precisa olho humano).
- `summary.json` — totais por categoria.

**Setup**: `bash tests/simulated/setup.sh` cria as 3 personas no DB com hash bcrypt.

Vars de ambiente úteis (`EDUCE_TEST_*` no Educe — generalizar com `<PROJECT>_TEST_*`):
- `<P>_TEST_API_BASE` (default `http://127.0.0.1:13000`)
- `<P>_TEST_LOG_DIR` (default `/<project>/logs`)
- `<P>_SIM_TENANT_ID`
- `<P>_SIM_MAX_ROUTES` (debug: limita)
- `<P>_SIM_SKIP_MUTATIONS=1` (só GET)

#### `unit` — testes por código, 5-15min

CLI delega para o test runner nativo de cada serviço:
- Go: `go test -cover -race ./...`
- Node/Nest: `npm test` ou `vitest run`
- Next.js: `vitest run` ou `jest`

Gera `coverage-summary.json` agregando cobertura por serviço.

---

### 22.4 Padrão de script (`tests/<mode>/<name>.sh`)

Skeleton obrigatório:

```bash
#!/usr/bin/env bash
# <Categoria> · <Nome curto>
# Descrição clara do que cobre e o esperado.
# Esperado: status X em caso Y. Falha = significado Z.

set -uo pipefail
_DIR="$(cd -P "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../lib.sh
source "$_DIR/lib.sh"

test_section "<Categoria> · <Nome>"

API="$(api_base)"

# Caso 1
assert_http_in "<descrição do caso>" "200|401" GET "$API/v1/<rota>"

# Caso 2 — body shape
http_call GET "$API/v1/<rota>"
if [[ "$HTTP_CODE" == "200" ]]; then
  if echo "$HTTP_BODY" | jq -e '.data | length > 0' >/dev/null 2>&1; then
    test_pass "<rota> retorna dados"
  else
    test_fail "<rota> sem 'data'" "$HTTP_BODY"
  fi
fi

test_summary "<categoria>/<nome>"
exit $TEST_EXIT_CODE
```

**MUST**
- Banner do `test_section` na primeira linha do output.
- Cada caso assertado vira uma linha `✓` ou `✗` ou `○ skip`.
- `test_summary` no fim agrega contadores pra o runner.
- Falhas incluem `HTTP_BODY` truncado nos primeiros 2000 chars (sem PII).

---

### 22.5 Seeds e personas de teste

**MUST**
- Personas declaradas em `tests/seeds/test-*.sql` ou `tests/<mode>/*.json` — versionadas, reproduzíveis.
- Senhas test-only **explicitamente flagadas** (ex.: prefixo `SimTest!`) e **rejeitadas em produção** por validador de senha fraca.
- Setup idempotente: `INSERT ... ON CONFLICT DO UPDATE` — re-rodar não duplica.
- Cleanup automático no fim de cada run? **Não** — deixa lixo pra inspeção. Limpe via comando explícito (`<project> test clean-seeds`).

**Personas mínimas pra cobrir RBAC + multi-tenancy**:

1. `superadmin` — platform role, vê tudo.
2. `tenant_admin_A` — escopo do tenant A.
3. `tenant_admin_B` — escopo do tenant B (pra testar isolamento).
4. `normal_user` — sem role, só dados próprios.
5. (Opcional) `viewer`, `editor`, `support` — combinações de roles dentro de A.

---

### 22.6 Integração com CI

**MUST**
- PR check: `<project> test smoke + security + authz + hardening` (rápido — ~3min total).
- Pré-deploy: `<project> test all` (full minus chaos+unit — ~6min).
- Nightly: `<project> test full` (inclui chaos + unit).
- Bloqueio de merge: fail no `summary.json` (`.totals.fail > 0`) trava merge.

**Dashboards**
- `summary.json` é parseado por job de métricas pra empurrar `tests_pass_total`, `tests_fail_total`, `tests_duration_seconds_bucket` pra Prometheus.
- Falha em smoke pós-deploy dispara rollback automático.

---

### 22.7 Pentest leve via ferramentas externas (complementar)

**SHOULD** — em CI noturno, não a cada PR:
- **OWASP ZAP baseline** (`zap-baseline.py -t https://api.example.com`) — passive scan.
- **Nuclei** (`nuclei -u https://api.example.com -t cves,exposures,misconfiguration`).
- **trivy fs** ou **grype** sobre o repo + imagens Docker pra CVE em deps + base images.
- **Semgrep** ruleset `p/owasp-top-ten` pra SAST.

Resultados em PR comment ou dashboard, **não bloqueiam merge** por default (alto ruído) — mas qualquer **Critical** sem ADR de aceite trava.

---

## 23. Makefile Padrão

```bash
make dev              # ambiente local
make test             # unit + integration
make test-unit
make test-integration
make lint
make fmt
make build
make run
make docker
make migrate
make docs             # gera/valida openapi
make security-scan    # sast + sca local
make smoketest
make pentest-light
make ci               # tudo que o CI roda
make clean
```

---

## 24. Qualidade e Git

**Commits:** Conventional Commits.
**Versionamento:** SemVer.

**Branches — trunk-based como padrão**

```
main      → produção (protegida, linear history)

feature/<ticket>-<slug>
fix/<ticket>-<slug>
hotfix/<ticket>-<slug>
```

GitFlow (`develop`) é opcional e exige justificativa — só vale a pena em times com release cadenciado pesado.

**Pull Requests**
- Tamanho alvo: ≤ 400 linhas alteradas.
- ≥ 1 reviewer (≥ 2 para `domain`, schema, segurança).
- **CODEOWNERS obrigatório.**
- CI verde obrigatório.
- Squash merge na `main`.
- Merge direto na `main` proibido.

---

## 25. Ownership

**MUST**
- Cada serviço tem **owner explícito** (squad ou pessoa).
- `CODEOWNERS` configurado.
- Documentação de **oncall** definida.
- Contato de escalação documentado no README.

---

## 26. Runbooks e Incidentes

### 26.1 Runbooks

**MUST**
- Serviços críticos têm runbook em `/docs/runbook.md`.
- Conteúdo mínimo: como diagnosticar falhas comuns, dashboards relevantes, comandos úteis, como fazer rollback, contatos.
- Incidentes recorrentes atualizam o runbook.

### 26.2 Incidentes

**MUST**
- Postmortem **blameless** para todo incidente Sev1/Sev2.
- RCA (root cause analysis) documentado.
- Ações preventivas rastreáveis (issue/task) com prazo.
- Repositório central de postmortems acessível ao time.

---

## 27. ADR — Architecture Decision Records

Toda decisão arquitetural relevante vira ADR.

```
/docs/adr/
  0001-use-postgresql.md
  0002-adopt-hexagonal-architecture.md
```

Formato MADR. Status: `proposed`, `accepted`, `deprecated`, `superseded by NNNN`.

**Quando criar:** escolha de banco/broker/linguagem, padrão arquitetural, mudança de contrato público, qualquer desvio deste documento.

---

## 28. Archive de Conversas e Tarefas

### 28.1 Chat Archive

**MUST** para conversas que produzem:
- Decisão arquitetural ou de segurança
- Mudança de contrato público
- Escolha de tecnologia
- Resolução de incidente

**SHOULD** para tasks de implementação significativas.

**MAY** para o resto.

```
<project>_archive/chat/
  <YYYY-MM-DD-HH-MM-SS>-<contexto>.md
```

Conteúdo: pergunta original, entendimento, resposta/decisão, alternativas consideradas, riscos, próximos passos.

> Registro indiscriminado de toda interação produz ruído. Registro seletivo do que importa produz contexto histórico útil.

### 28.2 Task Archive

**MUST** para toda task de implementação significativa.

```
<project>_archive/task/
  <task-name>.md
```

Conteúdo: contexto, objetivo, checklist, decisões, blockers, progresso. Atualizar ao fim de cada sessão.

---

## 29. Templates

```
/templates
├── README.md
├── ADR.md
├── TASK.md
├── PR_TEMPLATE.md
├── ISSUE_TEMPLATE.md
├── RUNBOOK.md
└── OPENAPI_TEMPLATE.yaml
```

README mínimo: o que é, como rodar, como testar, como deployar, dependências, observabilidade, oncall, runbook.

---

## 30. Performance — Metas Padrão

| Métrica | Alvo |
|---|---|
| API p95 | < 300 ms |
| API p99 | < 1 s |
| Startup | < 10 s |
| Imagem Docker | < 200 MB (Go/Rust), < 400 MB (Node) |

Metas específicas sobrescrevem, registradas no `/docs/slo.md`.

---

## 31. Feature Flags

Obrigatório para features críticas, migrações e rollouts graduais.
Capacidades: rollout por % de tráfego, segmentação por tenant/usuário, kill switch, expiração de flag.
Sugestões: Unleash, OpenFeature, GrowthBook.

---

## 32. LGPD e Dados Pessoais

**MUST**
- Classificação de dados: público, interno, confidencial, pessoal, pessoal sensível.
- PII nunca em logs (ver §16.1).
- Política de retenção documentada por tipo de dado.
- Processo para exercício de direitos (acesso, correção, eliminação, portabilidade).
- Criptografia em trânsito (TLS 1.2+) e em repouso para dados pessoais.
- DPIA para tratamentos de alto risco.

---

## 33. FinOps — Gestão de Custos

**SHOULD**
- Monitoramento de custo por serviço/squad/tenant.
- Budgets configurados com alertas de threshold.
- Revisão periódica de overprovisioning (CPU/memória/réplicas).
- Tags de billing consistentes em IaC.
- Custo por request rastreado em serviços de alto volume.

---

## 34. Uso de IA Assistida

**MUST**
- Código gerado por IA passa pelo mesmo PR review humano que qualquer outro.
- Autor humano é responsável: assina o commit, entende o código, mantém.
- Saídas de IA não substituem ADR.

**MUST NOT**
- Colar trecho gerado sem ler.
- Aceitar dependências sugeridas sem verificar nome (typosquatting é real).
- Submeter código que não passa em `make ci`.

**SHOULD**
- Prompt e contexto relevantes registrados no chat archive quando a decisão for não trivial.
- Verificar licença de snippets longos sugeridos.

---

## 35. Definition of Done

Uma task está pronta quando, cumulativamente:

- [ ] Testes passam (unit + integration), cobertura nos mínimos
- [ ] Caminhos críticos com testes explícitos
- [ ] Lint, fmt, security scan limpos
- [ ] Observabilidade implementada (logs, métricas, traces, audit se aplicável)
- [ ] OpenAPI atualizada (se for API)
- [ ] Migration testada com rollback (se houver schema change)
- [ ] Documentação atualizada (README, ADR, runbook se aplicável)
- [ ] Smoke tests executados em staging
- [ ] CI verde, code review aprovado
- [ ] Archive de task atualizado
- [ ] Feature flag configurada (se aplicável)
- [ ] CODEOWNERS aplicável revisou

---

## 36. Evolução

- Refactors incrementais. Big-bang rewrite exige ADR e plano de rollback.
- Toda migração de runtime/framework tem flag de coexistência.
- DDD e hexagonal podem ser adotados progressivamente — comece pelas bordas e pelos domínios mais complexos.

---

## Anexo A — Versões Correntes

> Atualizado independentemente do documento principal. Revisão trimestral.

| Stack | Versão alvo (2026-05) |
|---|---|
| Node.js | 24 LTS |
| Go | 1.25 |
| Rust | 1.85 |
| PostgreSQL | 16+ |
| Redis | 7+ |
| Kubernetes | 1.30+ |
| OpenAPI | 3.1 |
| OpenTelemetry | 1.x (estável) |

Mudanças de versão major exigem ADR.

---

## Anexo B — Glossário Mínimo

- **Bounded Context** — fronteira explícita dentro da qual um modelo de domínio é consistente.
- **Outbox Pattern** — gravar evento em tabela no mesmo commit do dado de negócio; publicador assíncrono lê a tabela e publica no broker. Garante consistência sem dual-write.
- **DLQ** — dead letter queue, fila de mensagens que falharam após retries.
- **Anti-Corruption Layer** — adapter que isola seu domínio do modelo externo.
- **SLO** — service level objective, alvo mensurável de qualidade (ex: 99.9% das requests < 300ms em 30 dias).
- **Error Budget** — quanto você pode falhar dentro do SLO antes de freezar features.
- **Blameless Postmortem** — análise de incidente focada em sistema/processo, não em culpa individual.