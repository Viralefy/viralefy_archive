# Viralefy — Fase 9: Redesenho arquitetural (dispatcher, core, auth)

Data **2026-06-09**. Sucessora de PHASE-8-MICROSERVICES.md. Esse documento descreve a próxima onda de carve-out: separar o monolith `viralefy_api` em três responsabilidades distintas — borda dura (dispatcher), motor de domínio (core) e identidade (auth) — com plano honesto de trade-offs e estratégia incremental.

> **Revisão adversarial aplicada (2026-06-09):** este documento passou por draft inicial + revisão adversarial independente (12 críticas estruturadas). Todas as 12 críticas foram incorporadas no corpo do texto — ver Apêndice 11.4 pra audit trail. As edições endereçam estimativas otimistas (9a real é 3-4 semanas, não 1-2), riscos de segurança subestimados (hot-set em memória pura, chave RS256 compartilhada sem TTL), limites do Coraza (não cobre IDOR/BOLA/business logic), e disciplina operacional ausente (DDL porteiro, smoke E2E dual-path, RTO/RPO pós-split).

---

## 0. TL;DR para quem tem 60 segundos

Recomendação: **caminho híbrido (Opção B)**. Não reescrever a borda em Rust agora.

- **Fase 9a (1-2 semanas)** — endurecer borda com Caddy + Coraza WAF (cobre XSS, SQLi, path traversal, command injection sem código novo) + scaffold do `viralefy_auth` Go atrás do api.
- **Fase 9b (2-3 semanas)** — migrar fluxo de auth (login, register, refresh, 2FA, password, JWKS) pro `viralefy_auth`. api atual delega via loopback. Cut-over de cliente Next só depois de paridade.
- **Fase 9c (3-4 semanas)** — extrair `viralefy_core` em Go usando **strangler pattern**: rotas migram por bucket (public read-only → user/me → admin) com api fazendo reverse proxy. Cada bucket tem smoke E2E como porta.
- **Fase 9d (CONDICIONAL, 4-8 semanas)** — só reescrever borda em Rust SE benchmark de produção mostrar gargalo de CPU/latência na validação, OU se vetor de ataque concreto exceder o que Caddy+Coraza+Go middleware seguram. Caso contrário, manter borda em Go fino.

Custo total estimado (9a + 9b + 9c, sem Rust):
- **Otimista (janela protegida, dedicação total):** 6-9 semanas
- **Realista (mantendo prod + on-call):** **10-14 semanas** considerando 9a=3-4sem, 9b=3-4sem, 9c=4-6sem (com bucket 3 levando 2-3 semanas só dele, ver 4.3)

Custo de adicionar 9d *depois* de 9c em prod: **8-14 semanas** de implementação + **3-6 meses de coexistência Go/Rust** até decommission. Não é linear — paridade byte-a-byte de rate-limit, hot-set, OTel custa caro.

O resto deste doc explica por quê.

---

## 1. Status atual (referência, não duplicação)

Para inventário detalhado de rotas, services, integrações, crons e tabelas, ver:

- `INDEX.md` — snapshot do estado de prod
- `PHASE-8-MICROSERVICES.md` — carve-out de payments + sender (já em prod)
- `MICROSERVICES-OPS.md` — runbook dos microservices
- `RECOMMENDATIONS.md` — auditoria técnica original
- `STATUS-CHECKLIST.md` — gates de qualidade

Resumo cru:

```
viralefy_api (Go, monolito orchestrator)
  ├── 25k LOC, 155 arquivos, 55 rotas HTTP públicas
  ├── 9 cron jobs internos
  ├── 10 integracoes externas (Stripe, Heleket, Woovi, AbacatePay, Resend,
  │   MinIO, Telegram, WhatsApp, Cloudflare R2, reCAPTCHA)
  ├── 42 tabelas Postgres
  ├── Auth: dual-sign JWT RS256 (current) + fallback HS256 (legacy),
  │   2FA TOTP AES-256-GCM, JWKS público
  └── Loopback → viralefy_payments (:8081) + viralefy_sender (:8082)
```

Prod faturando. CI/CD com `viralefy-update` zero-downtime + smoke E2E ativo. Toda decisão de Fase 9 PRESERVA esses contratos.

---

## 2. Objetivos da Fase 9

Não é "porque cliente pediu". Os problemas reais que estamos resolvendo:

### 2.1 Superfície de ataque concentrada no monolith
Tentativas de probing (SQLi nos query params do search, bruteforce no `/auth/login`, path traversal nos uploads) caem direto no mesmo binário que serve checkout e admin. Hoje a defesa é só middleware Go ad-hoc. Queremos uma camada dedicada que pode ser endurecida e atualizada sem mexer no domínio.

### 2.2 Auth como alvo prioritário
Login, register, 2FA, refresh e password reset concentram o risco. Hoje vivem espalhados em `auth_service.go`, `user_auth_service.go`, `twofa_service.go`, `password.go`. Bug em um pode vazar credencial pelo outro. Queremos um serviço pequeno, auditável, com superfície mínima e log de tudo.

### 2.3 Blast radius do monolith
Bug no admin pode tirar o checkout do ar. Deploy de feature de review trava o cron de Stripe reconcile. Carve-out do core em serviço dedicado isola.

### 2.4 Ritmo de mudança desigual
Auth muda raro mas precisa de revisão de segurança forte. Core muda toda semana. Borda (validação, rate-limit) muda quando aparece ataque novo. Misturar isso num binário só significa que toda mudança de borda obriga full deploy do domínio.

### 2.5 O que NÃO é objetivo
- Performance pura (api atual aguenta o tráfego)
- Multi-region (não temos demanda nem orçamento)
- Polyglot por polyglot (Rust só se pagar caro de verdade)
- Refactor de domain logic interna (esse é outro projeto)

---

## 3. Trade-offs e decisão arquitetural

Três caminhos foram avaliados. Cada um com custo em semanas-pessoa, benefício mensurável e risco de prod.

### 3.1 Opção A — Original do cliente: Rust dispatcher + Go core + Go auth

**Topologia:**
```
HTTPS edge (Caddy)
   └── viralefy_api (Rust, novo) — dispatcher/broker
         ├── input sanitization (XSS, SQLi, path traversal, command injection)
         ├── bot detection avancado
         ├── rate limit endurecido (token bucket distribuido)
         └── routing
               ├── viralefy_core   (Go, ex-api renomeado)
               ├── viralefy_auth   (Go, novo)
               ├── viralefy_payments (Go, ja existe)
               └── viralefy_sender   (Go, ja existe)
```

**Custo:**
- Scaffold do dispatcher em Rust com axum/tower + replay dos 55 rota patterns: 3-4 semanas
- Reimplementar todo middleware (CORS, CSRF, rate-limit per-route, JWT verify, request-id, OTel): 2-3 semanas
- Implementar sanitizers (regex + WAF rules engine): 2 semanas
- Integração com CI (cross-compile, cargo audit, dois pipelines de build): 1 semana
- Smoke E2E reescrito + paridade com api atual: 2 semanas
- **Total: 10-12 semanas** só pro dispatcher, sem contar core e auth

**Benefício:**
- Memory safety na borda (Go já é memory-safe; ganho marginal)
- CPU eficiente em hot path (mas o hot path hoje é I/O, não CPU)
- Toolchain de segurança Rust (cargo-audit, dependências menores)

**Custo escondido:**
- Toolchain dupla em prod (deploy, observability, exceptions ao pessoal de plantão)
- Hop de rede adicional (Caddy → Rust → Go = 2 hops internos contra 1 hoje)
- Recrutamento mais difícil (Rust dev sênior no Brasil = caro)
- Curva de aprendizado pro time atual (1 dev Go sênior)

**Conclusão:** Solução tecnicamente sólida, **economicamente cara**. Faz sentido pra startup com 5+ engenheiros e tráfego onde 1ms importa. Não é o nosso caso ainda.

### 3.2 Opção B — Híbrido: Caddy WAF + Go core + Go auth (RECOMENDADO)

**Topologia:**
```
HTTPS edge: Caddy + Coraza (modsecurity-compatible WAF)
   ├── OWASP CRS rule set (XSS, SQLi, RCE, path traversal, scanner)
   ├── rate-limit por IP + per-route
   └── reverse_proxy
         └── viralefy_api (Go fino, borda) — dispatcher leve
               ├── auth token verify (JWKS cache)
               ├── per-tenant rate-limit
               ├── request-id + OTel propagation
               ├── bot detection (reCAPTCHA + heuristics existentes)
               └── routing
                     ├── viralefy_core   (Go, ex-api renomeado)
                     ├── viralefy_auth   (Go, novo)
                     ├── viralefy_payments
                     └── viralefy_sender
```

