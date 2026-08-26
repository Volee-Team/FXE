#!/usr/bin/env python3
"""Extract every user-visible string in the app.

Used two ways:
  * `python3 scripts/extract-copy.py` prints the current inventory.
  * `scripts/check-copy.sh` diffs it against docs/copy-approved.txt in CI.

WHY
---
Alex, 2026-08-16: "text should either come straight from tara or made by u and
checked by me first". The failure mode is an AI writing cliche filler like
"Press play - Start Hitting!" and it reaching a real member because nobody
noticed one new line in a diff.

A rule in CLAUDE.md cannot catch that; a machine can. This is the extractor,
and the snapshot it feeds is the gate.
"""
import re, os, sys

SRC = "FXETennis"
PATTERNS = [
    r'Text\(\s*"([^"]{2,})"',
    r'Label\(\s*"([^"]{2,})"',
    r'Button\(\s*"([^"]{2,})"',
    r'\.navigationTitle\(\s*"([^"]{2,})"',
    r'EmptyLine\(\s*"([^"]{2,})"',
    r'OutlinedButtonLabel\(\s*"([^"]{2,})"',
    r'FilledButtonLabel\(\s*"([^"]{2,})"',
    r'\.accessibilityLabel\(\s*"([^"]{2,})"',
    r'\.accessibilityHint\(\s*"([^"]{2,})"',
    r'ClinicExplainerSheet|NTRPExplainerSheet',   # presence only, no capture
]
CAPTURING = [p for p in PATTERNS if '(' in p and '?' not in p[:3]]

# Identifiers, SF Symbol names, and interpolated fragments are not prose.
NOISE = re.compile(
    r'^(clinic|home|auth|profile|admin|tab|status)\.'   # accessibility ids
    r'|^[a-z][a-z0-9]*(\.[a-z][a-z0-9]*)+$'            # dotted.symbol.names
    r'|^\\\('                                            # starts with interpolation
    r'|^[%$]'
)

def extract():
    found = set()
    for root, _, files in os.walk(SRC):
        for f in sorted(files):
            if not f.endswith(".swift"):
                continue
            for line in open(os.path.join(root, f), encoding="utf-8"):
                for p in CAPTURING:
                    for m in re.finditer(p, line):
                        s = m.group(1).strip()
                        if not s or NOISE.match(s):
                            continue
                        found.add(s)
    return sorted(found)

if __name__ == "__main__":
    for s in extract():
        print(s)
