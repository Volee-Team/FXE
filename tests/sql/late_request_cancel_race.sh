#!/bin/bash
# late_request_cancel_race.sh
#
# 20261125000002: cancel_clinic tells a player whose late request is still
# waiting and closes the request. That holds only if a request filed while
# the cancel is in flight is seen by it. request_late_spot takes the clinic
# row FOR SHARE, so Tara's cancel (an UPDATE of that row) waits for the
# request to commit and then finds it. Without the lock the sql-auditor
# showed "clinic=canceled requests=pending rob_cancel_notices=0": Rob never
# told, and his request left waiting on a canceled clinic.
#
# Rob asks and holds his transaction 3 s; Tara cancels 1 s in.
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111
ROB=44444444-4444-4444-4444-444444444444
ROB_P=a0000000-0000-0000-0000-000000000003
CLINIC=$(psql -tAqc "
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status, duration_minutes, published_at)
  values ('Probe Late Request Cancel Race', 'coed', 'Clinic', 'probe', now() + interval '3 hours', now() + interval '4 hours',
          now() - interval '2 days', now() - interval '1 day', now() - interval '1 hour', 8, 'published', 60, now() - interval '2 days')
  returning id;" | head -1 | tr -d '[:space:]')
TMP=$(mktemp -d)
as_user() { psql -tAq <<SQL 2>&1
begin;
select set_config('request.jwt.claims', '{"sub":"$1","role":"authenticated"}', true);
set local role authenticated;
$2
select pg_sleep($3);
commit;
SQL
}
as_user "$ROB" "select 'requested ' || (public.request_late_spot('$CLINIC', '$ROB_P', 'probe')).status;" 3 > "$TMP/a" &
A=$!
sleep 1
as_user "$TARA" "select 'canceled ' || (public.cancel_clinic('$CLINIC', 'Rain')).status;" 0 > "$TMP/b"
wait $A

CLINIC_NOW=$(psql -tAc "select status from public.clinics where id = '$CLINIC';" | tr -d '[:space:]')
REQUESTS=$(psql -tAc "select coalesce(string_agg(status, ','), 'none') from public.late_requests where clinic_id = '$CLINIC';" | tr -d '[:space:]')
NOTICES=$(psql -tAc "select count(*) from public.notifications where account_id = '$ROB' and entity_id = '$CLINIC' and type = 'clinic_canceled';" | tr -d '[:space:]')

echo "  Rob's request : $(grep -oE 'requested [a-z_]+|ERROR:.*' "$TMP/a" | head -1)"
echo "  Tara's cancel : $(grep -oE 'canceled [a-z_]+|ERROR:.*' "$TMP/b" | head -1)"
echo "  clinic now    : $CLINIC_NOW   (must be canceled)"
echo "  requests      : $REQUESTS   (must be declined)"
echo "  Rob told      : $NOTICES   (must be 1)"
echo ""

psql -q -c "delete from public.notifications where entity_id = '$CLINIC';
            delete from public.clinic_messages where clinic_id = '$CLINIC';
            delete from public.late_requests where clinic_id = '$CLINIC';
            delete from public.clinics where id = '$CLINIC';" >/dev/null
rm -rf "$TMP"

FAIL=0
[ "$CLINIC_NOW" = "canceled" ] || { echo "FAIL: the clinic is $CLINIC_NOW after the cancel"; FAIL=1; }
[ "$REQUESTS" = "declined" ]   || { echo "FAIL: a request racing the cancel was left $REQUESTS"; FAIL=1; }
[ "$NOTICES" = "1" ]           || { echo "FAIL: Rob got $NOTICES cancel notices, not 1"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: a late request that races Tara's cancel is seen by it, told and closed"
exit $FAIL
