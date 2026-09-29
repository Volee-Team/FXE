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
# Since 2026-09-29 it also enforces the navy banner (Kat: "dont forget the
# blue banner!"): a `.navigationTitle(` needs `.navyBanner()` within the three
# lines after it, or the screen uses `.bannerTitle(` or `.navyTitle(`,
# which carry it.
# BrandHeader.swift, where the two modifiers are defined, is skipped.
#
#   bash scripts/check-title-edge.sh
set -euo pipefail
cd "$(dirname "$0")/.."

fail=0
while IFS= read -r file; do
  awk -v F="$file" '
    { line[NR] = $0 }
    /\.(navigationTitle|bannerTitle|navyTitle)\(/ {
      ok = 0
      for (i = NR - 3; i < NR; i++) if (i > 0 && (line[i] ~ /\.crispTopEdge\(\)/ || line[i] ~ /crispTopEdge: on the ScrollView/)) ok = 1
      if (!ok) { printf "  MISSING  %s:%d  %s\n", F, NR, $0; bad = 1 }
    }
    /\.navigationTitle\(/ { pending[NR] = $0 }
    END {
      for (n in pending) {
        found = 0
        for (i = n + 1; i <= n + 3; i++) if (line[i] ~ /\.navyBanner\(\)/) found = 1
        if (!found) { printf "  NO BANNER %s:%d  %s\n", F, n, pending[n]; bad = 1 }
      }
      exit bad
    }
  ' "$file" || fail=1
done < <(find FXETennis -name '*.swift' ! -path '*/Components/BrandHeader.swift' | sort)

# Every bar button sits on the navy banner, so every ToolbarItem in a screen
# carries .onNavy() (white text, no iOS 26 glass bubble; BrandHeader.swift).
while IFS= read -r file; do
  items=$(grep -c 'ToolbarItem(placement' "$file" || true)
  navy=$(grep -c '\.onNavy()' "$file" || true)
  if [ "$items" -ne "$navy" ]; then
    printf "  NOT ON NAVY %s  %s toolbar items, %s .onNavy()\n" "$file" "$items" "$navy"; fail=1
  fi
done < <(grep -l 'ToolbarItem(placement' $(find FXETennis -name '*.swift' ! -path '*/Components/BrandHeader.swift') | sort)

if [ "$fail" -ne 0 ]; then
  echo
  echo "MISSING: a title without .crispTopEdge(); scrolled text will show through it on iOS 26."
  echo "  Add .crispTopEdge() just before the title."
  echo "NO BANNER: a .navigationTitle(...) without .navyBanner() after it; the bar would be cream."
  echo "  Use .navyTitle(...) instead, or .bannerTitle(...) on a top-level page."
  echo "NOT ON NAVY: a ToolbarItem without .onNavy() after its closing brace; its text may vanish."
  exit 1
fi
echo "Every navigation title sits on a solid edge and on the navy banner."
