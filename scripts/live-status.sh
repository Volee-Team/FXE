#!/bin/bash
# live-status.sh: what is actually true right now, asked of the live systems.
#
# Why (2026-10-16): the model's "still open" list said Tara's bank was not
# linked and no real charge had happened, both done in that same session
# (Alex: "you legit helped me connect the bank and do the first payment").
# The list was recalled, not re-derived: hard rule 12 applied to status as
# much as to test counts, and nothing enforced it. This script is the
# re-derivation. Run it before writing any status list; anything it cannot
# see (Stripe dashboard settings, Apple, people's replies) is reported with
# when it was last verified by hand, from docs/live-facts.md.
#
# Read-only everywhere. Uses the Supabase CLI's own token (macOS keychain) for
# one SELECT through the management API, and gh for GitHub. Prints no secrets.
set -u
cd "$(dirname "$0")/.." || exit 1
REF=amnaxvznkadkgzdxzegw
TOK=$(security find-generic-password -s "Supabase CLI" -w 2>/dev/null | sed 's/^go-keyring-base64://' | (base64 -d 2>/dev/null || cat))
q() {
  curl -s -X POST "https://api.supabase.com/v1/projects/$REF/database/query" \
    -H "Authorization: Bearer $TOK" -H "Content-Type: application/json" \
    -d "$(python3 -c 'import json,sys; print(json.dumps({"query": sys.argv[1]}))' "$1")"
}
echo "══ Live status, $(date '+%Y-%m-%d %H:%M %Z') ══"

echo "-- Hosted switches"
q "select key, case when key in ('payments_enabled','card_required') then value else (value <> '')::text end as v from public.app_settings where key in ('payments_enabled','payments_enabled_at','stripe_live_since','card_required') order by key" |
  python3 -c "import json,sys; [print(f\"   {r['key']}: {r['v']}\") for r in json.load(sys.stdin)]" 2>/dev/null || echo "   (could not read: is the CLI signed in?)"

echo "-- Money on hosted (live mode only)"
q "select count(*) filter (where kind<>'refund' and status='succeeded') as charged, count(*) filter (where kind='refund' and status='succeeded') as refunded, count(*) filter (where status='failed') as failed, count(*) filter (where status in ('pending','processing')) as waiting, coalesce(to_char(max(created_at) at time zone 'America/New_York','Mon DD HH12:MI AM'),'never') as last from public.payments where livemode is true" |
  python3 -c "import json,sys; r=json.load(sys.stdin)[0]; print(f\"   charges succeeded {r['charged']}, refunds {r['refunded']}, failed {r['failed']}, waiting {r['waiting']}, last {r['last']}\")" 2>/dev/null
q "select count(*) filter (where card_last4 is not null and deleted_at is null) as cards, count(*) filter (where deleted_at is null and role::text='member') as members from public.accounts" |
  python3 -c "import json,sys; r=json.load(sys.stdin)[0]; print(f\"   members {r['members']}, with a saved card {r['cards']}\")" 2>/dev/null

echo "-- Stripe secrets on hosted (last changed)"
curl -s "https://api.supabase.com/v1/projects/$REF/secrets" -H "Authorization: Bearer $TOK" |
  python3 -c "
import json,sys
for s in json.load(sys.stdin):
    if s.get('name','').startswith('STRIPE'): print('  ', s['name'], s.get('updated_at','?')[:16])" 2>/dev/null

echo "-- Migrations (local vs hosted)"
supabase migration list --linked < /dev/null 2>/dev/null | python3 -c '
import json,sys
t=sys.stdin.read()
try:
    m=json.loads(t[t.index("{"):t.rindex("}")+1])["migrations"]
    un=[x["local"] or x["remote"] for x in m if x["local"]!=x["remote"]]
    ok=sum(1 for x in m if x["local"]==x["remote"])
    print("   %d of %d paired%s" % (ok, len(m), ("; not paired: %s" % un) if un else ""))
except Exception: print("   (could not read)")'

echo "-- GitHub"
gh pr list --state open --json number,title,isDraft -q '.[] | "   #\(.number)\(if .isDraft then " (draft)" else "" end) \(.title)"' 2>/dev/null
echo "   newest tags: $(git tag -l 'v0.1.0-*' --sort=-creatordate | head -3 | tr '\n' ' ')"
echo "   tara-answers issues open: $(gh issue list --label tara-answers --state open --json number -q 'length' 2>/dev/null)"

echo "-- Verified by hand (docs/live-facts.md; re-check anything older than a few days)"
sed -n '/^| Fact/,$p' docs/live-facts.md 2>/dev/null | tail -n +3 | sed 's/^/   /'