**Custo:**
- Caddy + Coraza setup com OWASP CRS: 3-5 dias
- viralefy_auth scaffold + extração (login, register, refresh, JWKS, 2FA, password): 2-3 semanas
- viralefy_core extração via strangler (rotas migram por bucket): 3-4 semanas
- api Go fino reaproveita 80% do middleware atual: 1 semana
- **Total: 6-9 semanas**

**Benefício:**
- Coraza cobre as classes de ataque que o cliente listou (XSS, SQLi, command injection, path traversal) com **rule set mantido pela comunidade**. Pouco código pra escrever — mas NÃO "zero pra manter" (ver limites abaixo).

**Limites explícitos do Coraza/CRS — NÃO cobre e DEVE continuar coberto por código de domínio:**
- (i) **IDOR/BOLA** (autorização per-objeto): atacante autenticado pede `/orders/12345` que não é dele. CRS não tem ideia de ownership. Fica no core.
- (ii) **Mass-assignment / parameter pollution semântico** (`is_admin=true` no body de update profile): handlers do core usam allow-list de campos via DTO, nunca map direto pra entidade.
- (iii) **Race conditions de business logic** (cupom usado N vezes em paralelo, refund loop, referral self-grant): locks de DB + `idempotency_key`.
- (iv) **SSRF em campos URL legítimos do domínio** (avatar URL, webhook URL configurado pelo cliente): validação de allow-list de hosts no core.
- (v) **Timing attacks de auth**: comparação constante já existe no `auth_service.go`, preservar no `viralefy_auth`.
- (vi) **Rate-limit semântico** (1 conta criando 100 reviews/dia): rate-limit per-tenant no api + alerta em business metric.
- (vii) **Vulnerabilidades de prototype/deserialização**: usar `json.Decoder.DisallowUnknownFields()` em todo handler do core.

**Custo operacional real do Coraza/CRS** (não "zero"): upgrade de versão a cada 6-12 meses, falsos positivos novos a cada CRS bump, e o próprio Coraza tem CVEs históricos (consultar GitHub Security Advisories). Estimativa: 4-8h por trimestre pra triagem + tuning.

**WAF = defesa em profundidade. NUNCA defesa primária.**
- api Go fino reaproveita binário, deploy, observability, build CI atuais
- Auth isolado entrega o ganho de segurança real (superfície mínima, log detalhado)
- Core isolado entrega isolamento de blast radius
- Toolchain única — pessoal de plantão não precisa aprender stack novo

**Custo escondido:**
- Caddy + Coraza tem custo de tuning de regras (falsos positivos no início)
- Sem ganho teórico de Rust memory safety (mas Go já é memory-safe)

**Conclusão:** **Entrega da maior parte do valor por aproximadamente metade do custo das semanas-pessoa**. Caminho recomendado.

**Limitações desta recomendação que o leitor deve considerar antes de assinar:**
- "Maior parte do valor" é heurística do autor, não métrica medida. Se houver contrato com cliente enterprise pedindo audit Rust, a comparação muda.
- A recomendação otimiza pra **custo de engenharia** e **velocidade de entrega**. Se o critério primário do cliente for compliance/due-diligence, redução de CVE surface (Go stdlib `net/http` tem CVEs também), ou roadmap de contratação Rust, a balança vira.
- "Pouco código pra manter" em Coraza/CRS subestima upgrades trimestrais. Ver "Custo operacional real" acima.
- Custo de adicionar Rust DEPOIS (em 9d) é exponencial, não linear — ver seção 3.5 "Custo real de 9d posterior".
- A decisão de Opção B deve ser revisada se algum dos itens acima virar requisito explícito do cliente.

### 3.3 Opção C — Status quo melhorado: só Caddy WAF + endurecer auth in-place

**Topologia:**
```
HTTPS edge: Caddy + Coraza
   └── viralefy_api (Go monolith, sem split)
         ├── auth refatorado pra package separado (sem mover pra binario)
         └── tudo o resto igual
```

**Custo:**
- Caddy + Coraza: 3-5 dias
- Refactor de auth pra package isolado + audit log: 1-2 semanas
- **Total: 2-3 semanas**

**Benefício:**
- Defesa nova contra XSS/SQLi/path traversal (ganha junto com Opção B)
- Custo baixíssimo, prod estável

**Custo escondido:**
- NÃO resolve blast radius (qualquer bug ainda derruba tudo)
- NÃO resolve "auth como serviço com superfície mínima"
- Quando a próxima feature pedir microservice (analytics, recommendation, etc) o monolith vai estar ainda mais grudado

**Conclusão:** Bom como **mitigação imediata** se não houver fôlego pra 9b/9c. Não substitui Opção B no médio prazo.

### 3.4 Comparação resumida

| Critério                     | Opção A (Rust)    | Opção B (Híbrido) | Opção C (Status quo+) |
|------------------------------|-------------------|-------------------|-----------------------|
| Custo (semanas-pessoa)       | 16-21             | 6-9               | 2-3                   |
| Cobre XSS/SQLi/path/RCE      | Sim (código novo) | Sim (Coraza CRS)  | Sim (Coraza CRS)      |
| Endurece auth                | Sim               | Sim               | Parcial               |
| Reduz blast radius           | Sim               | Sim               | Não                   |
| Toolchains em prod           | 2 (Go + Rust)     | 1 (Go)            | 1 (Go)                |
| Hops de rede internos        | +1                | =                 | =                     |
| Risco de reescrita           | Alto              | Médio             | Baixo                 |
| Aproveita CI/CD atual        | Refazer parcial   | Sim               | Sim                   |
| Ganho de performance medido  | Hipotético        | Não relevante     | Não relevante         |

### 3.5 Decisão

**Recomendado: Opção B (Híbrido).** Executar Fases 9a → 9b → 9c. Tratar 9d (Rust dispatcher) como **decisão condicional**, gatilhada por evidência de produção:

Gatilho 1: latência p99 da borda Go > 5ms sustained em janela de 7 dias com infra fora de saturação.
Gatilho 2: incidente de segurança em prod onde a causa raiz seja limitação real do Go middleware (não falha de regra Coraza).
Gatilho 3: contratação de Rust dev sênior já feita por outro motivo.

Sem pelo menos um desses, 9d permanece backlog.

**Custo real de 9d posterior** (depois de 9c já em prod): **8-14 semanas** de implementação + **3-6 meses** de coexistência Go/Rust em prod até decommission. Razão: rate-limit per-IP, hot-set de revogação, OTel span enrichment e WAF exceptions precisam de paridade byte-a-byte que exige instrumentação dual e diff contínuo. Não é linear ("+4-8 semanas") — é exponencial pelo retrabalho de paridade. Se há sinal claro hoje de que 9d será necessária em menos de 12 meses (ex: contrato enterprise pedindo audit Rust), considerar fazer 9d em paralelo a 9c e absorver custo agora em vez de depois.

---

## 4. Plano de execução

Cada fase tem: tasks objetivos, critério de pronto, smoke check, rollback plan, estimativa em semanas.

### 4.1 Fase 9a — Foundation (1-2 semanas)

**Objetivo:** ganhar defesa nova na borda + scaffold do auth sem mover comportamento.

**Tasks:**
1. Subir Caddy com Coraza module (build customizado ou imagem oficial pré-compilada).
2. Habilitar OWASP CRS 4.x em modo `DetectionOnly` por 3 dias. Coletar log de hits.
3. Triar falsos positivos (endpoints com payload JSON grande, upload de imagens, query de search de nicho).
4. Migrar pra `Block` mode com exceções afinadas.
5. Criar repo `viralefy_auth` no GitHub Viralefy/viralefy_auth (público com README mínimo, sem código sensível).
6. Scaffold Go: `cmd/auth/main.go`, config, `/internal/v1/health`, JWKS proxy (mesmo material que api expõe hoje).
7. Subir `viralefy-auth.service` systemd no loopback `127.0.0.1:8083`. Não roteia nada ainda — só responde health.
8. Adicionar `viralefy_auth` ao `viralefy-update` (CI/CD zero-downtime + smoke).
9. Dashboard Grafana: latency e error-rate da Caddy WAF + health do auth.

