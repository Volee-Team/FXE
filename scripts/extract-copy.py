#!/usr/bin/env python3
"""Extract every user-visible string across EVERY surface.

Used two ways:
  * `python3 scripts/extract-copy.py` prints the inventory (one per line).
  * `python3 scripts/extract-copy.py --report` prints it grouped by file, for review.
  * `scripts/check-copy.sh` diffs it against docs/copy-approved.txt in CI.

WHY
---
Alex, 2026-08-16: "text should either come straight from tara or made by u and
checked by me first". The failure mode is AI filler like "Press play - Start
Hitting!" reaching a real member because nobody noticed one new line in a diff.

SCANNING SWIFT ONLY WAS NOT ENOUGH. On 2026-08-27 Tara read the toast "You're in
the Player Pool. Tara picks from here." in the prototype walkthrough. Invented,
by me, one turn after hard rule 13 was written. The gate did not catch it because
it only scanned FXETennis/, and that string was in a web page. A gate with a
blind spot teaches you to trust it in exactly the places it cannot see.

Now scans Swift AND the web admin AND any prototype HTML.
"""
import re, os, sys, collections

# Every surface a human can read words on.
ROOTS = [
    ("FXETennis", (".swift",)),
    ("web",       (".html", ".js")),
]

SWIFT = [
    r'Text\(\s*"([^"]{2,})"',
    r'Label\(\s*"([^"]{2,})"',
    r'Button\(\s*"([^"]{2,})"',
    r'\.navigationTitle\(\s*"([^"]{2,})"',
    r'EmptyLine\(\s*"([^"]{2,})"',
    r'OutlinedButtonLabel\(\s*"([^"]{2,})"',
    r'FilledButtonLabel\(\s*"([^"]{2,})"',
    r'\.accessibilityLabel\(\s*"([^"]{2,})"',
    r'\.accessibilityHint\(\s*"([^"]{2,})"',
]
# Web: prose in HTML text nodes, plus strings that are clearly sentences in JS.
WEB = [
    r'>([A-Z][^<>{}]{11,}?)<',                 # HTML text nodes
    r'(?:return|=|\()\s*"([A-Z][^"]{11,})"',   # JS sentences
    r"(?:return|=|\()\s*'([A-Z][^']{11,})'",
    r'placeholder="([^"]{4,})"',
    r'aria-label="([^"]{4,})"',
]

# Identifiers, symbol names, CSS, interpolation fragments: not prose.
NOISE = re.compile(
    r'^(clinic|home|auth|profile|admin|tab|status)\.'
    r'|^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$'
    r'|^\\\('
    r'|^[%$#]'
    r'|^[A-Z_]+$'
    r'|^\s*$'
    r'|^(GET|POST|http|https|utf|viewport|width=)'
)

def extract():
    found = collections.defaultdict(set)
    for root, exts in ROOTS:
        if not os.path.isdir(root):
            continue
        for dirpath, dirnames, files in os.walk(root):
            # Dependencies and test tooling are not the product's copy.
            # web/node_modules alone would add tens of thousands of strings.
            dirnames[:] = [d for d in dirnames if d not in ("node_modules", "test-results", "playwright-report", "tests", ".vercel")]
            for f in sorted(files):
                if not f.endswith(exts):
                    continue
                path = os.path.join(dirpath, f)
                pats = SWIFT if f.endswith(".swift") else WEB
                text = open(path, encoding="utf-8", errors="replace").read()
                # Comments explain code to developers; they are not user copy.
                text = re.sub(r'^\s*(//|--|\*|/\*).*$', '', text, flags=re.M)
                for p in pats:
                    for m in re.finditer(p, text):
                        s = " ".join(m.group(1).split())
                        if not s or NOISE.match(s):
                            continue
                        found[path].add(s)
    return found

if __name__ == "__main__":
    found = extract()
    if "--report" in sys.argv:
        total = sum(len(v) for v in found.values())
        print(f"{total} user-visible strings across {len(found)} files\n")
        for path in sorted(found):
            print(f"--- {path} ({len(found[path])}) ---")
            for s in sorted(found[path]):
                print(f"    {s}")
            print()
    else:
        for s in sorted({s for v in found.values() for s in v}):
            print(s)
