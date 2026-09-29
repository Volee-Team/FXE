# 0032: The gator in colour

**Date:** 2026-09-29 · **Status:** Active · **Source:** Tara, relayed by Alex
2026-09-29: *"I do ask the gator is changed in color first"* (before testers
get a build), and the artwork itself, sent by Alex the same day.

## What we chose

1. The mark is the same drawing as before (decision 22: gator, crossed
   racquets, the ball, F and E), now in colour: a green gator, cream racquets
   and letters, on navy. The file as Alex sent it is the source of truth and
   lives in the repo: `docs/brand/gator-2026-09-29.webp`.
2. Every copy of the mark is generated from that one file by
   `scripts/make-logo-assets.py`, never edited by hand: the app icon, the
   in-app mark (launch screen and header), and two web files. Changing the
   logo again is: replace the source, run the script, look at it.
3. On navy the mark is a cut-out (the navy lifted out by a flood fill from
   the border, so the dark lines inside the gator stay). On light pages
   (the printable QR card) it is the navy square with rounded corners,
   because cream racquets on a cream card disappear.

## Rejected

- **Recolouring the old grey PNG in code or by hand**: two drawings that
  must be kept in step, and the next change would be a third.
- **The cut-out on the light QR card**: the racquets and letters are cream
  and vanish.

## How we would know we were wrong

Tara or Kat sees the icon on a phone and it reads muddy at small size (the
home screen icon is about 60 points). The fix is a simplified icon source,
run through the same script.

## Verified

Built and run on the iPhone 17 Pro simulator on 2026-09-29: the header mark
and the app-switcher icon are the green gator; `web/qr.html` and
`web/app/index.html` checked in the browser. The icon is 1024 by 1024 with
no alpha channel (`sips -g hasAlpha`: no), which App Store Connect requires.
