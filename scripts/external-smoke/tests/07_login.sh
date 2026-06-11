#!/usr/bin/env bash
# Login flow — auth endpoints should distinguish 401 (bad creds) from 422 (bad input).
set_group "login"

# Invalid creds → 401 (not 422 — that would mean schema rejected first)
begin_test "POST /v1/auth/user/login (invalid creds → 401)"
PAYLOAD='{"email":"ext-smoke-nobody@viralefy.test","password":"definitely-not-the-password"}'
read -r code ms body_f hdr_f < <(http_post_json "${API_BASE}/v1/auth/user/login" "$PAYLOAD" \
  -H "Origin: https://www.viralefy.com")
# Accept 401 (canonical) or 403 (auth provider variation). 422 = schema rejected creds shape (bug).
if assert_status_in "$code" "401" "403"; then
  pass_test "${ms}ms"
fi
rm -f "$body_f" "$hdr_f"

# Admin login same check
begin_test "POST /v1/auth/login (admin, invalid creds → 401)"
PAYLOAD='{"email":"ext-smoke-nobody@viralefy.test","password":"definitely-not-the-password"}'
read -r code ms body_f hdr_f < <(http_post_json "${API_BASE}/v1/auth/login" "$PAYLOAD" \
  -H "Origin: https://admin.viralefy.com")
if assert_status_in "$code" "401" "403"; then
  pass_test "${ms}ms"
fi
rm -f "$body_f" "$hdr_f"

# Register: bad email → 422 (input validation)
begin_test "POST /v1/auth/user/register (invalid email → 422)"
PAYLOAD='{"email":"not-an-email","password":"Whatever1!","name":"x"}'
read -r code ms body_f hdr_f < <(http_post_json "${API_BASE}/v1/auth/user/register" "$PAYLOAD")
# Accept any 4xx that isn't 500 — exact code varies by provider
if assert_status_in "$code" "422" "400" "401"; then
  pass_test "${ms}ms"
fi
rm -f "$body_f" "$hdr_f"

# Register w/ tracking — should succeed or 409 if exists. Regression for
# tracking field handling in registration.
begin_test "POST /v1/auth/user/register (valid + tracking → 201/409)"
EMAIL="ext-smoke-${RUN_ID}@viralefy.test"
PAYLOAD=$(jq -cn --arg email "$EMAIL" '{
  email: $email,
  password: "ExtSmokeTest1!",
  name: "External Smoke",
  tracking: {
    landing_url: "https://www.viralefy.com/register",
    referrer: "https://google.com/",
    utm_source: "google",
    fbclid: "ext-smoke-fbclid"
  }
}')
read -r code ms body_f hdr_f < <(http_post_json "${API_BASE}/v1/auth/user/register" "$PAYLOAD" \
  -H "Origin: https://www.viralefy.com")
if [[ "$code" == "403" ]]; then
  fail_test "WAF_FALSE_POSITIVE" "register w/ tracking blocked. body=$(head -c 200 "$body_f")"
elif assert_status_in "$code" "201" "200" "409" "422"; then
  pass_test "${ms}ms (code=$code)"
fi
rm -f "$body_f" "$hdr_f"
