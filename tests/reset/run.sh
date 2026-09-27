#!/bin/bash
# The reset link Tara makes for a member (admin-reset-link, decision 0017),
# end to end against the local stack with the edge functions served:
#
#   RESET_PAGE_URL=http://localhost:8790/reset.html supabase functions serve --env-file <file> &
#   bash tests/reset/run.sh
#
# What it proves, each check written from the rule, not the code:
#   * only a live admin can make a link: signed out 401, a member 403, a
#     deleted admin 403;
#   * an admin account is never a target (a leaked link would be an admin
#     session), even when it has a player row;
#   * the link is the reset page with the token hash in the FRAGMENT, never
#     the query (a fragment reaches no server log), and carries no email and
#     no access token;
#   * every link made leaves one audit row naming the member and Tara;
#   * the token signs in as that member once, and a second use fails;
#   * the password it sets is the one that works afterwards, the old one no
#     longer does;
#   * a deleted account gets no link, and no audit row.
#
# Fixtures: Dana's password is changed and put back; Priya's account and then
# Tara's are marked deleted and restored; a player row is added to Tara's
# account and removed; the audit rows made here are deleted at the end (the
# DIRTY DATABASE rule in tests/run-probes.sh).

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

API=${FXE_API_URL:-http://127.0.0.1:54321}
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
PAGE=${RESET_PAGE_URL:-http://localhost:8790/reset.html}
ANON=$(supabase status -o env 2>/dev/null | grep '^ANON_KEY' | cut -d= -f2 | tr -d '"')

TARA_ACC=11111111-1111-1111-1111-111111111111
DANA_ACC=66666666-6666-6666-6666-666666666666
PRIYA_ACC=55555555-5555-5555-5555-555555555555
DANA=a0000000-0000-0000-0000-000000000004
PRIYA=a0000000-0000-0000-0000-000000000005

FAILED=0
check() { if [ "$2" = "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1 (expected '$2', got '$3')"; FAILED=1; fi; }
sql() { docker exec "$DB" psql -U postgres -d postgres -Atc "$1"; }
field() { python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d$1 if d is not None else '')
except Exception: print('')"; }
token_for() { # email password -> access token or empty
  curl -s -X POST "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
       -d "{\"email\":\"$1\",\"password\":\"$2\"}" | field "['access_token']"; }
mint() { # jwt-or-empty body -> "<status> <json>"
  local auth=(); [ -n "$1" ] && auth=(-H "Authorization: Bearer $1")
  curl -s -w ' %{http_code}' -X POST "$API/functions/v1/admin-reset-link" -H "apikey: $ANON" \
       -H "Content-Type: application/json" ${auth[@]+"${auth[@]}"} -d "$2" \
  | awk '{code=$NF; $NF=""; sub(/ $/, ""); print code " " $0}'; }
verify() { # token_hash -> "<status> <json>"
  curl -s -w ' %{http_code}' -X POST "$API/auth/v1/verify" -H "apikey: $ANON" -H "Content-Type: application/json" \
       -d "{\"type\":\"recovery\",\"token_hash\":\"$1\"}" \
  | awk '{code=$NF; $NF=""; sub(/ $/, ""); print code " " $0}'; }

[ -n "$ANON" ] || { echo "  FAIL  no anon key: is the local stack running?"; exit 1; }
START=$(sql "select clock_timestamp()")
TARA=$(token_for tara@fxe.test password)
MARIA=$(token_for maria@fxe.test password)
check "fixture: Tara and Maria can sign in" "yes yes" "$([ -n "$TARA" ] && echo yes) $([ -n "$MARIA" ] && echo yes)"

echo "── who may make a link"
check "signed out: 401" "401" "$(mint "" "{\"player_id\":\"$DANA\"}" | cut -d' ' -f1)"
r=$(mint "$MARIA" "{\"player_id\":\"$DANA\"}")
check "a member: 403 not_authorized" "403 not_authorized" "${r%% *} $(echo "${r#* }" | field "['error']")"
check "no audit row from refused calls" "0" "$(sql "select count(*) from public.reset_links_issued where issued_at > '$START'")"

echo "── bad input"
check "not a uuid: 400" "400" "$(mint "$TARA" '{"player_id":"x"}' | cut -d' ' -f1)"
check "a JSON null body: 400" "400" "$(mint "$TARA" 'null' | cut -d' ' -f1)"
check "no such player: 404" "404" "$(mint "$TARA" '{"player_id":"a0000000-0000-0000-0000-0000000000ff"}' | cut -d' ' -f1)"

echo "── Tara makes a link for Dana"
r=$(mint "$TARA" "{\"player_id\":\"$DANA\"}")
check "200" "200" "${r%% *}"
LINK=$(echo "${r#* }" | field "['link']")
case "$LINK" in "$PAGE#token_hash="*"&type=recovery") ok=yes;; *) ok="$LINK";; esac
check "the link is the reset page with the token hash in the fragment" "yes" "$ok"
case "$LINK" in *"?"*) q="$LINK";; *) q=none;; esac
check "nothing rides in the query string" "none" "$q"
case "$LINK" in *dana*|*access_token*|*@*) leak="$LINK";; *) leak=none;; esac
check "the link carries no email and no access token" "none" "$leak"
check "one audit row: Dana's account, made by Tara" "1|$DANA_ACC|$TARA_ACC" \
  "$(sql "select count(*) || '|' || min(account_id::text) || '|' || min(issued_by::text) from public.reset_links_issued where issued_at > '$START'")"

