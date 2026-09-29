#!/bin/bash
# pro_mark_race.sh
#
# The pro's two marks (20260928600001, decision 0025) against what can change
# under them while they wait. tests/sql/pro_role.sql runs in one session and
# cannot interleave anything, so three guards were reachable only here (the
# sql-auditor, 2026-09-28):
#
#   1. Tara cancels today's clinic and holds that transaction open; the pro
#      marks a No-show a second later. The mark takes the clinic row FOR
#      SHARE, so it waits, then sees "canceled" and is refused. Without the
#      lock it ran at once and marked a clinic that was being canceled.
#   2. A fee lands on Lena's row while the pro's mark waits for that row: the
#      pro must hear clinic_locked, the word every row of a charged clinic
#      gets, never charged_refund_first, which would say who was charged.
#   3. A fee lands on Lena's row while the pro's mark waits for PRIYA's row
#      (no card, never charged): the mark goes through on her row, then the
#      second look sees the clinic charged and undoes it. Without the second
#      look Priya's row was markable a moment after Lena's was not.
#
# The fee in 2 and 3 is written by a session that holds the row lock, standing
# in for admin_charge_clinic, which takes the same row lock (hard rule 9: the
# resulting rows are asserted, not the error alone).
#
# Usage: bash tests/sql/pro_mark_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111
CASEY=77777777-7777-7777-7777-777777777777   # the seeded pro
LENA=88888888-8888-8888-8888-888888888888
LENA_P=a0000000-0000-0000-0000-000000000007
PRIYA_P=a0000000-0000-0000-0000-000000000005

# Casey is a pro through Tara's own switch (the seed does this; a probe that
# ran after a hand change must not fail for that reason).
psql -tAq -c "select set_config('request.jwt.claims', '{\"sub\":\"$TARA\"}', false);
              select public.admin_set_pro('$CASEY', true);" >/dev/null

new_clinic() { # name
  psql -tAqc "
    insert into public.clinics (name, audience, category, description, starts_at, ends_at,
        member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
    values ('$1', 'coed', 'Clinic', 'race probe', now(), now() + interval '1 hour',
            now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
    returning id;" | head -1 | tr -d '[:space:]'
}
new_in() { # clinic, player
  psql -tAqc "
    insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged,
        was_member, duration_minutes)
    values ('$1', '$2', 'in', 'self', 1800, true, 60)
    returning id;" | head -1 | tr -d '[:space:]'
}

C1=$(new_clinic 'PRO RACE CANCEL');  R1=$(new_in "$C1" "$LENA_P")
C2=$(new_clinic 'PRO RACE CHARGED'); R2=$(new_in "$C2" "$LENA_P")
C3=$(new_clinic 'PRO RACE BESIDE');  R3L=$(new_in "$C3" "$LENA_P"); R3P=$(new_in "$C3" "$PRIYA_P")

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
# As the owner: lock one row as a charge would, write a live fee on another
# (or the same) row, hold, commit.
fee_while_holding() { # row to hold, row to charge, seconds
  psql -tAq <<SQL 2>&1
begin;
select id from public.registrations where id = '$1' for update;
insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, stripe_payment_intent_id)
values ('$2', '$LENA', 'clinic_fee', 1800, 'succeeded', true, 'pi_pro_race_' || md5(random()::text));
select pg_sleep($3);
commit;
SQL
}
mark() { # registration -> "ok" or the error's word
  local out
  out=$(as_user "$CASEY" "select public.pro_set_no_show('$1', true);" 0)
  echo "$out" | grep -oE 'ERROR: +[a-z_]+' | sed -E 's/ERROR: +//' | head -1 | grep . || echo ok
}

# 1. cancel in flight
as_user "$TARA" "select (public.cancel_clinic('$C1')).status;" 3 > "$TMP/a" &
A=$!; sleep 1
T0=$(date +%s)
M1=$(mark "$R1")
T1=$(date +%s)
wait $A
# 2. a fee on the same row, in flight
fee_while_holding "$R2" "$R2" 3 > "$TMP/b" &
B=$!; sleep 1
M2=$(mark "$R2")
wait $B
# 3. a fee on Lena's row while the pro waits for Priya's
fee_while_holding "$R3P" "$R3L" 3 > "$TMP/c" &
C=$!; sleep 1
M3=$(mark "$R3P")
wait $C

S1=$(psql -tAc "select c.status || ':' || r.no_show from public.registrations r join public.clinics c on c.id = r.clinic_id where r.id = '$R1';" | tr -d '[:space:]')
S2=$(psql -tAc "select no_show::text from public.registrations where id = '$R2';" | tr -d '[:space:]')
S3=$(psql -tAc "select no_show::text from public.registrations where id = '$R3P';" | tr -d '[:space:]')

echo "  1 cancel in flight : pro heard '$M1' after $((T1 - T0))s; clinic:no_show now $S1   (must be clinic_canceled, waited, canceled:false)"
echo "  2 fee on the row   : pro heard '$M2'; Lena no_show $S2   (must be clinic_locked, false)"
echo "  3 fee beside it    : pro heard '$M3'; Priya no_show $S3   (must be clinic_locked, false)"
echo ""

psql -q -c "delete from public.payments where registration_id in ('$R1', '$R2', '$R3L', '$R3P');
            delete from public.notifications where entity_id in ('$C1', '$C2', '$C3', '$R1', '$R2', '$R3L', '$R3P');
            delete from public.registrations where clinic_id in ('$C1', '$C2', '$C3');
            delete from public.clinics where id in ('$C1', '$C2', '$C3');" >/dev/null
rm -rf "$TMP"

FAIL=0
[ "$M1" = "clinic_canceled" ]   || { echo "FAIL: a mark racing a cancel answered '$M1'"; FAIL=1; }
# With the lock the mark waits about 2 s (the cancel holds 3 s and the mark
# starts 1 s in); without it, only docker's own overhead, which reached 1 s
# on 2026-09-28 and so passed a threshold of 1.
[ $((T1 - T0)) -ge 2 ]          || { echo "FAIL: the mark did not wait for the cancel (no clinic lock)"; FAIL=1; }
[ "$S1" = "canceled:false" ]    || { echo "FAIL: after the race the clinic and row are $S1"; FAIL=1; }
[ "$M2" = "clinic_locked" ]     || { echo "FAIL: a mark on a row charged meanwhile answered '$M2'"; FAIL=1; }
[ "$S2" = "false" ]             || { echo "FAIL: the charged row was marked"; FAIL=1; }
[ "$M3" = "clinic_locked" ]     || { echo "FAIL: a mark beside a fresh charge answered '$M3'"; FAIL=1; }
[ "$S3" = "false" ]             || { echo "FAIL: the uncharged row of a clinic charged meanwhile was marked"; FAIL=1; }
[ "$FAIL" -eq 0 ] && echo "PASS: a pro's mark waits for Tara's cancel, and a charge in flight locks every row of the clinic alike"
exit $FAIL
