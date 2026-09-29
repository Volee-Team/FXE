#!/bin/bash
# The calendar feed (decision 0029) end to end, against the local stack with
# the edge functions served:
#
#   supabase functions serve &
#   bash tests/calendar/run.sh
#
# What it proves, each check written from the rule, not the code:
#   * the link needs nothing but the URL (no apikey, no JWT), as Apple's
#     Calendar, Google and Outlook send nothing else;
#   * Maria's feed, worked out by hand from the seed: exactly one event, the
#     invitation in Evening Coed, tentative, "(Response Needed)";
#   * after she registers, is pooled, is placed and has her clinic canceled
#     (all through the real RPCs, as herself and as Tara): exactly her You're
#     In! and Response Needed clinics; the Player Pool and the canceled clinic
#     absent; a spot she gives up gone at the next fetch;
#   * nothing about where or which court: only an allowlist of properties
#     appears, no line starts LOCATION, URL or DESCRIPTION, the word "court"
#     is nowhere though Tara assigned one, and the description is not sent;
#   * times are UTC and equal Postgres's own rendering of the clinic's times;
#   * RFC 5545 on the wire: text/calendar; charset=utf-8, CRLF on every line,
#     no line over 75 octets, a clinic name with , ; \ and a line break escaped;
#   * a malformed, unknown, reset-away or deleted account's token is 404 with
#     an empty body (the same answer for all, and the one hosted-smoke.sh
#     tells apart from "not deployed"); POST is 405; HEAD has no body.
#
# Fixtures, all removed at the end (the DIRTY DATABASE rule in
# tests/run-probes.sh): Maria's registrations and the notifications they
# wrote, one clinic this script adds, Thursday Morning Cardio put back to
# published, Ken's deleted_at cleared, every feed token made here deleted.
# Last, it runs the iCalendar unit tests (tests/calendar/ics.test.ts) when
# deno is installed.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

