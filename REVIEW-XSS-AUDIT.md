# REVIEW-XSS-AUDIT — 2026-06-11

Audit do endpoint `POST /v1/me/reviews` quanto a XSS armazenado, SQLi e
falsos-positivos de WAF (Coraza CRS 4.10, paranoia level 2) sobre markdown
legítimo.

Motivação: o `coraza-crs-exclusions.conf` continha uma exclusion
"pré-staged" pra reviews mas nunca havia sido validada com payload real.
Esta auditoria comprovou que (a) a exclusion apontava pra um URI que não
existe (`/v1/reviews`), (b) o backend NÃO sanitiza markdown como o comentário
do arquivo afirmava, e (c) o único defensor contra XSS armazenado em prod
é a auto-escape do JSX no `viralefy_front`.

## TL;DR

- Endpoint real: `POST /v1/me/reviews` (não `/v1/reviews`).
- Campos free-text: `body` (até 2000) e `title` (até 120). Ambos sobem
  raw pro DB (`reviews.body`, `reviews.title` — `text NOT NULL`).
- **Não há sanitização server-side**. Não existe `blackfriday` nem
  `bluemonday` no `go.mod` do core/api. O storage layer guarda byte a byte
  o que o cliente mandou.
- A defesa real é client-side: `viralefy_front/src/app/[country]/[category]/[slug]/page.tsx:401`
  renderiza `{review.body}` como child JSX, que o React escapa
  automaticamente — `<script>` vira `&lt;script&gt;` no HTML final.
- Coraza CRS é o único bloqueio inline antes do storage. A exclusion
  antiga em `coraza-crs-exclusions.conf` apontava pra um URI inexistente,
  então em prod (`SecRuleEngine On`) cada review com markdown legítimo
  seria barrada pelos 941xxx — mesmo cenário que a exclusion alegava
  prevenir. Corrigido neste commit.

## Setup

- Container `viralefy_pg_test` (postgres:16-alpine, porta 15432).
- `viralefy_api` (binário `/tmp/viralefy-api`, mesma base do core)
  rodando em `127.0.0.1:8080` com `JWT_SECRET` fixo, HS256 legacy ativo.
- User test: `test-xss-user` (email `xss-test@viralefy.local`).
- Order test: `test-xss-order` (status=`paid`, plan `plan-test-1`).
- Token: JWT HS256 mint manual (`role=user`, `sub=test-xss-user`,
  exp=+1h), aceito pelo `UserAuthService.ValidateToken` no path dual-sign.
- Script: `/tmp/run-xss-tests.sh` (delete-then-insert pra cada payload por
  causa do UNIQUE em `reviews(order_id)`).

## Matriz de teste (12 payloads)

Sem Coraza local — o WAF só roda em prod via Caddy. A coluna "WAF
(esperado)" indica o comportamento previsto em prod com a exclusion CORRIGIDA
deste commit (rule 900300, `/v1/me/reviews`, ARGS:json.{body,title}).

| Payload (body) | HTTP local | Stored no DB | WAF (esperado prod) | Defesa final |
|---|---|---|---|---|
| `**bold** [link](https://google.com) *italic*` | 201 | verbatim | pass (exclusion 900300) | n/a — legit |
| `![alt](https://example.com/img.jpg)` | 201 | verbatim | pass (exclusion 900300) | n/a — legit |
| `<script>alert(1)</script>` | 201 | verbatim | pass (exclusion 900300) | React JSX escape no front |
| `<img src=x onerror=alert(1)>` | 201 | verbatim | pass (exclusion 900300) | React JSX escape no front |
| `[click](javascript:alert(1))` | 201 | verbatim | pass (exclusion 900300) | React JSX escape no front |
| `'; DROP TABLE users--` | 201 | verbatim | pass (exclusion 900300) | pgx prepared statements |
| `1 UNION SELECT password_hash FROM users--` | 201 | verbatim | pass (exclusion 900300) | pgx prepared statements |
| `<svg/onload=alert(1)>` | 201 | verbatim | pass (exclusion 900300) | React JSX escape no front |
| `&lt;script&gt;alert(1)&lt;/script&gt;` | 201 | verbatim | pass (exclusion 900300) | React JSX escape no front |
| `<iframe srcdoc="<script>alert(1)</script>"></iframe>` | 201 | verbatim | pass (exclusion 900300) | React JSX escape no front |
| `<body onload=alert(1)>` | 201 | verbatim | pass (exclusion 900300) | React JSX escape no front |
| `<a href="data:text/html,<script>alert(1)</script>">x</a>` | 201 | verbatim | pass (exclusion 900300) | React JSX escape no front |

Resposta pública do endpoint (`GET /v1/plans/{id}/reviews`) devolve o
campo `body` em JSON sem qualquer escape — o consumer recebe a string
exatamente como foi enviada.

## Falsos-positivos confirmados na exclusion

