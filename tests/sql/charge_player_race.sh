#!/bin/bash
# charge_player_race.sh
#
# admin_charge_player (20261002000001, decision 0037) decides what a person
# owes and charges it under two locks: the clinic FOR SHARE, then the
# registration FOR UPDATE. charge_each_player.sql runs in one session and
# cannot see whether those locks hold (sql-auditor, 2026-10-04: removing
# either left every check green). Three races, each asserted on the rows
# that result, never on an error (hard rule 9):
#
#   1. Tara removes Casey (the sick player) and holds that transaction open;
#      a Charge tap on Casey lands one second later. Casey must end canceled
#      with no payment.
#   2. Tara marks Ken a no-show and holds it open; a Charge tap on Ken lands
#      one second later. Ken's one payment must be the no_show fee.
#   3. Tara cancels a clinic (a rain-out) and holds it open; a Charge tap on
#      Maria in that clinic lands one second later. No payment.
#
# Without the registration lock, 1 charges Casey and 2 charges a clinic_fee;
# without the clinic lock, 3 charges Maria for a canceled clinic.
#
# Usage: bash tests/sql/charge_player_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111
MARIA=22222222-2222-2222-2222-222222222222
KEN=33333333-3333-3333-3333-333333333333
CASEY=77777777-7777-7777-7777-777777777777
MARIA_P=a0000000-0000-0000-0000-000000000001
KEN_P=a0000000-0000-0000-0000-000000000002
CASEY_P=a0000000-0000-0000-0000-000000000006

# What the settings were, so they can be put back exactly.
WAS_ON=$(psql -tAc "select value from public.app_settings where key = 'payments_enabled';" | tr -d '[:space:]')
WAS_AT=$(psql -tAc "select coalesce((select value from public.app_settings where key = 'payments_enabled_at'), '<none>');" | tr -d '\n')
psql -q <<SQL >/dev/null
update public.app_settings set value = 'true' where key = 'payments_enabled';
insert into public.app_settings (key, value) values ('payments_enabled_at', (now() - interval '10 days')::text)
  on conflict (key) do update set value = excluded.value;
update public.accounts set stripe_customer_id = 'cus_race_' || left(id::text, 4), card_brand = 'visa', card_last4 = '4242'
 where id in ('$MARIA', '$KEN', '$CASEY');
SQL

new_clinic() {
  psql -tAqc "
    insert into public.clinics (name, audience, category, description, starts_at, ends_at,
        member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
    values ('CHARGE RACE $1', 'coed', 'Clinic', 'race probe', now() - interval '3 hours', now() - interval '2 hours',
            now() - interval '5 days', now() - interval '4 days', 8, 'published', 60)
    returning id;" | head -1 | tr -d '[:space:]'
}
put_in() {
  psql -tAqc "
    insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
    values ('$1', '$2', 'in', 'self', 1800, true, 60) returning id;" | head -1 | tr -d '[:space:]'
}
C1=$(new_clinic one);   R1=$(put_in "$C1" "$CASEY_P")
C2=$(new_clinic two);   R2=$(put_in "$C2" "$KEN_P")
C3=$(new_clinic three); R3=$(put_in "$C3" "$MARIA_P")

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
race() { # holder statement, charged registration, label
  as_tara "$1" 3 > "$TMP/$3.a" &
  local A=$!
  sleep 1
  as_tara "select 'charged ' || ((public.admin_charge_player('$2'))->>'kind');" 0 > "$TMP/$3.b"
  wait $A
}

race "select public.cancel_registration('$R1', null);" "$R1" one
race "select public.admin_set_no_show('$R2', true);" "$R2" two
race "select (public.cancel_clinic('$C3')).status;" "$R3" three

R1_STATUS=$(psql -tAc "select status from public.registrations where id = '$R1';" | tr -d '[:space:]')
R1_PAID=$(psql -tAc "select count(*) from public.payments where registration_id = '$R1';" | tr -d '[:space:]')
R2_KINDS=$(psql -tAc "select coalesce(string_agg(kind::text, ',' order by created_at), 'none') from public.payments where registration_id = '$R2';" | tr -d '[:space:]')
C3_STATUS=$(psql -tAc "select status from public.clinics where id = '$C3';" | tr -d '[:space:]')
R3_PAID=$(psql -tAc "select count(*) from public.payments where registration_id = '$R3';" | tr -d '[:space:]')

for k in one two three; do
  echo "  race $k: charge -> $(grep -oE 'charged [a-z_]+|ERROR:.*' "$TMP/$k.b" | head -1)"
done
echo "  Casey removed while charged : $R1_STATUS, $R1_PAID payments   (must be canceled, 0)"
echo "  Ken marked no-show          : $R2_KINDS   (must be no_show)"
echo "  clinic canceled while charged: $C3_STATUS, $R3_PAID payments   (must be canceled, 0)"
echo ""

psql -q <<SQL >/dev/null
delete from public.payments where registration_id in ('$R1', '$R2', '$R3');
delete from public.notifications where entity_id in ('$R1', '$R2', '$R3', '$C1', '$C2', '$C3');
delete from public.registrations where clinic_id in ('$C1', '$C2', '$C3');
delete from public.clinics where id in ('$C1', '$C2', '$C3');
update public.accounts set stripe_customer_id = null, card_brand = null, card_last4 = null
 where id in ('$MARIA', '$KEN', '$CASEY');
update public.app_settings set value = '$WAS_ON' where key = 'payments_enabled';
SQL
if [ "$WAS_AT" = "<none>" ]; then
  psql -q -c "delete from public.app_settings where key = 'payments_enabled_at';" >/dev/null
else
  psql -q -c "update public.app_settings set value = '$WAS_AT' where key = 'payments_enabled_at';" >/dev/null
fi
rm -rf "$TMP"

FAIL=0
[ "$R1_STATUS" = "canceled" ] && [ "$R1_PAID" = "0" ] || { echo "FAIL: Casey was removed and still charged ($R1_STATUS, $R1_PAID)"; FAIL=1; }
[ "$R2_KINDS" = "no_show" ] || { echo "FAIL: Ken was marked a no-show and charged $R2_KINDS"; FAIL=1; }
[ "$C3_STATUS" = "canceled" ] && [ "$R3_PAID" = "0" ] || { echo "FAIL: a charge landed on a clinic being canceled ($C3_STATUS, $R3_PAID)"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: a Charge tap that races a removal, a no-show or a cancel waits for it"
exit $FAIL
