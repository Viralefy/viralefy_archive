# Viralefy — Roadmap até v1 estável

Snapshot 2026-06-06. Compilado de [RECOMMENDATIONS.md](RECOMMENDATIONS.md) + sustos achados em sessão (cred leak, sitemap vazio, currency rate stale) + cleanups pendentes.

Ordenação: **dependência primeiro, depois risco existencial, depois leverage downstream**. Cada fase termina com a próxima podendo começar sem retrabalho.

Legend: ✅ done · 🟡 in flight · ⬜ pending · ⏸ deferred

---

## Fase 0 — Já feito nesta rodada (2026-06-05 → 06)

- ✅ Hotfix sitemap: 19 buckets per-lang vazios (`COUNTRY_LANG` faltava 35 países)
- ✅ Tier 4 SEO: `/pricing`, `/cities`+50, `/vs`+10, `/help`+12, `/case-studies`+6
- ✅ Cred leak da página de login + 4 READMEs limpos
- ✅ Seed env-driven (`ADMIN_BOOTSTRAP_*`), zero default password no código
- ✅ Currency rate cascade: `seedPlanPrices` lê DB, `CurrencyService.Update` cascateia em `plan_prices`
- ✅ Front `priceFor()` aplica rate quando não há manual override

---

## Fase 1 — Cleanup pós-cascade (low-effort, fecha pontas soltas)

- ✅ 1.1 Auditar callsites `plan.prices[code]` no front — confirmado: residuais são JSON-LD (USD canonical, correto)
- ⬜ 1.2 `plan_prices_consistency_check` cron + Prometheus counter `viralefy_plan_price_drift_total{currency}` (2-3h)
- ⬜ 1.3 Test integração postgres pra `RecomputePricesForCurrency` (1h)
- ⬜ 1.4 Limpar `seedPlanPrices` da chamada em CreatePlan — agora o cascade pega tudo (30min)

---

## Fase 2 — Risco existencial (sem dependências, alto leverage)

- ⬜ 2.1 **Postgres backup automatizado** — systemd timer `pg_dump.timer` nightly, retenção 7d+4w+6m, escrita local + opcional sync remoto. Métrica Prometheus `viralefy_backup_last_success_timestamp` + alerta se > 36h. (3-4h)
- ⬜ 2.2 **Sentry** — front + backoffice + API (Go SDK), DSN via env, source maps no front. Captura erros futuros sem instrumentação adicional. (2-3h)
- ⬜ 2.3 **Status page público** — `/status` lendo Prometheus (`up{job=*}`) → cards verde/amarelo/vermelho por serviço. Schema StatusPage para SEO. (2h)

---

## Fase 3 — Velocidade de dev (dependency: tudo abaixo passa por CI)

- ⬜ 3.1 **CI/CD GitHub Actions** — workflow por repo: `go build + go test` (api), `tsc + node --test` (front/backoffice/ops), bloqueia merge sem verde. (3-4h)
- ⬜ 3.2 **Husky/lefthook pre-commit** opcional — corre `gofmt`/`tsc` localmente (1h)
- ⬜ 3.3 Lint Go (`go vet` + `staticcheck`) na CI (1h)

---

## Fase 4 — Segurança hardening

- ⬜ 4.1 **JWT HS256 → RS256** — gerar keypair, store private em `/etc/viralefy/jwt-private.pem`, publish public em `/v1/.well-known/jwks.json`. Migração: dual-sign por 7d. (6-8h)
- ⬜ 4.2 **Rate-limit por IP no login** (admin + user) — bloqueia 100 tentativas/15min (3-4h)
- ⬜ 4.3 **Anti-fraude velocity** — flag pedido se 3+ orders / 24h do mesmo IP/email/fingerprint. Bloqueia hard se 10+/h. Tabela `fraud_signals`. (6-8h)
- ⬜ 4.4 **Email reputation watcher** — Resend webhook `bounced/complained` → `email_reputation` table + auto-disable após 3 bounces (3-4h)
- ⬜ 4.5 **Auditoria de secrets em git history** (gitleaks scan, fix se achar) (1h)

