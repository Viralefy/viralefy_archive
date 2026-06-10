#!/usr/bin/env python3
"""
Bucket 3 smoke E2E — /v1/admin/* via SQL-minted RS256 token (no TOTP).

Environment constraints:
 - Coraza WAF (OWASP CRS 4.x) blocks methods outside the default set
   (GET/HEAD/POST/OPTIONS) at the edge with HTTP 403, rule 911100.
   PUT/PATCH/DELETE never reach core. We exercise mutations via POST.
 - tower_governor in dispatcher: 1 req/s sustained, burst 30, per-IP.
   We pace bursts with sleeps and inject a small delay between rounds
   to avoid 429 noise contaminating RBAC validation.
 - viralefy-api (legacy) is `inactive (dead)` — only viralefy-core (:8084)
   and viralefy-dispatcher (:8090) listen. So any audit_log entry
   written *after* a /v1/admin/* POST proves core wrote it.
"""

import datetime
import json
import os
import subprocess
import time
import uuid
import urllib.request
import urllib.error
import ssl

import jwt

KEY_PATH = "/etc/viralefy/jwt-rs256.pem"
KID = "vfCOltLYjII"
ADMIN_EMAIL = "viralefy@gmail.com"
ADMIN_ID = "94931e5f-9bf1-4fd8-9d1d-b8559a728b9a"
BASE = "https://api.viralefy.com"

with open(KEY_PATH, "rb") as f:
    KEY = f.read()


def mint(role: str, *, ttl_seconds: int = 900) -> tuple[str, str]:
    now = datetime.datetime.now(datetime.timezone.utc)
    jti = str(uuid.uuid4())
    claims = {
        "sub": ADMIN_ID,
        "typ": "admin",
        "role": role,
        "email": ADMIN_EMAIL,
        "iat": int(now.timestamp()),
        "exp": int((now + datetime.timedelta(seconds=ttl_seconds)).timestamp()),
        "jti": jti,
    }
    return jwt.encode(claims, KEY, algorithm="RS256", headers={"kid": KID}), jti


def http(method: str, path: str, token: str, body: bytes | None = None, ua: str = "smoke-admin/1") -> int:
    req = urllib.request.Request(BASE + path, method=method, data=body)
    req.add_header("Authorization", f"Bearer {token}")
    req.add_header("User-Agent", ua)
    if body is not None:
        req.add_header("Content-Type", "application/json")
    ctx = ssl.create_default_context()
    try:
        with urllib.request.urlopen(req, context=ctx, timeout=10) as resp:
            return resp.status
    except urllib.error.HTTPError as e:
        return e.code
    except Exception:
        return -1


def psql(sql: str) -> str:
    env = os.environ.copy()
    env["PGPASSWORD"] = "dVIG47Qj0cpdZewr0sK97bNyeH8CWtVl"
    cp = subprocess.run(
        ["psql", "-h", "localhost", "-U", "viralefy", "-d", "viralefy", "-Atc", sql],
        env=env, capture_output=True, text=True, timeout=10,
    )
    return cp.stdout.strip()


def truncate(s: str) -> str:
    if len(s) < 24:
        return "<short>"
    return f"{s[:10]}...{s[-10:]}"


report = {"started_at": datetime.datetime.now(datetime.timezone.utc).isoformat()}

# Step 1+2: mint superadmin, hit 27 read endpoints
super_tok, super_jti = mint("superadmin")
report["superadmin_token_fingerprint"] = truncate(super_tok)
report["superadmin_jti"] = super_jti

endpoints = [
    ("GET", "/v1/admin/me"),
    ("GET", "/v1/admin/roles"),
    ("GET", "/v1/admin/admins"),
    ("GET", "/v1/admin/plans"),
    ("GET", "/v1/admin/gateways"),
    ("GET", "/v1/admin/orders"),
    ("GET", "/v1/admin/metrics/summary"),
    ("GET", "/v1/admin/currencies"),
    ("GET", "/v1/admin/tickets"),
    ("GET", "/v1/admin/invoices"),
    ("GET", "/v1/admin/reviews"),
    ("GET", "/v1/admin/coupons"),
    ("GET", "/v1/admin/fraud/signals"),
    ("GET", "/v1/admin/ab/experiments"),
    ("GET", "/v1/admin/vendors"),
    ("GET", "/v1/admin/users"),
    ("GET", "/v1/admin/proofs/pending"),
    ("GET", "/v1/admin/orders?limit=1"),
    ("GET", "/v1/admin/orders?status=paid"),
    ("GET", "/v1/admin/users?limit=1"),
    ("GET", "/v1/admin/plans?limit=1"),
    ("GET", "/v1/admin/tickets?status=open"),
    ("GET", "/v1/admin/invoices?limit=1"),
    ("GET", "/v1/admin/reviews?limit=1"),
    ("GET", "/v1/admin/coupons?limit=1"),
    ("GET", "/v1/admin/gateways?limit=1"),
    ("GET", "/v1/admin/currencies?limit=1"),
]

smoke = []
for i, (method, path) in enumerate(endpoints):
    code = http(method, path, super_tok)
    smoke.append({"method": method, "path": path, "status": code})
    if i % 20 == 19:
        # cooldown to avoid governor burst exhaustion
        time.sleep(5)

report["smoke"] = smoke
report["smoke_count"] = len(smoke)
report["smoke_2xx"] = sum(1 for r in smoke if 200 <= r["status"] < 300)

# Step 3: RBAC — viewer reads ok, POST writes 403
# Cool down so rate limiter has full burst available
time.sleep(8)

