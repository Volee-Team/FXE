#!/bin/bash
# declined_card_race.sh
#
# 20260928700001, from the rule (decision 0026): a decline stands only if no
# charge ATTEMPTED after it has gone through. Stripe delivers events
# concurrently, so the success of a later attempt and the failure of an
# earlier one can be recorded at the same moment in two transactions. The
# failure must see the success once it commits: payments_card_decline locks
# the account row before deciding, so its decision is a new statement with a
# fresh snapshot. Without the lock the failure's check reads a snapshot taken
# before the success committed, and the player is blocked though a later
# charge went through.
#
#   A: Maria's clinic fee, attempted an hour ago, goes through; A holds its
#      transaction open for two seconds.
#   B: one second later, her no-show fee, attempted two hours ago, fails with
#      insufficient_funds.
# The account must end with no decline. The resulting state is asserted.
#
# It makes its own clinic, registration and payments, and deletes them after.

set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
MARIA=22222222-2222-2222-2222-222222222222
MARIA_P=a0000000-0000-0000-0000-000000000001

read -r CLINIC REG S F <<<"$(psql -tAq -F' ' <<SQL
with c as (
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('RACE declined card', 'coed', 'Clinic', 'race probe', now() - interval '5 days', now() - interval '5 days' + interval '1 hour',
          now() - interval '12 days', now() - interval '11 days', 8, 'published', 60) returning id),
r as (
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  select id, '$MARIA_P', 'in', 'admin', 1800, true, 60 from c returning id, clinic_id),
s as (
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  select id, '$MARIA', 'clinic_fee', 1800, 'processing', now() - interval '1 hour' from r returning id),
f as (
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, first_attempted_at)
  select id, '$MARIA', 'no_show', 1800, 'processing', now() - interval '2 hours' from r returning id)
select (select clinic_id from r), (select id from r), (select id from s), (select id from f);
SQL
)"
SAVED="$(psql -tAq -c "select coalesce(card_last4,'')||'|'||coalesce(card_added_at::text,'') from public.accounts where id='$MARIA'")"
psql -q -c "update public.accounts set stripe_customer_id=coalesce(stripe_customer_id,'cus_race'), card_brand='visa', card_last4='4242', card_added_at=now() - interval '10 days' where id='$MARIA'; update public.accounts set card_declined_at=null, card_decline_code=null where id='$MARIA';" >/dev/null

psql -q <<SQL >/dev/null 2>&1 &
begin;
update public.payments set status = 'succeeded', livemode = true where id = '$S';
select pg_sleep(2);
commit;
SQL
A=$!
sleep 1
psql -q -c "update public.payments set status = 'failed', failure_code = 'insufficient_funds', failure_reason = 'race' where id = '$F';" >/dev/null 2>&1
wait $A

GOT="$(psql -tAq -c "select coalesce(card_decline_code,'clear') from public.accounts where id='$MARIA'")"

psql -q >/dev/null <<SQL
delete from public.payments where registration_id = '$REG';
delete from public.registrations where id = '$REG';
delete from public.clinics where id = '$CLINIC';
update public.accounts set stripe_customer_id=null, card_brand=null, card_last4=nullif(split_part('$SAVED','|',1),''),
       card_added_at=nullif(split_part('$SAVED','|',2),'')::timestamptz where id='$MARIA';
update public.accounts set card_declined_at=null, card_decline_code=null where id='$MARIA';
SQL

if [ "$GOT" = "clear" ]; then
  echo "PASS declined_card_race: a failure recorded while a later-attempted success commits leaves the card clear"
else
  echo "FAIL declined_card_race: expected clear, got $GOT"
  exit 1
fi
