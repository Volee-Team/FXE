#!/usr/bin/env python3
"""Rewrite the counts check-doc-claims.sh reports as stale, to the derived number.

    python3 scripts/fix-doc-counts.py          # rewrite in place, print what changed
    python3 scripts/fix-doc-counts.py --dry    # print only

Why (2026-09-28): merging five builders' branches into build-6 meant fixing
the same probe, unit-test, UI-test, browser-test and migration counts in the
same five files by hand four times in one night. The checker already knows
the right numbers; this applies them. It only touches the lines the checker
would flag (the same nouns, the same table rows), never prose like "was 13".

Run check-doc-claims.sh afterwards: it stays the judge.
"""
import pathlib, re, subprocess, sys

ROOT = pathlib.Path(__file__).resolve().parent.parent
out = subprocess.run(["bash", "scripts/check-doc-claims.sh"], cwd=ROOT, capture_output=True, text=True).stdout
m = re.search(r"Derived now: probes=(\d+) unit=(\d+) xcuitests=(\d+) playwright=(\d+) migrations=(\d+)", out)
if not m:
    sys.exit("check-doc-claims.sh printed no 'Derived now' line")
probes, unit, ui, pw, mig = m.groups()

EXCUSE = re.compile(r"as of 20\d\d|\bwas \d|\bthen \d|at the time|used to|previously|→", re.I)
NOUNS = [
    (r"\b\d+( (?:sql |SQL )?probes?)\b", probes),
    (r"\b\d+( (?:swift |Swift )?unit(?: |\n)tests?)\b", unit),
    (r"\b\d+((?: |\n)(?:XCUITests?|UI tests?))\b", ui),
    (r"\b\d+( (?:Playwright|browser) tests?)\b", pw),
    (r"\b\d+( migrations?)\b", mig),
]
TABLE = [  # launch-checklist rows: first cell pattern -> number
    (r"^\| Swift unit tests", unit),
    (r"^\| Web admin browser tests", pw),
    (r"^\| XCUITests", ui),
]
DOCS = ["docs/roadmap.md", "docs/whats-next.md", "docs/architecture.md", "docs/launch-checklist.md",
        "README.md", "web/README.md", "supabase/functions/README.md"]

dry = "--dry" in sys.argv
for rel in DOCS:
    p = ROOT / rel
    if not p.exists():
        continue
    text = p.read_text()
    new_lines = []
    lines = text.split("\n")
    for i, line in enumerate(lines):
        nxt = lines[i + 1] if i + 1 < len(lines) else ""
        orig = line
        if not EXCUSE.search(line):
            joined = line + "\n" + nxt
            for pat, want in NOUNS:
                joined = re.sub(pat, lambda mm: want + mm.group(1), joined)
            line = joined.split("\n")[0]
            if rel == "docs/launch-checklist.md":
                for first, want in TABLE:
                    if re.match(first, line):
                        cells = line.split("|")
                        for k in range(3, len(cells)):
                            if cells[k].strip().isdigit():
                                cells[k] = f" {want} "
                                break
                        line = "|".join(cells)
        if line != orig:
            print(f"{rel}:{i + 1}: {orig.strip()[:70]}  ->  {line.strip()[:70]}")
        new_lines.append(line)
    if not dry:
        p.write_text("\n".join(new_lines))
