#!/bin/bash
# child_lock_race.sh
#
# 20261118000002 (decision 0061, Review, second pass): once Tara approves or
# declines a program for a child, the parent cannot rename the child or
# change the birthday (child_locked). That check is only as good as the
# lock under it: update_my_child takes the child FOR UPDATE, and Tara's
# admin_decide_program_approval and admin_preapprove_program take it
# FOR KEY SHARE first. Without Tara's lock, a rename that started while her
# decision was uncommitted saw the request still open, and both committed:
# Tara's approval then belonged to a renamed child.
#
#   Tara approves and holds her transaction open for three seconds; the
#   parent renames the child one second in. Then the same with Tara's
#   preapproval. The rename must wait and then be refused, so the child
#   keeps the name Tara approved.
#   The other order (rename first, then Tara) is not a hole: she decides on
#   the child as renamed, and the script checks that too.
#
# Asserted on the rows (hard rule 9).
#
# Usage: bash tests/sql/child_lock_race.sh
set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111
MARIA=22222222-2222-2222-2222-222222222222
ELITE=$(psql -tAc "select id from public.junior_programs where name = 'Elite';" | tr -d '[:space:]')
TMP=$(mktemp -d)
FAIL=0

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
new_child() { # first name -> id; the parent asks for Elite
  psql -tAq <<SQL | sed -n 's/^KID://p' | head -1
begin;
select set_config('request.jwt.claims', '{"sub":"$MARIA","role":"authenticated"}', true);
select 'KID:' || id from public.add_my_child('$1', 'Lockrace', date '2014-01-01');
select public.request_program_approval((select id from public.players where account_id = '$MARIA' and first_name = '$1' and is_active), '$ELITE');
commit;
SQL
}
state() {
  psql -tAc "select p.first_name || '|' || coalesce((select a.status from public.program_approvals a where a.player_id = p.id and a.program_id = '$ELITE'), 'none')
               from public.players p where p.id = '$1';" | tr -d '[:space:]'
}
race() { # label, first account, first statement, second account, second statement, expected
  as_user "$2" "$3" 3 > "$TMP/a" &
  local A=$!
  sleep 1
  as_user "$4" "$5" 0 > "$TMP/b"
  wait $A
  local got; got=$(state "$KID")
  printf '  %-30s first: %-24s second: %-24s state %s (want %s)\n' "$1" \
    "$(grep -oE 'ERROR: +[a-z_]+|done' "$TMP/a" | head -1)" "$(grep -oE 'ERROR: +[a-z_]+|done' "$TMP/b" | head -1)" "$got" "$6"
  [ "$got" = "$6" ] || { echo "FAIL: $1 ended $got, expected $6"; FAIL=1; }
}

KID=$(new_child Decided)
race "Tara approves, then rename" "$TARA" "select public.admin_decide_program_approval('$KID', '$ELITE', true); select 'done';" \
     "$MARIA" "select public.update_my_child('$KID', 'RenamedA', 'Lockrace', date '2014-01-01'); select 'done';" "Decided|approved"
KID=$(new_child Preapproved)
race "Tara preapproves, then rename" "$TARA" "select public.admin_preapprove_program('$KID', '$ELITE'); select 'done';" \
     "$MARIA" "select public.update_my_child('$KID', 'RenamedB', 'Lockrace', date '2014-01-01'); select 'done';" "Preapproved|approved"
KID=$(new_child Before)
race "rename, then Tara approves" "$MARIA" "select public.update_my_child('$KID', 'RenamedC', 'Lockrace', date '2014-01-01'); select 'done';" \
     "$TARA" "select public.admin_decide_program_approval('$KID', '$ELITE', true); select 'done';" "RenamedC|approved"

psql -q <<SQL >/dev/null
delete from public.program_approvals where player_id in (select id from public.players where account_id = '$MARIA' and last_name = 'Lockrace');
delete from public.players where account_id = '$MARIA' and last_name = 'Lockrace';
update public.accounts set account_type = 'adult' where id = '$MARIA'
   and not exists (select 1 from public.players where account_id = '$MARIA' and kind = 'junior');
SQL
rm -rf "$TMP"

echo ""
[ "$FAIL" -eq 0 ] && echo "PASS: a rename racing Tara's decision waits for it and is refused; the approved child keeps the approved name"
exit $FAIL
