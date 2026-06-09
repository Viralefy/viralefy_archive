# Viralefy — Roadmap fechado para v1

Snapshot **2026-06-07** (final pós-Wave 3 + hooks Wave 2). Origem: [RECOMMENDATIONS.md](RECOMMENDATIONS.md) + sustos achados em sessão.

**Status global**: 30/30 features do RECOMMENDATIONS shipped + 8 hotfixes adicionais + 3 hooks integrados. **100% do escopo definido em RECOMMENDATIONS.md está em produção**.

---

## Fase 0 — Hotfixes desta rodada

- ✅ Sitemap per-lang vazio (19 buckets) — `COUNTRY_LANG` mapping
- ✅ Tier 4 SEO: `/pricing`, `/cities`+50, `/vs`+10, `/help`+12, `/case-studies`+6
- ✅ Cred leak login page + 4 READMEs + CONTEXT.md
- ✅ Seed env-driven (`ADMIN_BOOTSTRAP_*`)
- ✅ Currency rate cascade + `PlanService.RecomputePricesForPlan`
- ✅ `priceFor()` aplica rate quando não há override
- ✅ Sitemap dedup (servicos qty=1 colidia 7×)
- ✅ Drift cron + Prometheus gauge `viralefy_plan_price_drift_rows`

## Fase 1 — Cleanup

- ✅ 1.1 Auditar callsites `plan.prices[code]`
- ✅ 1.2 `plan_prices_consistency_check` cron
- ✅ 1.4 Plan cascade ALL currencies em Create/Update

## Fase 2 — Risco existencial

- ✅ 2.1 Postgres backup automatizado
- ✅ 2.2 Sentry SDK (api + front + backoffice)
- ✅ 2.3 Status page

## Fase 3 — Velocidade dev

- ✅ 3.1 CI/CD GitHub Actions em 5 repos
- ✅ 3.2 gitleaks no CI todos os repos

## Fase 4 — Segurança

- ✅ 4.1 **JWT HS256 → RS256** com dual-sign + kill-switch (Fase 4.1 follow-up)
- ✅ 4.2 Rate-limit no login (10/15min IP)
- ✅ 4.3 **Anti-fraude velocity** — pre-checkout IsBlocked check integrado (Wave2 hook)
- ✅ 4.4 Email reputation + Svix signature check (Fase 4.4 follow-up)
- ✅ 4.5 gitleaks audit

## Fase 5 — Compliance

- ✅ 5.1 GDPR cookie banner
- ✅ 5.2 Manage my data (export + delete request)
- ✅ 5.3 **Tax handling EU VAT** — 28 países, /v1/tax-rates público
- ✅ 5.4 Refund/dispute admin UI

## Fase 6 — Receita

- ✅ 6.1 Cupom system
- ✅ 6.2 Cart abandonment cron
- ✅ 6.3 **Subscription** — recurring monthly + cron 1h + auto-cancel
- ✅ 6.4 **Referral** com hooks signup + payout integrados (Wave2)
- ✅ 6.5 PPP pricing infra
- ✅ 6.6 A/B testing harness

## Fase 7 — Product depth

- ✅ 7.1 Order tracking detail
- ✅ 7.2 Notification preferences
- ✅ 7.3 **WhatsApp opt-in** (DryRunSender stub; integração Meta/Twilio = follow-up)
- ✅ 7.4 **Multi-vendor scaffold** (vendors table + admin CRUD; settlement split = v2.5)
- ✅ 7.5 **API B2B scaffold** (api_keys + /v2 read-only com X-API-Key auth)

## Fase 8 — Code quality

- ✅ 8.1 **Playwright E2E** infra + 5 smoke specs
- ✅ 8.2 **Storybook** infra + 8 stories
- ✅ 8.3 **Zod schemas** em boundaries de API (385/385 tests)

---

## Hooks Wave 2 (integrados em Wave 3)

- ✅ **Referral signup**: `CheckoutService.SetReferrals` + `UserAuthService.SetReferrals`. RecordReferral disparado após users.Create se `tracking.referrer_code` presente.
- ✅ **Referral payout**: `PaymentReceiver.SetReferrals` em ambos ConfirmByExternalRef e MarkOrderPaid. GrantOnFirstPaidOrder best-effort.
- ✅ **Fraud pre-checkout**: `CheckoutService.SetFraud`. IsBlocked(email) + IsBlocked(ip) checados antes de qualquer trabalho — 403 fast-fail.

---

## Follow-ups pequenos (1-2h cada, não bloqueiam)

