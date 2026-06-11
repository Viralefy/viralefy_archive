#!/usr/bin/env bash
# lib.sh — External smoke test helpers.
#
# Used by run.sh + every script in tests/. Provides:
#  - assertion primitives (assert_eq, assert_in, assert_lt)
#  - curl wrappers that capture status, body, latency, request_id
#  - structured logging that NEVER prints secrets (auth headers stripped)
#  - results aggregator (JSONL appended to $RESULTS_FILE)
#
# Contract: every test file is sourced (not exec'd). Tests call begin_test,
# do their assertions, then either pass_test or fail_test. The aggregator
# counts PASS/FAIL and exits non-zero at end if any FAIL.

set -uo pipefail

# ----- env -----
: "${WWW_BASE:=https://www.viralefy.com}"
: "${ADMIN_BASE:=https://admin.viralefy.com}"
: "${API_BASE:=https://api.viralefy.com}"
: "${REQ_TIMEOUT:=10}"
: "${P95_BUDGET_MS:=1000}"
: "${RESULTS_FILE:=/tmp/external-smoke-results.jsonl}"
: "${FAILURES_FILE:=/tmp/external-smoke-failures.json}"
: "${SUMMARY_FILE:=/tmp/external-smoke-summary.md}"
: "${RUN_ID:=local-$(date +%s)}"

# ----- ANSI (only when TTY) -----
if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_GRN=$'\033[32m'; C_YEL=$'\033[33m'; C_DIM=$'\033[2m'; C_RST=$'\033[0m'
else
  C_RED=""; C_GRN=""; C_YEL=""; C_DIM=""; C_RST=""
fi

# ----- counters (mutated via files because subshells reset shell vars) -----
COUNTERS_DIR=$(mktemp -d)
echo 0 > "$COUNTERS_DIR/pass"
echo 0 > "$COUNTERS_DIR/fail"
echo 0 > "$COUNTERS_DIR/total"

_bump() { local f="$COUNTERS_DIR/$1"; local n; n=$(<"$f"); echo $((n + 1)) > "$f"; }

# ----- logging -----
log()   { printf '%s[%s]%s %s\n' "$C_DIM" "$(date +%H:%M:%S)" "$C_RST" "$*" >&2; }
warn()  { printf '%s[%s] WARN%s %s\n' "$C_YEL" "$(date +%H:%M:%S)" "$C_RST" "$*" >&2; }
err()   { printf '%s[%s] ERR%s  %s\n' "$C_RED" "$(date +%H:%M:%S)" "$C_RST" "$*" >&2; }
ok()    { printf '%s[%s] OK%s   %s\n' "$C_GRN" "$(date +%H:%M:%S)" "$C_RST" "$*" >&2; }

# Sanitize a string for logs — strip bearer tokens + cookies + obvious secret fields.
# Uses POSIX ERE only (no PCRE) so it runs on stock GNU/BSD sed.
sanitize() {
  sed -E \
    -e 's/([Aa]uthorization): *Bearer +[A-Za-z0-9._-]+/\1: Bearer ***REDACTED***/g' \
    -e 's/([Cc]ookie): *[^"]+/\1: ***REDACTED***/g' \
    -e 's/"(password|secret|token|api_key|admin_token)":"[^"]+"/"\1":"***REDACTED***"/g' \
    <<<"${1:-}"
}

# ----- test lifecycle -----
CURRENT_TEST=""
CURRENT_GROUP=""

set_group() { CURRENT_GROUP="$1"; }

begin_test() {
  CURRENT_TEST="$1"
  _bump total
  log "→ ${CURRENT_GROUP}/${CURRENT_TEST}"
}

pass_test() {
  _bump pass
  ok "${CURRENT_GROUP}/${CURRENT_TEST}${1:+ — $1}"
  jq -cn --arg g "$CURRENT_GROUP" --arg t "$CURRENT_TEST" --arg n "${1:-}" \
    '{group:$g, test:$t, status:"pass", note:$n}' >> "$RESULTS_FILE"
}

fail_test() {
  _bump fail
  local reason="${1:-unknown}"
  local detail="${2:-}"
  err "${CURRENT_GROUP}/${CURRENT_TEST} — ${reason}"
  [[ -n "$detail" ]] && err "       $(sanitize "$detail" | head -c 500)"
  jq -cn --arg g "$CURRENT_GROUP" --arg t "$CURRENT_TEST" \
         --arg r "$reason" --arg d "$(sanitize "$detail")" \
    '{group:$g, test:$t, status:"fail", reason:$r, detail:$d}' >> "$RESULTS_FILE"
}

# ----- curl wrappers -----
# http_get URL [extra_curl_args...]
#   Echos "<status_code>\t<latency_ms>\t<body_file>\t<headers_file>"
http_get() {
  local url="$1"; shift
  _http "GET" "$url" "" "$@"
}

http_post_json() {
  local url="$1" body="$2"; shift 2
  _http "POST" "$url" "$body" -H "Content-Type: application/json" "$@"
}

http_options() {
  local url="$1"; shift
  _http "OPTIONS" "$url" "" "$@"
}

