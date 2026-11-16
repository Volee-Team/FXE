#!/bin/bash
# court_booking_race.sh
#
# Court reservations under a rush, the way phones make it (decision 0058):
# signed-in members calling book_court through the API (PostgREST) at the
# same moment, modelled on rush_via_api.sh.
#
#   1. N members, one slot: court 3, two days out at 7:00 PM New York, 60
#      minutes. Exactly 1 booking; every other answer is a refusal that says
#      court_taken; nothing answers 500.
#   2. One member, five courts at once, the same slot three days out.
#      Exactly 1 booking (1 a day); the rest say day_limit or court_taken.
#
# The exclusion constraint alone would pass 1; 2 needs the advisory lock
# (two bookings on different courts never overlap, so only the lock stops
# both counting "0 today" at once).
#
# Local only (no fixtures in hosted, ever). The JWT secret and keys come from
# `supabase status` into variables and are never printed. courts_live is set
# on for the run and put back after, and the probe accounts removed, by an
# EXIT trap, so a run that dies halfway leaves nothing behind.
#
# Usage: bash tests/sql/court_booking_race.sh [members]   (default 50)
set -uo pipefail
N=${1:-50}
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }

ENV=$(supabase status -o env 2>/dev/null)
API=${FXE_API_URL:-$(echo "$ENV" | sed -n 's/^API_URL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')}
ANON=$(echo "$ENV" | sed -n 's/^ANON_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
SECRET=$(echo "$ENV" | sed -n 's/^JWT_SECRET="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
[ -n "$API" ] && [ -n "$ANON" ] && [ -n "$SECRET" ] || { echo "No local API settings from supabase status"; exit 2; }

WAS_LIVE=$(psql -tAc "select value from public.app_settings where key = 'courts_live';" | tr -d '[:space:]')
[ -n "$WAS_LIVE" ] || { echo "FAIL: no courts_live setting (is 20261116000001 applied?)"; exit 1; }
TMP=""
cleanup() {
  psql -q -c "delete from public.court_bookings b using public.accounts a where a.id = b.account_id and a.email like 'courter%@probe.test';" >/dev/null 2>&1
  psql -q -c "delete from auth.users where email like 'courter%@probe.test';" >/dev/null 2>&1
  psql -q -c "update public.app_settings set value = '$WAS_LIVE' where key = 'courts_live';" >/dev/null 2>&1
  [ -n "$TMP" ] && rm -rf "$TMP"
}
trap cleanup EXIT
psql -q -c "update public.app_settings set value = 'true' where key = 'courts_live';" >/dev/null

SLOT1=$(psql -tAc "select to_json((((now() at time zone 'America/New_York')::date + 2) + time '19:00') at time zone 'America/New_York')#>>'{}';" | tr -d '[:space:]')
SLOT2=$(psql -tAc "select to_json((((now() at time zone 'America/New_York')::date + 3) + time '10:00') at time zone 'America/New_York')#>>'{}';" | tr -d '[:space:]')

echo "Setting up: $N members for one slot, then one member for five courts"
psql -q <<SQL
do \$\$
declare i int; uid uuid;
begin
  for i in 1..$N loop
    uid := gen_random_uuid();
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                            email_confirmed_at, created_at, updated_at)
    values (uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'courter' || i || '@probe.test', 'x', now(), now(), now());
    insert into public.accounts (id, first_name, last_name, email, role)
    values (uid, 'Courter', i::text, 'courter' || i || '@probe.test', 'member');
    insert into public.players (account_id, kind, first_name, last_name, adult_rating, is_member)
    values (uid, 'adult', 'Courter', i::text, '3.5', true);
  end loop;
end \$\$;
SQL

TMP=$(mktemp -d)
psql -tA -c "select a.id from public.accounts a where a.email like 'courter%@probe.test' order by a.email;" > "$TMP/ids"
SECRET="$SECRET" python3 - "$TMP/ids" "$TMP" <<'PY'
import base64, hashlib, hmac, json, os, sys, time
secret = os.environ["SECRET"].encode()
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
for n, uid in enumerate(l.strip() for l in open(sys.argv[1]) if l.strip()):
    body = b64(json.dumps({"sub": uid, "role": "authenticated", "aud": "authenticated",
                           "exp": int(time.time()) + 3600}).encode())
    sig = b64(hmac.new(secret, f"{head}.{body}".encode(), hashlib.sha256).digest())
    open(f"{sys.argv[2]}/t{n}", "w").write(f"{head}.{body}.{sig}")
PY
unset SECRET

book() {  # token file, court, slot, output prefix
  curl -s -o "$4.body" -w '%{http_code}\n' -X POST "$API/rest/v1/rpc/book_court" \
    -H "apikey: $ANON" -H "Authorization: Bearer $(cat "$1")" -H "Content-Type: application/json" \
    -d "{\"p_court\":$2,\"p_starts_at\":\"$3\",\"p_minutes\":60}" > "$4.res"
}

# 1. Everyone at court 3, at once.
for f in "$TMP"/t*; do
  case "$(basename "$f")" in *.*) continue;; esac
  book "$f" 3 "$SLOT1" "$f.r1" &
