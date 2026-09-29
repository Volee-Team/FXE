#!/usr/bin/env bash
# hosted-smoke.sh: what a signed-out holder of the app's publishable key can
# reach on the HOSTED project. Read-only, no Docker, no credentials beyond the
# key that ships in the iOS binary and web/config.js.
#
# The probe suite proves the grant model on a throwaway Postgres. This is the
# same question asked of production: every base table, view and RPC must
# answer a signed-out caller with 401/403, never a 200 with rows. It is the
# one check that catches "the migration pushed but the grant did not" (the
# class of bug from 2026-08-13 and 2026-08-19).
#
# A 404 is NOT closed (changed 2026-09-27). PostgREST answers 404 PGRST202
# both for a function that does not exist and for one called with the wrong
# argument names, with the same body, so calling every function with '{}'
# made "missing on hosted" indistinguishable from "refused". Each function is
# now called with its real argument names (placeholder values), so 404 means
# the object is not on hosted, and that is a failure: a migration that did
# not reach production is exactly what this script exists to catch.
#
#   bash scripts/hosted-smoke.sh              # against amnaxvznkadkgzdxzegw
#
# Exit 1 on any 200. Prints one line per target.
set -u
URL="${SUPABASE_URL:-https://amnaxvznkadkgzdxzegw.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-$(grep -o 'sb_publishable_[A-Za-z0-9_-]*' "$(dirname "$0")/../web/config.js" | head -1)}"
[ -n "$KEY" ] || { echo "no publishable key found"; exit 2; }

RELATIONS="clinics registrations players accounts player_notes clinic_templates payments devices notifications app_settings waivers waiver_acceptances card_consents review_links review_responses reset_links_issued calendar_feeds late_requests clinic_messages clinic_message_recipients news_posts news_reads clinics_public my_registrations my_clinic_messages my_news my_past_clinics clinics_admin templates_admin registrations_admin payments_ledger revenue_by_clinic"
EDGE="delete-account stripe-charge stripe-setup-intent push admin-reset-link stripe-payouts"
# Edge functions that take no JWT on purpose, each with its own credential and
# a refusal that is not 401: review-submit (the link token; 400/404 without
# one) and stripe-webhook (Stripe's signature; 400 bad_signature). Their
# closedness is checked by their own harnesses. check-doc-inventory.sh
# requires every function directory to be in EDGE or here. calendar-feed
# (decision 0029) has no JWT either: its check is its own block below.
EDGE_EXEMPT="review-submit stripe-webhook calendar-feed"
# Called from the web admin in a browser, so they need CORS (_shared/cors.ts).
BROWSER_EDGE="review-submit stripe-charge admin-reset-link stripe-payouts"

bad=0; n=0
check() {  # kind name code
  n=$((n+1))
  case "$3" in
    401|403) printf 'closed %-12s %-28s %s\n' "$1" "$2" "$3" ;;
    406) if [ "$1" = "net-schema" ]; then printf 'closed %-12s %-28s %s\n' "$1" "$2" "$3"
         else printf 'ODD    %-12s %-28s %s\n' "$1" "$2" "$3"; bad=$((bad+1)); fi ;;
    404) printf 'MISSING %-11s %-28s %s (not on hosted, or its arguments here are stale)\n' "$1" "$2" "$3"; bad=$((bad+1)) ;;
    200) printf 'OPEN   %-12s %-28s %s\n' "$1" "$2" "$3"; bad=$((bad+1)) ;;
    *)   printf 'ODD    %-12s %-28s %s\n' "$1" "$2" "$3"; bad=$((bad+1)) ;;
  esac
}
for r in $RELATIONS; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$URL/rest/v1/$r?select=*&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $KEY")
  check relation "$r" "$code"
done
# Every callable function in public, with its real argument names and
# placeholder values, generated from the local schema by
# scripts/gen-smoke-functions.sh into scripts/hosted-smoke-functions.txt
# (2026-09-27; until then this was a hand-kept list that missed 35 of 81).
# check-doc-inventory.sh fails when the file and the schema disagree.
while IFS=$'\t' read -r f args; do
  [ -n "$f" ] || continue
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/rest/v1/rpc/$f" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d "$args")
  check rpc "$f" "$code"