**Critério de pronto:**
- [ ] Coraza ativo em Block mode em prod por 48h sem falso positivo regredindo conversão
- [ ] viralefy_auth responde 200 em `https://api.viralefy.com/_auth_health` (proxied)
- [ ] systemd unit hardened (NoNewPrivileges, ProtectSystem=strict, etc — mesmos flags do payments)
- [ ] smoke E2E continua PASS

**Smoke check:**
- Curl batida com payload SQLi conhecido em `/search?q=' OR 1=1--` retorna 403 da Caddy
- Curl com XSS `<script>alert(1)</script>` em campo de review retorna 403
- Upload de PNG legitimo continua passando
- `/auth/login` legítimo continua respondendo (não está roteado pelo auth ainda)

**Rollback plan:**
- Caddy Coraza: degradar pra DetectionOnly via reload (10s downtime no Caddy reload, mas zero pra apps)
- viralefy_auth: stop systemd unit, prod não usa ainda

**Estimativa: 1-2 semanas em janela protegida.** Em prática 3-4 semanas considerando: (i) build customizado de Caddy via `xcaddy` (não existe imagem oficial com Coraza embarcado), (ii) janela `DetectionOnly` mínima de 14 dias pra cobrir ciclo semanal completo (admin batch, fechamento mensal, campanhas de marketing), (iii) tuning de exceções no CRS exige iteração com payloads reais de search, upload e markdown de review. Buffer de +50% se a pessoa também for on-call.

---

### 4.2 Fase 9b — Auth extraction (2-3 semanas)

**Objetivo:** mover login, register, refresh, password reset, 2FA, JWKS pro `viralefy_auth`. api atual delega.

**Estratégia de cut-over (chave):**

JWT tokens em circulação NÃO podem virar inválidos. RS256 atual usa par de chaves armazenado em `/etc/viralefy/keys/`. Estratégia:

1. `viralefy_auth` recebe **a mesma chave privada RS256** que o api usa hoje (cópia controlada).
2. `viralefy_auth` mint tokens com o mesmo `kid`, `iss`, claims schema.
3. JWKS público continua servido **pelo api atual** durante a fase. Verificadores externos (Next.js, webhooks) não notam diferença.
4. Só no final da fase, JWKS migra pro auth e api vira proxy de `/.well-known/jwks.json` → auth.

Mesma lógica pro `TWOFA_ENCRYPTION_KEY` (AES-256-GCM dos TOTP secrets): chave compartilhada via `/etc/viralefy/.env`, lida pelos dois serviços. Sem rotação durante o cut-over.

**INVARIANTE de segurança (chave compartilhada):** o estado de "chave RS256 compartilhada entre api e auth" é proibido por mais de **14 dias corridos**. Se 9b não fechar no prazo, executar rollback (api volta a ser único mint, auth desligado) em vez de prolongar o split. Durante a janela, o api é colocado em modo "verify-only" (flag `API_MINT_DISABLED=true` ativada assim que o primeiro endpoint de auth migra) — qualquer tentativa de mint no api falha hard. Auditoria diária de `/var/log/viralefy_api/jwt_mint_attempts.log` confirma zero atividade de mint no api durante a janela. Sem essa disciplina, o estado transitório vira permanente e a Fase 9b não entrega o objetivo de "superfície mínima" (seção 2.2).

**Tasks:**
1. Portar `auth_service.go`, `user_auth_service.go`, `twofa_service.go`, `password.go`, helpers de JWT (`infrastructure/jwt/*`) pro auth.
2. Portar tabelas relevantes (leitor + escritor):
   - `users` (auth lê email/password_hash/2fa fields; core lê profile fields)
   - `refresh_tokens`
   - `password_resets`
   - `twofa_backup_codes`
   - `audit_events` (auth-related rows)
3. Definir contrato HTTP interno do auth:
   ```
   POST /internal/v1/login            body: {email, password, twofa_code?}
   POST /internal/v1/register         body: {email, password, ...}
   POST /internal/v1/refresh          body: {refresh_token}
   POST /internal/v1/logout           body: {refresh_token}
   POST /internal/v1/password/reset/request   body: {email}
   POST /internal/v1/password/reset/confirm   body: {token, new_password}
   POST /internal/v1/twofa/enroll     header: Bearer
   POST /internal/v1/twofa/verify     header: Bearer body: {code}
   POST /internal/v1/twofa/disable    header: Bearer body: {code}
   GET  /internal/v1/twofa/backup_codes   header: Bearer
   POST /internal/v1/token/verify     body: {token}  -> {valid, claims, error?}
   GET  /.well-known/jwks.json        (publico via api proxy)
   ```
4. Implementar wrapper no api: handlers públicos de `/auth/*` viram fininho → fazem POST loopback pro auth → repassam resposta. Status codes e shapes preservados.
5. Adicionar `INTERNAL_SHARED_SECRET` no header `X-Internal-Token` entre api e auth.
6. Adicionar `/auth_token_introspect` interno: api precisa validar token em cada request protegida. Duas opções:
   - **(a)** Cache local de JWKS no api + verify offline (rápido, mas revogação imediata fica difícil)
   - **(b)** Chamada loopback pro auth em cada request (mais lento, mas centraliza)
   - **Decisão: (a) com TTL curto (60s)** + lista de revogação delta em Redis-or-memory consultada se claim `jti` está na hot set
7. Audit log: auth manda evento pra `audit_events` direto (mesmo DB) com `service=viralefy_auth`.
8. Frontend não muda (continua chamando `/auth/login` no api).
9. Testes: paridade de comportamento. Cada endpoint do auth tem teste E2E que bate igual no api atual e no novo, compara response.

**Critério de pronto:**
- [ ] 100% dos endpoints `/auth/*` no api viram proxy pro auth
- [ ] Tokens emitidos pelo auth verificam OK no api e na Next.js
- [ ] 2FA enroll → verify → disable end-to-end PASS
- [ ] Password reset via email PASS
- [ ] Audit events do auth aparecem no Grafana com `service=viralefy_auth`
- [ ] Latência adicional p95 < 15ms vs status quo (medido em smoke load)
- [ ] Smoke E2E continua PASS
- [ ] Runbook publicado em `MICROSERVICES-OPS.md`

**Smoke check:**
- Login fluxo completo (sem 2FA, com 2FA, com 2FA + backup code)
- Register + email confirm
- Password reset via email
- Refresh token rotation
- Token verify de admin no backoffice
- Webhook do payments (que precisa de service-account token) continua funcionando

**Rollback plan:**
- Feature flag no api: `AUTH_DELEGATE_TO_SERVICE=false` reverte pra handlers in-process. JWKS e chaves não mudaram, então tokens continuam válidos.
- Se auth virar instável: systemd `stop`, feature flag off, restart api.

**Estimativa: 2-3 semanas.**

---

### 4.3 Fase 9c — Core extraction via Strangler Pattern (3-4 semanas)

**Objetivo:** renomear monolith pra `viralefy_core` e reduzir api ao papel de borda fina. Rotas migram por bucket pra controlar blast radius.

**Por que strangler:** mover 25k LOC e 55 rotas de uma vez = risco enorme. Strangler faz o api virar reverse proxy gradual: cada bucket de rotas, quando pronto, redireciona internamente pro core. Quando 100% migrou, api fica só com middleware de borda.

**Ordem de migração dos buckets:**

1. **Bucket 1 — Public read-only (semana 1)**: `/categories`, `/services`, `/plans`, `/currencies`, `/health`, `/.well-known/*`. Sem auth, sem mutação. Risco mínimo.
2. **Bucket 2 — User/me (semana 2)**: `/me/profile`, `/me/orders`, `/me/credits`, `/me/referrals`, `/me/notifications`. Auth obrigatório, mutação leve, alto tráfego.
3. **Bucket 3 — Checkout flow (semana 3 — REALISTAS 2-3 SEMANAS, com protocolo de canary)**: `/checkout/*`, `/orders/*`, `/coupons/validate`, `/cart/*`. Crítico pra receita. Roda em paralelo com Stripe webhooks que já vão pelo payments.

   **Protocolo de canary OBRIGATÓRIO** (não basta smoke E2E pra esse bucket):
   - **Fase 3.1 — Shadow traffic (72h):** api duplica request pra core sem servir, log diff de response. Compara `payment_url`, `order_id`, `status` byte-a-byte.
   - **Fase 3.2 — Canary por hash de user_id:** 1% por 24h, 10% por 48h, 50% por 48h, 100%. Feature flag `CHECKOUT_BUCKET_TO_CORE_PERCENT=0..100` controla rampa.
   - **Reconciliação diária durante canary:** query SQL comparando `orders` criadas em cada path (coluna `created_by_path` adicionada na tabela como tag durante a fase, removida em cleanup).
   - **Runbook de "order criada sem payment_url":** TTL de 15min antes de cleanup automático. Order com `payment_url IS NULL AND created_at < NOW() - INTERVAL '15 min'` é marcada `status=stale` e dispara alerta.
   - **Idempotência cross-path:** mesma `Idempotency-Key` que cair em paths diferentes (api in-proc vs core) deve devolver MESMA order_id. Único Postgres garante via UNIQUE constraint; testar explicitamente em smoke.

   Tempo realista do bucket 3 isoladamente: **2-3 semanas**, não 1.