done
wait
OK1=$(cat "$TMP"/*.r1.res | awk '$1 == 200' | wc -l | tr -d ' ')
BAD1=$(cat "$TMP"/*.r1.res | awk '$1 >= 500' | wc -l | tr -d ' ')
CODES1=$(cat "$TMP"/*.r1.res | sort | uniq -c | tr '\n' ' ')
REFUSED1=$(grep -l 'court_taken' "$TMP"/*.r1.body 2>/dev/null | wc -l | tr -d ' ')
ROWS1=$(psql -tAc "select count(*) from public.court_bookings b join public.accounts a on a.id = b.account_id
                    where a.email like 'courter%@probe.test' and b.status = 'booked' and b.starts_at = '$SLOT1';")

# 2. The first member at all five courts, at once.
for c in 1 2 3 4 5; do
  book "$TMP/t0" "$c" "$SLOT2" "$TMP/t0.c$c.r2" &
done
wait
OK2=$(cat "$TMP"/*.r2.res | awk '$1 == 200' | wc -l | tr -d ' ')
BAD2=$(cat "$TMP"/*.r2.res | awk '$1 >= 500' | wc -l | tr -d ' ')
REFUSED2=$(grep -lE 'day_limit|court_taken' "$TMP"/*.r2.body 2>/dev/null | wc -l | tr -d ' ')
ROWS2=$(psql -tAc "select count(*) from public.court_bookings b join public.accounts a on a.id = b.account_id
                    where a.email like 'courter%@probe.test' and b.status = 'booked' and b.starts_at = '$SLOT2';")

echo ""
echo "  1. $N members, one slot   : answers $CODES1"
echo "     bookings                : $ROWS1   (must be exactly 1)"
echo "     refused court_taken     : $REFUSED1   (must be $((N - 1)))"
echo "  2. one member, five courts : $OK2 answered 200, $REFUSED2 refused"
echo "     bookings                : $ROWS2   (must be exactly 1)"
echo ""

FAIL=0
[ "$ROWS1" = "1" ]             || { echo "FAIL: $ROWS1 bookings on one slot, expected 1"; FAIL=1; }
[ "$OK1" = "1" ]               || { echo "FAIL: $OK1 answered 200 on one slot, expected 1"; FAIL=1; }
[ "$REFUSED1" = "$((N - 1))" ] || { echo "FAIL: $REFUSED1 refused court_taken, expected $((N - 1))"; FAIL=1; }
[ "$BAD1" = "0" ] && [ "$BAD2" = "0" ] || { echo "FAIL: $BAD1 and $BAD2 answers were 5xx"; FAIL=1; }
[ "$ROWS2" = "1" ]             || { echo "FAIL: $ROWS2 bookings for one member on one day, expected 1"; FAIL=1; }
[ "$OK2" = "1" ] && [ "$REFUSED2" = "4" ] || { echo "FAIL: one member's five: $OK2 ok, $REFUSED2 refused (expected 1 and 4)"; FAIL=1; }
[ "$FAIL" = "0" ] && echo "PASS: $N members on one slot and one member on five courts, exactly 1 booking each"
exit $FAIL
