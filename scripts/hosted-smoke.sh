#!/usr/bin/env bash
# hosted-smoke.sh: what a signed-out holder of the app's publishable key can
# reach on the HOSTED project. Read-only, no Docker, no credentials beyond the
# key that ships in the iOS binary and web/config.js.
#
# The probe suite proves the grant model on a throwaway Postgres. This is the
# same question asked of production: every base table, view and RPC must
# answer a signed-out caller with 401/403/404, never a 200 with rows. It is
# the one check that catches "the migration pushed but the grant did not"
# (the class of bug from 2026-08-13 and 2026-08-19).
#
#   bash scripts/hosted-smoke.sh              # against amnaxvznkadkgzdxzegw
#
# Exit 1 on any 200. Prints one line per target.
set -u
URL="${SUPABASE_URL:-https://amnaxvznkadkgzdxzegw.supabase.co}"
KEY="${SUPABASE_ANON_KEY:-$(grep -o 'sb_publishable_[A-Za-z0-9_-]*' "$(dirname "$0")/../web/config.js" | head -1)}"
[ -n "$KEY" ] || { echo "no publishable key found"; exit 2; }

RELATIONS="clinics registrations players accounts player_notes clinic_templates payments devices notifications app_settings waivers waiver_acceptances review_links review_responses late_requests clinic_messages clinic_message_recipients news_posts news_reads clinics_public my_registrations my_clinic_messages my_news my_past_clinics clinics_admin templates_admin registrations_admin payments_ledger revenue_by_clinic"
FUNCTIONS="register_for_clinic cancel_registration leave_pool delete_my_account accept_waiver current_waiver my_waiver_accepted admin_charge_clinic admin_set_no_show place_player cancel_clinic search_players revenue_summary admin_create_review_link admin_review_responses create_my_account"
EDGE="delete-account stripe-charge stripe-setup-intent push"

bad=0; n=0
check() {  # kind name code
  n=$((n+1))
  case "$3" in
    200) printf 'OPEN   %-12s %-28s %s\n' "$1" "$2" "$3"; bad=$((bad+1)) ;;
    *)   printf 'closed %-12s %-28s %s\n' "$1" "$2" "$3" ;;
  esac
}
for r in $RELATIONS; do
  code=$(curl -s -o /dev/null -w '%{http_code}' "$URL/rest/v1/$r?select=*&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $KEY")
  check relation "$r" "$code"
done
for f in $FUNCTIONS; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/rest/v1/rpc/$f" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Type: application/json" -d '{}')
  check rpc "$f" "$code"
done
for e in $EDGE; do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/functions/v1/$e" -H "apikey: $KEY" -H "Content-Type: application/json" -d '{}')
  check edge "$e" "$code"
done
# pg_net's schema (20260923000001). Its queue holds each push request's
# X-Push-Secret header until sent and grants PUBLIC everything; a migration
# cannot revoke that (supabase_admin owns it), so what keeps it closed is the
# API exposing only public and graphql_public. PostgREST answers 406 PGRST106.
code=$(curl -s -o /dev/null -w '%{http_code}' "$URL/rest/v1/http_request_queue?select=*&limit=1" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Accept-Profile: net")
check net-schema http_request_queue "$code"
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$URL/rest/v1/rpc/http_post" -H "apikey: $KEY" -H "Authorization: Bearer $KEY" -H "Content-Profile: net" -H "Content-Type: application/json" -d '{"url":"https://example.invalid"}')
check net-schema http_post "$code"
echo "checked $n targets, $bad open to a signed-out caller"
[ "$bad" = "0" ]
