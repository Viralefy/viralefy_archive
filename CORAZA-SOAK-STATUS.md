# Coraza WAF Soak Status

**Last audit**: 2026-06-10 07:40 UTC
**Engine**: `SecRuleEngine DetectionOnly` (UNCHANGED — no flip)
**Decision**: **NO FLIP** — continue soak. Concrete blocker identified.

---

## Re-audit results (24h window ending 2026-06-10 07:30 UTC)

### Traffic baseline (real prod)
- **Total requests**: 16,474 (from journalctl `caddy.service`).
- **Unique remote IPs**: 2,274 (genuine external traffic — top: 177.148.143.130, 177.148.140.40, 95.47.138.133, Googlebot 66.249.68.x, etc.).
- **Unique URIs hit**: 4,234.
- **Status distribution**: 13851x 200, 1250x 404, 649x 429 (rate limit), 179x 401, 148x 502.
- **Organic registrations**: 13 POST `/v1/auth/user/register`.

### Audit log
- File: `/var/log/caddy-waf/audit.log` — 219 KB, 166 transactions logged (born 2026-06-10 01:21 UTC).
- `SecAuditEngine On` + `SecAuditLogRelevantStatus ".*"` (every txn). Sampling rate vs total traffic ~1% — audit log only persists a subset of transactions, but the **error log inside journalctl** is the canonical source for rule matches.

### Coraza rule matches (journalctl, 24h)
- **Total warnings**: 27 events.
- **All 27 from a single source IP**: `62.238.41.231` (the prod box itself = operator smoke tests).
- **No external IP tripped any rule.**
- **Rule ID breakdown**:
  - 6x 980170 (anomaly score correlation) — reporting only
  - 6x 949110 (anomaly score exceeded) — reporting only
  - 3x 942100 (libinjection SQLi) — see FP analysis below
  - 3x 941100, 3x 941110, 3x 941160, 3x 941390 — XSS, all from `?q=<script>...`
- **URI breakdown**:
  - 18x `/v1/plans?q=%3Cscript%3Ealert(1)%3C/script%3E` — operator XSS probe
  - 6x `/v1/plans?q=1+OR+1=1--` — operator SQLi probe
  - **3x `/v1/auth/user/register` — REAL FP RISK**

---

## False-positive analysis — the blocker

### The single non-probe detection
```
rule 942100 SQL Injection Attack Detected via libinjection
data: "Matched Data: novc found within ARGS:json.password: HotSetTest123!@#"
uri: /v1/auth/user/register
anomaly score: 5/5 (== blocking threshold)
```

**Why this matters**:
1. The payload (`HotSetTest123!@#`) is a perfectly normal generator-style strong password.
2. Libinjection fingerprinted the symbol pattern as SQLi (`novc` is its internal token, not a substring).
3. Score landed exactly at the blocking threshold (5). One match → block under `SecRuleEngine On`.
4. **Any user signing up with a 1Password/Bitwarden-style password (mixed case + digits + 2+ symbols) is at risk.**
5. The WAF cannot meaningfully protect a password field — values are bcrypt-hashed; they never appear in SQL as identifiers.

### Why the source IP being the host doesn't make this safe
The matching pattern is real — a real user is statistically likely to trigger it within hours of going live, especially since password manager defaults produce exactly this entropy class.

---

## Attempted mitigation (rolled back)

Tried to pre-stage exclusion rule `900600` targeting `ARGS:json.password` for `/v1/auth/(user/)?(register|login)` with `ctl:ruleRemoveTargetById=942100;ARGS:json.password,...`.

