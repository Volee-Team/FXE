#!/bin/bash
# membership_accept_race.sh
#
# 20261118000002 (decision 0061, Review, second pass): Tara flips a member's
# membership while that member taps Accept on her invitation. Tara's switch
# updates the players row (a FOR NO KEY UPDATE lock) and then
# follow_membership locks the member's clinics; the Accept locks the clinic
# and then reads the player. When that read was FOR SHARE it waited for
# Tara's row lock while she waited for the clinic: a deadlock, and Postgres
# killed one of the two. FOR KEY SHARE does not conflict with an update that
# leaves the key alone, so both go through. (It still conflicts with
# remove_my_child's FOR UPDATE: remove_child_race.sh.)
#
#   Tara (as the owner, the way admin_set_membership's statements run)
#   updates Maria's membership, waits two seconds, then follows it; Maria's
#   Accept starts one second in.
#
# Asserted on the rows: Maria's spot is You're In!, her membership is the
# new value, and neither session hit a deadlock.
#
# Usage: bash tests/sql/membership_accept_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
MARIA=22222222-2222-2222-2222-222222222222
MARIA_P=a0000000-0000-0000-0000-000000000001
TMP=$(mktemp -d)

WAS=$(psql -tAc "select is_member from public.players where id = '$MARIA_P';" | tr -d '[:space:]')
CLINIC=$(psql -tAqc "
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('MEMBERSHIP ACCEPT RACE', 'coed', 'Clinic', 'race probe', now() + interval '5 days', now() + interval '5 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id;" | head -1 | tr -d '[:space:]')
REG=$(psql -tAqc "
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values ('$CLINIC', '$MARIA_P', 'response_needed', 'admin', 1800, true, 60)
  returning id;" | head -1 | tr -d '[:space:]')

psql -tAq > "$TMP/a" 2>&1 <<SQL &
begin;
update public.players set is_member = not is_member where id = '$MARIA_P';
select pg_sleep(2);
select 'followed ' || public.follow_membership('$MARIA_P');
commit;
SQL
A=$!
sleep 1
psql -tAq > "$TMP/b" 2>&1 <<SQL
begin;
select set_config('request.jwt.claims', '{"sub":"$MARIA","role":"authenticated"}', true);
set local role authenticated;
select 'accepted ' || (public.respond_to_invitation('$REG', true)).status;
commit;
SQL
wait $A

SPOT=$(psql -tAc "select status from public.registrations where id = '$REG';" | tr -d '[:space:]')
NOW=$(psql -tAc "select is_member from public.players where id = '$MARIA_P';" | tr -d '[:space:]')
DEAD=$(cat "$TMP/a" "$TMP/b" | grep -c 'deadlock detected')

echo "  Tara's switch  : $(grep -oE 'followed [0-9]+|ERROR:.*' "$TMP/a" | head -1)"
echo "  Maria's Accept : $(grep -oE 'accepted [a-z_]+|ERROR:.*' "$TMP/b" | head -1)"
echo "  spot now       : $SPOT   (must be in)"
echo "  member now     : $NOW   (was $WAS; must have flipped)"
echo "  deadlocks      : $DEAD   (must be 0)"
echo ""

psql -q -c "update public.players set is_member = '$WAS'::boolean where id = '$MARIA_P';
            delete from public.notifications where entity_id = '$REG' or entity_id = '$CLINIC';
            delete from public.registrations where clinic_id = '$CLINIC';
            delete from public.clinics where id = '$CLINIC';" >/dev/null
rm -rf "$TMP"

FAIL=0
[ "$SPOT" = "in" ]    || { echo "FAIL: Maria's Accept did not land ($SPOT)"; FAIL=1; }
[ "$NOW" != "$WAS" ]  || { echo "FAIL: Tara's membership change did not land"; FAIL=1; }
[ "$DEAD" = "0" ]     || { echo "FAIL: a deadlock killed one of the two"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: Tara's membership switch and the member's Accept, at once, both go through"
exit $FAIL