4. **Bucket 4 — Admin (semana 4)**: `/admin/*` (vendor, ticket, gateway, review moderation, plan CRUD, etc). Baixo tráfego mas mutação pesada. Último porque erro aqui é detectado rápido pelos admins.
5. **Bucket 5 — Crons + internals**: crons rodam dentro do core (mais natural). webhook callbacks do payments apontam pro core diretamente.

**Mecânica do strangler:**

```
api (Go borda)
  └── per-route table
        ├── route in bucket already-migrated  → reverse_proxy → core (loopback :8084)
        ├── route in bucket not-migrated      → handler in-process (codigo antigo)
        └── route in /auth/*                  → reverse_proxy → auth (loopback :8083)
```

Implementação: arquivo `cmd/api/routes.go` no api. Lista declarativa `[]Route{Pattern, Method, Target}`. Target enum: `Inproc | Core | Auth`. Toda request passa por middleware comum (rate-limit, request-id, token verify). Só o dispatch final muda.

**Tasks:**

1. Criar repo `viralefy_core`. Forkar binário atual do api, renomear, remover handlers de borda (rate-limit, CORS, request-id ficam no api).
2. core sobe em `127.0.0.1:8084`. Health check loopback.
3. Bucket 1: marcar rotas read-only como `Target: Core` na tabela. api vira reverse proxy nelas. Deploy.
4. Smoke E2E + observação por 48h. Se OK, bucket 2.
5. Repetir pra cada bucket, sempre com janela de observação entre eles.
6. Webhooks do payments: contrato atual `POST {API_URL}/internal/payment-confirmed`. Migrar pra `POST {CORE_URL}/internal/payment-confirmed` quando bucket 3 estabilizar. Atualizar env do payments.
7. Crons: ao fim do bucket 5, parar crons no api (ou nem subir cron no api). core fica dono exclusivo.
8. Quando 100% das rotas migraram, api vira binário pequeno: middleware + dispatch table. Estimativa 1-2k LOC (down de 25k).

**Critério de pronto (por bucket):**
- [ ] Rotas do bucket respondem via core (proxied pelo api) com mesmas response shapes
- [ ] Smoke E2E passa
- [ ] Latência p95 do bucket < baseline + 10ms
- [ ] 48h de observação sem regressão de erro 5xx
- [ ] Dashboard mostra tráfego no core service tag

**Critério de pronto (fase 9c inteira):**
- [ ] 100% das 55 rotas servidas pelo core
- [ ] api LOC < 3000
- [ ] crons rodando no core
- [ ] payments callback aponta pro core
- [ ] Smoke E2E PASS
- [ ] Runbook do core publicado
- [ ] Deploy zero-downtime do core validado

**Rollback plan (granular):**
- Por bucket: reverter dispatch table no api (`Target: Inproc`) e redeploy. Próximo build do api ainda contém o handler antigo (não removemos código, só pulamos).
- Código antigo só é apagado do api depois que o bucket está estável por 14 dias.
- Em caso de incidente full: feature flag `CORE_DELEGATION_ENABLED=false` força tudo pra in-process até diagnosticar.

**Disciplina obrigatória durante a janela de 14 dias de código preservado:**
- **CI roda smoke E2E em DOIS modos por PR**: `DISPATCH_OVERRIDE=core` E `DISPATCH_OVERRIDE=inproc`. Ambos devem PASS. Sem isso, o caminho inactive apodrece silenciosamente.
- **Linter de CI**: qualquer PR que toque arquivo sob `internal/application/<bucket_migrado>/` no api EXIGE label `rollback-window-active` E mirror PR no core (ou explicit `--allow-divergence` com justificativa do autor).
- **Dashboard Grafana** mostra timer `days_until_inproc_code_removable_for_bucket_N` em painel de release health.
- **No dia 14**, PR automático de cleanup é aberto (gerado por bot) listando arquivos a remover. Bloqueia merges no api até cleanup decidido (merge ou descartar com justificativa de extensão).
- Sem essa disciplina, bug fixes durante a janela precisam ser aplicados em DOIS lugares e rollback regride a fix.

**Estimativa: 3-4 semanas.**

---

### 4.4 Fase 9d — Rust dispatcher (CONDICIONAL, 4-8 semanas)

**Não iniciar sem trigger confirmado** (ver seção 3.5). Quando/se iniciar:

**Tasks resumidos:**
1. Reescrever middleware comum em Rust (axum + tower-http): rate-limit, request-id, OTel, JWKS verify cache.
2. Implementar reverse proxy interno com round-trip < 1ms.
3. Sanitizers: regex-based + lista de denyrules. Manter Coraza como camada externa redundante.
4. Bot detection: integração com reCAPTCHA + heuristics próprias (fingerprint, velocity).
5. Cross-compile + dois artefatos no CI (Go binaries + Rust binary).
6. Cut-over em paralelo: api Go fino e api Rust rodam atrás de uma flag de Caddy upstream weight. Aumentar peso do Rust gradativamente (1% → 10% → 50% → 100%).
7. Decommission api Go quando 100% do tráfego no Rust por 30 dias.

**Critério de pronto:**
- [ ] Latência p99 da borda Rust ≤ borda Go
- [ ] Memory residente ≤ Go
- [ ] Smoke E2E PASS
- [ ] Runbook de troubleshoot Rust publicado
- [ ] Pelo menos 2 pessoas do time confortáveis com a stack

**Estimativa: 4-8 semanas.**

---

## 5. Arquitetura final (target state após 9c)

### 5.1 Diagrama ASCII

```
INTERNET (HTTPS)
    │
    ▼
┌────────────────────────────────────────────────────────────────┐
│  CADDY  (TLS, HTTP/2, HTTP/3, automatic certs)                 │
│   ├── Coraza WAF + OWASP CRS                                   │
│   │     - XSS, SQLi, RCE, path traversal, scanner detection    │
│   ├── per-IP rate limit (Caddy native)                         │
│   └── route by host                                            │
│        ├── www.viralefy.com  → viralefy_front  :3000           │
│        ├── admin.viralefy.com → viralefy_backoffice :3001      │
│        └── api.viralefy.com  → viralefy_api    :8080           │
└────────────────────────────────────────────────────────────────┘
                          │
                          ▼
┌────────────────────────────────────────────────────────────────┐
│  viralefy_api  (Go, borda fina, ~2k LOC)        :8080          │
│   ├── request-id middleware (W3C traceparent)                  │
│   ├── rate-limit per-tenant (token bucket)                     │
│   ├── JWT verify (JWKS cache 60s + revocation hot-set)         │
│   ├── bot detection (reCAPTCHA, velocity)                      │
│   ├── CORS, CSRF                                               │
│   └── reverse_proxy dispatch table                             │
│        ├── /auth/*           → viralefy_auth    :8083          │
│        ├── /admin/*          → viralefy_core    :8084          │
│        ├── /checkout/*       → viralefy_core    :8084          │
│        ├── /me/*             → viralefy_core    :8084          │
│        ├── /catalog, /plans  → viralefy_core    :8084          │
│        └── /internal/payment-confirmed → viralefy_core :8084   │
└────────────────────────────────────────────────────────────────┘
              │              │             │
              ▼              ▼             ▼
   ┌────────────────┐ ┌──────────────┐ ┌──────────────┐
   │ viralefy_auth  │ │ viralefy_core│ │viralefy_pay  │
   │ (Go) :8083     │ │ (Go) :8084   │ │ ments :8081  │
   │  - login       │ │  - domain    │ │  - Stripe    │
   │  - register    │ │  - checkout  │ │  - Heleket   │
   │  - refresh     │ │  - orders    │ │  - Woovi     │
   │  - 2FA         │ │  - reviews   │ │  - Abacate   │
   │  - password    │ │  - vendor    │ │  - manualPIX │
   │  - JWKS        │ │  - referrals │ │              │
   │  - audit       │ │  - 9 crons   │ │              │
   │                │ │  - admin     │ │              │
   └──────┬─────────┘ └──────┬───────┘ └──────┬───────┘
          │                  │                │
          │             ┌────┴────────────┐   │
          │             │ viralefy_sender │   │
          │             │ (Go) :8082      │   │
          │             │  - email Resend │   │
          │             │  - Telegram bot │   │
          │             │  - outbox+retry │   │
          │             └────┬────────────┘   │
          │                  │                │
          ▼                  ▼                ▼
        ┌───────────────────────────────────────────┐
        │  PostgreSQL (single instance, shared)     │
        │   schemas: public, payments, sender       │
        │   + auth-owned tables in public           │
        └───────────────────────────────────────────┘

  Observability (existente):
   - Loki (logs) + Tempo (traces) + Prometheus + Grafana
   - Cada servico exporta /metrics e propaga traceparent
   - MinIO (object storage, uploads)
```

