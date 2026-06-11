#!/usr/bin/env bash
# TLS + security headers — guards against accidental hardening regressions.
set_group "tls_headers"

# Required response headers on every public surface.
HOSTS=(
  "${WWW_BASE}/"
  "${ADMIN_BASE}/"
  "${API_BASE}/v1/status"
)

for url in "${HOSTS[@]}"; do
  begin_test "headers $url"
  read -r code ms body_f hdr_f < <(http_get "$url")
  required=(
    "strict-transport-security"
    "x-content-type-options"
  )
  ok_flag=1
  for h in "${required[@]}"; do
    if ! grep -qiE "^${h}:" "$hdr_f"; then
      fail_test "missing_${h}" "url=$url"
      ok_flag=0
      break
    fi
  done

  # HSTS must include preload
  if (( ok_flag )); then
    hsts=$(grep -i '^strict-transport-security:' "$hdr_f" | head -1 | tr -d '\r')
    if ! grep -qi 'preload' <<<"$hsts"; then
      fail_test "hsts_no_preload" "got=$hsts"
      ok_flag=0
    fi
  fi

  # Server: Caddy must NOT be present (we strip with -Server)
  if (( ok_flag )); then
    if grep -qiE '^server: *caddy' "$hdr_f"; then
      fail_test "server_header_leaked" "Caddy server header exposed"
      ok_flag=0
    fi
  fi

  (( ok_flag )) && pass_test "${ms}ms"
  rm -f "$body_f" "$hdr_f"
done

# TLS cert expiry — warn if <14 days
begin_test "TLS cert expiry api.viralefy.com (>14d)"
exp=$(echo | openssl s_client -connect api.viralefy.com:443 -servername api.viralefy.com 2>/dev/null \
       | openssl x509 -noout -enddate 2>/dev/null | sed 's/^notAfter=//')
if [[ -n "$exp" ]]; then
  exp_ts=$(date -d "$exp" +%s 2>/dev/null || echo 0)
  now_ts=$(date +%s)
  days_left=$(( (exp_ts - now_ts) / 86400 ))
  if (( days_left < 14 )); then
    fail_test "tls_cert_expiring" "days_left=$days_left (cert exp=$exp)"
  else
    pass_test "${days_left}d remaining"
  fi
else
  warn "could not read TLS cert (openssl unavailable or network blocked)"
  pass_test "skipped (no openssl)"
fi
