# 0033: The navy banner on every page, and the logo over a smaller TENNIS

**Date:** 2026-09-29 · **Status:** Active · **Source:** Kat, relayed by Alex
2026-09-29, with a mockup of Profile under a navy title bar: *"dont forget the
blue banner!"* (she had asked before). Tara, the same day: *"Can 'tennis' be
smaller, logo bit larger. So other way around"*, about the top of the screen;
Alex: *"but also maybe everywhere?"*

## What we chose

1. **Every titled page sits under a navy banner**, the same navy and the same
   4pt gator-green line as Home's header, with the navy running up behind the
   clock. Top-level pages (Clinics, Profile, Today, Notifications, Tara's
   Clinics) carry their name at the leading edge in white Playfair, as in
   Kat's mockup (`bannerTitle`); pushed screens and sheets carry a small
   centred white serif title (`navyTitle`); a clinic's own page keeps its big
   serif name in the page and an empty banner with the back button
   (`navyBanner`). All three live in `FXETennis/Views/Components/BrandHeader.swift`.
2. **Bar buttons are white text on the navy with no glass bubble**
   (`onNavy()`). iOS 26 puts each bar button in a bubble that turns light or
   dark on its own, so no single text colour worked: navy "Done" vanished on a
   dark bubble, white on a light one. Bare white on navy is what iOS 17 and 18
   draw anyway. The back chevron keeps the system bubble, which chose a
   readable pair itself in every case seen (navy on light, 9.87:1; white on
   dark).
3. **The status bar is white everywhere**, set once in the Info.plist
   (`UIStatusBarStyle` plus `UIViewControllerBasedStatusBarAppearance` false,
   the second in `FXETennis/Resources/Info.plist` because Xcode has no
   generated form of it). Every screen's top is navy now; the one screen that
   had a porcelain strip behind the clock (the profile step at sign-up) has a
   navy one.
4. **Notifications:** Done alone on the right; Mark all read moved to the top
   of the list, because the page name plus two bar buttons were folded by
   iOS into a "…" menu that hid Done.
5. **The wordmark:** the gator leads and TENNIS sits small under it, in all
   three places it appears (Home's header: 50pt mark over 9pt type, was 34
   over 12; sign-in and the load-failure screen: 150 over 15, was 104 over
   22). Home's header grew 18 points to hold it. The launch screen, which
   shows the mark and "FXE Tennis" for a moment, is unchanged.

## Rejected

- **A UIKit `UINavigationBarAppearance` with a navy background**, the classic
  route: on iOS 26 it drew the navy and no title at all (no title pixels in
  the band, measured).
- **iOS 26's "inline large" title mode**: white and in the right place, but
  in the system font; the guide allows no third family.
- **`toolbarColorScheme(.dark)` per screen** for the white clock: it also
  turned the back button's bubble pale blue under a white chevron, 1.78:1.
- **A fixed navy tint on bar buttons for iOS 26**: right on a light bubble,
  invisible on a dark one.

## Enforced

`scripts/check-title-edge.sh` (CI) now also fails on a `.navigationTitle`
without the banner and on a `ToolbarItem` without `.onNavy()`; shown red by
removing the banner from My Clinics, and it found one bar button this change
had missed (the Done on a clinic opened from a notification).

## Verified

On the iPhone 17 Pro simulator, iOS 26.2: Home, Clinics, a clinic page,
Profile, My Clinics, Edit details, Notifications and sign-in, each looked at.
Not seen on iOS 17 or 18, where the bar buttons are white by the tint set in
`Brand.styleNavigationTitles`.