- `caddy validate` passed.
- `systemctl reload caddy` succeeded.
- **Result**: identical re-test (`HotSetTest123!@#` POST to `/v1/auth/user/register`) STILL tripped 942100 with score 5. Exclusion did not take effect.
- Likely cause: `ctl` actions in phase 1 evaluate before the JSON request body is parsed (phase 2), so the `ARGS:json.password` target isn't materialized yet when removal is requested. Needs `phase:2` or a different exclusion mechanism (e.g., transformation-stage `ctl:ruleEngine=Off` on `REQUEST_BODY` for this URI, or a custom rule that early-passes the password field before CRS evaluates).
- **Rolled back to original exclusions file**. Backup retained at `/etc/caddy/coraza/coraza-crs-exclusions.conf.bak.1781077132`.

---

## Decision: NO FLIP — continue soak

### Why
- **One unsolved organic FP risk** with a non-trivial mitigation path.
- Pre-staged exclusion attempt FAILED — not a known-good rollback target.
- Flipping `On` today would, with high confidence, block real registrations within hours.

### What needs to happen before flipping
1. **Fix the password exclusion**. Options to investigate:
   - Move `ctl` to phase 2: `phase:2, ctl:ruleRemoveTargetById=942100;ARGS:json.password`.
   - Or: per-URI `ctl:ruleEngine=Off` only for `REQUEST_BODY` evaluation on auth endpoints (analogous to the Stripe webhook block — id 900201 — which already works).
   - Or: bump CRS `tx.blocking_inbound_anomaly_score` threshold from 5 to 10 for paranoia-level 1 + add custom narrow rules for paths that don't accept passwords. (Heavier handed; not preferred.)
2. **Re-test fix**: confirm 0 warnings for symbol-rich passwords on `/v1/auth/*` endpoints.
3. **Soak 24-48h** post-fix to ensure no new FP categories emerge from real traffic patterns we haven't tested (review submissions, admin operations, search when shipped).
4. **Flip**.

### Rollback round-trip verified
- `cp coraza.conf.bak.* coraza.conf && systemctl reload caddy` → smoke pass — confirmed today via the failed exclusion test.
- Reload time: <2s.
- Total rollback window: <10s.

---

## Next steps & timeline

| Step | Owner | ETA |
|------|-------|-----|
| Fix `ARGS:json.password` exclusion (phase 2 or scoped ruleEngine=Off) | ops | 2026-06-10 → 2026-06-11 |
| Verify fix via repeated registration smoke (5+ symbol-rich passwords) | ops | 2026-06-11 |
| Soak in DetectionOnly with fix in place | ops | 2026-06-11 → 2026-06-13 |
| Re-audit and flip | ops | target 2026-06-13 |

Soak target advanced from the original "14 days" (2026-06-24) to **2026-06-13** because traffic coverage is already strong (16k req / 2.2k IPs / 4.2k URIs in 24h). The only gate is fixing the one identified FP.

---

## Files & references
- `/etc/caddy/coraza/coraza.conf` — main config (engine state).
- `/etc/caddy/coraza/coraza-crs-exclusions.conf` — pre-staged exclusions.
- `/etc/caddy/coraza/coraza-crs-exclusions.conf.bak.1781077132` — pre-attempt backup.
- `/etc/caddy/coraza/crs/rules/REQUEST-942-APPLICATION-ATTACK-SQLI.conf` — rule 942100 source.
- `/var/log/caddy-waf/audit.log` — JSON audit (every transaction since 01:21 UTC).
- `journalctl -u caddy` — canonical rule-match log (level=error, logger=http.handlers.waf).

## Query templates
```bash
# All Coraza warnings last 24h:
journalctl -u caddy --since "24 hours ago" -o cat | grep -iE "coraza.*warning"

# Rule ID frequency:
journalctl -u caddy --since "24 hours ago" -o cat | grep -iE "coraza.*warning" \
  | grep -oE 'id \\"[0-9]+\\"' | sort | uniq -c | sort -rn

# Source IPs:
journalctl -u caddy --since "24 hours ago" -o cat | grep -iE "coraza.*warning" \
  | grep -oE 'client \\"[0-9.]+\\"' | sort | uniq -c | sort -rn
```
