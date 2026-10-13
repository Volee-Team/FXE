#!/usr/bin/env bash
# check-doc-registry.sh: every doc has a registered job, and every retired
# doc says so on its first line.
#
# Alex, 2026-10-12: "we have tons of docs and some are becoming outdated and
# we need a SOLID system and ASOT to stick to". The 2026-10-12 audit found
# about sixty stale spots, most of them in docs nobody had a reason to open:
# snapshots (a feature review, an MVP draft, the August question list) that
# still read as current. So two rules, both mechanical:
#
#   1. Every file under docs/ outside docs/archive/ is named in the table
#      under CLAUDE.md's "## Where things are written down", either by its
#      own path or by a folder it sits in (`docs/decisions/` covers every
#      record). A doc nobody registered is a doc nobody keeps current.
#   2. Every file in docs/archive/ starts with the banner
#      "Archived YYYY-MM-DD. Current source: <file>." (an HTML file may wrap
#      it in a comment), so a reader who lands on one from a search knows at
#      once that it is history and where the live answer is.
#
#   bash scripts/check-doc-registry.sh
#
# Files are what git tracks plus new files git does not ignore, so a doc
# added in this commit counts before it is committed, and docs/prompt-log/
# (ignored since 2026-10-04) is only checked for the README git tracks.
# Exit 1 on any finding; one line per finding.
set -u
cd "$(dirname "$0")/.." || exit 2
{ git ls-files docs; git ls-files --others --exclude-standard docs; } | sort -u > "${TMPDIR:-/tmp}/doc-registry.$$"
python3 - "${TMPDIR:-/tmp}/doc-registry.$$" <<'PY'
import os, re, sys
files = [l.strip() for l in open(sys.argv[1]) if l.strip() and os.path.exists(l.strip())]
os.remove(sys.argv[1])
text = open("CLAUDE.md", encoding="utf-8").read()
m = re.search(r"^## Where things are written down\n(.*?)(?=^## )", text, re.S | re.M)
bad = []
if not m:
    print("  FAIL  CLAUDE.md has no '## Where things are written down' section")
    sys.exit(1)
listed = set()
for line in m.group(1).splitlines():
    if line.startswith("|"):
        listed.update(t for t in re.findall(r"`([^`]+)`", line) if t.startswith("docs/"))
def covered(f):
    if f in listed:
        return True
    return any(l.endswith("/") and f.startswith(l) for l in listed)
BANNER = re.compile(r"^(<!--\s*)?Archived \d{4}-\d{2}-\d{2}\. Current source: \S.*\.")
live = archived = 0
for f in files:
    if f.startswith("docs/archive/"):
        archived += 1
        try:
            first = open(f, encoding="utf-8").readline()
        except UnicodeDecodeError:
            bad.append(f"{f}: archived file is not text, so it cannot carry the banner")
            continue
        if not BANNER.match(first):
            bad.append(f"{f}: first line is not 'Archived YYYY-MM-DD. Current source: <file>.'")
        continue
    live += 1
    if not covered(f):
        bad.append(f"{f}: not named in CLAUDE.md's 'Where things are written down' table (add a row, or archive it)")
for l in sorted(listed):
    if not l.endswith("/") and not os.path.exists(l):
        bad.append(f"CLAUDE.md registry names {l}, which does not exist")
for b in bad:
    print("  FAIL ", b)
print(f"{live} live and {archived} archived files under docs/ checked: {len(bad)} problem(s).")
sys.exit(1 if bad else 0)
PY
