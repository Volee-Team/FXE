#!/usr/bin/env bash
# Every screen with a navigation title gives its bar a solid edge.
#
# iOS 26 fades scrolled content softly under a navigation bar, and under the
# club's serif titles that fade reads as text ghosting through the title
# ("Tuesday Ladies Clinics", seen on the simulator 2026-09-28). crispTopEdge()
# (Components/BrandHeader.swift) fixes it per screen, so a new screen written
# without it brings the ghost back with no test noticing. This fails the build
# instead: each `.navigationTitle(` must have `.crispTopEdge()` on one of the
# three lines before it, or on the scroll view it titles (say which with
# `// crispTopEdge: on the ScrollView` on the line before the title).
#
#   bash scripts/check-title-edge.sh
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
while IFS= read -r file; do
  awk -v F="$file" '
    { line[NR] = $0 }
    /\.navigationTitle\(/ {
      ok = 0
      for (i = NR - 3; i < NR; i++) if (i > 0 && (line[i] ~ /\.crispTopEdge\(\)/ || line[i] ~ /crispTopEdge: on the ScrollView/)) ok = 1
      if (!ok) { printf "  MISSING  %s:%d  %s\n", F, NR, $0; bad = 1 }
    }
    END { exit bad }
  ' "$file" || fail=1
done < <(find FXETennis -name '*.swift' | sort)

if [ "$fail" -ne 0 ]; then
  echo
  echo "A navigation title without .crispTopEdge(): scrolled text will show through it on iOS 26."
  echo "Add .crispTopEdge() just before .navigationTitle(...)."
  exit 1
fi
echo "Every navigation title sits on a solid edge."
