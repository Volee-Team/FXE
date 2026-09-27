#!/bin/bash
# one_fee_race.sh
#
# 20260927100001: one fee per player per clinic, under concurrency. The unique
# index payments_one_live_charge is (registration_id, kind), so two charges of
# DIFFERENT kinds for the same player in the same clinic, at the same instant,
# share no key: each one's "is there a live fee?" read misses the other's
# uncommitted row, and both insert. Only the per player-and-clinic advisory
# lock in admin_charge_registration makes the second wait and then see the
# first.
#
# Session A charges Dana's row a clinic fee and holds its transaction open for
# three seconds; session B, one second later, charges the same row a no-show
# fee (the flip-and-tap race, or two admins at once). With the lock, B waits,
# then is refused already_charged. Without it, B inserts at once. The
# resulting state is asserted, not the error: exactly one live fee.
#
# It flips payments_enabled on and gives Dana a card for the run, and puts
# both back (and deletes its own rows) at the end.

set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111
DANA=66666666-6666-6666-6666-666666666666
DANA_P=a0000000-0000-0000-0000-000000000004

WAS_ON=$(psql -tAqc "select value from public.app_settings where key = 'payments_enabled'" | tr -d '[:space:]')
read -r OLD_CUS OLD_LAST4 <<<"$(psql -tAqc "select coalesce(stripe_customer_id, '-'), coalesce(card_last4, '-') from public.accounts where id = '$DANA'" | tr '|' ' ')"

CLINIC="$(psql -tAq <<SQL | tr -d '[:space:]'
update public.app_settings set value = 'true' where key = 'payments_enabled';
update public.accounts set stripe_customer_id = 'cus_race_dana', card_brand = 'visa', card_last4 = '4242' where id = '$DANA';
with c as (
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('RACE one fee', 'coed', 'Clinic', 'race probe', now() - interval '3 hours', now() - interval '2 hours',
          now() - interval '5 days', now() - interval '4 days', 8, 'published', 60)
  returning id)
select id from c;
SQL
)"
REG=$(psql -tAqc "insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values ('$CLINIC', '$DANA_P', 'in', 'self', 1800, true, 60) returning id" | head -1 | tr -d '[:space:]')

charge_as_tara() { # kind, seconds to hold the transaction open
  psql -tAq <<SQL 2>&1
begin;
select set_config('request.jwt.claims', '{"sub":"$TARA","role":"authenticated"}', true);
set local role authenticated;
select 'got ' || (public.admin_charge_registration('$REG', '$1')).kind;
select pg_sleep($2);
commit;
SQL
}

charge_as_tara clinic_fee 3 > /tmp/one_fee_race_a.out &
A=$!
sleep 1
B_OUT=$(charge_as_tara no_show 0)
wait $A
A_OUT=$(cat /tmp/one_fee_race_a.out); rm -f /tmp/one_fee_race_a.out

LIVE=$(psql -tAqc "select count(*) from public.payments
  where registration_id = '$REG' and kind <> 'refund' and status in ('pending', 'processing', 'succeeded')" | tr -d '[:space:]')

psql -q <<SQL >/dev/null
delete from public.payments where registration_id = '$REG';
delete from public.registrations where id = '$REG';
delete from public.clinics where id = '$CLINIC';
update public.app_settings set value = '$WAS_ON' where key = 'payments_enabled';
update public.accounts set stripe_customer_id = nullif('$OLD_CUS', '-'), card_last4 = nullif('$OLD_LAST4', '-'),
       card_brand = case when '$OLD_LAST4' = '-' then null else card_brand end where id = '$DANA';
SQL

echo "session A: $(echo "$A_OUT" | grep -oE 'got [a-z_]+|ERROR:.*' | head -1)"
echo "session B: $(echo "$B_OUT" | grep -oE 'got [a-z_]+|ERROR:.*' | head -1)"
if [ "$LIVE" = "1" ]; then
  echo "PASS: one live fee for the player in the clinic after two concurrent charges of different kinds"
  exit 0
fi
echo "FAIL: $LIVE live fees for one player in one clinic (expected 1)"
exit 1
