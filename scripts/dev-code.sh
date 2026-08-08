#!/usr/bin/env bash
# ============================================================
# dev-code — instant sign-in code for the local dev cycle
# ============================================================
# GoTrue has no fixed email OTP (only SMS supports test_otp), so we can't
# hardcode a "super code". Instead this fires a fresh OTP for a fixed dev
# email and prints the code straight from Mailpit — one command, every time.
#
#   ./scripts/dev-code.sh                 # code for the default dev email
#   ./scripts/dev-code.sh alice@x.test    # code for any email
#
# Then type the printed code into the app's login screen.
set -euo pipefail

EMAIL="${1:-dev@girltea.test}"
API="http://127.0.0.1:54321"
MAILPIT="http://127.0.0.1:54324"
# Local dev anon key (publishable). Matches `supabase status`.
ANON="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZS1kZW1vIiwicm9sZSI6ImFub24iLCJleHAiOjE5ODM4MTI5OTZ9.CRXP1A7WOeoJeXxjNni43kdQwgnWNReilDMblYTn_I0"

# 1. Ask GoTrue to send a magic-link/OTP (creates the user on first use).
http=$(curl -s -o /dev/null -w "%{http_code}" -X POST "$API/auth/v1/otp" \
  -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d "{\"email\":\"$EMAIL\",\"create_user\":true}")
if [ "$http" != "200" ]; then
  echo "Failed to request OTP (HTTP $http). Is the local stack up? (supabase start)" >&2
  exit 1
fi

# 2. Pull the newest message for this email out of Mailpit and extract the code.
code=$(curl -s "$MAILPIT/api/v1/messages?limit=20" | python3 -c "
import sys, json, re, urllib.request
data = json.load(sys.stdin)
target = '$EMAIL'.lower()
mid = None
for m in data.get('messages', []):
    tos = [t.get('Address','').lower() for t in m.get('To', [])]
    if target in tos:
        mid = m['ID']; break
if not mid:
    sys.exit('No email found for ' + target)
raw = urllib.request.urlopen('$MAILPIT/api/v1/message/' + mid).read()
d = json.loads(raw)
for key in ('Text', 'HTML'):
    hit = re.search(r'\b\d{6}\b', d.get(key) or '')
    if hit:
        print(hit.group(0)); break
else:
    sys.exit('No 6-digit code in the latest email')
")

echo "$EMAIL  →  $code"
