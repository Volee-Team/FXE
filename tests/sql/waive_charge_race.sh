#!/bin/bash
# waive_charge_race.sh
#
# Tara's Waive (admin_set_fee_waived, decision 0040) and her Charge tap
# (admin_charge_player) on the same late cancel at the same instant. The
# sql-auditor (2026-10-12) showed that as a single UPDATE the Waive read its
# check on a snapshot from before the Charge committed: both could commit,
# leaving a pending charge on a row her screen calls "Fee waived". Two races,
# asserted on the rows that result (hard rule 9):
#
#   A. A Charge on Ken's late cancel is held open; a Waive lands one second
#      later. Ken must end charged and NOT waived.
#   B. A Waive on Rob's late cancel is held open; a Charge lands one second
#      later. Rob must end waived with NO payment.
#
# The invariant over both: no registration is waived and charged at once.
#
# Usage: bash tests/sql/waive_charge_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111
KEN=33333333-3333-3333-3333-333333333333
ROB=44444444-4444-4444-4444-444444444444
KEN_P=a0000000-0000-0000-0000-000000000002
ROB_P=a0000000-0000-0000-0000-000000000003

WAS_ON=$(psql -tAc "select value from public.app_settings where key = 'payments_enabled';" | tr -d '[:space:]')
WAS_AT=$(psql -tAc "select coalesce((select value from public.app_settings where key = 'payments_enabled_at'), '<none>');" | tr -d '\n')
psql -q <<SQL >/dev/null
update public.app_settings set value = 'true' where key = 'payments_enabled';
insert into public.app_settings (key, value) values ('payments_enabled_at', (now() - interval '10 days')::text)
  on conflict (key) do update set value = excluded.value;
update public.accounts set stripe_customer_id = 'cus_wrace_' || left(id::text, 4), card_brand = 'visa', card_last4 = '4242'
 where id in ('$KEN', '$ROB');
SQL

new_clinic() {
  psql -tAqc "
    insert into public.clinics (name, audience, category, description, starts_at, ends_at,
        member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
    values ('WAIVE RACE $1', 'coed', 'Clinic', 'race probe', now() - interval '3 hours', now() - interval '2 hours',
            now() - interval '5 days', now() - interval '4 days', 8, 'published', 60)
    returning id;" | head -1 | tr -d '[:space:]'
}
late_cancel() {
  psql -tAqc "
    insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
        late_cancel, canceled_at)
    values ('$1', '$2', 'canceled', 'self', 1800, true, 60, true, now() - interval '4 hours') returning id;" | head -1 | tr -d '[:space:]'
}
CA=$(new_clinic a); RA=$(late_cancel "$CA" "$KEN_P")
CB=$(new_clinic b); RB=$(late_cancel "$CB" "$ROB_P")

TMP=$(mktemp -d)
as_tara() { # statement, seconds to hold the transaction open
  psql -tAq <<SQL 2>&1
begin;
select set_config('request.jwt.claims', '{"sub":"$TARA","role":"authenticated"}', true);
set local role authenticated;
$1
select pg_sleep($2);
commit;
SQL
}
race() { # holder statement, lander statement, label
  as_tara "$1" 3 > "$TMP/$3.a" &
  local A=$!
  sleep 1
  as_tara "$2" 0 > "$TMP/$3.b"
  wait $A
}
race "select (public.admin_charge_player('$RA'))->>'kind';" "select public.admin_set_fee_waived('$RA', true);" a
race "select public.admin_set_fee_waived('$RB', true);" "select (public.admin_charge_player('$RB'))->>'kind';" b

state() { psql -tAc "select (r.fee_waived_at is not null)::text || ',' || (select count(*) from public.payments p where p.registration_id = r.id)::text from public.registrations r where r.id = '$1';" | tr -d '[:space:]'; }
SA=$(state "$RA"); SB=$(state "$RB")
BOTH=$(psql -tAc "select count(*) from public.registrations r where r.id in ('$RA', '$RB') and r.fee_waived_at is not null and public.registration_has_live_fee(r.id);" | tr -d '[:space:]')

for k in a b; do
  echo "  race $k: held -> $(grep -oE 'late_cancel|"fee_waived": [a-z]+|ERROR:.*' "$TMP/$k.a" | head -1); landed -> $(grep -oE 'late_cancel|"fee_waived": [a-z]+|ERROR:.*' "$TMP/$k.b" | head -1)"
done
echo "  Ken (Charge held, Waive landed): waived,payments = $SA   (must be false,1)"
echo "  Rob (Waive held, Charge landed): waived,payments = $SB   (must be true,0)"
echo "  waived and charged at once: $BOTH   (must be 0)"
echo ""

psql -q <<SQL >/dev/null
delete from public.payments where registration_id in ('$RA', '$RB');
delete from public.notifications where entity_id in ('$RA', '$RB', '$CA', '$CB');
delete from public.registrations where clinic_id in ('$CA', '$CB');
delete from public.clinics where id in ('$CA', '$CB');
update public.accounts set stripe_customer_id = null, card_brand = null, card_last4 = null where id in ('$KEN', '$ROB');
update public.app_settings set value = '$WAS_ON' where key = 'payments_enabled';
SQL
if [ "$WAS_AT" = "<none>" ]; then
  psql -q -c "delete from public.app_settings where key = 'payments_enabled_at';" >/dev/null
else
  psql -q -c "update public.app_settings set value = '$WAS_AT' where key = 'payments_enabled_at';" >/dev/null
fi
rm -rf "$TMP"

FAIL=0
[ "$SA" = "false,1" ] || { echo "FAIL: a Waive racing a Charge left Ken at $SA"; FAIL=1; }
[ "$SB" = "true,0" ] || { echo "FAIL: a Charge racing a Waive left Rob at $SB"; FAIL=1; }
[ "$BOTH" = "0" ] || { echo "FAIL: $BOTH registration(s) waived and charged at once"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: a Waive and a Charge on one late cancel never both land"
exit $FAIL
