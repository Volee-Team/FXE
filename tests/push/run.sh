#!/bin/bash
# Push delivery, end to end, against a mock of APNs (decision 0008).
#
#   bash tests/push/make-env.sh > /tmp/push.env
#   deno run --allow-net --allow-read --allow-write tests/push/mock-apns.ts /tmp/push.env /tmp/mock-apns.json &
#   supabase functions serve --env-file /tmp/push.env &
#   bash tests/push/run.sh /tmp/push.env /tmp/mock-apns.json
#
# Why this exists (2026-09-23): the push function, its provider-token
# signing, the device pruning and the trigger that calls it can all be built
# before Apple issues the key, and none of it can be trusted until it has
# run. The mock verifies each provider token's ES256 signature against the
# key make-env.sh generated, so a wrongly signed JWT is a FAIL here rather
# than a 403 on the first real invitation. What it cannot prove: Apple's own
# acceptance of the key, the topic, and a real device token over HTTP/2.
# That is one real invitation to Alex's phone once the key exists.
#
# Fixtures: notifications of type 'push_test' and devices with test tokens,
# written as postgres and deleted again at the end (the DIRTY DATABASE rule in
# tests/run-probes.sh). Prints one PASS/FAIL line per check, like the probes.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

ENVFILE=${1:-${PUSH_ENV_FILE:-/tmp/push.env}}
MOCKLOG=${2:-${MOCK_APNS_LOG:-/tmp/mock-apns.json}}
API=${FXE_API_URL:-http://127.0.0.1:54321}
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
# The URL the DATABASE uses to reach the function: pg_net runs inside the db
# container, which reaches the gateway by its container name.
FN_FROM_DB=${FXE_FN_FROM_DB:-http://supabase_kong_FXE-Tennis:8000/functions/v1/push}
ANON=$(supabase status -o env 2>/dev/null | grep '^ANON_KEY' | cut -d= -f2 | tr -d '"')
SECRET=$(grep '^PUSH_WEBHOOK_SECRET=' "$ENVFILE" 2>/dev/null | cut -d= -f2)

ROB=44444444-4444-4444-4444-444444444444
KEN=33333333-3333-3333-3333-333333333333
DANA=66666666-6666-6666-6666-666666666666
PRIYA=55555555-5555-5555-5555-555555555555

FAILED=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1 (expected '$2', got '$3')"; FAILED=1; fi
}
sql() { docker exec "$DB" psql -U postgres -d postgres -Atc "$1"; }
# push <secret> <notification id> -> "<http status> <body>"
push() {
  curl -s -w ' %{http_code}' -X POST "$API/functions/v1/push" -H "Content-Type: application/json" \
       -H "X-Push-Secret: $1" -d "{\"notification_id\":\"$2\"}" \
  | awk '{code=$NF; $NF=""; sub(/ $/, ""); print code " " $0}'; }
field() { python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d$1 if d is not None else '')
except Exception: print('')"; }
mockcount() { python3 -c "import json;print(len(json.load(open('$MOCKLOG'))))" 2>/dev/null || echo "?"; }
mocklast() { python3 -c "
import json
e=json.load(open('$MOCKLOG'))[-1]
print(e$1)" 2>/dev/null; }
newrow() { # account body [read]
  sql "insert into public.notifications (account_id, type, entity_type, body, read_at)
       values ('$1', 'push_test', 'clinic', \$b\$$2\$b\$, ${3:-null}) returning id" | head -1; }
cleanup() {
  sql "delete from public.notifications where type = 'push_test';
       delete from public.devices where apns_token like 'good-%' or apns_token like 'gone-%' or apns_token like 'bad-%';
       delete from vault.secrets where name in ('push_function_url', 'push_webhook_secret');" >/dev/null
}

if [ -z "$SECRET" ]; then echo "No PUSH_WEBHOOK_SECRET in $ENVFILE. Run: bash tests/push/make-env.sh > $ENVFILE"; exit 1; fi
if [ "$(mockcount)" = "?" ]; then echo "Mock APNs log $MOCKLOG not readable. Start tests/push/mock-apns.ts first."; exit 1; fi
if ! curl -s -o /dev/null "$API/functions/v1/push" -X POST; then
  echo "Edge functions are not being served. Run: supabase functions serve --env-file $ENVFILE"; exit 1
fi

echo "════ Push pipeline (mock APNs) ════"
cleanup

# ---- (a) The shared secret is the only way in, and a refusal changes nothing
N=$(newrow "$KEN" "probe row a")
M0=$(mockcount)
check "no secret header -> 401" "401" "$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/functions/v1/push" -H 'Content-Type: application/json' -d "{\"notification_id\":\"$N\"}")"
out=$(push "wrong-$SECRET" "$N")
check "wrong secret -> 401" "401" "${out%% *}"
check "wrong secret says not_authorized" "not_authorized" "$(echo "${out#* }" | field "['error']")"
check "row untouched after the refusals" "||" "$(sql "select coalesce(delivered_at::text,'')||'|'||coalesce(delivery_error,'')||'|' from public.notifications where id='$N'")"
check "mock saw nothing" "$M0" "$(mockcount)"
check "GET is refused" "405" "$(curl -s -o /dev/null -w '%{http_code}' "$API/functions/v1/push" -H "X-Push-Secret: $SECRET")"

# ---- (b) A row that does not exist
check "unknown notification -> 404" "404" "$(push "$SECRET" "00000000-0000-0000-0000-00000000dead" | cut -d' ' -f1)"
check "malformed id -> 400" "400" "$(push "$SECRET" "not-a-uuid" | cut -d' ' -f1)"

# ---- (c) An account with no registered phone
N=$(newrow "$ROB" "probe row c")
out=$(push "$SECRET" "$N")
check "no device -> 200" "200" "${out%% *}"
check "no device -> sent 0" "0" "$(echo "${out#* }" | field "['sent']")"
check "no device recorded on the row" "no_device|" "$(sql "select coalesce(delivery_error,'')||'|'||coalesce(delivered_at::text,'') from public.notifications where id='$N'")"
check "mock saw nothing for Rob" "$M0" "$(mockcount)"

# ---- (d) One good device. Ken has three test rows, one already read, so the
# badge must be 2 (worked by hand: rows K1 read, K2 and K3 unread).
sql "insert into public.devices (account_id, apns_token) values ('$KEN', 'good-ken-1')" >/dev/null
newrow "$KEN" "probe row K1" "now()" >/dev/null
sql "delete from public.notifications where account_id='$KEN' and body='probe row a'" >/dev/null
newrow "$KEN" "probe row K2" >/dev/null
BODY="Tuesday Ladies 3.0+ at 9:00: You're In! \"Bring water\" & a hat. 🎾"
N=$(newrow "$KEN" "$BODY")
out=$(push "$SECRET" "$N")
check "good device -> 200" "200" "${out%% *}"
check "good device -> sent 1 failed 0" "1 0" "$(echo "${out#* }" | field "['sent']") $(echo "${out#* }" | field "['failed']")"
check "delivered_at set, no error" "yes|" "$(sql "select case when delivered_at is not null then 'yes' else 'no' end||'|'||coalesce(delivery_error,'') from public.notifications where id='$N'")"
check "mock saw exactly one request" "$((M0 + 1))" "$(mockcount)"
check "sent to Ken's token" "good-ken-1" "$(mocklast "['token']")"
check "provider token verified by the mock (ES256, kid, team, signature)" "None" "$(mocklast "['token_problem']")"
check "apns-topic" "com.fxetennis.app" "$(mocklast "['headers']['apns-topic']")"
check "apns-push-type" "alert" "$(mocklast "['headers']['apns-push-type']")"
check "apns-priority" "10" "$(mocklast "['headers']['apns-priority']")"
check "apns-collapse-id is the row id" "$N" "$(mocklast "['headers']['apns-collapse-id']")"
check "alert body is the row body, verbatim" "$BODY" "$(mocklast "['body']['aps']['alert']['body']")"
check "badge is the unread count (2)" "2" "$(mocklast "['body']['aps']['badge']")"
check "sound default" "default" "$(mocklast "['body']['aps']['sound']")"
check "payload carries notification_id, type, entity_type" "$N push_test clinic" "$(mocklast "['body']['notification_id']") $(mocklast "['body']['type']") $(mocklast "['body']['entity_type']")"
KEN_ROW=$N

# ---- (e) A token Apple says is gone is pruned; its sibling still delivers
sql "insert into public.devices (account_id, apns_token) values ('$DANA', 'gone-dana-1'), ('$DANA', 'good-dana-2')" >/dev/null
M1=$(mockcount)
N=$(newrow "$DANA" "probe row e")
out=$(push "$SECRET" "$N")
check "gone + good -> sent 1 failed 1" "1 1" "$(echo "${out#* }" | field "['sent']") $(echo "${out#* }" | field "['failed']")"
check "errors carry Apple's reason" "Unregistered" "$(echo "${out#* }" | field "['errors'][0]")"
check "gone token deleted, good token kept" "good-dana-2" "$(sql "select string_agg(apns_token, ',' order by apns_token) from public.devices where account_id='$DANA'")"
check "delivered because one device took it" "yes|" "$(sql "select case when delivered_at is not null then 'yes' else 'no' end||'|'||coalesce(delivery_error,'') from public.notifications where id='$N'")"
check "mock saw two requests" "$((M1 + 2))" "$(mockcount)"

# ---- (f) A bad token is pruned, and the row says why nothing arrived
sql "insert into public.devices (account_id, apns_token) values ('$PRIYA', 'bad-priya-1')" >/dev/null
N=$(newrow "$PRIYA" "probe row f")
out=$(push "$SECRET" "$N")
check "bad token -> sent 0 failed 1" "0 1" "$(echo "${out#* }" | field "['sent']") $(echo "${out#* }" | field "['failed']")"
check "bad token deleted" "0" "$(sql "select count(*) from public.devices where account_id='$PRIYA'")"
check "delivery_error is Apple's reason, not delivered" "BadDeviceToken|" "$(sql "select coalesce(delivery_error,'')||'|'||coalesce(delivered_at::text,'') from public.notifications where id='$N'")"

# ---- (g) Idempotent: pg_net may retry, and a delivered row is never sent twice
M2=$(mockcount)
out=$(push "$SECRET" "$KEN_ROW")
check "second call for a delivered row -> skipped" "already_delivered" "$(echo "${out#* }" | field "['skipped']")"
check "mock saw no new request" "$M2" "$(mockcount)"

# ---- (h) A player cannot read the audit columns through PostgREST
MARIA_JWT=$(curl -s "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
  -d '{"email":"maria@fxe.test","password":"password"}' | field "['access_token']")
rest() { curl -s "$API/rest/v1/notifications?$1" -H "apikey: $ANON" -H "Authorization: Bearer $MARIA_JWT"; }
check "Maria signed in" "yes" "$([ -n "$MARIA_JWT" ] && echo yes)"
check "Maria: select=delivered_at refused" "42501" "$(rest 'select=delivered_at' | field "['code']")"
check "Maria: select=delivery_error refused" "42501" "$(rest 'select=delivery_error' | field "['code']")"
check "Maria: select=* refused (it names them)" "42501" "$(rest 'select=*' | field "['code']")"
# pg_net's queue carries X-Push-Secret in plain text until sent and grants
# PUBLIC everything; no migration can revoke it (supabase_admin owns it). The
# API must not expose the net schema at all. PGRST106 = schema not exposed.
check "Maria: net.http_request_queue not reachable" "PGRST106" "$(curl -s "$API/rest/v1/http_request_queue?select=*" -H "apikey: $ANON" -H "Authorization: Bearer $MARIA_JWT" -H "Accept-Profile: net" | field "['code']")"
check "Maria: net.http_post not callable" "PGRST106" "$(curl -s -X POST "$API/rest/v1/rpc/http_post" -H "apikey: $ANON" -H "Authorization: Bearer $MARIA_JWT" -H "Content-Profile: net" -H "Content-Type: application/json" -d '{"url":"http://example.invalid"}' | field "['code']")"
check "Maria: the app's own column list still reads" "list" "$(rest 'select=id,type,entity_type,entity_id,body,created_at,read_at' | python3 -c "import sys,json;print(type(json.load(sys.stdin)).__name__)")"

# ---- (i) No vault secrets: a notification is written, and nothing is queued
Q0=$(sql "select count(*) from net.http_request_queue")
out=$(sql "select public.notify_account('$KEN', 'push_test', null, null, 'probe row i'); select 'ok'" 2>&1 | tail -1)
check "notify_account succeeds with no secrets" "ok" "$out"
check "pg_net queue unchanged" "$Q0" "$(sql "select count(*) from net.http_request_queue")"

# ---- (j) Both secrets: the trigger alone delivers, with no one calling the function
sql "select vault.create_secret('$FN_FROM_DB', 'push_function_url'); select vault.create_secret('$SECRET', 'push_webhook_secret');" >/dev/null
M3=$(mockcount)
N=$(sql "select public.notify_account('$KEN', 'push_test', null, null, 'probe row j');
         select id from public.notifications where account_id='$KEN' and body='probe row j'" | tail -1)
for _ in $(seq 1 30); do
  [ "$(sql "select delivered_at is not null from public.notifications where id='$N'")" = "t" ] && break
  sleep 1
done
check "trigger -> pg_net -> push delivered the row" "t" "$(sql "select delivered_at is not null from public.notifications where id='$N'")"
check "mock saw the trigger's request" "$((M3 + 1)) $N" "$(mockcount) $(mocklast "['headers']['apns-collapse-id']")"

cleanup
check "fixtures removed" "0 0 0" "$(sql "select (select count(*) from public.notifications where type='push_test')||' '||(select count(*) from public.devices where apns_token ~ '^(good|gone|bad)-')||' '||(select count(*) from vault.secrets where name like 'push_%')")"

echo ""
if [ $FAILED -eq 0 ]; then echo "PASS: Push pipeline"; else echo "FAIL: Push pipeline"; exit 1; fi