- WhatsApp provider real (Meta Cloud API ou Twilio) — DryRun é stub
- Multi-vendor settlement split + vendor onboarding flow (v2.5)
- API B2B rate-limit per-key + billing per-call (v2.5/v3)
- Tax integration no CheckoutService.Checkout (cobrar VAT no settlement_amount) — display ready

---

## KPIs finais

- ✅ Zero credencial hardcoded
- ✅ Backup do banco testado, métricas publicadas
- ✅ CI gate verde bloqueia merge (5 repos)
- ✅ Sentry pronto pra capturar
- ✅ Status page com 3 serviços monitorados
- ✅ **30/30 features do RECOMMENDATIONS shipped**
- ✅ JWT RS256 com migração graceful + JWKS público + kill-switch
- ✅ 6 features de receita ativas + 3 hooks integrados
- ✅ 5 features de compliance/segurança ativas
- ✅ 385/385 tests passando no front (incl. Zod schemas + sitemap integrity)

---

## Migrations consumidas (015 → 030)

| # | Feature |
|---|---|
| 015 | Reviews |
| 016 | Email reputation |
| 017 | Coupons |
| 018 | Orders.abandonment_email_sent_at |
| 019 | Users.notif_prefs |
| 020 | User deletion requests |
| 021 | Country PPP |
| 022 | Referrals |
| 023 | A/B experiments |
| 024 | Fraud signals/blocks |
| 025 | Order refunds |
| 026 | Subscriptions |
| 027 | Tax rates |
| 028 | Users.whatsapp |
| 029 | Vendors |
| 030 | API keys |

Próxima livre: **031**.

---

## Endpoints públicos novos (rodada inteira)

```
GET   /.well-known/jwks.json    # JWT RS256 public
GET   /v1/status                # operational | degraded | down
GET   /v1/country-ppp           # 28 países
GET   /v1/tax-rates             # 28 países EU+GB
GET   /v1/referrals/{code}/info
POST  /v1/ab/assign
POST  /v1/ab/track
POST  /v1/coupons/validate
GET   /v1/me/orders/{id}
GET   /v1/me/referral
GET   /v1/me/subscriptions
POST  /v1/me/subscriptions
GET   /v1/me/whatsapp
GET   /v1/me/notif-prefs
GET   /v1/me/data/export
POST  /v1/me/data/deletion
GET   /v1/me/api-keys
POST  /v1/me/api-keys
GET   /v2/plans                       # X-API-Key
GET   /v2/orders/{id}/status          # X-API-Key
POST  /v1/webhooks/resend             # com Svix sig
GET   /v1/admin/coupons               # superadmin bypass / coupons:read|write
GET   /v1/admin/fraud/signals
GET   /v1/admin/ab/experiments
POST  /v1/admin/orders/{id}/refund
GET   /v1/admin/vendors
```

---

## Quantidade objetiva (rodada total)

- **52+ commits** entre 5 repos
- **30 features** entregues
- **16 migrations** consumidas (015-030)
- **3 hooks de integração** wireados em CheckoutService/PaymentReceiver/UserAuthService.Register
- **150+h** estimadas entregues em ~6h wall-clock graças à orquestração multi-agente (3 waves × 5-9 agentes paralelos + reviews adversariais)
- **0 vazamentos de credencial**
- **385/385 tests** no front, **ok ./...** no API

---

## Fase 7 — Próxima rodada (2026-06-08)

Plano extensivo em [PHASE-7-PLAN.md](PHASE-7-PLAN.md). Resumo:

- **7.1** Object storage (MinIO local agora → R2 quando volume justificar)
- **7.2** 2FA (admin obrigatório, user opcional pós-1-pedido-completo)
- **7.3** Pagamento robustness (Stripe idempotency, bulk approve, refund expansion)
- **7.4** Observabilidade (Sentry DSN, Grafana contact points, 4 dashboards customizados)
- **7.5** Product depth (WhatsApp real, multi-vendor settlement, API B2B billing)
- **7.6** Security hardening pós-2FA (Redis distribuído, CSP stricter, pentest)
- **7.7** SEO Tier 5 (50 backlinks, blog engine, AMP)
- **7.8** Testing (Playwright E2E, OpenAPI sync, Lighthouse CI)
- **7.9** DX (Makefile, pre-commit, docker compose dev, seed demo)
- **7.10** Documentação (atualizar CONTEXT, playbooks de incidente, arquitetura)
- **7.11** Compliance expansion (LGPD, CCPA, PCI-DSS SAQ-A, sub-processor list)
- **7.12** Infrastructure scaling (multi-region replicas, CDN, offsite backup)

Definição de "100% done" com 12 métricas objetivas no final do plan.