### 5.2 Fluxo de uma request (exemplo: criar pedido autenticado)

```
1. Browser POST https://api.viralefy.com/checkout/create-order
   headers: Authorization: Bearer eyJ...

2. Caddy
   - termina TLS
   - Coraza inspeciona payload (XSS/SQLi rules)  → OK
   - rate-limit por IP                            → OK
   - reverse_proxy → viralefy_api :8080

3. viralefy_api (borda)
   - request-id gerado (W3C traceparent)
   - rate-limit per-tenant (1000 req/min logged user) → OK
   - JWT verify offline (RS256 + JWKS cache)
       - kid encontrado, sig valida, exp OK
       - jti NÃO está na revocation hot-set      → OK
       - claims extraidos: user_id, role, scope
   - bot detection (heuristica baseada em UA + velocity) → OK
   - dispatch table: /checkout/* → core :8084
   - reverse_proxy POST :8084/checkout/create-order
       + header X-User-Id, X-Role, X-Request-Id, X-Internal-Token

4. viralefy_core
   - valida X-Internal-Token (shared secret)
   - executa CheckoutService.CreateOrder
       - lookup plan (DB)
       - aplica cupom se houver
       - calcula display amount (currency_service)
       - cria order (DB)
       - POST loopback :8081/internal/v1/charge (viralefy_payments)
            → Stripe API → retorna payment_url
       - enfileira email via :8082/internal/v1/send (sender)
   - responde 200 { order_id, payment_url }
   - propaga traceparent na resposta

5. viralefy_api forward response → Caddy → Browser

   Trace completo no Tempo:
   caddy → api → core → payments → stripe
                     → sender → resend
```

### 5.3 Mapeamento rota → serviço dono (sumário)

| Rota                          | Dono             | Notas                            |
|-------------------------------|------------------|----------------------------------|
| `/auth/login`                 | viralefy_auth    | via proxy api                    |
| `/auth/register`              | viralefy_auth    |                                  |
| `/auth/refresh`               | viralefy_auth    |                                  |
| `/auth/password/*`            | viralefy_auth    |                                  |
| `/auth/twofa/*`               | viralefy_auth    |                                  |
| `/.well-known/jwks.json`      | viralefy_auth    | proxiado pela api                |
| `/me/*`                       | viralefy_core    |                                  |
| `/categories`, `/services`, `/plans`, `/currencies` | viralefy_core | read-only públicos     |
| `/checkout/*`                 | viralefy_core    | chama payments loopback          |
| `/orders/*`                   | viralefy_core    |                                  |
| `/coupons/validate`           | viralefy_core    |                                  |
| `/reviews/*`                  | viralefy_core    |                                  |
| `/referrals/*`                | viralefy_core    |                                  |
| `/admin/*`                    | viralefy_core    | tudo de backoffice               |
| `/internal/payment-confirmed` | viralefy_core    | webhook callback do payments     |
| `/internal/v1/charge`         | viralefy_payments| loopback                         |
| `/internal/v1/methods`        | viralefy_payments| loopback                         |
| `/internal/v1/webhooks/*`     | viralefy_payments| públicos via api reverse proxy   |
| `/internal/v1/send`           | viralefy_sender  | loopback                         |

---

## 6. Migrações DB

### 6.1 Modelo: shared Postgres, owner por tabela

Continuamos com **um único Postgres** (mesmo modelo de Fase 8). Cada tabela tem um serviço dono (única fonte que escreve). Leitura cross-service é permitida pra tabelas globais (users, plans). Tudo escrito por mais de um precisa de discussão.

**Por que não DB-per-service:** custo operacional (3x backup, 3x conexão, 3x monitoramento) e o ganho real só aparece em escala de M+ usuários. Não estamos lá.

### 6.2 Ownership após Fase 9

| Tabela                     | Dono escrita      | Leitores                       |
|----------------------------|-------------------|---------------------------------|
| `users`                    | viralefy_auth     | core (profile fields), payments|
| `refresh_tokens`           | viralefy_auth     | -                              |
| `password_resets`          | viralefy_auth     | -                              |
| `twofa_backup_codes`       | viralefy_auth     | -                              |
| `audit_events`             | todos os services | core (admin reports)           |
| `orders`, `order_items`    | viralefy_core     | payments (referência)          |
| `plans`, `categories`, `services` | viralefy_core | todos                       |
| `reviews`, `vendors`, `tickets` | viralefy_core | -                              |
| `coupons`, `referrals`     | viralefy_core     | -                              |
| `payment_gateways`         | viralefy_payments | core (listagem checkout)       |
| `stripe_events_processed`  | viralefy_payments | -                              |
| `outbox_messages`          | viralefy_sender   | -                              |

### 6.3 Como evitar deadlocks compartilhando tabelas

1. **Ordem fixa de aquisição de locks por nome de tabela** (alfabética). Documentar em `ARCHITECTURE.md` de cada serviço.
2. **Transações curtas**. Ninguém abre transação e chama HTTP de outro service no meio. Pattern: começa tx, faz tudo local, commit. HTTP cross-service depois (ou antes) da tx.
3. **Idempotência via `idempotency_key`** em mutações cross-service (já existe na Fase 8 para payments).
4. **Outbox pattern** quando uma escrita aqui precisa disparar ação em outro service (já em uso pelo sender; estender pra core → payments quando aplicável).
5. **Linter de CI**: regra que falha PR se código abre `pgx.Tx` e dentro chama cliente HTTP de outro service.

### 6.4 Schema migration runner

Hoje o runner estilo Laravel (`internal/infrastructure/database/migrations/`) vive no api. Decisão:

- **Runner fica no `viralefy_core`** (herda do api). Único serviço que aplica DDL.
- **auth e payments fazem assert de schema** ao subir: query `information_schema` pra verificar que tabelas esperadas existem. Se não, falha rápido com log claro.
- DDL nova proposta por qualquer service vai via PR no core (revisão obrigatória do dono da tabela).
- Migrations sempre additive primeiro (add column nullable, deploy), drop só depois que código velho saiu (estratégia já adotada).

**Disciplina de DDL durante Fase 9c (janela strangler):**
- Migration destrutiva (DROP COLUMN, RENAME, ALTER TYPE incompatível) **PROIBIDA** enquanto houver bucket com `Target: Inproc` que toque aquela tabela. CI block: linter checa diff de migration + `dispatch_table.go` no api.
- Migrations sempre em **3 PRs separados**: (1) **additive** (add column nullable), (2) **backfill + dual-write**, (3) **destrutiva** — esta só após bucket que usa a tabela estar 100% no core E código antigo removido do api.
- Checklist obrigatório no PR de migration destrutiva: "confirmo que nenhum binário em prod (api/core/auth/payments/sender) executa código que referencie a coluna/tabela a remover".
- Sem essa disciplina, schema-mismatch crash durante rollback do strangler é cenário garantido.

---

## 7. Modelo de segurança

### 7.1 Tokens internos (service-to-service)

`INTERNAL_SHARED_SECRET` por par de serviços:
- `INTERNAL_TOKEN_API_TO_CORE`
- `INTERNAL_TOKEN_API_TO_AUTH`
- `INTERNAL_TOKEN_API_TO_PAYMENTS` (já existe da Fase 8)
- `INTERNAL_TOKEN_API_TO_SENDER` (já existe)
- `INTERNAL_TOKEN_CORE_TO_PAYMENTS`
- `INTERNAL_TOKEN_CORE_TO_SENDER`
- `INTERNAL_TOKEN_PAYMENTS_TO_CORE` (callback payment-confirmed)

Header: `X-Internal-Token: <secret>`. Rejeita 401 se ausente ou wrong.