viewer_tok, _ = mint("viewer")
report["viewer_token_fingerprint"] = truncate(viewer_tok)

viewer_reads = [
    ("GET", "/v1/admin/me", 200),
    ("GET", "/v1/admin/plans", 200),
    ("GET", "/v1/admin/orders", 200),
    ("GET", "/v1/admin/reviews", 200),
]
# Use only POST endpoints; PUT/DELETE/PATCH are blocked by WAF (403 != RBAC).
viewer_writes_expected_403 = [
    ("POST", "/v1/admin/admins", b'{"email":"x@x.com","name":"x","password":"xxxxxxxxxx","role":"viewer"}'),
    ("POST", "/v1/admin/plans", b'{"name":"x","price_cents":100,"currency_code":"BRL","quantity":1}'),
    ("POST", "/v1/admin/coupons", b'{"code":"X","discount_pct":10}'),
    ("POST", "/v1/admin/vendors", b'{"name":"x","slug":"x"}'),
    ("POST", "/v1/admin/ab/experiments", b'{"key":"x","variants":["a","b"]}'),
]

rbac = {"viewer_reads": [], "viewer_writes": []}
for method, path, expected in viewer_reads:
    code = http(method, path, viewer_tok)
    rbac["viewer_reads"].append({"method": method, "path": path, "status": code, "expected": expected, "ok": code == expected})
    time.sleep(0.4)

for method, path, body in viewer_writes_expected_403:
    # Each request paced to stay under 1/s sustained
    time.sleep(1.2)
    code = http(method, path, viewer_tok, body)
    rbac["viewer_writes"].append({"method": method, "path": path, "status": code, "expected": 403, "ok": code == 403})

report["rbac"] = rbac
report["rbac_writes_all_403"] = all(r["ok"] for r in rbac["viewer_writes"])

# Step 4: hot-set revocation
time.sleep(5)
rev_tok, rev_jti = mint("superadmin")

pre = http("GET", "/v1/admin/me", rev_tok)
t_insert = time.monotonic()
psql(f"INSERT INTO revoked_jtis (jti, expires_at) VALUES ('{rev_jti}', NOW() + INTERVAL '1 hour') ON CONFLICT DO NOTHING;")
psql(f"SELECT pg_notify('revoked_jtis_inserted', '{rev_jti}');")
time.sleep(1.5)
post = http("GET", "/v1/admin/me", rev_tok)
t_post = time.monotonic()

report["hotset"] = {
    "jti": rev_jti,
    "pre_status": pre,
    "post_status": post,
    "elapsed_seconds_revoke_to_observed": round(t_post - t_insert, 3),
    "revoked_ok": pre == 200 and post == 401,
}

psql(f"DELETE FROM revoked_jtis WHERE jti = '{rev_jti}';")

# Step 5: audit_log. Use POST /v1/admin/admins (PermAdminsManage) with a
# fingerprinted email; then assert the row appears in audit_log.
time.sleep(3)

audit_ua = f"smoke-admin-audit/{uuid.uuid4()}"
unique_email = f"smoke-{int(time.time())}-{uuid.uuid4().hex[:8]}@viralefy.local"
mut_body = json.dumps({
    "email": unique_email,
    "name": "Smoke Admin",
    "password": "Tx9$cT!a93kpL2qx",
    "role": "viewer",
}).encode()

# Snapshot last audit_log id to detect new rows reliably
before_last = psql(
    f"SELECT COALESCE(MAX(created_at)::text, '1970-01-01') FROM audit_log WHERE actor_id = '{ADMIN_ID}';"
)

mut_status = http("POST", "/v1/admin/admins", super_tok, mut_body, ua=audit_ua)

# Wait briefly for goroutine to land
time.sleep(0.7)

# Pull rows newer than the snapshot
audit_rows = psql(
    f"SELECT id || '|' || action || '|' || target_type || '|' || COALESCE(metadata::text, 'null') "
    f"FROM audit_log "
    f"WHERE actor_id = '{ADMIN_ID}' AND created_at > '{before_last}'::timestamptz "
    f"ORDER BY created_at DESC LIMIT 5;"
)

parsed = []
for line in audit_rows.splitlines():
    parts = line.split("|", 3)
    if len(parts) == 4:
        parsed.append({"id": parts[0], "action": parts[1], "target_type": parts[2], "metadata": parts[3]})

# Cleanup the created admin
created_id_rows = psql(
    f"SELECT id FROM admins WHERE email = '{unique_email}';"
)
for cid in created_id_rows.splitlines():
    if cid:
        psql(f"DELETE FROM admins WHERE id = '{cid}';")

# A new row attributable to core: it must contain our unique UA and the
# /v1/admin/admins path. Since legacy api is inactive, this row was
# written by viralefy-core (port 8084), routed by dispatcher (port 8090).
core_match = False
core_entry = None
for e in parsed:
    md = e["metadata"]
    if audit_ua in md and "/v1/admin/admins" in md:
        core_match = True
        core_entry = e
        break

report["audit"] = {
    "mutation_status": mut_status,
    "unique_ua": audit_ua,
    "unique_email": unique_email,
    "new_entries_after_mutation": parsed,
    "core_match": core_match,
    "core_entry": core_entry,
    "note": (
        "legacy viralefy-api is `inactive (dead)`; only viralefy-core listens on :8084. "
        "Therefore any new audit_log row with our unique UA + path is written by core."
    ),
}

print(json.dumps(report, indent=2, default=str))
with open("/tmp/smoke_admin_report.json", "w") as f:
    json.dump(report, f, indent=2, default=str)
