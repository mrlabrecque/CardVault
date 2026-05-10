#!/usr/bin/env bash
# Bright Data POST /request sanity check — no multi-line curl paste in Terminal.
# Same env names as Supabase Edge Function secrets.
#
#   export BRIGHTDATA_API_KEY='your-api-key'
#   export BRIGHTDATA_UNLOCKER_ZONE='your-web-unlocker-zone-name'
#   ./supabase/scripts/test-brightdata-request.sh
#
# Success: JSON with "status_code" and "body". Failure: JSON error or HTML.

set -euo pipefail

if [[ -z "${BRIGHTDATA_API_KEY:-}" || -z "${BRIGHTDATA_UNLOCKER_ZONE:-}" ]]; then
  echo "Set both (same as Supabase → Edge Functions → Secrets):" >&2
  echo "  export BRIGHTDATA_API_KEY='…'" >&2
  echo "  export BRIGHTDATA_UNLOCKER_ZONE='…'" >&2
  exit 1
fi

BODY=$(python3 -c 'import json, os
print(json.dumps({
  "zone": os.environ["BRIGHTDATA_UNLOCKER_ZONE"],
  "url": "https://geo.brdtest.com/welcome.txt",
  "format": "json",
  "method": "GET",
}))')

curl -sS -X POST 'https://api.brightdata.com/request' \
  --header "Authorization: Bearer ${BRIGHTDATA_API_KEY}" \
  --header 'Content-Type: application/json' \
  --data-raw "$BODY"
echo