done < "$(dirname "$0")/hosted-smoke-functions.txt"
for e in $EDGE; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/functions/v1/$e" -H "apikey: $KEY" -H "Content-Type: application/json" -d '{}')
  check edge "$e" "$code"
done
# calendar-feed (decision 0029): a calendar app sends nothing but the URL,
# so the token in it is the credential. A made-up token must get the
# function's own refusal, a 404 with an EMPTY body; the gateway's 404 for a
# function that was never deployed carries a body ("Requested function was
# not found" on hosted, "Function not found" locally), so the body is what
# tells refused from missing. A 200 would be a feed served for a guess.
n=$((n+1))
feed_body=$(mktemp)
code=$(curl -s -o "$feed_body" -w '%{http_code}' "$URL/functions/v1/calendar-feed?t=$(printf '0%.0s' $(seq 64))")
if [ "$code" = "404" ] && [ ! -s "$feed_body" ]; then
  printf 'closed %-12s %-28s %s\n' edge calendar-feed "404 (unknown token)"
elif [ "$code" = "404" ]; then
  printf 'MISSING %-11s %-28s %s (not deployed: the 404 is the gateway'"'"'s, with a body)\n' edge calendar-feed "$code"; bad=$((bad+1))
else
  printf 'OPEN   %-12s %-28s %s (a made-up token must be 404)\n' edge calendar-feed "$code"; bad=$((bad+1))
fi
rm -f "$feed_body"
# pg_net's schema (20260923000001). Its queue holds each push request's
# X-Push-Secret header until sent and grants PUBLIC everything; a migration
# cannot revoke that (supabase_admin owns it), so what keeps it closed is the
# API exposing only public and graphql_public. PostgREST answers 406 PGRST106.
code=$(curl -s -o /dev/null -w '%{http_code}' "$URL/rest/v1/http_request_queue?select=*&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Accept-Profile: net")
check net-schema http_request_queue "$code"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/rest/v1/rpc/http_post" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Profile: net" -H "Content-Type: application/json" -d '{"url":"https://example.invalid"}')
check net-schema http_post "$code"
# The functions the web admin calls from the browser must answer the
# preflight with the admin site's origin, or the browser never sends the call.
# Locally the gateway answers preflights itself, so only hosted can go red here
# (2026-09-27: stripe-charge answered 405 with no header, so Charge clinic on
# the web would have queued fees that never reached Stripe).
ADMIN_ORIGIN=https://fxe-tennis-admin.vercel.app
for e in $BROWSER_EDGE; do
  n=$((n+1))
  # The status matters as much as the header: hosted's gateway answers a
  # function that does not exist with 404 AND "allow-origin: *", so a check on
  # the header alone passes for a function that was never deployed.
  head=$(curl -s -o /dev/null -D - -X OPTIONS "$URL/functions/v1/$e" -H "Origin: $ADMIN_ORIGIN" \
          -H "Access-Control-Request-Method: POST" -H "Access-Control-Request-Headers: authorization,apikey,content-type,x-client-info" | tr -d '\r')
  status=$(echo "$head" | awk 'NR==1{print $2}')
  allow=$(echo "$head" | awk -F': ' 'tolower($1)=="access-control-allow-origin"{print $2}')
  if { [ "$status" = "200" ] || [ "$status" = "204" ]; } && { [ "$allow" = "$ADMIN_ORIGIN" ] || [ "$allow" = "*" ]; }; then
    printf 'cors   %-12s %-28s allows the admin site\n' edge "$e"
  else
    printf 'NOCORS %-12s %-28s preflight from the admin site: http %s, allow-origin "%s" (the browser will refuse every call)\n' edge "$e" "$status" "$allow"; bad=$((bad+1))
  fi
done
echo "checked $n targets, $bad open, missing or odd to a signed-out caller"
[ "$bad" = "0" ]
