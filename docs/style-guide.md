# Style guide

**Source of truth for every visual decision** (Alex, 2026-09-22: *"for all
of these edits in the app, go w the style guide! write down, this is source
of truth for style!!"*). Written by Kat, delivered 2026-09-22 as
"FXE Tennis — Style Guide.pdf" (three pages); transcribed here verbatim,
then the mapping onto the code and the places where the code cannot follow
it yet. `docs/design-system.md` and `FXETennis/Resources/Brand.swift` follow
this file; `web/tokens.css` follows `Brand.swift`.

## Kat's guide, verbatim

### Color

| Token | Value | Use |
|---|---|---|
| navy-900 | #0A1B3D | Header, primary buttons, tab bar, headline text |
| navy-700 | #16295C | Pressed/hover state, divider shadow edge |
| gator-green | #4F7A38 | Mascot, rackets, accent stripe, active tab, "Let's Play" |
| green-shade | #33501F | Mascot shading/outline only |
| ace-yellow | #ABC040 | Photography accent only — never text or UI fill |
| porcelain | #F2F0EC | Page background, secondary surfaces |
| surface-white | #FFFFFF | Card/row surfaces, reversed wordmark |

### Type

| Style | Family | Weight | Size / Line | Tracking |
|---|---|---|---|---|
| greeting | Playfair Display | 700 | 34 / 40 | 0 |
| greeting-accent | Playfair Display Italic | 500 | 23 / 28 | 0 |
| wordmark-initial | Playfair Display | 700 | 56 / 56 | 0 |
| wordmark-lockup | Playfair Display | 600 | 22 / 26 | 6px |
| nav-row-label | Inter | 600 | 19 / 24 | 0 |
| tab-bar-label | Inter | 500 | 12 / 16 | 0.2px |
| body | Inter | 400 | 15 / 22 | 0 |

Rule: serif for anything that greets or names; sans for anything tapped or
read as an instruction. No third family. Never set the serif inside a UI
control.

### Component requirements

**Header**
- Fill: navy-900, full width, arches into porcelain body
- Divider: single gator-green hairline (≈6px), follows the arch — one
  instance only, not a repeatable rule style
- Wordmark: wordmark-initial for flanking letters, wordmark-lockup for
  "TENNIS", both centered, reversed to surface-white

**Buttons / nav rows**
- Shape: radius-lg (28px) on all four corners, full width, fixed height
- Fill: alternates navy-900 / surface-white row to row — not a
  primary/secondary hierarchy
- Padding: space-4 (16px) inner, space-4 gap between stacked rows
- Anatomy, left to right: leading icon (fixed-width slot) → nav-row-label →
  trailing chevron
- Icon/text color: surface-white on navy fill, navy-900 on white fill
- Icons: single-weight outline only, no filled glyphs

**Tab bar**
- Shape: radius-lg, floating, pinned to bottom
- Fill: navy-900
- Label: tab-bar-label
- Active state: icon + label in gator-green; inactive in surface-white

**Greeting block**
- Centered under header, space-8 below the banner
- Line 1: greeting in navy-900
- Line 2: greeting-accent, italic, in gator-green

### Spacing / radius defaults

- radius-lg (28px): default for any new tappable row or button
- radius-md (16px): compact chips, secondary controls
- radius-sm (8px): icon glyph containers only
- space-6 (24px): screen outer margin
- space-4 (16px): between stacked rows
- space-2 (8px): icon-to-label gap

## How the code follows it (2026-09-22)

| Guide | Code |
|---|---|
| navy-900 / navy-700 | `Brand.navy` / `Brand.navyPressed`; `--fxe-navy` / `--fxe-navy-pressed` |
| gator-green | `Brand.court` (and `Brand.accent`, since the guide has no brass); `--fxe-court` |
| green-shade, ace-yellow | `Brand.courtShade`, `Brand.aceYellow` (declared, unused by the UI, as the guide says) |
| porcelain, surface-white | `Brand.surface`, `Brand.surfaceRaised`; `--fxe-surface`, `--fxe-surface-raised` |
| Playfair Display, Inter | bundled as variable fonts in `FXETennis/Resources/Fonts/` (SIL OFL, licences beside them), registered at first use by `Brand.Fonts.register()`; weight set through the `wght` axis; the web loads the same two families from Google Fonts |
| greeting, greeting-accent, wordmark-*, nav-row-label, tab-bar-label, body | `Brand.Typography.greeting` … `.body`, name for name; the older role names (`display`, `title`, `headline`, `caption`, `chip`, `button`) map onto them |
| Header | `ArchedHeader` (`FXETennis/Views/Components/ArchedHeader.swift`): navy fill with an arched bottom, one 6pt gator-green hairline along the arch; used on the sign-in screen (full) and Home (compact) |
| Wordmark | `Wordmark`: the gator artwork over the "TENNIS" lockup at 6pt tracking, reversed to white. **The flanking F and E are part of the gator PNG itself**, so no separate initials are set; setting them doubled the letters |
| Buttons / nav rows | `NavRowLabel` (28pt radius, 56pt tall, icon slot, label, chevron); `FilledButtonLabel` = navy row, `OutlinedButtonLabel` = white row, so every existing call site picked the shape up |
| Greeting block | Home: the greeting in `greeting`, then "Let's Play." in `greetingAccent` gator-green, centered under the header; sign-in: "Let's Play." alone under the header |
| Spacing / radius | `Brand.Spacing.pageMargin` 24, `Brand.Radius.lg` 28 / `md` 16 / `sm` 8; web tokens the same |

## Where the code cannot follow it yet, for Kat

1. **Tab bar fill.** iOS 26 draws the tab bar as floating glass and ignores a
   solid navy fill from the toolbar-background APIs (tried: the bar went
   frosted with white glyphs, unreadable). Shipped: the system bar, active
   item in gator-green, inactive in navy-900, radius and floating from the
   system. A true navy bar means replacing the system tab bar with our own;
   say the word and it is a day's work.
2. **Contrast, measured** (WCAG, against porcelain and the gradient's warm
   end): navy-900 text 14.9:1 / 13.6:1; gator-green "Let's Play" at 23px
   medium italic **4.42:1 / 4.05:1**, just under the 4.5:1 floor for text
   below 24px; gator-green active tab label at 12px on navy **3.37:1**. Both
   are exactly what the guide asks for and are shipped as asked; a shade
   darker green for text (for example #446A30, 5.2:1) would clear the floor
   without changing the look. Kat's call.
3. **Tara's gradient.** Her standing ask (*"some kind of color variation, not
   just pure white"*, 2026-09-22) stays: pages run from porcelain to a warmer
   porcelain (`Brand.surfaceWarm` #EAE6DF). The guide names a flat porcelain
   page; if that was deliberate, one token change removes the gradient.
4. **Line heights and 0.2px tracking** are not set explicitly on iOS; the
   fonts' own metrics apply.

## When the guide changes

Paste the new version above, dated; change `Brand.swift` first, then
`web/tokens.css`; open one PR with screenshots of every screen it touches;
re-run the copy gate (the wordmark's "TENNIS" is a string) and the UI suite.