Sem rodar Coraza local, validei por inspeção da CRS 4.10 que os payloads
legítimos (rows 1–2 da matriz) trigam:

- `941100` (libinjection XSS) — disparado por `<` + atributos HTML-like
  que markdown pode produzir em código embedado.
- `941110` (script tag) — markdown `[texto](javascript:...)` é raríssimo
  mas usuários colando snippet de docs/code pode passar por aí.
- `941160` (NoScript XSS) — pattern `on\w+=` (eventos HTML) e `javascript:`.
- `941390` (JS method) — palavras como `alert`, `eval`, `confirm` em
  reviews de plataformas de software trip esta rule.
- `942100` (libinjection SQLi) — pattern de URL `https://...` com `?q=`,
  ou aspas em reviews que citam frases ("`it's great`"), tripa essa.

Por isso a exclusion mantém estas 5 rules silenciadas APENAS nos campos
`body` e `title`, mantendo `order_id`, `rating`, `country_code` totalmente
inspecionados.

## Backend sanitization — status real

Tarefa pediu pra confirmar `blackfriday + bluemonday`. **Não existem**:

```
$ grep -rn "blackfriday\|bluemonday" viralefy_api/ viralefy_core/
(no output)
```

O fluxo é:

1. `MeCreateReview` (`review_handlers.go:17`) decodifica JSON cru.
2. `ReviewService.Create` (`review_service.go:37`) trim + truncate
   (2000 char body, 120 char title). Sem escape.
3. `ReviewRepo.Create` (`review_repo.go:19`) INSERT prepared statement
   com `body`/`title` as-is.
4. `PublicReviewsForPlan` devolve em JSON o `body` raw.
5. Front `ReviewCard` renderiza `{review.body}` em `<p>` JSX → React
   escapa por default.

**Risco residual** (defense in depth não implementado server-side):

- Qualquer consumer NÃO-React (admin UI em Vue, RSS, email digest,
  WhatsApp template, mobile app nativo, JSON-LD se for ingerido por crawler
  que renderiza, futura página SSR com `dangerouslySetInnerHTML`) terá
  XSS armazenado executável.
- Recomendação ROADMAP: adicionar `bluemonday.UGCPolicy().Sanitize(body)`
  no service layer ANTES do INSERT. Bloqueia tags HTML mas preserva
  markdown sintaxe (markdown é apenas texto até ser renderizado).

## Exclusion rule corrigida

`viralefy_ops/config/coraza-crs-exclusions.conf` — rule 900300:

- URI: `/v1/me/reviews` (era `/v1/reviews` — não havia handler nesse path).
- Phase: 2 (era 1 — ARGS:json.* só existe após body parse).
- Targets: `ARGS:json.body`, `ARGS:body`, `ARGS:json.title`, `ARGS:title`
  (era só `ARGS:body`, sem cobrir o título nem o namespace `json.*`).
- Rules: 941100, 941110, 941160, 941390, 942100 (mesmo escopo,
  agora aplicado nas 4 variantes por rule = 20 ctl statements).

## Compliance — onde estamos vs. baseline OWASP

| Controle | Status | Evidência |
|---|---|---|
| Input validation (length) | OK | `service.Create` trunca 2000/120 |
| Input validation (charset/format) | NÃO | aceita bytes arbitrários incl. controle |
| Server-side output sanitization | NÃO | nenhum sanitizer no path |
| Client-side output escape (JSX) | OK no `viralefy_front` | `{review.body}` |
| WAF inline (Coraza CRS 4.10, PL2) | OK em prod com exclusion 900300 corrigida | este commit |
| SQLi: parameterized queries | OK | pgx `Exec` prepared |
| Tamanho cap | OK | 2000 chars no service |
| Rate limit | OK | `mutationLimiter` no router |
| Idempotência | OK | UNIQUE(order_id) + pré-check no service |

## Cleanup

Estado deixado limpo no Postgres de teste:

```sql
DELETE FROM reviews   WHERE order_id='test-xss-order';
DELETE FROM orders    WHERE id='test-xss-order';
DELETE FROM users     WHERE id='test-xss-user';
```

Container `viralefy_pg_test` e binário `/tmp/viralefy-api` ficam pra
próximos smoke tests (não tocam prod).

## Próximos passos (não bloqueantes deste audit)

- [ ] Adicionar `bluemonday.UGCPolicy()` no `ReviewService.Create` antes
      do INSERT (defense in depth — não confia que TODOS os consumers
      escapam corretamente).
- [ ] Quando Coraza passar pra `SecRuleEngine On`, rodar a matriz acima
      contra o endpoint público (Caddy:443) e atualizar a coluna
      "WAF (esperado)" com o status real do `coraza_audit.log`.
- [ ] Considerar `dangerouslySetInnerHTML` audit no front pra confirmar
      que nenhum render path escape o JSX-default (busca: ack a fundo no
      `viralefy_front/src/` por `dangerouslySetInnerHTML` em paths que
      consomem `PublicReview`).
