#!/bin/bash
# accept_full_race.sh
#
# 20261109000001 (decision 0054, Tara's item 11): a player's Accept is refused
# once You're In! plus guests is at capacity, and that refusal is only as good
# as the lock under it. respond_to_invitation takes the clinic row FOR UPDATE
# on an Accept, so a second Accept for the last spot waits for the first and
# then counts it. With the old FOR SHARE (two share locks do not conflict)
# both read one free spot and both land in You're In!: one over the cap that
# Tara never chose. tara_items_0054.sql cannot see this: it runs in one
# session.
#
#   Room for 2, Ken in. Rob and Dana each hold an invitation sent while
#   there was room. Rob accepts and holds his transaction open for three
#   seconds; Dana accepts one second later. Exactly one of them ends In, the
#   other is still invited, and the clinic holds 2.
#
# The resulting rows are asserted, not the error (hard rule 9).
#
# Usage: bash tests/sql/accept_full_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
ROB=44444444-4444-4444-4444-444444444444
DANA=66666666-6666-6666-6666-666666666666
KEN_P=a0000000-0000-0000-0000-000000000002
ROB_P=a0000000-0000-0000-0000-000000000003
DANA_P=a0000000-0000-0000-0000-000000000004

CLINIC=$(psql -tAqc "
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('ACCEPT FULL RACE', 'coed', 'Clinic', 'race probe', now() + interval '5 days', now() + interval '5 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 2, 'published', 60)
  returning id;" | head -1 | tr -d '[:space:]')
psql -tAqc "
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values ('$CLINIC', '$KEN_P', 'in', 'self', 1800, true, 60);" >/dev/null
REG_ROB=$(psql -tAqc "
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged,
      was_member, duration_minutes, invited_at)
  values ('$CLINIC', '$ROB_P', 'response_needed', 'self', 2300, false, 60, now())
  returning id;" | head -1 | tr -d '[:space:]')
REG_DANA=$(psql -tAqc "
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged,
      was_member, duration_minutes, invited_at)
  values ('$CLINIC', '$DANA_P', 'response_needed', 'self', 1800, true, 60, now())
  returning id;" | head -1 | tr -d '[:space:]')

TMP=$(mktemp -d)
as_user() { # account, statement, seconds to hold the transaction open
  psql -tAq <<SQL 2>&1
begin;
select set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true);
set local role authenticated;
$2
select pg_sleep($3);
commit;
SQL
}

as_user "$ROB" "select 'accepted ' || (public.respond_to_invitation('$REG_ROB', true)).status;" 3 > "$TMP/a" &
A=$!
sleep 1
as_user "$DANA" "select 'accepted ' || (public.respond_to_invitation('$REG_DANA', true)).status;" 0 > "$TMP/b"
wait $A

IN_NOW=$(psql -tAc "select count(*) from public.registrations where clinic_id = '$CLINIC' and status = 'in';" | tr -d '[:space:]')
STILL=$(psql -tAc "select count(*) from public.registrations where id in ('$REG_ROB', '$REG_DANA') and status = 'response_needed';" | tr -d '[:space:]')

echo "  Rob's Accept  : $(grep -oE 'accepted [a-z_]+|ERROR:.*' "$TMP/a" | head -1)"
echo "  Dana's Accept : $(grep -oE 'accepted [a-z_]+|ERROR:.*' "$TMP/b" | head -1)"
echo "  You're In! now: $IN_NOW   (must be 2)"
echo "  still invited : $STILL   (must be 1)"
echo ""

psql -q -c "delete from public.notifications where entity_id in ('$REG_ROB', '$REG_DANA') or entity_id = '$CLINIC';
            delete from public.registrations where clinic_id = '$CLINIC';
            delete from public.clinics where id = '$CLINIC';" >/dev/null
rm -rf "$TMP"

FAIL=0
[ "$IN_NOW" = "2" ] || { echo "FAIL: two Accepts for the last spot left $IN_NOW in a clinic of 2"; FAIL=1; }
[ "$STILL" = "1" ]  || { echo "FAIL: $STILL invitations still open (one must be)"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: two Accepts for the last spot take it once"
exit $FAIL
