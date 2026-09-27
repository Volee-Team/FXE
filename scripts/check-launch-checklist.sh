#!/usr/bin/env bash
# check-launch-checklist.sh: keeps docs/launch-checklist.md trustworthy.
#
# Alex, 2026-09-27: "i like having one thing to totally trust". The checklist
# is that thing, and a list is only trustworthy if every row says who owns it
# and where it stands, done rows say when, the steps file never points at a
# row that is not there, and the whole list has been re-derived recently.
# Those four are mechanical, so they are a CI check, not a habit.
#
#   bash scripts/check-launch-checklist.sh            # docs/launch-checklist.md
#   bash scripts/check-launch-checklist.sh FILE STEPS # for testing the checker
#
# Exit 1 on any failure; prints one line per problem.
set -u
cd "$(dirname "$0")/.." || exit 2
LIST="${1:-docs/launch-checklist.md}"
STEPS="${2:-docs/for-alex.md}"
python3 - "$LIST" "$STEPS" <<'PY'
import re, sys, datetime
lst, steps = sys.argv[1], sys.argv[2]
text = open(lst, encoding="utf-8").read()
bad = []
ids = set()
OWNER = re.compile(r"\[(Alex|Tara|Kat|John|me|Apple|Stripe)\]")
STATUS = re.compile(r"^\*\*(DONE|OPEN|BLOCKED|DECIDE|LATER)\b")
for n, line in enumerate(text.splitlines(), 1):
    m = re.match(r"^\| ([A-G]\d+) \|", line)
    if not m:
        continue
    rid = m.group(1)
    if rid in ids:
        bad.append(f"{lst}:{n} row {rid} appears twice")
    ids.add(rid)
    cells = [c.strip() for c in line.strip().strip("|").split("|")]
    if len(cells) < 4:
        bad.append(f"{lst}:{n} row {rid} has {len(cells)} cells, expected ID | item | owner | status")
        continue
    owner, status = cells[2], cells[3]
    if not OWNER.search(owner):
        bad.append(f"{lst}:{n} row {rid} has no owner in brackets: {owner[:40]!r}")
    sm = STATUS.match(status)
    if not sm:
        bad.append(f"{lst}:{n} row {rid} status does not start with DONE/OPEN/BLOCKED/DECIDE/LATER in bold: {status[:40]!r}")
    elif sm.group(1) == "DONE" and not re.search(r"\d{4}-\d{2}-\d{2}", status):
        bad.append(f"{lst}:{n} row {rid} is DONE without a date")

m = re.search(r"Last full\s+re-derivation:\s*\*\*(\d{4}-\d{2}-\d{2})\*\*", text)
if not m:
    bad.append(f"{lst}: no 'Last full re-derivation: **YYYY-MM-DD**' line")
else:
    age = (datetime.date.today() - datetime.date.fromisoformat(m.group(1))).days
    if age > 21:
        bad.append(f"{lst}: last full re-derivation was {age} days ago (limit 21): re-check every row by command and update the date")

try:
    stext = open(steps, encoding="utf-8").read()
    for n, line in enumerate(stext.splitlines(), 1):
        for ref in re.findall(r"checklist ([A-G]\d+)", line):
            if ref not in ids:
                bad.append(f"{steps}:{n} points at checklist {ref}, which is not a row")
except FileNotFoundError:
    bad.append(f"{steps}: missing")

for b in bad:
    print("  FAIL ", b)
print(f"{len(ids)} rows checked, {len(bad)} problem(s).")
sys.exit(1 if bad else 0)
PY
