#!/usr/bin/env bash
# Frontend pages — must return 200 with HTML.
set_group "frontend_pages"

PAGES=(
  "${WWW_BASE}/"
  "${WWW_BASE}/pricing"
  "${WWW_BASE}/login"
  "${WWW_BASE}/register"
  "${WWW_BASE}/us/instagram-followers"
  "${ADMIN_BASE}/"
  "${ADMIN_BASE}/login"
)

for url in "${PAGES[@]}"; do
  begin_test "GET $url"
  read -r code ms body_f hdr_f < <(http_get "$url")
  if assert_status "$code" "200" "$url"; then
    # Must be HTML (text/html in Content-Type) — guards against JSON error pages
    if ! grep -qiE '^content-type:.*text/html' "$hdr_f"; then
      fail_test "not_html" "content-type=$(grep -i '^content-type:' "$hdr_f" | head -1)"
    else
      pass_test "${ms}ms"
      assert_latency_under "$ms" "$P95_BUDGET_MS"
    fi
  fi
  rm -f "$body_f" "$hdr_f"
done
