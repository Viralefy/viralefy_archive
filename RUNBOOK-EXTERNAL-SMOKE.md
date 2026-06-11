# RUNBOOK — External Smoke (prod regression detector)

**Owner:** ops • **Last updated:** 2026-06-11 • **Schedule:** every 15 min, 24/7

## Why this exists

On 2026-06-10 the Coraza WAF (rule 931130, "Possible RFI") blocked legitimate
checkout submissions because users' `tracking.landing_url` field contained a
`https://www.viralefy.com/...` URL. The internal `viralefy-smoke` only tested
trivial payloads — no real `tracking` block — so the regression reached prod
and was discovered by a user reporting "erro de rede".

This routine runs the **real** checkout payload (Heleket gateway, USDT,
`tracking.{landing_url,referrer,utm_source,fbclid,gclid}`) from an
**external** runner (GitHub-hosted ubuntu-latest, not viralefy infra) and
fails CI red within 15 min if that flow breaks again.

## Where it lives

| File | Purpose |
|---|---|
| `.github/workflows/external-smoke.yml` | GH Actions workflow (cron `*/15 * * * *`) |
| `scripts/external-smoke/run.sh` | Orchestrator |
| `scripts/external-smoke/lib.sh` | Curl wrappers, assertions, result aggregator |
| `scripts/external-smoke/tests/*.sh` | One file per test group (8 total) |

## Test coverage (36 assertions across 8 groups)

1. **frontend_pages** — `/`, `/pricing`, `/login`, `/register`, `/us/instagram-followers`, `admin/`, `admin/login` (200 + `text/html`)
2. **api_public** — `/v1/{plans,categories,currencies,country-ppp,tax-rates}`, `/v1/status`, `/.well-known/jwks.json` (200 + array non-empty / JWK validation)
3. **auth_gates** — `/v1/me/orders`, `/v1/me/2fa/status`, `/v1/admin/me`, `/v1/admin/orders` (401 no-auth + JSON envelope)
4. **cors** — `OPTIONS` on `/v1/auth/user/login`, `/v1/me/orders`, `/v1/checkout` (204 + ACAO matches origin)
5. **checkout_flow** — real `POST /v1/checkout` with Heleket gateway + full `tracking` block → 201 with `order_id` + `payment_url`. **This is the regression test for 2026-06-10.**
6. **waf** — SQLi / XSS / LFI / path-traversal must 403
7. **login** — invalid creds → 401 (not 422); register w/ tracking → 201/409/422 (not 403)
8. **tls_headers** — HSTS preload, X-Content-Type-Options, no `Server: Caddy` leak, TLS cert ≥ 14d to expiry

Runtime: ~1m45s per execution. Budget: 5 min workflow timeout.

## When it fails — triage tree

