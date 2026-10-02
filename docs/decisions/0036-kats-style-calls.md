# 0036: Kat's three style calls

**Date:** 2026-10-01 · **Status:** Active · **Source:** Kat, relayed by Alex
2026-10-01, answering the three questions in `docs/for-alex.md` §7:
*"1. Keep it. 2. Use the darker green 3. I prefer the green line tbh"*.

## What we chose

1. **The bottom tab bar stays the system's.** iOS 26 draws it as frosted glass
   and will not take a solid navy fill; ours has an outlined icon and label,
   green for the active tab. No custom navy bar (about a day of work, and it
   would lose the system's behaviour on every iOS version).
2. **Text takes the darker green, fills keep hers.** Her gator-green
   `#4F7A38` measures 4.42:1 on porcelain, just under the 4.5:1 floor for
   small text. `Brand.courtText` (`#446A30`, 5.51:1) now colours "Let's Play."
   on Home and sign-in and the active tab's label; `Brand.court` stays for
   the header's line, the logo and every fill. The web admin never used green
   for text, so nothing changed there.
3. **The green line under the navy header stays**, straight, 4 points, the
   same line under every page's banner (decision 0033).

## Rejected

- **Darkening `Brand.court` itself.** It would change the logo's ground line
  and every fill to fix a problem only text has.
