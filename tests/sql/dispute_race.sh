#!/bin/bash
# dispute_race.sh
#
# 20260928200001: stripe_record_dispute under concurrency. Stripe can deliver
# two events for one dispute at once (it does not wait for one delivery to be
# answered before sending the next). The order guard (an event older than the
# one recorded changes nothing) is in the UPDATE's WHERE, so when two
# deliveries touch the same row the second waits for the first's lock and
# then checks the guard again against the committed row. A version that reads
# the stored event time first and updates after would let the older event,
# committing second, win.
#
# Both events are OPEN statuses on purpose: Stripe's created event
# (needs_response, 11:00) arriving alongside the later updated event
# (under_review, 12:00, evidence submitted). With a decided status in the race
# the other guard (a decided dispute is never reopened, also in the WHERE)
# would hide a broken order guard: the first draft of this probe raced "lost"
# against "under_review" and stayed green under a read-then-write mutant.
#
# Two rounds on one fee, each two sessions:
#   1. A records under_review (12:00) and holds its transaction open for two
#      seconds; B, one second later, records needs_response (11:00).
#   2. The same with the roles swapped: A holds the older event, B the newer.
# Either way the row must end under_review at 12:00. The resulting state is
# asserted, not the answers.
#
# It makes its own clinic, registration and payment, and deletes them at the end.

set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
PRIYA=55555555-5555-5555-5555-555555555555
PRIYA_P=a0000000-0000-0000-0000-000000000005
PI="pi_race_dispute_$RANDOM$RANDOM"

CLINIC="$(psql -tAq <<SQL | tr -d '[:space:]'
with c as (
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('RACE dispute', 'coed', 'Clinic', 'race probe', now() - interval '5 days', now() - interval '5 days' + interval '1 hour',
          now() - interval '12 days', now() - interval '11 days', 8, 'published', 60)
  returning id)
select id from c;
SQL
)"
REG=$(psql -tAqc "insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values ('$CLINIC', '$PRIYA_P', 'in', 'self', 2300, false, 60) returning id" | head -1 | tr -d '[:space:]')
PAY=$(psql -tAqc "insert into public.payments (registration_id, account_id, kind, amount_cents, status, stripe_payment_intent_id, livemode)
  values ('$REG', '$PRIYA', 'clinic_fee', 2300, 'succeeded', '$PI', true) returning id" | head -1 | tr -d '[:space:]')

record() { # status, event hour, seconds to hold the transaction open
  psql -tAq <<SQL 2>&1
begin;
set local role service_role;
select 'answered ' || public.stripe_record_dispute('$PI', 'dp_race', '$1', 'fraudulent', 2300, 2300,
  timestamptz '2026-09-20 08:00+00', timestamptz '2026-10-01 23:59:59+00', timestamptz '2026-09-20 $2:00+00');
select pg_sleep($3);
commit;
SQL
}
state() { psql -tAqc "select coalesce(dispute_status, 'NULL') || '@' || coalesce(to_char(dispute_event_at at time zone 'UTC', 'HH24:MI'), 'NULL') from public.payments where id = '$PAY'" | tr -d '[:space:]'; }
fresh() { psql -qc "update public.payments set stripe_dispute_id = null, dispute_status = null, dispute_reason = null,
  dispute_amount_cents = null, dispute_withdrawn_cents = null, disputed_at = null, dispute_due_by = null, dispute_event_at = null
  where id = '$PAY'" >/dev/null; }

# Round 1: the newer event holds the row; the older one waits, then is stale.
record under_review 12 2 > /tmp/dispute_race_a.out &
A=$!; sleep 1
B1=$(record needs_response 11 0); wait $A
A1=$(cat /tmp/dispute_race_a.out)
R1=$(state)

# Round 2: the older event holds the row; the newer one waits, then lands.
fresh
record needs_response 11 2 > /tmp/dispute_race_a.out &
A=$!; sleep 1
B2=$(record under_review 12 0); wait $A
A2=$(cat /tmp/dispute_race_a.out); rm -f /tmp/dispute_race_a.out
R2=$(state)

psql -q <<SQL >/dev/null
delete from public.payments where registration_id = '$REG';
delete from public.registrations where id = '$REG';
delete from public.clinics where id = '$CLINIC';
SQL

echo "round 1: A (under_review 12:00) $(echo "$A1" | grep -oE 'answered [a-z_]+|ERROR:.*' | head -1); B (needs_response 11:00) $(echo "$B1" | grep -oE 'answered [a-z_]+|ERROR:.*' | head -1); row $R1"
echo "round 2: A (needs_response 11:00) $(echo "$A2" | grep -oE 'answered [a-z_]+|ERROR:.*' | head -1); B (under_review 12:00) $(echo "$B2" | grep -oE 'answered [a-z_]+|ERROR:.*' | head -1); row $R2"
if [ "$R1" = "under_review@12:00" ] && [ "$R2" = "under_review@12:00" ]; then
  echo "PASS: two concurrent deliveries of one dispute leave the newer event's state, in either order"
  exit 0
fi
echo "FAIL: expected under_review@12:00 after both rounds, got $R1 and $R2"
exit 1
