#!/bin/bash
# move_in_cancel_race.sh
#
# 20261104000001 (decision 0047): before clinic day, invite_from_pool moves a
# Waitlist player straight to You're In! and sends "You're all set". Its
# refusal on a canceled clinic is only as good as the clinic lock under it
# (FOR SHARE, taken before the conditional UPDATE). Without it, a Move In
# racing cancel_clinic reads the clinic before the cancel commits and leaves
# Ken in You're In! of a clinic that is not happening, holding a "You're all
# set" push (the sql-auditor, 2026-11-04). waitlist_move_in.sql and
# after_the_fact.sql run in one session and cannot see this.
#
#   Tara cancels the clinic and holds that transaction open for three
#   seconds; one second later she taps Move In on Ken's Waitlist row (a
#   second tab, the laptop and the phone). Ken must not end in You're In!,
#   no "You're all set" may be written, and the clinic stays canceled.
#
# The resulting rows are asserted, not the error (hard rule 9).
#
# Usage: bash tests/sql/move_in_cancel_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111
KEN_P=a0000000-0000-0000-0000-000000000002

CLINIC=$(psql -tAqc "
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('MOVE IN CANCEL RACE', 'coed', 'Clinic', 'race probe', now() + interval '5 days', now() + interval '5 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id;" | head -1 | tr -d '[:space:]')
# Ken is on the Waitlist, five days before the clinic: Move In territory.
REG=$(psql -tAqc "
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged,
      was_member, duration_minutes)
  values ('$CLINIC', '$KEN_P', 'pool', 'self', 1800, true, 60)
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

as_user "$TARA" "select 'canceled ' || (public.cancel_clinic('$CLINIC')).status;" 3 > "$TMP/a" &
A=$!
sleep 1
as_user "$TARA" "select 'moved ' || (public.invite_from_pool('$REG')).status;" 0 > "$TMP/b"
wait $A

KEN_NOW=$(psql -tAc "select status from public.registrations where id = '$REG';" | tr -d '[:space:]')
CLINIC_NOW=$(psql -tAc "select status from public.clinics where id = '$CLINIC';" | tr -d '[:space:]')
ALL_SET=$(psql -tAc "select count(*) from public.notifications where entity_id = '$REG' and type = 'youre_in';" | tr -d '[:space:]')

echo "  Tara's cancel  : $(grep -oE 'canceled [a-z_]+|ERROR:.*' "$TMP/a" | head -1)"
echo "  Tara's Move In : $(grep -oE 'moved [a-z_]+|ERROR:.*' "$TMP/b" | head -1)"
echo "  Ken now        : $KEN_NOW   (must not be in)"
echo "  clinic now     : $CLINIC_NOW   (must be canceled)"
echo "  all set sent   : $ALL_SET   (must be 0)"
echo ""

psql -q -c "delete from public.notifications where entity_id = '$REG' or entity_id = '$CLINIC';
            delete from public.registrations where clinic_id = '$CLINIC';
            delete from public.clinics where id = '$CLINIC';" >/dev/null
rm -rf "$TMP"

FAIL=0
[ "$KEN_NOW" != "in" ]         || { echo "FAIL: a Move In racing a cancel left Ken in a canceled clinic"; FAIL=1; }
[ "$CLINIC_NOW" = "canceled" ] || { echo "FAIL: the clinic is $CLINIC_NOW after the cancel"; FAIL=1; }
[ "$ALL_SET" = "0" ]           || { echo "FAIL: $ALL_SET \"You're all set\" for a canceled clinic"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: a Move In that races Tara's cancel waits for it and is refused"
exit $FAIL