API=${FXE_API_URL:-http://127.0.0.1:54321}
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
ANON=$(supabase status -o env 2>/dev/null | grep '^ANON_KEY' | cut -d= -f2 | tr -d '"')
FEED="$API/functions/v1/calendar-feed"

MARIA_P=a0000000-0000-0000-0000-000000000001
KEN_ACC=33333333-3333-3333-3333-333333333333
TUESDAY=d0000000-0000-0000-0000-000000000001     # public open: a member is pooled
THURSDAY=d0000000-0000-0000-0000-000000000002    # Tara places Maria, then cancels it
SATURDAY=d0000000-0000-0000-0000-000000000003    # member window open: You're In!
EVENING=d0000000-0000-0000-0000-000000000005     # the seed's invitation
INVITE=e0000000-0000-0000-0000-000000000001
ODD=cf300000-0000-0000-0000-000000000001         # a clinic whose name needs escaping

FAILED=0
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1 (expected '$2', got '$3')"; FAILED=1; fi; }
sql() { docker exec "$DB" psql -U postgres -d postgres -Atc "$1"; }
field() { python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d$1 if d is not None else '')
except Exception: print('')"; }
token_for() { curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
       -d "{\"email\":\"$1\",\"password\":\"password\"}" | field "['access_token']"; }
rpc() { # jwt name json -> body
  curl -s -X POST "$API/rest/v1/rpc/$2" -H "apikey: $ANON" -H "Authorization: Bearer $1" -H "Content-Type: application/json" -d "$3"; }
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
fetch() { # token -> status; body in $TMP/body, headers in $TMP/head. No headers sent at all.
  curl -s -D "$TMP/head" -o "$TMP/body" -w '%{http_code}' "$FEED?t=$1"; }
unfolded() { python3 -c "import sys; print(open(sys.argv[1], encoding='utf-8', newline='').read().replace('\r\n ', ''), end='')" "$TMP/body"; }
summaries() { unfolded | tr -d '\r' | grep '^SUMMARY:' | cut -d: -f2- | sort | paste -sd '#' -; }
utc() { sql "select to_char($1 at time zone 'UTC', 'YYYYMMDD\"T\"HH24MISS\"Z\"') from public.clinics where id = '$2'"; }

[ -n "$ANON" ] || { echo "  FAIL  no anon key: is the local stack running?"; exit 1; }
START=$(sql "select clock_timestamp()")
MARIA=$(token_for maria@fxe.test); ROB=$(token_for rob@fxe.test); TARA=$(token_for tara@fxe.test); KEN=$(token_for ken@fxe.test)
check "fixture: Maria, Rob, Tara and Ken sign in" "yes yes yes yes" \
  "$([ -n "$MARIA" ] && echo yes) $([ -n "$ROB" ] && echo yes) $([ -n "$TARA" ] && echo yes) $([ -n "$KEN" ] && echo yes)"

echo "── Maria's link"
T=$(rpc "$MARIA" my_calendar_feed_token '{}' | tr -d '"')
check "her token is 64 lowercase hex" "yes" "$(echo "$T" | grep -qE '^[0-9a-f]{64}$' && echo yes || echo "$T")"
check "asking again gives the same token" "$T" "$(rpc "$MARIA" my_calendar_feed_token '{}' | tr -d '"')"

echo "── the seed alone, by hand: one invitation"
check "200 with no apikey and no JWT" "200" "$(fetch "$T")"
check "Content-Type is text/calendar; charset=utf-8" "text/calendar; charset=utf-8" \
  "$(grep -i '^content-type:' "$TMP/head" | cut -d' ' -f2- | tr -d '\r')"
check "exactly one event" "1" "$(grep -c '^BEGIN:VEVENT' "$TMP/body")"
check "it is the invitation, marked Response Needed" "Evening Coed (Response Needed)" "$(summaries)"
check "tentative" "STATUS:TENTATIVE" "$(tr -d '\r' < "$TMP/body" | grep '^STATUS:')"
check "its UID is the registration" "UID:$INVITE@fxetennis" "$(tr -d '\r' < "$TMP/body" | grep '^UID:')"
check "DTSTART is the clinic's start in UTC" "DTSTART:$(utc starts_at "$EVENING")" "$(tr -d '\r' < "$TMP/body" | grep '^DTSTART:')"
check "DTEND is the clinic's end in UTC" "DTEND:$(utc ends_at "$EVENING")" "$(tr -d '\r' < "$TMP/body" | grep '^DTEND:')"
check "the calendar is called FXE Tennis" "X-WR-CALNAME:FXE Tennis" "$(tr -d '\r' < "$TMP/body" | grep '^X-WR-CALNAME:')"

echo "── Maria's week through the real RPCs"
# JSON bodies built outside the checks: inside "$( ... )" the escaped quotes
# left the braces unquoted, and bash's brace expansion split each body in two
# at its comma (the first run of this file).
body() { printf '{"p_clinic":"%s","p_player":"%s"%s}' "$1" "$MARIA_P" "${2:-}"; }
B_SAT=$(body "$SATURDAY"); B_TUE=$(body "$TUESDAY"); B_THU=$(body "$THURSDAY" ',"p_status":"in"')
check "Saturday Members Only: You're In!" "in" "$(rpc "$MARIA" register_for_clinic "$B_SAT" | field "['status']")"
check "Tuesday Ladies 3.0+: Player Pool" "pool" "$(rpc "$MARIA" register_for_clinic "$B_TUE" | field "['status']")"
check "Tara places her in Thursday Morning Cardio" "in" "$(rpc "$TARA" place_player "$B_THU" | field "['status']")"
SAT_REG=$(sql "select id from public.registrations where clinic_id = '$SATURDAY' and player_id = '$MARIA_P' and status = 'in'")
B_COURT=$(printf '{"p_registration":"%s","p_court":4}' "$SAT_REG")
rpc "$TARA" assign_court "$B_COURT" >/dev/null
check "Tara gives her court 4 on Saturday" "4" "$(sql "select court_number from public.registrations where id = '$SAT_REG'")"
B_CANCEL=$(printf '{"p_clinic":"%s"}' "$THURSDAY")
check "Tara cancels Thursday Morning Cardio" "canceled" "$(rpc "$TARA" cancel_clinic "$B_CANCEL" | field "['status']")"
# A clinic whose name needs every escape and a fold (added by hand: no admin
# screen lets Tara type a line break into a name, but the feed must survive one).
sql "insert into public.clinics (id, name, audience, category, description, starts_at, ends_at, member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
     values ('$ODD', E'Doubles, Drills; Games \\\\ Fun\nand a very long second line with café crème to make the summary fold', 'coed', 'Clinic',
             'Courts 1 to 4 behind the clubhouse', now() + interval '9 days', now() + interval '9 days 1 hour',
             now() - interval '2 days', now() - interval '1 day', 8, 'published', 60);
     insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
     values ('$ODD', '$MARIA_P', 'in', 'self', 1800, true, 60);" >/dev/null

echo "── what her calendar holds now"
check "200" "200" "$(fetch "$T")"
ODD_ESC='Doubles\, Drills\; Games \\ Fun\nand a very long second line with café crème to make the summary fold'
check "exactly her You're In! and Response Needed clinics (Pool and the canceled clinic absent)" \
  "$(printf '%s\n' "$ODD_ESC" "Evening Coed (Response Needed)" "Saturday Members Only" | sort | paste -sd '#' -)" "$(summaries)"
check "two confirmed, one tentative" "CONFIRMED CONFIRMED TENTATIVE" \
  "$(tr -d '\r' < "$TMP/body" | grep '^STATUS:' | cut -d: -f2 | sort | paste -sd ' ' -)"
check "Saturday's DTSTART is its start in UTC" "yes" \
  "$(unfolded | tr -d '\r' | grep -q "^DTSTART:$(utc starts_at "$SATURDAY")$" && echo yes || echo no)"
check "every time is UTC (YYYYMMDDTHHMMSSZ)" "" \
  "$(unfolded | tr -d '\r' | grep -E '^(DTSTART|DTEND|DTSTAMP):' | grep -vE ':[0-9]{8}T[0-9]{6}Z$')"
check "only these properties appear" "BEGIN CALSCALE DTEND DTSTAMP DTSTART END METHOD PRODID REFRESH-INTERVAL STATUS SUMMARY UID VERSION X-PUBLISHED-TTL X-WR-CALNAME" \
  "$(unfolded | tr -d '\r' | sed -E 's/[:;].*//' | sort -u | paste -sd ' ' -)"
check "no line starts LOCATION, URL or DESCRIPTION" "0" "$(unfolded | tr -d '\r' | grep -cE '^(LOCATION|URL|DESCRIPTION)[:;]')"
check "the word court is nowhere (court 4 is assigned)" "0" "$(grep -ci 'court' "$TMP/body")"
check "the description is not sent" "0" "$(grep -c 'clubhouse' "$TMP/body")"
check "every line ends CRLF" "yes" "$(python3 -c "
import sys; b=open(sys.argv[1],'rb').read()
print('yes' if b.endswith(b'\r\n') and b.count(b'\n') == b.count(b'\r\n') else 'no')" "$TMP/body")"
check "no line longer than 75 octets" "0" "$(python3 -c "
import sys; b=open(sys.argv[1],'rb').read()
print(sum(1 for l in b.split(b'\r\n') if len(l) > 75))" "$TMP/body")"
check "the long name was folded" "yes" "$(grep -q $'^ ' "$TMP/body" && echo yes || echo no)"

echo "── a spot she gives up leaves at the next fetch"
B_GIVEUP=$(printf '{"p_registration":"%s","p_note":null}' "$SAT_REG")
check "Maria cancels Saturday" "canceled" "$(rpc "$MARIA" cancel_registration "$B_GIVEUP" | field "['status']")"
fetch "$T" >/dev/null
check "Saturday is gone" "0" "$(grep -c 'Saturday Members Only' "$TMP/body")"

echo "── other people"
R=$(rpc "$ROB" my_calendar_feed_token '{}' | tr -d '"')
check "Rob gets his own token" "yes" "$([ ${#R} -eq 64 ] && [ "$R" != "$T" ] && echo yes || echo no)"
check "Rob's feed holds none of Maria's clinics" "200 0" "$(fetch "$R") $(grep -c '^BEGIN:VEVENT' "$TMP/body")"

echo "── refusals: a bare 404, one answer for all"
for bad in "$(printf '0%.0s' $(seq 64))" "abc" "$(echo "$T" | tr 'a-f' 'A-F')" "${T}0" ""; do
  code=$(fetch "$bad"); size=$(wc -c < "$TMP/body" | tr -d ' ')
  check "token '${bad:0:12}…' (${#bad} chars): 404, empty body" "404 0" "$code $size"
done
check "no t at all: 404, empty body" "404 0" \
  "$(curl -s -o "$TMP/body" -w '%{http_code}' "$FEED") $(wc -c < "$TMP/body" | tr -d ' ')"
NEW=$(rpc "$MARIA" reset_my_calendar_feed '{}' | tr -d '"')
check "reset gives a new token" "yes" "$([ ${#NEW} -eq 64 ] && [ "$NEW" != "$T" ] && echo yes || echo no)"
check "the old link is dead" "404" "$(fetch "$T")"
check "the new one works" "200" "$(fetch "$NEW")"
K=$(rpc "$KEN" my_calendar_feed_token '{}' | tr -d '"')
check "Ken's link works while he exists" "200" "$(fetch "$K")"
sql "update public.accounts set deleted_at = now() where id = '$KEN_ACC'" >/dev/null
check "a deleted account's link is 404, empty" "404 0" "$(fetch "$K") $(wc -c < "$TMP/body" | tr -d ' ')"
sql "update public.accounts set deleted_at = null where id = '$KEN_ACC'" >/dev/null
check "POST is 405" "405" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$FEED?t=$NEW")"
check "HEAD: 200 and no body" "200 0" "$(curl -s -I -o /dev/null -w '%{http_code} %{size_download}' "$FEED?t=$NEW")"

# Leave nothing behind.
sql "delete from public.notifications where created_at > '$START';
     delete from public.registrations where registered_at > '$START' and player_id = '$MARIA_P';
     delete from public.registrations where clinic_id = '$ODD';
     delete from public.clinics where id = '$ODD';
     update public.clinics set status = 'published', canceled_at = null where id = '$THURSDAY';
     delete from public.calendar_feeds where created_at > '$START';" >/dev/null
check "fixtures removed" "0 0 0 published" "$(sql "select (select count(*) from public.registrations where registered_at > '$START')
  || ' ' || (select count(*) from public.calendar_feeds) || ' ' || (select count(*) from public.notifications where created_at > '$START')
  || ' ' || (select status from public.clinics where id = '$THURSDAY')")"

if command -v deno >/dev/null 2>&1; then
  echo "── the iCalendar rules (deno test tests/calendar/ics.test.ts)"
  if out=$(deno test tests/calendar/ics.test.ts 2>&1); then
    echo "  PASS  $(echo "$out" | sed 's/\x1b\[[0-9;]*m//g' | grep -E 'passed' | tail -1)"
  else
    echo "$out" | tail -20; echo "  FAIL  ics.test.ts"; FAILED=1
  fi
fi

if [ $FAILED -eq 0 ]; then echo "Calendar feed: all checks passed."; else echo "Calendar feed: FAILURES above."; exit 1; fi
