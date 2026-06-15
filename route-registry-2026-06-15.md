# Viralefy Route Registry — 2026-06-15

- Total de rotas no inventário: **142**
- Source: `viralefy_core/internal/interface/http/router.go` + Caddyfile + dispatcher proxy.rs
- Geração: cruzamento automático router.go → routes-inventory.json + validação manual via diff (zero ghost, zero dead)

## Coluna de personas

- `anon`: sem Authorization, sem X-API-Key
- `user`: JWT user-kind válido (RS256, dual-sign auth+core)
- `admin`: JWT admin-kind com role=admin (RBAC perms)
- `superadmin`: JWT admin-kind com role=superadmin
- `b2b_key`: X-API-Key emitido via /v1/me/api-keys
- `bad_jwt`: token sintaticamente válido + assinatura inválida

## Categorias × acesso esperado

| categoria | quem PODE | quem NÃO PODE (espera 401/403) |
|---|---|---|
| health | todos | (n/a) |
| public | todos | (n/a) |
| webhook | provider via signature | (anyone w/ assinatura inválida → 400/401) |
| authenticated | user (próprio escopo) | anon, bad_jwt, b2b_key, admin sem cross-fluxo |
| admin | admin/superadmin com perm | anon, user, b2b_key, bad_jwt |
| b2b | b2b_key (X-API-Key) | anon, user, admin, bad_jwt |
| internal | loopback X-Internal-Token (defesa profunda — Caddy retorna 404) | mundo externo |

## Inventário (método · path · service · categoria · auth-required · personas-permitidas)

