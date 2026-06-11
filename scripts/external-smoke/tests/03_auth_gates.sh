#!/usr/bin/env bash
# Auth gates — protected endpoints must 401 without Bearer.
set_group "auth_gates"

PROTECTED=(
  "/v1/me/orders"
  "/v1/me/2fa/status"
  "/v1/admin/me"
  "/v1/admin/orders"
)

for path in "${PROTECTED[@]}"; do
  begin_test "GET $path (no auth)"
  read -r code ms body_f hdr_f < <(http_get "${API_BASE}${path}")
  if assert_status "$code" "401" "$path"; then
    # Must return JSON error envelope (not HTML).
    if jq -e '.error.code' "$body_f" >/dev/null 2>&1; then
      pass_test "${ms}ms"
    else
      fail_test "401_not_json_envelope" "$(head -c 200 "$body_f")"
    fi
  fi
  rm -f "$body_f" "$hdr_f"
done
