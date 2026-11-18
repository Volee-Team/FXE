#!/bin/bash
# remove_child_race.sh
#
# 20261118000002 (decision 0061, Review): a parent's Remove of a child and a
# booking for that child, from two devices at once. remove_my_child takes the
# child FOR UPDATE and then refuses while the child holds an upcoming spot or
# a pending late request; register_for_clinic, request_late_spot and the
# Accept of respond_to_invitation read the child FOR KEY SHARE and only while
# active. The two locks conflict, so whichever goes first, the other sees it.
# Without them, a booking that read the child before the removal committed
# would leave an archived child holding a spot nobody can see or cancel.
#
#   Three pairs, each in both orders: Remove vs Register, Remove vs Accept
#   (Tara's invitation), Remove vs a late request. The first holds its
#   transaction open for three seconds; the second starts one second in.
#
# THE INVARIANT, asserted on the rows (hard rule 9), never on the errors: a
# child is never archived while holding a live spot or a pending late
# request. And the expected winner: whoever went first.
#
# Usage: bash tests/sql/remove_child_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
MARIA=22222222-2222-2222-2222-222222222222
TMP=$(mktemp -d)
FAIL=0

# Her junior text, for the length of the script (the child must be signed).
HAD_SETTING=$(psql -tAc "select count(*) from public.app_settings where key = 'junior_waiver_version';" | tr -d '[:space:]')
OLD_SETTING=$(psql -tAc "select value from public.app_settings where key = 'junior_waiver_version';" | tr -d '[:space:]')
psql -q -c "insert into public.waivers (version, kind, title, organizer, body)
            values ('juniors-race', 'junior', 'Race Waiver', 'Race', 'race text') on conflict do nothing;
            insert into public.app_settings (key, value) values ('junior_waiver_version', 'juniors-race')
            on conflict (key) do update set value = excluded.value;" >/dev/null

CLINIC=$(psql -tAqc "
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('REMOVE CHILD RACE', 'juniors', 'Clinic', 'race probe', now() + interval '5 days', now() + interval '5 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id;" | head -1 | tr -d '[:space:]')
LATE=$(psql -tAqc "
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes)
  values ('REMOVE CHILD RACE LATE', 'juniors', 'Clinic', 'race probe', now() + interval '2 hours', now() + interval '3 hours',
          now() - interval '2 days', now() - interval '1 day', now() - interval '1 minute', 8, 'published', 60)
  returning id;" | head -1 | tr -d '[:space:]')

as_maria() { # statement, seconds to hold the transaction open
  psql -tAq <<SQL 2>&1
begin;
select set_config('request.jwt.claims', '{"sub":"$MARIA","role":"authenticated"}', true);
set local role authenticated;
$1
select pg_sleep($2);
commit;
SQL
}

new_child() { # name -> id, signed
  psql -tAq <<SQL | sed -n 's/^KID://p' | head -1
begin;
select set_config('request.jwt.claims', '{"sub":"$MARIA","role":"authenticated"}', true);
select 'KID:' || id from public.add_my_child('$1', 'Race', date '2016-01-01');
select public.accept_child_waiver((select id from public.players where account_id = '$MARIA' and first_name = '$1' and is_active), 'juniors-race', 'Maria Race');
commit;
SQL
}

state() { # child -> "active|live spots|pending late requests"
  psql -tAc "select p.is_active::text || '|' ||
      (select count(*) from public.registrations r where r.player_id = p.id and r.status in ('in','pool','response_needed')) || '|' ||
      (select count(*) from public.late_requests l where l.player_id = p.id and l.status = 'pending')
    from public.players p where p.id = '$1';" | tr -d '[:space:]'
}

race() { # label, first statement, second statement, expected state
  local label=$1 first=$2 second=$3 want=$4 got
  as_maria "$first" 3 > "$TMP/a" &
  local A=$!
  sleep 1
  as_maria "$second" 0 > "$TMP/b"
  wait $A
  got=$(state "$KID")
  printf '  %-34s first: %-28s second: %-28s state %s (want %s)\n' "$label" \
    "$(grep -oE 'ERROR: +[a-z_]+|done' "$TMP/a" | head -1)" "$(grep -oE 'ERROR: +[a-z_]+|done' "$TMP/b" | head -1)" "$got" "$want"
  case "$got" in false\|0\|0) ;; false*) echo "FAIL: $label left an archived child holding something"; FAIL=1 ;; esac
  [ "$got" = "$want" ] || { echo "FAIL: $label ended $got, expected $want"; FAIL=1; }
}


