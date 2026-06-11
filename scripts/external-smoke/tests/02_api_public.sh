#!/usr/bin/env bash
# Public read-only API — 200 + sane JSON shape.
set_group "api_public"

# /v1/status (degraded is acceptable — only overall=down is a failure)
begin_test "GET /v1/status"
read -r code ms body_f hdr_f < <(http_get "${API_BASE}/v1/status")
if assert_status "$code" "200"; then
  overall=$(jq -r '.data.overall // "missing"' "$body_f" 2>/dev/null)
  case "$overall" in
    operational|degraded) pass_test "overall=$overall, ${ms}ms" ;;
    *) fail_test "bad_overall" "overall=$overall body=$(head -c 200 "$body_f")" ;;
  esac
fi
rm -f "$body_f" "$hdr_f"

# Arrays — each must be non-empty (where applicable)
declare -A ENDPOINTS=(
  ["/v1/plans"]=".data"
  ["/v1/categories"]=".data"
  ["/v1/currencies"]=".data"
  ["/v1/country-ppp"]=".data"
  ["/v1/tax-rates"]=".data"
)

for path in "${!ENDPOINTS[@]}"; do
  begin_test "GET $path"
  read -r code ms body_f hdr_f < <(http_get "${API_BASE}${path}")
  if assert_status "$code" "200"; then
    if assert_json_array_nonempty "$body_f" "${ENDPOINTS[$path]}"; then
      pass_test "${ms}ms"
      assert_latency_under "$ms" "$P95_BUDGET_MS"
    fi
  fi
  rm -f "$body_f" "$hdr_f"
done

# JWKS
begin_test "GET /.well-known/jwks.json"
read -r code ms body_f hdr_f < <(http_get "${API_BASE}/.well-known/jwks.json")
if assert_status "$code" "200"; then
  keys=$(jq -r '.keys | length // 0' "$body_f" 2>/dev/null || echo 0)
  if (( keys > 0 )); then
    # Each key must have kty + kid + alg
    bad=$(jq -r '.keys[] | select(.kty==null or .kid==null or .alg==null) | .kid // "anon"' "$body_f" 2>/dev/null)
    if [[ -z "$bad" ]]; then
      pass_test "${keys} keys, ${ms}ms"
    else
      fail_test "jwks_incomplete_key" "keys missing fields: $bad"
    fi
  else
    fail_test "jwks_empty" "$(head -c 200 "$body_f")"
  fi
fi
rm -f "$body_f" "$hdr_f"