HASH=$(python3 -c "import sys,urllib.parse as u; print(u.parse_qs(u.urlparse(sys.argv[1]).fragment)['token_hash'][0])" "$LINK")
r=$(verify "$HASH")
SESSION=$(echo "${r#* }" | field "['access_token']")
check "the token verifies once" "200" "${r%% *}"
check "the session it gives is Dana's" "$DANA_ACC" "$(echo "${r#* }" | field "['user']['id']")"
r=$(verify "$HASH")
check "a second use fails" "no" "$([ "${r%% *}" = "200" ] && echo yes || echo no)"

NEWPW="Reset-$(date +%s)-ok"
code=$(curl -s -o /dev/null -w '%{http_code}' -X PUT "$API/auth/v1/user" -H "apikey: $ANON" -H "Authorization: Bearer $SESSION" \
       -H "Content-Type: application/json" -d "{\"password\":\"$NEWPW\"}")
check "the reset session may set a new password" "200" "$code"
check "the new password signs Dana in" "yes" "$([ -n "$(token_for dana@fxe.test "$NEWPW")" ] && echo yes || echo no)"
check "the old password no longer does" "no" "$([ -n "$(token_for dana@fxe.test password)" ] && echo yes || echo no)"
# Put Dana back as seeded, through the API as she would (never SQL on auth).
curl -s -o /dev/null -X PUT "$API/auth/v1/user" -H "apikey: $ANON" -H "Authorization: Bearer $(token_for dana@fxe.test "$NEWPW")" \
     -H "Content-Type: application/json" -d '{"password":"password"}'
check "fixture restored: Dana's seed password works again" "yes" "$([ -n "$(token_for dana@fxe.test password)" ] && echo yes || echo no)"

echo "── a deleted account"
sql "update public.accounts set deleted_at = now() where id = '$PRIYA_ACC'" >/dev/null
before=$(sql "select count(*) from public.reset_links_issued")
r=$(mint "$TARA" "{\"player_id\":\"$PRIYA\"}")
check "409 account_deleted" "409 account_deleted" "${r%% *} $(echo "${r#* }" | field "['error']")"
check "and no audit row" "$before" "$(sql "select count(*) from public.reset_links_issued")"
sql "update public.accounts set deleted_at = null where id = '$PRIYA_ACC'" >/dev/null

echo "── an admin account is never a target"
TARA_PLAYER=$(sql "insert into public.players (account_id, kind, first_name, last_name) values ('$TARA_ACC', 'adult', 'Tara', 'Coach') returning id" | head -1)
before=$(sql "select count(*) from public.reset_links_issued")
r=$(mint "$TARA" "{\"player_id\":\"$TARA_PLAYER\"}")
check "a player row on an admin account: 403 admin_target" "403 admin_target" "${r%% *} $(echo "${r#* }" | field "['error']")"
check "and no audit row" "$before" "$(sql "select count(*) from public.reset_links_issued")"
sql "delete from public.players where id = '$TARA_PLAYER'" >/dev/null

echo "── a deleted admin"
sql "update public.accounts set deleted_at = now() where id = '$TARA_ACC'" >/dev/null
r=$(mint "$TARA" "{\"player_id\":\"$DANA\"}")
check "403 not_authorized" "403 not_authorized" "${r%% *} $(echo "${r#* }" | field "['error']")"
check "and no audit row" "$before" "$(sql "select count(*) from public.reset_links_issued")"
sql "update public.accounts set deleted_at = null where id = '$TARA_ACC'" >/dev/null

# Leave nothing behind.
sql "delete from public.reset_links_issued where issued_at > '$START'" >/dev/null

if [ $FAILED -eq 0 ]; then echo "Reset link: all checks passed."; else echo "Reset link: FAILURES above."; exit 1; fi