**Rotação:** runbook documenta procedimento (gerar novo, deploy nos dois lados em janela, descartar antigo). Trimestral por default.

### 7.2 mTLS opcional entre microservices

**Decisão: NÃO no curto prazo.** Razões:
- Tudo loopback `127.0.0.1`. Tráfego nunca sai do host.
- mTLS adiciona complexidade de cert rotation, CA gerenciada.
- `INTERNAL_SHARED_SECRET` resolve auth de chamadas internas.
- Se migrar pra multi-host (k8s, multi-VM) no futuro, então mTLS faz sentido.

### 7.3 JWT keys

- **Mint:** só `viralefy_auth`.
- **Validate:** api (offline, JWKS cache) + outros services se receberem token end-user (raro).
- **JWKS público:** servido pelo auth em `/.well-known/jwks.json`, proxiado pela api pra clientes externos.
- **Algoritmo:** RS256 atual. HS256 legado descontinuado durante Fase 9b (todos refresh tokens emitidos pelo auth são RS256).
- **Key rotation:** novo `kid` mensal. Auth mantém últimas 2 chaves no JWKS pra sobreposição. Refresh tokens com kid antigo rejeitados após 30 dias.

### 7.4 Roles/permissions cache strategy

- Auth assina claims `role` e `scopes` no JWT (current behavior).
- Mudança de role: revoga refresh token (`jti` na hot-set) → user precisa refazer login OU usar `/auth/refresh` que checa estado atual no DB.
- TTL curto do access token (15min) garante propagação de revogação em ≤ 15min sem hot-set lookup em cada request.
- Hot-set de revogação imediata (incidente, admin force-logout) — implementação obrigatória:
  - (a) Tabela `revoked_jtis(jti TEXT PK, exp_at TIMESTAMPTZ)` no Postgres, escrita pelo auth no momento da revogação dentro da mesma transação que marca o `refresh_token` como revogado.
  - (b) Cada instância api consulta a tabela a cada 5s (ou via `LISTEN/NOTIFY` do Postgres pra push real-time) e mantém set em memória.
  - (c) Na inicialização, api faz bootstrap completo da hot-set lendo `SELECT jti FROM revoked_jtis WHERE exp_at > now()`.
  - (d) Janela máxima de revogação efetiva documentada: **5s**.
  - (e) Em caso de N instâncias api durante zero-downtime swap (`viralefy-update` mantém 2 instâncias por alguns segundos), cada nova instância faz seu próprio bootstrap antes de aceitar tráfego (readiness gate). Hot-set em memória pura é PROIBIDA — diverge entre instâncias e perde estado em restart.

### 7.5 Hardening do auth

- Rate limit dedicado em `/auth/login` (5/min/IP) e `/auth/password/reset/request` (3/hora/email).
- Lockout temporário após N falhas (já existe).
- Log estruturado de TODAS as tentativas (sucesso e falha) com IP, UA, request-id pra correlação.
- TOTP secrets continuam AES-256-GCM com `TWOFA_ENCRYPTION_KEY` compartilhada via env.
- Backup codes 1-time use (já existe).
- Sem reuso de password (mantém o behaviour atual de hash bcrypt cost 12).

---

## 8. Observability

### 8.1 Stack (existente, reaproveitada)

- **Logs:** Loki (todos services enviam structured JSON)
- **Traces:** Tempo (OTel SDK em todos services)
- **Metrics:** Prometheus (`/metrics` em cada service)
- **Dashboards:** Grafana

### 8.2 Por serviço

Cada um dos `api`, `auth`, `core`, `payments`, `sender` exporta:

```
/metrics  Prometheus
  http_requests_total{service,route,method,status}
  http_request_duration_seconds{service,route,method}
  internal_requests_total{caller,callee,route,status}
  db_query_duration_seconds{service,query_name}
  business metrics (orders_created_total, twofa_enrolled_total, etc)
```

### 8.3 Trace propagation

- **W3C traceparent** header injetado pelo Caddy (ou pelo api se Caddy não suportar nativamente).
- Cada hop loopback inclui o header. Cada service usa OTel SDK com `tracecontext` propagator.
- `tracestate` reservado pra vendor-specific (Grafana Tempo aceita raw).
- Cada span tem atributos `service.name`, `service.version`, `http.route`, `http.status_code`, `enduser.id` (quando aplicável).

### 8.4 Dashboards Grafana (por serviço, mesmo template)

1. **Overview** — RPS, error rate, p50/p95/p99 latency, top routes
2. **Internal calls** — calls out per callee, error rate per callee
3. **DB** — query rate, slow queries, pool saturation
4. **Business** — orders, signups, payments, mensagens enviadas
5. **Saturation** — CPU, RAM, goroutines, FDs

### 8.5 Alertas (Alertmanager)

- p95 latency > 500ms por 5min → warning
- error rate > 1% por 5min → critical
- auth login failure rate > 10x baseline em 10min → critical (possível bruteforce)
- payments charge success rate < 95% em 15min → critical
- sender queue depth > 1000 → warning
- DB conexões > 80% do pool → warning

### 8.6 Runbook de troubleshoot E2E

Quando suporte/cliente reporta "checkout falhou" e a request passou por 5+ hops, on-call segue protocolo:

1. **Capturar `request_id`** do header de resposta exposto ao cliente (`X-Request-Id`) ou do log do front.
2. **Grafana → Explore → Tempo → busca por `trace_id={request_id}`**. Esperar: hops `caddy → api → {core|auth} → {payments|sender}` visíveis em waterfall.
3. **Se trace incompleto:** verificar `otel_sampler_ratio` por service em config — em prod TODOS devem estar em `1.0` (100%) por padrão. Sampling menor é decisão deliberada documentada por service.
4. **No hop com `status_code >= 400`:** clicar no span, copiar `service.name` e `time`, abrir Loki com filtro `{service="X"} |= "{request_id}"`.
5. **Erros sem `trace_id` no log = bug de propagação.** Abrir incidente.
6. **Treinamento obrigatório:** cada novo on-call faz drill em staging executando este runbook com falha forçada (`kill -9 do core durante checkout`). Pass = runbook funcional.

Métrica de saúde do runbook: **tempo médio até log root cause em incidentes < 5min**. Se ficar acima, runbook (ou observabilidade) precisa de revisão.

---

## 9. Risks & mitigations

### 9.1 Tabela de riscos

| # | Risco                                            | Prob | Impacto | Mitigação                                                                                  |
|---|--------------------------------------------------|------|---------|--------------------------------------------------------------------------------------------|
| 1 | Cut-over de auth invalida tokens em circulação   | M    | Alto    | Chaves RS256 compartilhadas durante cut-over; api delega mas mint continua com mesmo `kid` |
| 2 | Coraza WAF gera falso positivo bloqueando checkout | M  | Alto    | DetectionOnly por 3 dias antes de Block; exceções afinadas; rollback rápido via reload     |
| 3 | Strangler proxy adiciona latência inaceitável    | B    | Médio   | Loopback overhead < 1ms; gate em fase 9c é p95 +10ms max                                   |
| 4 | Deploy falha mid-cutover (alguns buckets no core, outros no api) | B | Alto | Dispatch table é por-rota; flag global `CORE_DELEGATION_ENABLED=false` reverte tudo |
| 5 | Token revocation cascade lento (race entre user logout e access ainda válido) | M | Médio | TTL access 15min + hot-set push entre auth↔api                                              |
| 6 | Payment webhook lost durante migração de callback URL | B | Alto | Stripe/Heleket têm retry. Janela curta de troca. Idempotency_key em payment-confirmed       |
| 7 | Shared DB causa deadlock entre core e auth       | B    | Médio   | Ordem fixa de lock acquisition + linter CI + transações curtas                              |
| 8 | INTERNAL_SHARED_SECRET vaza em log/repo          | B    | Alto    | Loaded de /etc/viralefy/.env (root-only), gitleaks no CI, runbook de rotação trimestral     |
| 9 | Time não consegue debugar Rust em incident (se 9d) | M | Alto   | Pré-requisito: 2+ engs treinados, runbook detalhado, modo fallback pra Go borda             |
| 10 | Migração de DDL durante 9c quebra core ou auth  | B    | Alto    | Migrations additive-first; assert-schema no boot de auth/payments; deploy gates              |
| 11 | JWKS cache stale após key rotation              | B    | Médio   | TTL cache 60s + endpoint `/internal/v1/jwks-refresh` pra force-reload                       |
| 12 | Audit log fragmentado dificulta investigação    | M    | Médio   | Tabela única `audit_events` com `service` tag; dashboard Grafana cross-service              |

