#!/usr/bin/env bash
# gen-smoke-functions.sh: write scripts/hosted-smoke-functions.txt from the
# LOCAL schema: every callable function in public (trigger functions excluded),
# one line "name<TAB>json-args", the JSON carrying the real argument names with
# placeholder values. hosted-smoke.sh calls each on hosted as a signed-out
# caller and needs 401/403; check-doc-inventory.sh regenerates it into a temp
# file and fails if the committed copy differs, so a new function cannot reach
# production unlisted (twice on 2026-09-27 before this existed).
#
#   supabase db reset && bash scripts/gen-smoke-functions.sh           # rewrite
#   bash scripts/gen-smoke-functions.sh --stdout                        # print only
set -euo pipefail
cd "$(dirname "$0")/.."
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
OUT=scripts/hosted-smoke-functions.txt
rows=$(docker exec "$DB" psql -U postgres -d postgres -AtF $'\t' -c "
  select p.proname, pg_get_function_identity_arguments(p.oid)
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace
  where n.nspname = 'public' and p.prokind = 'f'
    and p.prorettype <> 'trigger'::regtype
    and not exists (select 1 from pg_depend d where d.objid = p.oid and d.deptype = 'e')
  order by 1, 2")
body=$(python3 -c '
import sys, json
Z = "00000000-0000-0000-0000-000000000000"
def val(t):
    t = t.strip()
    if t.endswith("[]"): return []
    if t == "uuid": return Z
    if t in ("integer", "bigint", "smallint", "numeric", "real", "double precision"): return 1
    if t == "boolean": return False
    if t == "date": return "2026-01-01"
    if t.startswith("timestamp"): return "2026-01-01T00:00:00Z"
    if t in ("json", "jsonb"): return {}
    return "x"
for line in sys.stdin.read().splitlines():
    name, _, args = line.partition("\t")
    obj = {}
    for a in [x for x in args.split(", ") if x.strip()]:
        a = a.replace("DEFAULT", " DEFAULT").split(" DEFAULT")[0]
        parts = a.strip().split(" ", 1)
        if parts[0] in ("IN", "INOUT", "VARIADIC"): parts = parts[1].split(" ", 1)
        obj[parts[0]] = val(parts[1] if len(parts) > 1 else "text")
    print(name + "\t" + json.dumps(obj, separators=(",", ":"), sort_keys=True))
' <<< "$rows")
if [ "${1:-}" = "--stdout" ]; then printf '%s\n' "$body"; else printf '%s\n' "$body" > "$OUT"; echo "wrote $OUT: $(printf '%s\n' "$body" | wc -l | tr -d ' ') functions"; fi
