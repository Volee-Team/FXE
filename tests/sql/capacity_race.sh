#!/bin/bash
# capacity_race.sh
#
# The Thursday 8:00 AM race, tested for real.
#
# Member priority is the only place in this app where software decides capacity
# instead of Tara. If register_for_clinic did check-then-insert without locking
# the clinic row, concurrent registrations would overfill the clinic. That bug
# would appear on the most popular clinic, at the exact moment everyone is
# watching, and it would be intermittent.
#
# SQL alone cannot test this: a single session is serial by definition. So this
# fires N genuinely concurrent psql processes at one capacity-1 clinic and
# asserts exactly one of them lands in You're In!.
#
# Usage: bash tests/sql/capacity_race.sh [concurrency]   (default 12)

set -uo pipefail
N=${1:-12}
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}

psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }

echo "Setting up: 1 clinic, capacity 1, $N member players all registering at once"

CLINIC=$(psql -tAqc "
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('RACE PROBE', 'coed', now() + interval '3 days', now() + interval '3 days 1 hour',
      now() - interval '1 hour', now() + interval '12 hours', 1, 'published')
  returning id;" | head -1 | tr -d '[:space:]')

# Distinct member players, each with their own account, so every racer is a
# legitimately separate authenticated user rather than one user retrying.
psql -q <<SQL
do \$\$
declare i int; uid uuid; pid uuid;
begin
  for i in 1..$N loop
    uid := gen_random_uuid();
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                            email_confirmed_at, created_at, updated_at)
    values (uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'racer' || i || '@probe.test', 'x', now(), now(), now());
    insert into public.accounts (id, first_name, last_name, email, role)
    values (uid, 'Racer', i::text, 'racer' || i || '@probe.test', 'member');
    insert into public.players (account_id, kind, first_name, last_name, adult_rating, is_member)
    values (uid, 'adult', 'Racer', i::text, '3.5', true);
  end loop;
end \$\$;
SQL

# Fire all N at once. Each blocks on the clinic row lock inside the function,
# which is exactly the contention we want to exercise.
TMP=$(mktemp -d)
for i in $(seq 1 "$N"); do
  (
    psql -tAc "
      select set_config('request.jwt.claims',
        json_build_object('sub', a.id)::text, false)
      from public.accounts a where a.email = 'racer$i@probe.test';
      select (public.register_for_clinic('$CLINIC',
        (select p.id from public.players p
          join public.accounts a on a.id = p.account_id
         where a.email = 'racer$i@probe.test'))).status;
    " > "$TMP/r$i" 2>&1
  ) &
done
wait

IN=$(psql -tAc "select count(*) from public.registrations where clinic_id = '$CLINIC' and status = 'in';")
POOL=$(psql -tAc "select count(*) from public.registrations where clinic_id = '$CLINIC' and status = 'pool';")
TOTAL=$(psql -tAc "select count(*) from public.registrations where clinic_id = '$CLINIC';")

echo ""
echo "  concurrent registrations : $N"
echo "  status = in              : $IN   (must be exactly 1)"
echo "  status = pool            : $POOL"
echo "  total rows               : $TOTAL   (must equal $N: nobody silently lost)"
echo ""

# Clean up the probe's own rows only.
psql -q -c "delete from public.registrations where clinic_id = '$CLINIC';" >/dev/null
psql -q -c "delete from public.clinics where id = '$CLINIC';" >/dev/null
psql -q -c "delete from auth.users where email like 'racer%@probe.test';" >/dev/null
rm -rf "$TMP"

FAIL=0
[ "$IN" = "1" ]     || { echo "FAIL: capacity 1 clinic ended up with $IN confirmed players"; FAIL=1; }
[ "$TOTAL" = "$N" ] || { echo "FAIL: expected $N rows, got $TOTAL"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: exactly one You're In!, everyone else in the Player Pool, nobody lost"
exit $FAIL
