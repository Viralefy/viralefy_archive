#!/usr/bin/env bash
# REAL checkout flow — regression test for the 2026-06-10 Coraza 931130 FP.
#
# The bug: Coraza WAF rule 931130 (Possible RFI) treated the legitimate
# tracking.landing_url=https://www.viralefy.com/... as a Remote File
# Inclusion attempt and 403'd a real checkout submission.
#
# This test sends the exact payload shape the front sends (with
# tracking.landing_url + referrer + utm_source + fbclid) so any future
# WAF regression that re-blocks this is caught in ≤15min.
set_group "checkout_flow"

# Step 1 — fetch a real plan
begin_test "GET /v1/plans (extract plan_id)"
read -r code ms body_f hdr_f < <(http_get "${API_BASE}/v1/plans")
PLAN_ID=""
if assert_status "$code" "200"; then
  PLAN_ID=$(jq -r '.data[] | select(.active==true) | .id' "$body_f" 2>/dev/null | head -1)
  if [[ -n "$PLAN_ID" ]]; then
    pass_test "plan_id=$PLAN_ID, ${ms}ms"
  else
    fail_test "no_active_plan" "$(head -c 200 "$body_f")"
  fi
fi
rm -f "$body_f" "$hdr_f"

# Bail early if no plan
if [[ -z "$PLAN_ID" ]]; then
  warn "skipping checkout — no plan_id available"
  return 0
fi

# Step 2 — fetch payment methods for that plan, pick Heleket
begin_test "GET /v1/plans/$PLAN_ID/payment-methods (extract heleket gateway_id)"
read -r code ms body_f hdr_f < <(http_get "${API_BASE}/v1/plans/${PLAN_ID}/payment-methods?country=us&display_currency=USD")
GATEWAY_ID=""
if assert_status "$code" "200"; then
  # Endpoint may return enveloped {"data":[...]} or a bare array — handle both.
  GATEWAY_ID=$(jq -r '(.data // .) | .[] | select(.provider=="heleket") | .gateway_id' "$body_f" 2>/dev/null | head -1)
  if [[ -z "$GATEWAY_ID" || "$GATEWAY_ID" == "null" ]]; then
    GATEWAY_ID=$(jq -r '(.data // .) | .[0].gateway_id // empty' "$body_f" 2>/dev/null)
  fi
  if [[ -n "$GATEWAY_ID" && "$GATEWAY_ID" != "null" ]]; then
    pass_test "gateway_id=$GATEWAY_ID, ${ms}ms"
  else
    fail_test "no_gateway" "$(head -c 200 "$body_f")"
  fi
fi
rm -f "$body_f" "$hdr_f"

if [[ -z "$GATEWAY_ID" || "$GATEWAY_ID" == "null" ]]; then
  warn "skipping checkout — no gateway_id"
  return 0
fi

# Step 3 — REAL checkout with tracking payload (the regression test)
EMAIL="ext-smoke-${RUN_ID}@viralefy.test"
PAYLOAD=$(jq -cn \
  --arg plan_id "$PLAN_ID" \
  --arg email "$EMAIL" \
  --arg gateway_id "$GATEWAY_ID" \
  '{
    plan_id: $plan_id,
    email: $email,
    name: "External Smoke Test",
    display_currency: "USD",
    payment_method: "gateway",
    gateway_id: $gateway_id,
    pay_currency: "USDT",
    new_profile: {
      platform: "instagram",
      handle: "extsmoketest",
      display_name: "External Smoke"
    },
    tracking: {
      landing_url: "https://www.viralefy.com/us/instagram-followers",
      referrer: "https://google.com/",
      utm_source: "google",
      utm_medium: "cpc",
      utm_campaign: "ext-smoke-regression",
      fbclid: "ext-smoke-fbclid",
      gclid: "ext-smoke-gclid"
    },
    country: "us",
    target_country: "us"
  }')

IDEM_KEY="ext-smoke-${RUN_ID}-$(date +%s%N)"

begin_test "POST /v1/checkout (real payload w/ tracking.landing_url — Coraza 931130 regression)"
read -r code ms body_f hdr_f < <(http_post_json "${API_BASE}/v1/checkout" "$PAYLOAD" \
  -H "Origin: https://www.viralefy.com" \
  -H "Referer: https://www.viralefy.com/us/instagram-followers" \
  -H "User-Agent: viralefy-external-smoke/1.0" \
  -H "Idempotency-Key: $IDEM_KEY")

# Accept 201 (created) OR 200 (idempotent replay). Anything else is a regression.
# CRITICAL: 403 here means WAF blocked legitimate traffic again — the exact bug
# we are guarding against.
if [[ "$code" == "403" ]]; then
  # Capture trace_id so on-call can grep Coraza audit log immediately.
  trace=$(jq -r '.error.trace_id // "n/a"' "$body_f" 2>/dev/null)
  fail_test "WAF_FALSE_POSITIVE" "checkout w/ tracking blocked — Coraza regression. trace_id=$trace body=$(head -c 300 "$body_f")"
elif assert_status_in "$code" "201" "200"; then
  order_id=$(jq -r '.data.id // .data.order_id // empty' "$body_f" 2>/dev/null)
  pay_url=$(jq -r '.data.payment_url // .data.pay_url // empty' "$body_f" 2>/dev/null)
  if [[ -n "$order_id" ]]; then
    pass_test "order_id=$order_id, payment_url=${pay_url:+yes}, ${ms}ms"
    # Persist for downstream cleanup tooling.
    echo "$order_id $EMAIL" >> /tmp/external-smoke-orders.txt
  else
    fail_test "checkout_no_order_id" "$(head -c 300 "$body_f")"
  fi
fi
assert_latency_under "$ms" "$((P95_BUDGET_MS * 3))"  # checkout allowed more
rm -f "$body_f" "$hdr_f"
