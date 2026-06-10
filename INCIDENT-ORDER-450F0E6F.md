# INCIDENT: drift HIGH `orders_paid_no_external_ref` em 2026-06-10

## Resumo

- Reconcile cron detectou 1 drift HIGH em 2026-06-10 (03:30 UTC daily run): order `450f0e6f-843c-4fae-88eb-ab378a8f194c` com `status=paid` e `external_ref` vazio, violando o invariante `orders_paid_no_external_ref`.
- Causa raiz: **false positive** do invariante. Order pertencia ao gateway PIX Manual (`provider=manual_pix`), que por design não emite `external_ref` (pagamento off-platform). A query do invariante filtrava por `payment_method='gateway'` (enum coarse: gateway/credits) sem inspecionar `payment_gateways.provider`, então toda order de qualquer gateway, inclusive os manuais, caía na sentinela.
- Fix: refinar a query para excluir gateways `provider LIKE 'manual_%'`. Build + deploy do binário `/usr/local/sbin/viralefy-reconcile`. Re-run pós-fix: drift HIGH `orders_paid_no_external_ref` = 0 (count). Sobrou só `orders_pending_over_7d` (LOW, 4 rows, abandono esperado de QA).

## Detalhes da order

| Campo | Valor |
|---|---|
| `id` | `450f0e6f-843c-4fae-88eb-ab378a8f194c` |
| `user_id` | `39a79449-c4c0-4e16-88b8-ef3a6e2d684d` (`qa@viralefy.com`) |
| `status` | `paid` |
| `payment_method` | `gateway` |
| `gateway_id` | `70f6db61-675c-4801-9c9b-bdb72aa74213` (`PIX Manual`, `provider=manual_pix`, `active=false` desde 2026-06-09) |
| `external_ref` | (vazio — esperado pra manual_pix) |
| `amount_cents` | 990 |
| `currency` | BRL |
| `display_amount` | 9.90 BRL |
| `created_at` | 2026-05-30 19:56:56 UTC |
| `updated_at` | 2026-06-04 21:43:19 UTC |
| `payment_extra.pix_key` | `contato@viralefy.com` |
| `baseline_source` | `manual_pending` |

Order é claramente de teste do QA (usuário `qa@viralefy.com`, baseline `qa_brand` no Instagram, fluxo PIX Manual usado durante setup inicial antes dos gateways reais ficarem ativos).

Sem registros em `audit_log` pra esse target (audit não cobria o admin-mark-paid flow naquela época) nem em `order_proofs` (proofs vieram depois).

## Causa raiz

O invariante v1:

```sql
SELECT id FROM orders
WHERE status = 'paid'
  AND payment_method = 'gateway'
  AND (external_ref IS NULL OR external_ref = '')
```

Confundia dois conceitos:
- `orders.payment_method` é um enum coarse (`gateway` vs `credits`) — diz se a order foi paga via gateway ou via créditos internos.
- `payment_gateways.provider` é o adapter real (`stripe`, `heleket`, `abacatepay`, `woovi`, `manual_pix`, …).

Providers manuais (`manual_pix`, futuro `manual_usdt`) implementam `application.PaymentProvider` retornando `ExternalRef: ""` deliberadamente (ver `viralefy_core/internal/infrastructure/external/payment/manual.go:23`). Eles são acionados via `InvoiceService.AdminMarkPaid` quando o admin confirma o comprovante recebido por e-mail. Não existe `external_ref` porque o gateway externo não existe — o "gateway" é o admin com um e-mail.

A `payment_method='gateway'` no invariante portanto incluía todas as orders de PIX Manual, gerando false positives sempre que houvesse qualquer venda manual paga.

## Fix aplicado

`viralefy_core/cmd/reconcile-cron/main.go` — invariante `orders_paid_no_external_ref` agora JOIN com `payment_gateways` e exclui `provider LIKE 'manual_%'`:

```sql
SELECT o.id FROM orders o
LEFT JOIN payment_gateways pg ON pg.id = o.gateway_id
WHERE o.status = 'paid'
  AND o.payment_method = 'gateway'
  AND (o.external_ref IS NULL OR o.external_ref = '')
  AND (pg.provider IS NULL OR pg.provider NOT LIKE 'manual_%')
ORDER BY o.created_at DESC
LIMIT 10
```

Mantém detecção de drift real (Stripe/Heleket/Abacate/Woovi sem confirmar gravar ref) e ignora providers manuais que por contrato não têm ref.

Build: `cd viralefy_core && go build -trimpath -ldflags='-s -w' -o bin/viralefy-reconcile ./cmd/reconcile-cron`.

Deploy manual: `scp` pra `/usr/local/sbin/viralefy-reconcile` (binário não é coberto pelo `viralefy-update` ainda — ver Action Items).

## Verificação

```
$ systemctl start viralefy-reconcile
$ journalctl -u viralefy-reconcile --since "1 min ago" -o cat | tail
[DRIFT low] orders_pending_over_7d: 4 row(s) — sample: [f245b859 ecea6ab1 bc3ed549 ff2da02e]
{"timestamp":"2026-06-10T17:56:02Z","duration_ms":74,"invariants_checked":15,
 "drifts":[{"name":"orders_pending_over_7d","severity":"low","count":4,...}],
 "errors":0}
reconcile-cron: 1 drift(s) detectado(s), 0 erro(s), 74ms
```

`orders_paid_no_external_ref` saiu do report. Sobrou `orders_pending_over_7d` (LOW, 4 pending de QA — abandono esperado, fora do escopo deste incidente).

## Lessons learned

1. **Invariantes precisam encodar o contrato, não o estado superficial.** A v1 olhava só pra `payment_method`; o contrato real era "provider externo deve emitir ref". JOIN com `payment_gateways` corrige isso.
2. **Providers manuais são uma classe distinta.** `manual_pix` (e futuros `manual_*`) escapam de várias invariantes que assumem gateway online. Convém marcar todos com prefixo `manual_` pra filtros uniformes.
3. **Audit_log não cobria admin-mark-paid em 2026-05.** Hoje ainda não. Sem o log, investigação ficou só com `orders.updated_at` (4 dias depois de criada — bate com aprovação manual de PIX).
4. **Binário do reconcile-cron não está no pipeline `viralefy-update`.** Deploy foi manual via scp. Risco médio: se rebuild da infra acontecer, binário some.

## Action items

| # | Item | Prioridade | Estado |
|---|---|---|---|
| 1 | Refinar invariant `orders_paid_no_external_ref` excluindo providers manuais | HIGH | Done — este commit |
| 2 | Adicionar build do `reconcile-cron` no `viralefy_ops/bin/viralefy-update` (mesma pattern do `viralefy-api`) | MED | Aberto |
| 3 | Adicionar `audit_log` entry no `InvoiceService.AdminMarkPaid` (atualmente silent) | MED | Aberto |
| 4 | Considerar invariante adicional `manual_paid_no_proof` — manual_pix paid sem `order_proofs` row | LOW | Aberto |
| 5 | Backfill: documentar no RUNBOOK que `payment_gateways.provider='manual_pix'` é um adapter sem ref | LOW | Aberto |

## Apêndice — query útil

Para inspecionar todas as orders paid sem external_ref no futuro (já filtrando manuais):

```sql
SELECT o.id, o.payment_method, pg.provider, pg.active, o.created_at
FROM orders o
LEFT JOIN payment_gateways pg ON pg.id = o.gateway_id
WHERE o.status = 'paid'
  AND (o.external_ref IS NULL OR o.external_ref = '')
ORDER BY o.created_at DESC;
```

Em 2026-06-10 retornou 2 rows: a `450f0e6f` (manual_pix) e `e3e0e913` (`payment_method=credits`, gateway null — também correto, pago via créditos internos sem gateway).