Open the failed run in [GitHub Actions](https://github.com/Viralefy/viralefy_archive/actions/workflows/external-smoke.yml) → "Run external smoke" step shows colored test-by-test output. Step Summary shows a markdown table of failures with `group`, `test`, `reason`, `detail`. The `external-smoke-failures.json` artifact has full structured data (90d retention).

| Failure reason | Likely cause | First action |
|---|---|---|
| `checkout_flow/WAF_FALSE_POSITIVE` | Coraza rule re-blocking legitimate `tracking.*` field | SSH prod, `tail /var/log/caddy/coraza-audit.log`, grep `trace_id` from failure detail. Check OWASP CRS exclusions in `/etc/caddy/coraza/*.conf` |
| `waf/WAF_NOT_BLOCKING` | OWASP CRS disabled or misconfigured — security regression | `systemctl status caddy`, verify `coraza_waf` directive present, check rule load |
| `frontend_pages/status_mismatch` (5xx) | Next.js front crashed or build broken | Check `systemctl status viralefy-front`, journal last 200 lines |
| `auth_gates/status_mismatch` (200 instead of 401) | RBAC middleware removed/bypassed — **incident SEV2** | Page on-call immediately, check `viralefy-core` middleware chain |
| `api_public/json_not_array_or_empty` | DB seed missing, migration ran but rollback partial | Check `psql ... 'SELECT count(*) FROM plans WHERE active'` |
| `cors/bad_acao` | Coraza/Caddy CORS config drift, ACAO header missing | Diff `/etc/caddy/Caddyfile` against `viralefy_ops/etc/caddy/Caddyfile` |
| `tls_headers/tls_cert_expiring` | ACME renewal failed | `journalctl -u caddy --since "24h ago" | grep -i acme` |
| `tls_headers/server_header_leaked` | Caddy config lost the `-Server` directive | Restore from ops repo |
| `latency_over_budget` (WARN only) | Backend slow — not a hard fail. Investigate if persistent across runs |
| `api_public/bad_overall` (`overall=down`) | `/v1/status` says system down — see `services[]` in body for which component |

## Test users / cleanup

Each `05_checkout_flow.sh` execution creates one user + one **unpaid** order:

- Email pattern: `ext-smoke-gh-<run_id>-<attempt>@viralefy.test`
- Domain `viralefy.test` is RFC 6761 reserved — guaranteed to never collide with real users.
- Orders never reach paid status (we don't pay the Heleket invoice), so they expire naturally.

**Cleanup options (pick one — TBD):**

1. **(recommended)** Add invariant to `viralefy-reconcile` cron (in `viralefy_core/cron/reconcile.rs`):
   ```rust
   // Delete unpaid orders + their users where email ends in @viralefy.test
   // and created_at < now() - interval '24h'
   ```
   Pros: zero new endpoint, runs alongside existing reconcile.
   Cons: couples reconcile with smoke concerns.

2. **Internal endpoint** `POST /internal/v1/test-cleanup` gated by `X-Internal-Token`, run as a separate scheduled GH Actions workflow once per day. Token stored as GH Actions secret `INTERNAL_TEST_TOKEN`, matched against `${INTERNAL_TEST_TOKEN}` env on the core service. Pros: explicit. Cons: another secret + endpoint surface.

3. **Manual psql** weekly: `DELETE FROM orders WHERE email LIKE 'ext-smoke-%@viralefy.test' AND status != 'paid' AND created_at < now() - interval '7 days'; DELETE FROM users WHERE email LIKE '%@viralefy.test' AND created_at < now() - interval '7 days';`. Lowest effort, manual.

Current decision: **option 1** — to be implemented as follow-up in `viralefy_core`. Until then, ~96 test orders/day will accumulate. Run manual cleanup (option 3) weekly until automated.

## Secrets / configuration

Optional GH Actions secret:

- `ADMIN_WEBHOOK_URL` — if set, failures POST a JSON body `{event:"external_smoke_fail", run_id, total, failures, items[]}` to this URL. Useful for Slack/Telegram webhooks. To add: `gh secret set ADMIN_WEBHOOK_URL --body 'https://...' --repo Viralefy/viralefy_archive`. Without it, failures only surface via the red CI badge / GH Actions email.

## Local execution

```bash
cd viralefy_archive
RUN_ID=local-$(date +%s) ./scripts/external-smoke/run.sh
# Prints colored output; writes /tmp/external-smoke-{results.jsonl,failures.json,summary.md}
```

Override endpoints (e.g. point at staging):

```bash
API_BASE=https://api-staging.viralefy.com ./scripts/external-smoke/run.sh
```

## What this routine does NOT cover

- Authenticated user flows (orders/profiles/2FA) — would need a stable test account + 2FA bypass
- Payment webhook delivery (Heleket → core) — needs sandbox + idempotency assertions
- Email delivery (`viralefy_sender`) — needs receiving inbox
- Backoffice mutations — covered by internal `smoke_admin.py` (SQL-minted token, runs on prod machine)
- Performance budget (just warns) — see SLO-DEFINITIONS.md for real perf SLOs

## Related docs

- `RUNBOOK-SMOKE-ADMIN.md` — internal admin smoke (runs on prod machine, SQL-minted token)
- `CORAZA-SOAK-STATUS.md` — WAF FP history (Coraza 931130 was *not* in the soak list; this routine closes that gap)
- `SLO-DEFINITIONS.md` — error budget context for latency warnings
- `RUNBOOK-INCIDENT-RESPONSE.md` — incident severity classification when smoke fails
