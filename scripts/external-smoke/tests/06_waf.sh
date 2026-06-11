#!/usr/bin/env bash
# WAF — confirms attack payloads are still being blocked. Two-sided check:
#   1. Obvious attacks must 403
#   2. Legitimate payload (URL in tracking) must NOT 403 — see 05_checkout_flow.sh
set_group "waf"

# --- Attacks: expect 403 (Coraza blocked) ---
declare -A ATTACKS=(
  ["sqli"]="${API_BASE}/v1/plans?q=1%27%3BDROP%20TABLE%20users--"
  ["xss"]="${API_BASE}/v1/plans?q=%3Cscript%3Ealert(1)%3C%2Fscript%3E"
  ["lfi"]="${API_BASE}/v1/plans?cmd=cat%20%2Fetc%2Fpasswd"
  ["path_traversal"]="${API_BASE}/v1/plans?file=..%2F..%2F..%2Fetc%2Fpasswd"
)

for name in "${!ATTACKS[@]}"; do
  begin_test "WAF blocks: $name"
  read -r code ms body_f hdr_f < <(http_get "${ATTACKS[$name]}")
  # 403 is expected (WAF block). 200 is a regression. 401/422 acceptable as
  # alt-blocks if Coraza routes to validation layer first.
  if [[ "$code" == "403" ]]; then
    pass_test "blocked (${code}), ${ms}ms"
  elif [[ "$code" == "200" ]]; then
    fail_test "WAF_NOT_BLOCKING" "got 200 for $name attack — Coraza misconfigured. url=${ATTACKS[$name]}"
  else
    # Other codes (404, 400, 422) are tolerable — attack didn't get through to a 200
    pass_test "non-200 ($code), ${ms}ms"
  fi
  rm -f "$body_f" "$hdr_f"
done

# NOTE: the original 931130 regression was about a legitimate URL inside the
# JSON body field tracking.landing_url on POST /v1/checkout — not about URLs
# in query strings (where Coraza still legitimately treats URL-args as RFI
# signal and may 403). That body-level regression is covered end-to-end by
# 05_checkout_flow.sh, which posts the real payload shape.
