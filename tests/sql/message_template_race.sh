#!/bin/bash
# message_template_race.sh
#
# 20260928900001 (decision 0030): the same text saved twice at the same moment
# is kept once. The phone and the laptop at once, or a double click. Session A
# saves a text as Tara and holds its transaction open for three seconds;
# session B saves the same text one second later. With the unique index over
# live rows, B's insert waits for A to commit, does nothing, and returns A's
# row: one live row, one id for both.
#
# Why this exists beside message_templates.sql: a check-then-insert ("is the
# text there? no, so insert") passes every single-session check in that probe,
# and fails here, because B's read cannot see A's uncommitted row and both
# insert. And an insert with no ON CONFLICT fails here the other way: B gets a
# unique violation instead of the row. The resulting state is asserted, not
# the error: exactly one live row for the text, and both sessions got its id.
#
# Deletes its own rows at the end (a probe fixture, not Tara's data).

set -uo pipefail
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }
TARA=11111111-1111-1111-1111-111111111111
TEXT="Race probe saved message $(date +%s)-$$"
A_FILE=$(mktemp)

save_as_tara() { # seconds to hold the transaction open
  psql -tAq <<SQL 2>&1
begin;
select set_config('request.jwt.claims', '{"sub":"$TARA","role":"authenticated"}', true);
set local role authenticated;
select 'got ' || (public.admin_save_message_template('$TEXT')).id;
select pg_sleep($1);
commit;
SQL
}

save_as_tara 3 > "$A_FILE" &
A=$!
sleep 1
B_OUT=$(save_as_tara 0)
wait $A
A_OUT=$(cat "$A_FILE"); rm -f "$A_FILE"

LIVE=$(psql -tAqc "select count(*) from public.message_templates where body = '$TEXT' and archived_at is null" | tr -d '[:space:]')
psql -qc "delete from public.message_templates where body = '$TEXT'" >/dev/null

A_ID=$(echo "$A_OUT" | grep -oE 'got [0-9a-f-]{36}' | head -1)
B_ID=$(echo "$B_OUT" | grep -oE 'got [0-9a-f-]{36}' | head -1)
echo "session A: ${A_ID:-$(echo "$A_OUT" | grep -oE 'ERROR:.*' | head -1)}"
echo "session B: ${B_ID:-$(echo "$B_OUT" | grep -oE 'ERROR:.*' | head -1)}"
if [ "$LIVE" = "1" ] && [ -n "$A_ID" ] && [ "$A_ID" = "$B_ID" ]; then
  echo "PASS: two saves of one text at the same moment kept one live row, and both got its id"
  exit 0
fi
echo "FAIL: $LIVE live rows for the text (expected 1); A returned ${A_ID:-no row}, B returned ${B_ID:-no row} (expected the same id)"
exit 1
