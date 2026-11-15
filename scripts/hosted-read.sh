#!/usr/bin/env bash
# One read-only SQL query against hosted, for diagnosis.
#
#   bash scripts/hosted-read.sh "select count(*) from payments"
#
# Runs inside `begin transaction read only`, so any write fails at the
# database: this can look, never touch (hosted is written by `supabase db
# push` and by nothing else). Uses the Supabase CLI's own token from the
# macOS keychain through the management API, the same way live-status.sh
# does, and prints no secret. Rows come back one JSON object per line.
#
# Promoted from a scratchpad helper on 2026-11-14 after it had been rebuilt
# by hand three times when the scratchpad was cleared.
set -euo pipefail
[ $# -eq 1 ] || { echo "usage: $0 \"<select ...>\"" >&2; exit 2; }
REF=amnaxvznkadkgzdxzegw
TOK=$(security find-generic-password -s "Supabase CLI" -w 2>/dev/null | sed 's/^go-keyring-base64://' | (base64 -d 2>/dev/null || cat))
SQL="begin transaction read only;
${1%;};
commit;"
BODY=$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$SQL")
printf 'Authorization: Bearer %s\n' "$TOK" |
  curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H @- -H "Content-Type: application/json" --data-binary "$BODY" |
  python3 -c 'import json,sys
out=json.load(sys.stdin)
rows = out if isinstance(out, list) else [out]
for r in rows: print(json.dumps(r, default=str))
sys.exit(1 if isinstance(out, dict) and "message" in out else 0)'
