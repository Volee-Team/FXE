#!/bin/bash
# place_player_race.sh
#
# 20260928000001, and the sql-auditor's finding of 2026-09-28: place_player
# sends Tara's #1 ("You're all set for ...") only when the placement is what
# put the player in, and it can tell that exactly only because it takes two
# locks. A single-session probe cannot see either, so this races them for
# real, one scenario per lock. The resulting rows are asserted, not errors
# (hard rule 9).
#
#   1. Two taps on Put in clinic. The first place_player(clinic, Dana, 'in')
#      holds its transaction open for three seconds; the second, a second
#      later, waits on the clinic row (FOR UPDATE), then sees Dana already in
#      and sends nothing. Without that lock the second finds no row, lands on
#      ON CONFLICT DO UPDATE once the first commits, and sends #1 again.
#   2. An Accept in flight. Priya accepts her invitation and holds that
#      transaction open for three seconds; Tara's place_player(clinic, Priya,
#      'in'), a second later, waits on Priya's row (FOR UPDATE), then sees her
#      in and sends nothing: Priya gets her #3 and not #1 as well. Without that
#      lock Tara's read still sees Response Needed and #1 goes out on top.
#
# Usage: bash tests/sql/place_player_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111
PRIYA=55555555-5555-5555-5555-555555555555
DANA_P=a0000000-0000-0000-0000-000000000004
PRIYA_P=a0000000-0000-0000-0000-000000000005

CLINIC=$(psql -tAqc "
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('PLACE RACE', 'coed', 'Clinic', 'race probe', now() + interval '6 days', now() + interval '6 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id;" | head -1 | tr -d '[:space:]')
# Priya holds an invitation, as invite_from_pool leaves it.
PRIYA_REG=$(psql -tAqc "
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged,
      was_member, duration_minutes, invited_at)
  values ('$CLINIC', '$PRIYA_P', 'response_needed', 'self', 2300, false, 60, now())
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

# ---- 1. Two taps
as_user "$TARA" "select 'placed ' || (public.place_player('$CLINIC', '$DANA_P', 'in')).status;" 3 > "$TMP/a" &
A=$!
sleep 1
as_user "$TARA" "select 'placed ' || (public.place_player('$CLINIC', '$DANA_P', 'in')).status;" 0 > "$TMP/b"
wait $A

# ---- 2. An Accept in flight, then Tara's placement
as_user "$PRIYA" "select 'accepted ' || (public.respond_to_invitation('$PRIYA_REG', true)).status;" 3 > "$TMP/c" &
C=$!
sleep 1
as_user "$TARA" "select 'placed ' || (public.place_player('$CLINIC', '$PRIYA_P', 'in')).status;" 0 > "$TMP/d"
wait $C

DANA_LIVE=$(psql -tAc "select count(*) from public.registrations where clinic_id = '$CLINIC' and player_id = '$DANA_P'
  and status in ('in', 'pool', 'response_needed');" | tr -d '[:space:]')
DANA_ONE=$(psql -tAc "select count(*) from public.notifications n join public.registrations r on r.id = n.entity_id
  where r.clinic_id = '$CLINIC' and r.player_id = '$DANA_P' and n.type = 'youre_in';" | tr -d '[:space:]')
PRIYA_TOLD=$(psql -tAc "select coalesce(string_agg(n.type, ',' order by n.type), 'nothing') from public.notifications n
  where n.account_id = '$PRIYA' and n.entity_id = '$PRIYA_REG';" | tr -d '[:space:]')

echo "  two taps, first  : $(grep -oE 'placed [a-z_]+|ERROR:.*' "$TMP/a" | head -1)"
echo "  two taps, second : $(grep -oE 'placed [a-z_]+|ERROR:.*' "$TMP/b" | head -1)"
echo "  Dana live rows   : $DANA_LIVE   (must be 1)"
echo "  Dana's #1 rows   : $DANA_ONE   (must be 1: the second tap sends nothing)"
echo "  Priya's accept   : $(grep -oE 'accepted [a-z_]+|ERROR:.*' "$TMP/c" | head -1)"
echo "  Tara's placement : $(grep -oE 'placed [a-z_]+|ERROR:.*' "$TMP/d" | head -1)"
echo "  Priya was told   : $PRIYA_TOLD   (must be invitation_accepted_player: #3, not #1 as well)"
echo ""

# Clean up the probe's own rows only: the notifications about its
# registrations first (Dana and Priya are seeded players, so nothing
# cascades), then the registrations and the clinic.
psql -q -c "delete from public.notifications where entity_id in (select id from public.registrations where clinic_id = '$CLINIC');
            delete from public.registrations where clinic_id = '$CLINIC';
            delete from public.clinics where id = '$CLINIC';" >/dev/null
rm -rf "$TMP"

FAIL=0
[ "$DANA_LIVE" = "1" ] || { echo "FAIL: Dana holds $DANA_LIVE live rows after two taps"; FAIL=1; }
[ "$DANA_ONE" = "1" ]  || { echo "FAIL: two taps sent Dana $DANA_ONE You're In notifications"; FAIL=1; }
[ "$PRIYA_TOLD" = "invitation_accepted_player" ] || { echo "FAIL: Priya was told '$PRIYA_TOLD'"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: one You're In per placement under a double tap, and none on top of an Accept in flight"
exit $FAIL