# 1. Remove first, Register second: the registration waits, then finds no active child.
KID=$(new_child RaceOne)
race "remove, then register" "select public.remove_my_child('$KID'); select 'done';" \
     "select (public.register_for_clinic('$CLINIC', '$KID', null)).status; select 'done';" "false|0|0"
# 2. Register first, Remove second: the removal waits, then sees the spot.
KID=$(new_child RaceTwo)
race "register, then remove" "select (public.register_for_clinic('$CLINIC', '$KID', null)).status; select 'done';" \
     "select public.remove_my_child('$KID'); select 'done';" "true|1|0"
# 3. Remove first, late request second.
KID=$(new_child RaceThree)
race "remove, then ask late" "select public.remove_my_child('$KID'); select 'done';" \
     "select (public.request_late_spot('$LATE', '$KID', null)).status; select 'done';" "false|0|0"
# 4. Late request first, Remove second.
KID=$(new_child RaceFour)
race "ask late, then remove" "select (public.request_late_spot('$LATE', '$KID', null)).status; select 'done';" \
     "select public.remove_my_child('$KID'); select 'done';" "true|0|1"
# 5 and 6. Tara's invitation: Accept vs Remove, both orders. The invitation is
# itself a live spot, so the removal is refused either way and the Accept lands.
KID=$(new_child RaceFive)
REG=$(psql -tAqc "insert into public.registrations (clinic_id, player_id, status, source) values ('$CLINIC', '$KID', 'response_needed', 'admin') returning id;" | head -1 | tr -d '[:space:]')
race "accept, then remove" "select (public.respond_to_invitation('$REG', true)).status; select 'done';" \
     "select public.remove_my_child('$KID'); select 'done';" "true|1|0"
KID=$(new_child RaceSix)
REG=$(psql -tAqc "insert into public.registrations (clinic_id, player_id, status, source) values ('$CLINIC', '$KID', 'response_needed', 'admin') returning id;" | head -1 | tr -d '[:space:]')
race "remove, then accept" "select public.remove_my_child('$KID'); select 'done';" \
     "select (public.respond_to_invitation('$REG', true)).status; select 'done';" "true|1|0"

psql -q <<SQL >/dev/null
delete from public.notifications where entity_id in (select id from public.registrations where clinic_id in ('$CLINIC', '$LATE'))
   or entity_id in ('$CLINIC', '$LATE');
delete from public.late_requests where clinic_id in ('$CLINIC', '$LATE');
delete from public.registrations where clinic_id in ('$CLINIC', '$LATE');
delete from public.clinics where id in ('$CLINIC', '$LATE');
delete from public.junior_waiver_acceptances where version = 'juniors-race';
delete from public.players where account_id = '$MARIA' and kind = 'junior' and last_name = 'Race';
update public.accounts set account_type = 'adult' where id = '$MARIA'
   and not exists (select 1 from public.players where account_id = '$MARIA' and kind = 'junior');
SQL
if [ "$HAD_SETTING" = "1" ]; then
  psql -q -c "update public.app_settings set value = '$OLD_SETTING' where key = 'junior_waiver_version';" >/dev/null
else
  psql -q -c "delete from public.app_settings where key = 'junior_waiver_version';" >/dev/null
fi
psql -q -c "delete from public.waivers where version = 'juniors-race';" >/dev/null
rm -rf "$TMP"

echo ""
[ "$FAIL" -eq 0 ] && echo "PASS: a Remove and a booking for the same child, either order, never leave an archived child holding a spot or a request"
exit $FAIL