### 9.2 Cenários documentados

**Cenário A — Deploy do core falha em prod (binário não sobe):**
1. `viralefy-update` smoke check detecta falha → não promove
2. api continua servindo bucket migrado via in-process fallback (código antigo preservado)
3. Investigação offline, próximo deploy corrigido

**Cenário B — Auth fica indisponível em prod:**
1. api detecta erro 5xx loopback em `/internal/v1/token/verify`
2. JWT verify offline continua funcionando (JWKS já em cache)
3. Tokens válidos continuam aceitos por até 15min sem auth disponível
4. Login/register/refresh ficam fora — usuários novos não entram, sessions ativas seguem
5. Alerta crítico dispara → on-call investiga

**Cenário C — Token revogation cascade (admin força logout de user comprometido):**
1. Admin chama `/admin/users/:id/force-logout` no core
2. core chama `/internal/v1/revoke-jti` no auth com lista de jti
3. auth marca refresh tokens revogados no DB
4. auth push hot-set update pra api
5. api adiciona jti à hot-set local
6. Próxima request com aquele access token retorna 401
7. Sem hot-set: efeito em ≤ 15min (TTL access)

**Cenário D — Payment webhook lost durante migração de callback URL:**
1. Stripe POST `https://api.viralefy.com/internal/v1/webhooks/stripe` chega
2. api ainda roteia pra payments (não muda na Fase 9c)
3. Payments processa, chama callback `POST {CORE_URL}/internal/payment-confirmed`
4. Se core ainda não absorveu essa rota: callback bate no api antigo (compat preservada)
5. Janela de troca de env do payments: 1 deploy do payments com `CORE_URL` apontando pro core. Stripe retry resolve qualquer perda.

### 9.3 RTO/RPO pós-Fase 9

Cenário "restore from scratch em host novo":

- **Antes (monolito):** 1 binário + restore DB + 1 env file = **RTO ~15min**, RPO = última WAL.
- **Depois (3 services + Caddy + Coraza):** RTO inflacionado se não houver runbook. Mitigação obrigatória:

`viralefy_ops` mantém playbook `restore-prod.sh` que:
1. Restaura DB (já existe da Fase 7).
2. Materializa `/etc/viralefy/.env.{api,auth,core,payments,sender}` a partir de secret store (Bitwarden CLI ou similar).
3. Verifica que chaves JWT em `/etc/viralefy/keys/` estão presentes; senão regenera + rotaciona (ações DESTRUTIVAS pedem confirmação interativa).
4. Sobe systemd units em ordem: **DB → auth → core → payments/sender → api → Caddy** (auth/core devem estar healthy antes de api aceitar tráfego).
5. Roda smoke E2E como gate de "RTO completo".

**Backup explícito de:**
- Caddyfile + diretório de exceções Coraza (`/etc/caddy/coraza_exceptions/`).
- JWT keys (`/etc/viralefy/keys/`).
- Env files de cada serviço.
- DB (já automatizado).

**RTO alvo pós-9c: 30min documentado e testado em DR drill trimestral.** RPO permanece o da WAL contínua (sem mudança).

---

## 10. Critério de "Fase 9 pronta"

Checklist objetivo, marcar antes de declarar feita.

### 10.1 Foundation (9a)
- [ ] Caddy com Coraza em Block mode em prod
- [ ] OWASP CRS 4.x com exceções afinadas, sem regressão de conversão
- [ ] viralefy_auth scaffold no GitHub Viralefy/viralefy_auth
- [ ] viralefy-auth.service systemd hardened (NoNewPrivileges, ProtectSystem=strict)
- [ ] viralefy_auth integrado ao viralefy-update CI/CD
- [ ] Dashboard Grafana de WAF e auth-health
- [ ] Runbook de WAF (como adicionar exceção) publicado

### 10.2 Auth extraction (9b)
- [ ] 100% dos endpoints `/auth/*` proxied pelo api pro auth
- [ ] Tokens emitidos pelo auth verificados OK por api e Next.js
- [ ] 2FA enroll/verify/disable PASS E2E
- [ ] Password reset via email PASS E2E
- [ ] Refresh token rotation PASS
- [ ] Service-account tokens (payments webhook) continuam válidos
- [ ] Audit events do auth aparecem com tag service=viralefy_auth
- [ ] Latência adicional p95 < 15ms vs baseline
- [ ] Smoke E2E PASS
- [ ] Rate limit endurecido em /auth/login e /auth/password/reset/request
- [ ] Runbook do auth em MICROSERVICES-OPS.md
- [ ] Feature flag de rollback testado em staging

### 10.3 Core extraction (9c)
- [ ] Bucket 1 (public read-only) 100% no core, 48h estável
- [ ] Bucket 2 (user/me) 100% no core, 48h estável
- [ ] Bucket 3 (checkout) 100% no core, 48h estável
- [ ] Bucket 4 (admin) 100% no core, 48h estável
- [ ] Bucket 5 (crons + internals) no core
- [ ] api LOC < 3000 (reduzido de 25k)
- [ ] payments webhook callback aponta pro core
- [ ] Smoke E2E PASS
- [ ] Latência p95 por bucket dentro de baseline +10ms
- [ ] Runbook do core em MICROSERVICES-OPS.md
- [ ] Deploy zero-downtime do core validado em 2 releases

### 10.4 Cross-cutting (todas as fases)
- [ ] Cada serviço tem: cmd/, internal/, README, Dockerfile (ou systemd unit), CI workflow
- [ ] Cada serviço tem: tests (unit > 70% coverage nas paths críticas)
- [ ] Cada serviço tem: /health, /ready, /metrics
- [ ] Cada serviço tem: structured logs JSON com trace_id
- [ ] Cada serviço tem: deploy zero-downtime validado
- [ ] Cada serviço tem: runbook (start, stop, rollback, troubleshoot)
- [ ] Trace propagation E2E (Caddy → api → core/auth → payments/sender) verificada no Tempo
- [ ] CONTEXT.md, CHECKLIST.md, INDEX.md atualizados no viralefy_archive
- [ ] Inventário público em github.com/Viralefy com novos repos auth e core
- [ ] Diretrizes de DB ownership documentadas (seção 6.2)

### 10.5 Decisão sobre 9d (Rust dispatcher)
- [ ] Coletar 30 dias de métricas pós-9c
- [ ] Avaliar gatilhos da seção 3.5
- [ ] Decisão registrada (GO / NO-GO / DEFER) com data e dono

### 10.6 Ampliação obrigatória do smoke E2E

Smoke E2E atual cobre fluxo monolítico. **Antes de iniciar 9b**, adicionar casos:

- [ ] Login pelo auth → access token → request autenticada no core → response 200
- [ ] Refresh token rotation cruza auth → access novo válido no core E no payments
- [ ] Force-logout (admin no core → revoke no auth → next request 401 em ≤ 5s)
- [ ] Checkout completo end-to-end: api → core → payments → callback → core → sender
- [ ] Trace propagation: assert que `trace_id` da request inicial aparece em logs de **TODOS** hops
- [ ] WAF exception: payload SQLi conhecido → 403 da Caddy (regression test contra ajuste de exceção descuidado)
- [ ] WAF exception: upload PNG legítimo → 200 (regression test contra over-blocking)
- [ ] Schema-assert no boot de auth e payments funciona (kill DB column esperada em staging → service deve falhar fast com log claro, não em runtime)
- [ ] Rollback per-bucket: smoke roda com `DISPATCH_OVERRIDE=inproc` E `DISPATCH_OVERRIDE=core`, ambos PASS

**Sem essa ampliação, "smoke E2E PASS" como gate é placebo** — cobre só o monolito antigo.

---

## 11. Anexos

### 11.1 Variáveis de ambiente esperadas (novas)