---

## Fase 5 — Compliance

- ⬜ 5.1 **GDPR cookie banner** — opt-in/opt-out granular, persistir consent em `users.gdpr_consent`. (3-4h)
- ⬜ 5.2 **Manage my data** UI `/account/data` — download JSON (export) + request deletion (soft → 30d → hard). (5-7h)
- ⬜ 5.3 **Tax handling** — calcular VAT por país EU, exibir no checkout, gerar invoice com breakdown. Tabela `tax_rates`. (8-12h)
- ⬜ 5.4 **Refund/dispute admin UI** — fluxo no backoffice pra emitir reembolsos parciais + tracking gateway. (6-8h)

---

## Fase 6 — Receita (Tier 2 — quase tudo com escopo bem definido)

- ⬜ 6.1 **Cupom system** — `coupons` table (code, discount_pct/abs, max_uses, expires_at), aplicado no checkout, audit log. (6-10h)
- ⬜ 6.2 **Cart abandonment cron** — flag `orders.cart_abandoned_at`, cron envia email 1h e 24h pós-abandono via Resend. (3-5h)
- ⬜ 6.3 **Subscription** — auto-renew mensal de followers, cron mensal + payment retry. (10-15h)
- ⬜ 6.4 **Referral** — `referrals` table, código próprio do user, +5% credit no primeiro pagamento de quem indicou. (8-12h)
- ⬜ 6.5 **PPP pricing** — multiplicador por país (BR=0.6, IN=0.4, US=1.0) aplicado no display amount. (4-6h)
- ⬜ 6.6 **A/B testing harness** — `experiments` table + cookie assignment + Prometheus event counter. (6-8h)

---

## Fase 7 — Product depth (Tier 6)

- ⬜ 7.1 **Order tracking detail** — UI `/account/orders/{id}` com timeline: paid → captured → in_progress → delivered + ETA. (4-6h)
- ⬜ 7.2 **Notification preferences** — `users.notif_prefs` JSON, opt-in granular email/whatsapp/sms. (3-5h)
- ⬜ 7.3 **WhatsApp opt-in** + Resend transactional via WhatsApp Business API (4-6h)
- ⬜ 7.4 **Multi-vendor** ⏸ — grande, escopo de v2 (40-60h)
- ⬜ 7.5 **API B2B** ⏸ — grande, escopo de v2 (30-50h)

---

## Fase 8 — Code quality (Tier 5)

- ⬜ 8.1 **Playwright E2E** — fluxos críticos (browse → checkout → confirm) (6-10h, depende de 3.1 CI)
- ⬜ 8.2 **Storybook** front — para componentes reutilizáveis (4-6h)
- ⬜ 8.3 **Zod schemas** nas boundaries de API (Go ↔ TS) — geração automática via openapi (8-12h)

---

## Estratégia de execução

1. **Hoje/agora:** Fase 1.2 → Fase 2.1 → 2.2 → 2.3 (defensiva primeiro, ~1 dia)
2. **Amanhã:** Fase 3.1 (CI/CD — destrava confiança em qualquer mudança)
3. **D+2..3:** Fase 4 (segurança) + Fase 5.1 GDPR (low-hanging)
4. **D+4..7:** Fase 6 (receita) iterativo: 6.1 cupom → 6.2 abandonment → 6.5 PPP
5. **Semana 2:** Fase 5.2-5.4 + Fase 7.1-7.3
6. **Semana 3:** Fase 8 + sobras

Total ativo (sem deferidos): ~150-200h de implementação efetiva.

---

## KPI da rodada

- ✅ Zero credencial hardcoded em código ou commits
- ⬜ Backup do banco testado e restaurado em staging
- ⬜ CI gate vermelho bloqueia merge (verificado com PR proposital quebrado)
- ⬜ Sentry capturou primeiro erro em prod (smoke test)
- ⬜ Status page atualiza com base em Prometheus
- ⬜ 1 release sem hotfix manual