_http() {
  local method="$1" url="$2" body="$3"; shift 3
  local body_f hdr_f stat
  body_f=$(mktemp); hdr_f=$(mktemp)
  local -a args=(
    --max-time "$REQ_TIMEOUT"
    -s -o "$body_f" -D "$hdr_f"
    -w '%{http_code}\t%{time_total}\n'
    -X "$method"
  )
  if [[ -n "$body" ]]; then args+=(--data-raw "$body"); fi
  args+=("$@" "$url")

  local out
  out=$(curl "${args[@]}" 2>/dev/null) || true
  local code ttot
  code="${out%%$'\t'*}"
  ttot="${out##*$'\t'}"
  local ms
  ms=$(awk -v t="$ttot" 'BEGIN{printf "%d", t*1000}')
  printf '%s\t%s\t%s\t%s\n' "${code:-0}" "$ms" "$body_f" "$hdr_f"
}

# ----- assertions -----
assert_status() {
  local got="$1" want="$2" ctx="${3:-}"
  if [[ "$got" == "$want" ]]; then return 0; fi
  fail_test "status_mismatch" "want=$want got=$got ctx=$ctx"
  return 1
}

assert_status_in() {
  local got="$1"; shift
  local want
  for want in "$@"; do
    if [[ "$got" == "$want" ]]; then return 0; fi
  done
  fail_test "status_not_in_set" "got=$got allowed=$*"
  return 1
}

assert_json_array_nonempty() {
  local file="$1" path="${2:-.data}"
  local n
  n=$(jq -r "$path | if type==\"array\" then length else -1 end" "$file" 2>/dev/null || echo -1)
  if [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 )); then return 0; fi
  fail_test "json_not_array_or_empty" "path=$path got=$n body=$(head -c 200 "$file")"
  return 1
}

assert_latency_under() {
  local ms="$1" budget="$2"
  if (( ms <= budget )); then return 0; fi
  warn "latency ${ms}ms > budget ${budget}ms"
  jq -cn --arg g "$CURRENT_GROUP" --arg t "$CURRENT_TEST" --argjson ms "$ms" --argjson b "$budget" \
    '{group:$g, test:$t, status:"warn", reason:"latency_over_budget", ms:$ms, budget:$b}' >> "$RESULTS_FILE"
  return 0  # warning, not failure
}

assert_header_present() {
  local hdr_f="$1" name="$2"
  if grep -qiE "^${name}:" "$hdr_f"; then return 0; fi
  fail_test "header_missing" "expected=$name"
  return 1
}

assert_header_absent() {
  local hdr_f="$1" name="$2"
  if grep -qiE "^${name}:" "$hdr_f"; then
    fail_test "header_should_be_absent" "found=$name"
    return 1
  fi
  return 0
}

# ----- summary -----
finalize() {
  local pass fail total
  pass=$(<"$COUNTERS_DIR/pass")
  fail=$(<"$COUNTERS_DIR/fail")
  total=$(<"$COUNTERS_DIR/total")

  # failures.json (compact list for downstream tooling/alerts)
  jq -s '[ .[] | select(.status=="fail") ]' "$RESULTS_FILE" > "$FAILURES_FILE" 2>/dev/null || echo '[]' > "$FAILURES_FILE"

  # markdown summary (consumed by GH Actions $GITHUB_STEP_SUMMARY)
  {
    echo "# External smoke — run ${RUN_ID}"
    echo
    echo "| Metric | Value |"
    echo "|---|---|"
    echo "| Total | ${total} |"
    echo "| Pass  | ${pass} |"
    echo "| Fail  | ${fail} |"
    echo
    if (( fail > 0 )); then
      echo "## Failures"
      echo
      echo '| Group | Test | Reason | Detail |'
      echo '|---|---|---|---|'
      # FAILURES_FILE is a JSON array; iterate items, not the array itself.
      jq -r '.[] | "| \(.group) | \(.test) | \(.reason) | \((.detail // "") | gsub("\\|"; "\\|") | .[0:200]) |"' "$FAILURES_FILE"
    fi
  } > "$SUMMARY_FILE"

  printf '\n----- summary -----\n'
  printf 'total=%s pass=%s fail=%s\n' "$total" "$pass" "$fail"
  printf 'results:  %s\n' "$RESULTS_FILE"
  printf 'failures: %s\n' "$FAILURES_FILE"
  printf 'summary:  %s\n' "$SUMMARY_FILE"

  # Optional webhook
  if [[ -n "${ADMIN_WEBHOOK_URL:-}" && "$fail" -gt 0 ]]; then
    log "posting ${fail} failures to ADMIN_WEBHOOK_URL"
    jq -cn --arg run "$RUN_ID" --argjson f $fail --argjson t $total --slurpfile fails "$FAILURES_FILE" \
      '{event:"external_smoke_fail", run_id:$run, total:$t, failures:$f, items:$fails[0]}' \
      | curl -sS --max-time 10 -X POST -H 'Content-Type: application/json' \
              --data-binary @- "$ADMIN_WEBHOOK_URL" >/dev/null || warn "webhook post failed"
  fi

  if (( fail > 0 )); then return 1; fi
  return 0
}
