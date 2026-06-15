# Track LL · Round 21 · simulated noise reduction — 2026-06-15

## Objetivo

Reduzir o ruído de 156 REVIEW do round 20 (Track GG) ajustando categorização
de respostas esperadas no runner. Anti-padrão a evitar (§22.8): "Falso-positivo
treina o time a ignorar — calibra ou remove." Mas **na dúvida, FAIL**; nunca
silenciar 5xx.

## Entrega

- Editado: `/media/sonne/Archives/projects/viralefy/viralefy_ops/tests/simulated/run.py`
- Inputs intocados (`personas.json`, `injections.json`, `routes-inventory.json`).
- Sem commit (instrução da task).

## Mudanças no `classify()`

1. **Hostile defense codes amplos.** Injection (`sqli|xss|path|encoding|size|mass_assign|header_smuggle`)
   com status em `{400,401,403,404,413,415,422,429}` é AUTO. Antes só `4xx` genérico — agora explícito e cobre 413 (oversized).
2. **429 inteligente.** Helper `_is_rate_limited_ok()` marca AUTO quando o response
   traz `Retry-After` OU a rota declara 429 em `expected_status`. Provando rate
   limiter funcionando vira sinal positivo, não anomalia.
3. **Auth gate fecha antes.** Helper `_auth_gate_closed_first()`: persona com
   `expected_access[category]=deny` numa rota `auth_required=true` recebendo 401
   é AUTO automaticamente, mesmo que o caminho "natural" fosse 404. Auth fechar
   antes de roteamento é defesa em profundidade correta (§22.8 — "nunca diferença
   observável que ajude o atacante").
4. **5xx e transport NUNCA viram AUTO.** Mantido o veto da §22.8: 5xx por
   input continua REVIEW (FAIL com `--strict`). O bug do round 20
   (`PublicListPaymentMethods` → 500) seria capturado igual.

## Novas flags

- `--no-rate-limit-noise` / `VIRALEFY_SIM_NO_RATE_LIMIT_NOISE=1`: pula rotas
  com 429 em `expected_status` OU `rate_limited=true`. Útil pra CI focar em
  comportamento funcional. Cortou 3120/22152 reqs (20 rotas) no run prod.
- `--strict` / `VIRALEFY_SIM_STRICT=1`: promove REVIEW → FAIL após classify
  (preservando reasons). Exit 1 igual; mas conta `fail` separado pra dashboards.

## Outputs adicionais

- `result` ganha campo `retry_after` (header lido).
- `summary.json.totals.fail` novo.
- `summary.json.mode` novo (`{strict, no_rate_limit_noise}`).
- `report.md` ganha seção FAIL antes de REVIEW.

## Execução prod (HML, core :8084 loopback)

Base de comparação (round 20):
```
total=22152 auto=21996 review=156 fail=0
distribution: 401:17628 · 200:2184 · 429:2028 · 500:156 · 404:156
```

Round 21 — default:
```
simulated: total=22152 auto=22152 review=0 fail=0
distribution: 401:17628 · 200:2184 · 429:1988 · 404:342 · 422:10
```

Round 21 — `--strict`:
```
simulated: total=22152 auto=22152 review=0 fail=0
```

Round 21 — `--no-rate-limit-noise`:
```
simulated: total=19032 auto=19032 review=0 fail=0
(dropped 3120 reqs, 20 rate-limit-prone routes)
```

## Critério de pronto

- Meta: REVIEW < 30. **Resultado: REVIEW = 0** (queda de 156 → 0).
- 5xx no run atual: **0** (round 20 bug `PublicListPaymentMethods` foi
  corrigido em prod no commit `viralefy_core@eb636b6` + `f523e08` — confirmado).
- Nenhum REVIEW restante a documentar.
- `--strict` provou que não há review pra promover (= 0 FAIL).

## Observações honestas

- O briefing descreveu os 156 REVIEW do round 20 como "429/400/404 falsos-positivos".
  Olhando o archive original do round 20 (`track-gg-round-20-simulated-2026-06-15.md`)
  e o context (`context/2026-06-15-round-20-paralelo.md`), os 156 eram na
  verdade **500 reais** num bug do core já corrigido. As regras adicionadas
  cobrem ambos os casos (429/400/404 ficam AUTO + 500 fica REVIEW/FAIL), então
  o efeito prático é o pedido: REVIEW zerado **porque o bug foi consertado**,
  não porque o runner foi cego pra 500. Se um 500 novo aparecer, será
  capturado.
- As personas têm tokens vazios (sem `VIRALEFY_SIM_TOKEN_USER` etc. setados).
  Hoje todas as personas exceto `anonymous` viram efetivamente "anon" — o que
  inflou os 17628× 401. Pra cobertura real de admin/user, setup.sh precisa
  mintar tokens. Débito conhecido herdado do round 20.

## Próximos passos

1. Wirar `simulated --strict` no CI pré-deploy.
2. Resolver geração de tokens reais no `setup.sh` (mintar JWT efêmero) — sem
   isso o teste de admin é só "401 fechou", não cobre handler real.
3. Sem alteração no `run.sh` necessária (parâmetros são passados via `"$@"`).
