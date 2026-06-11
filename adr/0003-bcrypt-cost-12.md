# ADR-0003 — bcrypt cost 12 para senhas (não argon2id)

- **Status:** accepted
- **Data:** 2026-06-11
- **Decisores:** Equipe Viralefy
- **Diretriz relacionada:** §13 (bcrypt cost ≥ 12 ou argon2id)
- **Reavaliação:** 2027-06 (revisão anual de cripto)

## Contexto e Problem Statement

A diretriz §13 estabelece, na suite de testes de segurança (`tests/security/`), validação de "formato de password hash (bcrypt cost ≥ 12 / argon2id)". O `pentest/timing-attack.sh` mede variance de latência em login.

Estado atual (verificado via grep em 2026-06-11):

- `viralefy_auth/internal/application/password.go` — `const bcryptCost = 12` (canônico, novo serviço).
- `viralefy_core/internal/application/user_auth_service.go` — `bcrypt.GenerateFromPassword(..., 12)` (3 ocorrências: register, set_password, reset_password).
- `viralefy_core/internal/application/checkout_service.go` — `bcrypt.GenerateFromPassword(..., 12)` no autocadastro com senha gerada.
- `viralefy_core/internal/application/auth_service.go` — cost 12.
- `viralefy_api` (legacy) — idem cost 12 (espelha o core).
- `viralefy_core/internal/infrastructure/persistence/postgres/seed.go` — cost 12 (superadmin seed).
- **Exceção documentada:** TwoFA **backup codes** usam cost 10 em `twofa_service.go` (linha 63) e `viralefy_auth/internal/application/auth_service.go:261`. Migration `036_twofa.up.sql` comenta "Backup codes hashed bcrypt cost 10, comparison constant-time."

## Decision Drivers

- Conformidade com OWASP/NIST: bcrypt cost ≥ 12 atende recomendação 2024+.
- Latência de login: cost 12 ~250ms em CPU típica de VPS Hetzner; cost 14 ~1s (UX ruim).
- Migração de hash legado: usuários antigos não precisam re-hash; ao login next, opcionalmente upgrade.
- argon2id é tecnicamente superior, mas exige tuning (memory, iterations, parallelism) e biblioteca menos auditada que `golang.org/x/crypto/bcrypt`.

## Considered Options

### Option A — bcrypt cost 12 (status quo)

**Prós:** padrão da indústria, biblioteca battle-tested, latência aceitável.
**Contras:** bcrypt é mais fraco que argon2id contra GPU/ASIC modernos.

### Option B — argon2id (recomendado por OWASP desde 2021)

**Prós:** state-of-the-art, memory-hard (resistente a GPU).
**Contras:** parâmetros mais difíceis de calibrar, mais código novo para auditar.

### Option C — bcrypt cost 14+

**Prós:** mais resistente que cost 12.
**Contras:** latência de login >1s degrada UX.

## Decision Outcome

**Escolhida: Option A — bcrypt cost 12.**

Justificativa:

1. **Conformidade direta com a diretriz** (§13 cita "bcrypt cost ≥ 12 OU argon2id" — não exige argon2id).
2. **Latência apropriada** para login web (250ms p95).
3. **Bcrypt em `golang.org/x/crypto`** é maintido pela equipe Go core, alta confiança.
4. **TwoFA backup codes em cost 10** é aceito como exceção documentada: cada código é random 8-char alfanumérico (entropia >40 bits), uso único, e existem 10 códigos válidos. Brute force offline de um hash cost 10 ainda exige horas em GPU para crackar um único código; benefício de cost 12 não justifica latência cumulativa na geração de 10 hashes em hot path (`twofa_service.go` cria 10 hashes em loop).

## Validação

Cobertura assegurada por:

- `viralefy_ops/tests/security/auth-bypass.sh` (planejado §22.3) — assert `bcrypt cost ≥ 12` no formato armazenado.
- Smoke test pode parsear hash retornado em DB seed para garantir prefixo `$2a$12$` ou `$2y$12$`.

## Action items

- [x] Padronizar **toda nova ocorrência** de `bcrypt.GenerateFromPassword` com cost 12 (constante exportada de `application/password.go` em vez de literal).
- [ ] **Pendente:** extrair `const bcryptCost = 12` para `internal/shared/crypto/password.go` em `viralefy_core` (hoje cada arquivo usa literal 12; centralizar reduz risco de regressão).
- [ ] **Pendente:** adicionar `tests/security/password-hash-format.sh` em `viralefy_ops` que confirma todos hashes em `users.password_hash` começam com `$2a$12$` ou `$2y$12$`.
- [ ] **TwoFA backup codes:** decisão revisitada se OWASP soltar guidance específica.

## Consequences

### Positivas

- Conforme §13.
- Stack uniforme: todos os hashes de senha do MVP usam cost 12.

### Negativas

- Pequeno risco de cost 12 ficar abaixo do recomendado em 3-5 anos. Revisão anual mitiga.
- Hashes legados (pré-cost-12) podem existir; verificar se há `$2a$10$` ou `$2a$11$` em produção. Action item: query `SELECT substring(password_hash,1,7), count(*) FROM users GROUP BY 1;` para auditoria.

## Links

- Diretrizes §13
- `viralefy_auth/internal/application/password.go:15` — constante canônica
- OWASP Password Storage Cheat Sheet 2024
