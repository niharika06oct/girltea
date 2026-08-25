#!/usr/bin/env bash
# ============================================================
# cloud-code — instant sign-in code for the LIVE Supabase Cloud project
# ============================================================
# GoTrue has no fixed email OTP (only SMS supports test_otp), and the Cloud
# built-in mailer is rate-limited (~2-4/hour). So instead of triggering an
# email, this uses the admin `generate_link` endpoint to MINT a fresh 6-digit
# OTP directly — no email is sent, so there's no rate limit. One command,
# every time. Type the printed code into the app's login screen.
#
#   export SUPABASE_SERVICE_ROLE_KEY=sb_secret_...   # from Dashboard -> Project Settings -> API keys
#   ./scripts/cloud-code.sh                          # code for the default demo email
#   ./scripts/cloud-code.sh me@example.com           # code for any email
#
# The service_role key is a FULL-ACCESS secret: keep it in the env var only
# (never commit it), and rotate it in the dashboard when you're done demoing.
set -euo pipefail

EMAIL="${1:-niharikasingh0351@gmail.com}"
API="https://uicdlhczntenjhtfijhr.supabase.co"

: "${SUPABASE_SERVICE_ROLE_KEY:?Set SUPABASE_SERVICE_ROLE_KEY first (export SUPABASE_SERVICE_ROLE_KEY=sb_secret_...)}"
KEY="$SUPABASE_SERVICE_ROLE_KEY"

gen() { # $1 = link type (magiclink | signup)
  curl -s -X POST "$API/auth/v1/admin/generate_link" \
    -H "apikey: $KEY" -H "Authorization: Bearer $KEY" \
    -H "Content-Type: application/json" \
    -d "{\"type\":\"$1\",\"email\":\"$EMAIL\"}"
}

# Existing user -> magiclink. If the user doesn't exist yet, fall back to signup
# (which both creates the user and returns an OTP).
resp="$(gen magiclink)"
if echo "$resp" | grep -qiE 'user not found|"code":(404|422)'; then
  resp="$(gen signup)"
fi

code="$(printf '%s' "$resp" | python3 -c "
import sys, json
d = json.load(sys.stdin)
otp = d.get('email_otp') or (d.get('properties') or {}).get('email_otp')
if not otp:
    sys.exit('No OTP in response: ' + json.dumps(d)[:400])
print(otp)
")"

echo "$EMAIL  ->  $code"
