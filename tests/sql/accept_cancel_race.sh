#!/bin/bash
# accept_cancel_race.sh
#
# 20260928300001: respond_to_invitation refuses an Accept once the clinic is
# canceled, and the refusal is only as good as the lock under it. The
# function takes the clinic row FOR SHARE before its conditional UPDATE, so a
# cancel_clinic still in flight (an UPDATE of that row) makes the Accept wait
# and then see "canceled". Without the lock, or with a weaker FOR KEY SHARE,
# the Accept reads the clinic before the cancel commits and lands the player
# in You're In! of a clinic that is not happening (the sql-auditor showed it
# in a lab copy: "clinic=canceled rob=in", and Rob told both "has been
# canceled" and "Your spot is confirmed"). tests/sql/after_the_fact.sql and
# notification_copy.sql cannot see this: they run in one session.
#
#   Tara cancels the clinic and holds that transaction open for three
#   seconds; Rob taps Accept one second later. He must end in Response
#   Needed with no acceptance written anywhere, and the clinic canceled.
#
# The resulting rows are asserted, not the error (hard rule 9).
#
# Usage: bash tests/sql/accept_cancel_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111
ROB=44444444-4444-4444-4444-444444444444
ROB_P=a0000000-0000-0000-0000-000000000003

CLINIC=$(psql -tAqc "
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('ACCEPT CANCEL RACE', 'coed', 'Clinic', 'race probe', now() + interval '5 days', now() + interval '5 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id;" | head -1 | tr -d '[:space:]')
# Rob holds an invitation, as invite_from_pool leaves it.
REG=$(psql -tAqc "
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged,
      was_member, duration_minutes, invited_at)
  values ('$CLINIC', '$ROB_P', 'response_needed', 'self', 2300, false, 60, now())
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
as_user "$ROB" "select 'accepted ' || (public.respond_to_invitation('$REG', true)).status;" 0 > "$TMP/b"
wait $A

ROB_NOW=$(psql -tAc "select status from public.registrations where id = '$REG';" | tr -d '[:space:]')
CLINIC_NOW=$(psql -tAc "select status from public.clinics where id = '$CLINIC';" | tr -d '[:space:]')
ACCEPTS=$(psql -tAc "select count(*) from public.notifications where entity_id = '$REG'
  and type in ('invitation_accepted', 'invitation_accepted_player');" | tr -d '[:space:]')

echo "  Tara's cancel : $(grep -oE 'canceled [a-z_]+|ERROR:.*' "$TMP/a" | head -1)"
echo "  Rob's Accept  : $(grep -oE 'accepted [a-z_]+|ERROR:.*' "$TMP/b" | head -1)"
echo "  Rob now       : $ROB_NOW   (must be response_needed)"
echo "  clinic now    : $CLINIC_NOW   (must be canceled)"
echo "  acceptances   : $ACCEPTS   (must be 0)"
echo ""

psql -q -c "delete from public.notifications where entity_id = '$REG' or entity_id = '$CLINIC';
            delete from public.registrations where clinic_id = '$CLINIC';
            delete from public.clinics where id = '$CLINIC';" >/dev/null
rm -rf "$TMP"

FAIL=0
[ "$ROB_NOW" = "response_needed" ] || { echo "FAIL: an Accept racing a cancel left Rob $ROB_NOW"; FAIL=1; }
[ "$CLINIC_NOW" = "canceled" ]     || { echo "FAIL: the clinic is $CLINIC_NOW after the cancel"; FAIL=1; }
[ "$ACCEPTS" = "0" ]               || { echo "FAIL: $ACCEPTS acceptance notifications for a canceled clinic"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: an Accept that races Tara's cancel waits for it and is refused"
exit $FAIL
