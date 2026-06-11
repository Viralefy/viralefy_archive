#!/usr/bin/env bash
# CORS preflight — 204 + ACAO header matching the requesting origin.
set_group "cors"

ORIGIN="https://www.viralefy.com"
PATHS=(
  "/v1/auth/user/login"
  "/v1/me/orders"
  "/v1/checkout"
)

for path in "${PATHS[@]}"; do
  begin_test "OPTIONS $path (Origin: $ORIGIN)"
  read -r code ms body_f hdr_f < <(http_options "${API_BASE}${path}" \
      -H "Origin: $ORIGIN" \
      -H "Access-Control-Request-Method: POST" \
      -H "Access-Control-Request-Headers: content-type,authorization,idempotency-key")
  if assert_status_in "$code" "204" "200"; then
    acao=$(grep -i '^access-control-allow-origin:' "$hdr_f" | head -1 | tr -d '\r' | sed 's/[^:]*: *//')
    if [[ "$acao" == "$ORIGIN" || "$acao" == "*" ]]; then
      pass_test "ACAO=$acao, ${ms}ms"
    else
      fail_test "bad_acao" "expected=$ORIGIN got=$acao"
    fi
  fi
  rm -f "$body_f" "$hdr_f"
done
