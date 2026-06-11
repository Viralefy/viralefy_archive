#!/usr/bin/env bash
# run.sh — orchestrator. Sources lib.sh and every tests/*.sh in order,
# then finalizes the run (writes results, summary, failures, optional webhook).
#
# Exit code: 0 if all tests passed, 1 if any failed (so CI marks the job red).
# Designed to run on GitHub Actions ubuntu-latest with only bash/jq/curl/openssl.

set -uo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
# shellcheck source=lib.sh
source "$HERE/lib.sh"

# Truncate prior result files so re-runs don't accumulate.
: > "$RESULTS_FILE"
: > "$FAILURES_FILE"
: > /tmp/external-smoke-orders.txt

log "External smoke — run_id=$RUN_ID"
log "  www_base=$WWW_BASE"
log "  admin_base=$ADMIN_BASE"
log "  api_base=$API_BASE"
log "  budget_ms=$P95_BUDGET_MS"

# Source each test file. Tests use `return 0` to skip rather than exit so a
# bail-out in one test doesn't terminate the whole run.
for f in "$HERE"/tests/*.sh; do
  [[ -f "$f" ]] || continue
  log "===== $(basename "$f") ====="
  # shellcheck disable=SC1090
  source "$f" || warn "$(basename "$f") returned non-zero"
done

if finalize; then
  log "ALL GREEN"
  exit 0
else
  err "FAILURES PRESENT — see $FAILURES_FILE"
  exit 1
fi
