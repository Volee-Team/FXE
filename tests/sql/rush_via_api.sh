#!/bin/bash
# rush_via_api.sh
#
# The Thursday 8:00 rush the way phones really make it: N signed-in members
# calling register_for_clinic through the API (PostgREST) at the same moment,
# against a clinic with fewer spots than people.
#
# capacity_race.sh opens one database connection per racer, which is how to
# test the lock but not how the app reaches the database: a phone talks to
# the API, and the API queues requests into a small connection pool. At 200
# racers capacity_race.sh hits the local server's 100-connection limit and
# loses the racers that never connected (2026-10-01: 46 refused, every one
# that connected right). This one goes through the pool, as the app does.
#
# Asserts: every request answered 200; exactly CAPACITY are You're In!, the
# rest Player Pool; one row and one notification each; nobody lost. Prints
# the slowest answer, the number to watch for the real Thursday.
#
# Local only (no fixtures in hosted, ever). The JWT secret and keys come from
# `supabase status` into variables and are never printed.
#
# Usage: bash tests/sql/rush_via_api.sh [members] [capacity]   (default 200, 8)
set -uo pipefail
N=${1:-200}
CAP=${2:-8}
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
psql() { docker exec -i "$DB" psql -U postgres -d postgres "$@"; }

ENV=$(supabase status -o env 2>/dev/null)
API=${FXE_API_URL:-$(echo "$ENV" | sed -n 's/^API_URL="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')}
ANON=$(echo "$ENV" | sed -n 's/^ANON_KEY="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
SECRET=$(echo "$ENV" | sed -n 's/^JWT_SECRET="\{0,1\}\([^"]*\)"\{0,1\}$/\1/p')
[ -n "$API" ] && [ -n "$ANON" ] && [ -n "$SECRET" ] || { echo "No local API settings from supabase status"; exit 2; }

echo "Setting up: 1 clinic with $CAP spots, $N members registering through the API at once"
CLINIC=$(psql -tAqc "
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('RUSH PROBE', 'coed', now() + interval '3 days', now() + interval '3 days 1 hour',
      now() - interval '1 hour', now() + interval '12 hours', $CAP, 'published')
  returning id;" | head -1 | tr -d '[:space:]')

psql -q <<SQL
do \$\$
declare i int; uid uuid;
begin
  for i in 1..$N loop
    uid := gen_random_uuid();
    insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                            email_confirmed_at, created_at, updated_at)
    values (uid, '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated',
            'rusher' || i || '@probe.test', 'x', now(), now(), now());
    insert into public.accounts (id, first_name, last_name, email, role)
    values (uid, 'Rusher', i::text, 'rusher' || i || '@probe.test', 'member');
    insert into public.players (account_id, kind, first_name, last_name, adult_rating, is_member)
    values (uid, 'adult', 'Rusher', i::text, '3.5', true);
    insert into public.waiver_acceptances (account_id, version, legal_name, email, app_version)
    values (uid, public.waiver_version(), 'Rusher ' || i, 'rusher' || i || '@probe.test', 'probe');
  end loop;
end \$\$;
SQL

# One line per member: account id and player id, then a signed token each.
TMP=$(mktemp -d)
psql -tA -F' ' -c "select a.id, p.id from public.accounts a join public.players p on p.account_id = a.id where a.email like 'rusher%@probe.test';" > "$TMP/ids"
SECRET="$SECRET" python3 - "$TMP/ids" "$TMP" <<'PY'
import base64, hashlib, hmac, json, os, sys, time
secret = os.environ["SECRET"].encode()
b64 = lambda b: base64.urlsafe_b64encode(b).rstrip(b"=").decode()
head = b64(json.dumps({"alg": "HS256", "typ": "JWT"}).encode())
for n, line in enumerate(open(sys.argv[1]).read().split("\n")):
    if not line.strip(): continue
    uid, pid = line.split()
    body = b64(json.dumps({"sub": uid, "role": "authenticated", "aud": "authenticated",
                           "exp": int(time.time()) + 3600}).encode())
    sig = b64(hmac.new(secret, f"{head}.{body}".encode(), hashlib.sha256).digest())
    open(f"{sys.argv[2]}/t{n}", "w").write(f"{head}.{body}.{sig} {pid}")
PY
unset SECRET

# Fire all N at once.
for f in "$TMP"/t*; do
  (
    read -r TOKEN PID < "$f"
    curl -s -o "$f.body" -w '%{http_code} %{time_total}\n' -X POST "$API/rest/v1/rpc/register_for_clinic" \
      -H "apikey: $ANON" -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
      -d "{\"p_clinic\":\"$CLINIC\",\"p_player\":\"$PID\"}" > "$f.res"
  ) &
done
wait

OK=$(cat "$TMP"/t*.res | awk '$1 == 200' | wc -l | tr -d ' ')
CODES=$(cat "$TMP"/t*.res | awk '{print $1}' | sort | uniq -c | tr '\n' ' ')
SLOW=$(cat "$TMP"/t*.res | awk '{print $2}' | sort -n | tail -1)
P95=$(cat "$TMP"/t*.res | awk '{print $2}' | sort -n | awk '{a[NR]=$1} END {print a[int(NR*0.95)]}')
IN=$(psql -tAc "select count(*) from public.registrations where clinic_id = '$CLINIC' and status = 'in';")
POOL=$(psql -tAc "select count(*) from public.registrations where clinic_id = '$CLINIC' and status = 'pool';")
TOTAL=$(psql -tAc "select count(*) from public.registrations where clinic_id = '$CLINIC';")
NOTES=$(psql -tAc "select count(*) from public.notifications n join public.registrations r on r.id = n.entity_id where r.clinic_id = '$CLINIC';")

echo ""
echo "  members                  : $N"
echo "  answers                  : $CODES  (every one must be 200)"
echo "  slowest answer           : ${SLOW}s, 95th percentile ${P95}s"
echo "  You're In!               : $IN   (must be exactly $CAP)"
echo "  Player Pool              : $POOL   (must be $((N - CAP)))"
echo "  total rows               : $TOTAL   (must equal $N)"
echo "  notifications            : $NOTES   (must equal $N)"
echo ""

psql -q -c "delete from public.notifications where entity_id in (select id from public.registrations where clinic_id = '$CLINIC');" >/dev/null
psql -q -c "delete from public.registrations where clinic_id = '$CLINIC';" >/dev/null
psql -q -c "delete from public.clinics where id = '$CLINIC';" >/dev/null
psql -q -c "delete from public.waiver_acceptances w using auth.users u where u.id = w.account_id and u.email like 'rusher%@probe.test';" >/dev/null
psql -q -c "delete from auth.users where email like 'rusher%@probe.test';" >/dev/null
rm -rf "$TMP"

FAIL=0
[ "$OK" = "$N" ]              || { echo "FAIL: $OK of $N requests answered 200"; FAIL=1; }
[ "$IN" = "$CAP" ]            || { echo "FAIL: $IN in You're In!, expected $CAP"; FAIL=1; }
[ "$POOL" = "$((N - CAP))" ]  || { echo "FAIL: $POOL in the Player Pool, expected $((N - CAP))"; FAIL=1; }
[ "$TOTAL" = "$N" ]           || { echo "FAIL: $TOTAL rows, expected $N"; FAIL=1; }
[ "$NOTES" = "$N" ]           || { echo "FAIL: $NOTES notifications, expected $N"; FAIL=1; }
[ "$FAIL" = "0" ] && echo "PASS: $N members through the API, exactly $CAP in, nobody lost"
exit $FAIL