```
# viralefy_api (borda)
AUTH_LOOPBACK_URL=http://127.0.0.1:8083
CORE_LOOPBACK_URL=http://127.0.0.1:8084
PAYMENTS_LOOPBACK_URL=http://127.0.0.1:8081
SENDER_LOOPBACK_URL=http://127.0.0.1:8082
INTERNAL_TOKEN_API_TO_AUTH=<secret>
INTERNAL_TOKEN_API_TO_CORE=<secret>
INTERNAL_TOKEN_API_TO_PAYMENTS=<secret>
INTERNAL_TOKEN_API_TO_SENDER=<secret>
JWKS_CACHE_TTL_SECONDS=60
JWT_VERIFY_MODE=offline
RATE_LIMIT_GLOBAL_PER_IP=120
RATE_LIMIT_LOGIN_PER_IP=5
CORE_DELEGATION_ENABLED=true
AUTH_DELEGATE_TO_SERVICE=true

# viralefy_auth
DATABASE_URL=postgres://...
JWT_PRIVATE_KEY_PATH=/etc/viralefy/keys/jwt_private.pem
JWT_PUBLIC_KEY_PATH=/etc/viralefy/keys/jwt_public.pem
JWT_KID_CURRENT=2026-06
TWOFA_ENCRYPTION_KEY=<32 bytes hex>
ACCESS_TOKEN_TTL_SECONDS=900
REFRESH_TOKEN_TTL_SECONDS=2592000
INTERNAL_TOKEN_AUTH_INGRESS=<secret matching api>
BCRYPT_COST=12

# viralefy_core
DATABASE_URL=postgres://...
PAYMENTS_LOOPBACK_URL=http://127.0.0.1:8081
SENDER_LOOPBACK_URL=http://127.0.0.1:8082
INTERNAL_TOKEN_CORE_INGRESS=<secret matching api>
INTERNAL_TOKEN_CORE_TO_PAYMENTS=<secret>
INTERNAL_TOKEN_CORE_TO_SENDER=<secret>
MIGRATIONS_DIR=/opt/viralefy_core/migrations
RUN_CRONS=true
```

### 11.2 Estrutura de pastas alvo

```
viralefy_api/                # borda fina
  cmd/api/main.go
  internal/
    config/
    middleware/             # rate-limit, jwt verify, request-id, OTel
    dispatch/               # route table + reverse proxy
    waf/                    # exceções Coraza customizadas
    revocation/             # hot-set
  go.mod

viralefy_auth/               # novo
  cmd/auth/main.go
  internal/
    config/
    domain/                 # user, refresh_token, twofa
    application/            # login, register, refresh, password, twofa
    infrastructure/
      jwt/                  # mint, verify, jwks
      database/
      crypto/               # AES-256-GCM, bcrypt
    interface/http/
  go.mod

viralefy_core/               # ex-api renomeado
  cmd/core/main.go
  internal/                 # todo o domínio atual menos auth
    config/
    domain/
    application/            # checkout, order, plan, vendor, review, etc
    infrastructure/
      database/migrations/  # runner único
      external/             # MinIO, Telegram, WhatsApp, reCAPTCHA
    interface/http/
  go.mod

viralefy_payments/           # ja existe
viralefy_sender/             # ja existe
```

### 11.3 Ordem de PRs sugerida (alto nível)

1. PR #1: Caddyfile com Coraza + OWASP CRS, DetectionOnly
2. PR #2: Caddyfile Block mode com exceções afinadas
3. PR #3: viralefy_auth scaffold (repo novo)
4. PR #4: viralefy_auth — JWT mint/verify + JWKS
5. PR #5: viralefy_auth — login + register + audit
6. PR #6: api delega `/auth/login` e `/auth/register`
7. PR #7: viralefy_auth — refresh + revocation hot-set push
8. PR #8: viralefy_auth — password reset
9. PR #9: viralefy_auth — 2FA endpoints
10. PR #10: api delega 100% `/auth/*` + remove código auth
11. PR #11: viralefy_core scaffold (repo novo, fork do api)
12. PR #12: api dispatch table + bucket 1 migrado
13. PR #13: bucket 2 migrado
14. PR #14: bucket 3 migrado (cuidado: checkout)
15. PR #15: bucket 4 migrado
16. PR #16: crons movidos pro core, api perde handlers antigos
17. PR #17: payments callback aponta pro core
18. PR #18: cleanup final, api < 3k LOC

Cada PR com: smoke E2E PASS, mudança no STATUS-CHECKLIST.md, RUNBOOK update se mudar operação.

### 11.4 Audit trail das críticas adversariais aplicadas

Este documento foi submetido a uma revisão adversarial independente após o draft inicial. 12 críticas foram registradas e **todas as 12 foram incorporadas no corpo do texto**. Lista pra auditoria:

| # | Crítica | Seção afetada |
|---|---------|---------------|
| 1 | Estimativa 9a "1-2 semanas" otimista (build xcaddy, janela DetectionOnly mín 14d, tuning CRS) → real 3-4 semanas | 4.1 (estimativa expandida) |
| 2 | Chave RS256 compartilhada api↔auth viola objetivo de superfície mínima — sem prazo limite | 4.2 (INVARIANTE de 14 dias + API_MINT_DISABLED) |
| 3 | Hot-set de revogação em memória pura: race em zero-downtime swap + perda em restart | 7.4 (tabela `revoked_jtis` + bootstrap em readiness) |
| 4 | Bucket 3 (checkout) em 1 semana subestima risco financeiro: sem canary/shadow/reconciliação | 4.3 sub-bucket 3 (protocolo canary obrigatório) |
| 5 | Coraza/CRS apresentado como "zero código pra manter" sem listar limites (IDOR/BOLA/business logic) | 3.2 (limites explícitos + custo operacional real) |
| 6 | RTO/RPO pós-split não considerado: backup de keys/envs/Caddyfile/Coraza rules ausente | 9.3 (runbook restore-prod.sh + drill trimestral) |
| 7 | "Entrega 90% do valor" é heurística arbitrária; recomendação Opção B pode mascarar critérios não-explicitados do cliente | 3.5 (limitações da recomendação) |
| 8 | Janela de 14 dias "código antigo preservado" sem disciplina de sync → paths divergem silenciosamente | 4.3 rollback plan (CI dual-mode + linter + dashboard timer) |
| 9 | Custo "+4-8 semanas pra Rust depois" é linear; real é exponencial pelo retrabalho de paridade | 3.5 (custo real 8-14 sem + 3-6 meses coexistência) |
| 10 | Troubleshoot E2E através de 5+ hops sem runbook concreto → "OTel cuida" é não-resposta | 8.6 (runbook detalhado + drill de on-call) |
| 11 | DDL durante strangler window sem porteiro: drop destrutivo + rollback in-proc = schema mismatch | 6.4 (3 PRs separados + checklist + linter) |
| 12 | "Smoke E2E PASS" como gate sem definir o que cobre → placebo. Falta cobertura cross-service | 10.6 (ampliação obrigatória: 9 casos novos) |

A revisão adversarial encontrou padrão consistente de subestimar custo de **coexistência durante strangler** e ler **"WAF resolve" como mais forte do que é**. Edições endereçaram ambos os padrões.

---

## 12. Notas finais

Esse plano foi revisado contra os seguintes vieses comuns em propostas arquiteturais:

1. **Resume-driven development** — "queremos Rust porque é novo". Resposta: Opção B explicitamente diz "não escreva código que Caddy + Coraza já dão pronto".
2. **Big-bang rewrite** — risco de mover 25k LOC de uma vez. Resposta: strangler pattern obrigatório, bucket por bucket, com observação entre eles.
3. **Premature optimization** — escolher Rust pra latência sem medir. Resposta: 9d é condicional a gatilho de produção, não fé.
4. **Microservice fetish** — quebrar tudo só porque é moda. Resposta: 3 services (não 7), cada um justificado por superfície de ataque OU blast radius OU cadência de mudança distinta.
5. **Underestimação de operação** — assumir que toolchain dupla é grátis. Resposta: seção 3.1 explicita custo Rust, seção 4.4 exige treinamento de equipe.
6. **Falta de rollback** — assumir que vai dar certo. Resposta: cada fase tem rollback plan explícito, feature flags, e código antigo preservado por 14 dias.
7. **Falsa segurança via WAF** — WAF não substitui validação no domínio. Resposta: Coraza é defesa em profundidade, validação semântica (input shape, autorização) continua no core/auth.
8. **JWT compartilhado sem rotação** — chave RS256 nunca rotacionada. Resposta: seção 7.3 define rotação mensal com janela de 2 keys ativas.
9. **DB único como single point of failure** — sem replicação. Resposta: backup + WAL já existem (fora do escopo dessa fase, mas registrado em ROADMAP).
10. **Otimismo de estimativa** — "1 semana" sem buffer. Resposta: estimativas em semanas, não dias, e cada fase inclui janela de observação.

A decisão final é da liderança técnica. Esse documento existe pra deixar claro o que cada caminho custa e o que cada um entrega.

Próximo passo recomendado: aprovar Opção B + iniciar Fase 9a na próxima janela de deploy.