| Método | Path | Service | Categoria | Auth | Personas |
|---|---|---|---|---|---|
| GET | `/health` | all services | health | não | anon,user,admin,superadmin,b2b_key |
| GET | `/ready` | all services | health | não | anon,user,admin,superadmin,b2b_key |
| GET | `/metrics` | all services | health | não | anon,user,admin,superadmin,b2b_key |
| GET | `/.well-known/jwks.json` | viralefy_auth (8083, direct Caddy) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/plans` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/plans/00000000-0000-0000-0000-000000000000/reviews` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/plans/00000000-0000-0000-0000-000000000000/payment-methods` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/categories` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/categories/instagram/reviews` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/currencies` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/status` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/country-ppp` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/referrals/SIMTEST/info` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/tax-rates` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/coupons/validate` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/ab/assign` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/ab/track` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/track` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/me/consent` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/checkout` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/recovery-request` | viralefy_core (8084, via dispatcher 8090) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/webhooks/woovi` | viralefy_payments (8081, via Caddy) | webhook | não | anon (signature only) |
| POST | `/v1/webhooks/heleket` | viralefy_payments (8081, via Caddy) | webhook | não | anon (signature only) |
| POST | `/v1/webhooks/stripe` | viralefy_payments (8081, via Caddy) | webhook | não | anon (signature only) |
| POST | `/v1/webhooks/resend` | viralefy_payments (8081, via Caddy) | webhook | não | anon (signature only) |
| POST | `/v1/auth/login` | viralefy_auth or viralefy_core (dual via dispatcher) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/auth/login/2fa/enroll` | viralefy_auth or viralefy_core (dual via dispatcher) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/auth/login/2fa` | viralefy_auth or viralefy_core (dual via dispatcher) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/auth/user/register` | viralefy_auth or viralefy_core (dual via dispatcher) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/auth/user/login` | viralefy_auth or viralefy_core (dual via dispatcher) | public | não | anon,user,admin,superadmin,b2b_key |
| POST | `/v1/auth/user/login/2fa` | viralefy_auth or viralefy_core (dual via dispatcher) | public | não | anon,user,admin,superadmin,b2b_key |
| GET | `/v1/me/orders` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/orders/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/orders/00000000-0000-0000-0000-000000000000/proof` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/orders/00000000-0000-0000-0000-000000000000/proof-url` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/referral` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/journey` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/2fa/status` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/2fa/enroll` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/2fa/verify` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/2fa/disable` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/2fa/dismiss-prompt` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/subscriptions` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/subscriptions` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| DELETE | `/v1/me/subscriptions/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/whatsapp` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| PUT | `/v1/me/whatsapp` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/api-keys` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/api-keys` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| DELETE | `/v1/me/api-keys/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/notif-prefs` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| PUT | `/v1/me/notif-prefs` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/data/export` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/data/deletion` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/data/deletion` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| DELETE | `/v1/me/data/deletion` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/profiles` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/profiles` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| DELETE | `/v1/me/profiles/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/credits` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/transactions` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/recharge` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/invoices` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/tickets` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/tickets/open-count` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/tickets` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/tickets/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/tickets/00000000-0000-0000-0000-000000000000/messages` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| POST | `/v1/me/reviews` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/me/reviews/by-order/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | authenticated | sim | user (own data via JWT) |
| GET | `/v1/admin/me` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| POST | `/v1/admin/me/become-customer` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| POST | `/v1/admin/me/2fa/disable` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v1/admin/roles` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v1/admin/admins` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/admins` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| PUT | `/v1/admin/admins/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| DELETE | `/v1/admin/admins/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v1/admin/plans` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| POST | `/v1/admin/plans` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| PUT | `/v1/admin/plans/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| DELETE | `/v1/admin/plans/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/gateways` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| POST | `/v1/admin/gateways` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| PUT | `/v1/admin/gateways/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| DELETE | `/v1/admin/gateways/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/orders` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/orders/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| PATCH | `/v1/admin/orders/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/orders/00000000-0000-0000-0000-000000000000/capture-metrics` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v1/admin/metrics/summary` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/currencies` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| PUT | `/v1/admin/currencies/BRL` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/tickets` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/tickets/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| POST | `/v1/admin/tickets/00000000-0000-0000-0000-000000000000/messages` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| PATCH | `/v1/admin/tickets/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/invoices` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/invoices/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| POST | `/v1/admin/invoices/00000000-0000-0000-0000-000000000000/mark-paid` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v1/admin/reviews` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| PATCH | `/v1/admin/reviews/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/coupons` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| POST | `/v1/admin/coupons` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| PUT | `/v1/admin/coupons/SIMTEST` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/fraud/signals` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/ab/experiments` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/ab/experiments` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| PUT | `/v1/admin/ab/experiments/simtest-exp` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/orders/00000000-0000-0000-0000-000000000000/refund` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v1/admin/orders/00000000-0000-0000-0000-000000000000/refunds` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/vendors` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/vendors` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| PUT | `/v1/admin/vendors/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v1/admin/users` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/users/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| POST | `/v1/admin/users/00000000-0000-0000-0000-000000000000/credits/adjust` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/orders/00000000-0000-0000-0000-000000000000/mark-paid` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/orders/00000000-0000-0000-0000-000000000000/proof/decision` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v1/admin/proofs/pending` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| POST | `/v1/admin/proofs/bulk-decision` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v1/admin/orders/00000000-0000-0000-0000-000000000000/proof-url` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| DELETE | `/v1/admin/orders/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| DELETE | `/v1/admin/orders/00000000-0000-0000-0000-000000000000/hard` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/orders/00000000-0000-0000-0000-000000000000/restore` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/orders/bulk/soft-delete` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| DELETE | `/v1/admin/invoices/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| DELETE | `/v1/admin/invoices/00000000-0000-0000-0000-000000000000/hard` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/invoices/00000000-0000-0000-0000-000000000000/restore` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/invoices/bulk/soft-delete` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| DELETE | `/v1/admin/users/00000000-0000-0000-0000-000000000000` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| DELETE | `/v1/admin/users/00000000-0000-0000-0000-000000000000/hard` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/users/00000000-0000-0000-0000-000000000000/restore` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| POST | `/v1/admin/users/bulk/soft-delete` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/users/00000000-0000-0000-0000-000000000000/journey` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/visitors` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/visitors/sim-visitor-id` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=admin) |
| GET | `/v1/admin/trash` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v1/admin/honeypot` | viralefy_core (8084, via dispatcher 8090) | admin | sim | admin or superadmin (RBAC perms) (role=superadmin) |
| GET | `/v2/plans` | viralefy_core (8084) | b2b | sim | b2b_key (X-API-Key) |
| GET | `/v2/orders/00000000-0000-0000-0000-000000000000/status` | viralefy_core (8084) | b2b | sim | b2b_key (X-API-Key) |
| POST | `/internal/v1/payment-confirmed` | viralefy_core (8084, loopback only) | internal | sim | loopback only (X-Internal-Token) |

## Reconciliação contra implementação

- **Rotas fantasma** (no Caddy/Dispatcher mas sem handler): nenhuma
- **Rotas mortas** (handler existe mas sem rota no Caddy): nenhuma — todas as rotas de :8084 chegam via dispatcher :8090 (fallback default)
- **Endpoints loopback-only** (NÃO expostos via Caddy):
  - `/internal/v1/*` → Caddy retorna 404 explícito (defense-in-depth)
  - `/metrics` → bind loopback nos services + Caddy /api/metrics rebatido em 404 no backoffice
  - viralefy_auth (8083), viralefy_payments (8081), viralefy_sender (8082) — todos só em 127.0.0.1

## Bug encontrado pelo simulated (registrar como achado Track GG)

- `GET /v1/plans/{id}/payment-methods` retorna **500 INTERNAL_ERROR** para UUID inexistente (qualquer persona).
- Esperado: **404** (plano não encontrado).
- Repro loopback e WAN — bug em viralefy_core. Severidade **Medium** (não é vazamento nem auth bypass, mas é violação direta do §22.8 "nunca 500 por input legítimo").
