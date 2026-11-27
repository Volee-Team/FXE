#!/bin/bash
# private_register_race.sh
#
# 20261127000003: on a private clinic, register_for_clinic refuses anyone
# not on it (clinic_not_found) and answers already_registered to someone on
# it, so a player's own call never adds a row. The other way of writing it,
# "on it, so let them through", fails when Tara's removal of that player
# commits during the sign-up: the insert waits on registrations_one_live,
# then succeeds, and the removed player is back on a private clinic (the
# sql-auditor, 2026-11-27).
#
# Tara's removal of Maria is held open 3 s; Maria registers 1 s in.
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
MARIA=22222222-2222-2222-2222-222222222222
MARIA_P=a0000000-0000-0000-0000-000000000001
CLINIC=$(psql -tAqc "
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, published_at, is_private)
  values ('Probe Private Register Race', 'coed', 'Clinic', 'probe', now() + interval '3 days', now() + interval '3 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60, now() - interval '2 days', true)
  returning id;" | head -1 | tr -d '[:space:]')
psql -q -c "insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
            values ('$CLINIC', '$MARIA_P', 'in', 'admin', 1800, true, 60);" >/dev/null
TMP=$(mktemp -d)
psql -tAq > "$TMP/a" 2>&1 <<SQL &
begin;
update public.registrations set status = 'canceled', canceled_at = now()
 where clinic_id = '$CLINIC' and player_id = '$MARIA_P';
select pg_sleep(3);
commit;
SQL
A=$!
sleep 1
psql -tAq > "$TMP/b" 2>&1 <<SQL
begin;
select set_config('request.jwt.claims', '{"sub":"$MARIA","role":"authenticated"}', true);
set local role authenticated;
select 'registered ' || (public.register_for_clinic('$CLINIC', '$MARIA_P', null)).status;
commit;
SQL
wait $A

LIVE=$(psql -tAc "select count(*) from public.registrations where clinic_id = '$CLINIC' and player_id = '$MARIA_P' and status <> 'canceled';" | tr -d '[:space:]')
echo "  Maria's register : $(grep -oE 'registered [a-z_]+|ERROR:.*' "$TMP/b" | head -1)"
echo "  live rows after  : $LIVE   (must be 0)"
echo ""

psql -q -c "delete from public.notifications where entity_id = '$CLINIC';
            delete from public.payments where registration_id in (select id from public.registrations where clinic_id = '$CLINIC');
            delete from public.registrations where clinic_id = '$CLINIC';
            delete from public.clinics where id = '$CLINIC';" >/dev/null
rm -rf "$TMP"

if [ "$LIVE" = "0" ]; then
  echo "PASS: a removal racing a sign-up on a private clinic leaves the player off it"
  exit 0
fi
echo "FAIL: the removed player is back on the private clinic ($LIVE live rows)"
exit 1
