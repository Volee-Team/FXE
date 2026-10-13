# Style guide

**Source of truth for every visual decision** (Alex, 2026-09-22: *"for all
of these edits in the app, go w the style guide! write down, this is source
of truth for style!!"*). Written by Kat, delivered 2026-09-22 as
"FXE Tennis — Style Guide.pdf" (three pages); transcribed here verbatim,
then the mapping onto the code, Kat's answers to where the code could not
follow it (decision 0036), and the status colours and accessibility rules
(folded in from the retired design-system doc on 2026-10-12).
`FXETennis/Resources/Brand.swift` follows this file; `web/tokens.css`
follows `Brand.swift`.

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
| Header | `BrandHeader` (`FXETennis/Views/Components/BrandHeader.swift`): navy, **straight across** (Kat, 2026-09-26: *"I'm not wild about the swoopy thing. I think I just like the straight line across."*), one 4pt gator-green line along the bottom edge; sign-in (full wordmark, 150pt mark over 15pt TENNIS) and Home (50pt mark over 9pt TENNIS); Tara, 2026-09-29: *"Can 'tennis' be smaller, logo bit larger"* (decision 0033) |
| Page titles | Every titled page under the same navy with the same green line (Kat, 2026-09-29: *"dont forget the blue banner!"*): the page name in white Playfair at the leading edge on top-level pages, small and centred on pushed screens and sheets; bar buttons white, no glass bubble (decision 0033) |
| Page background | `CourtBackdrop` (`FXETennis/Views/Components/CourtBackdrop.swift`): Tara's court photo under a porcelain wash, from her front-page mockup (2026-09-26, *"more color"*, *"The screens just look really white"*). `.front` on Home, sign-in and onboarding; `.page`, an even stronger wash, on list and detail screens; sheets keep the plain gradient. Not in the guide; Tara's and Kat's later word wins |
| Wordmark | `Wordmark`: the gator artwork over the "TENNIS" lockup at 6pt tracking, reversed to white. **The flanking F and E are part of the gator PNG itself**, so no separate initials are set; setting them doubled the letters |
| Buttons / nav rows | `NavRowLabel` (28pt radius, 56pt tall, icon slot, label, chevron); `FilledButtonLabel` = navy row, `OutlinedButtonLabel` = white row, so every existing call site picked the shape up |
| Greeting block | Home: the greeting in `greeting`, then "Let's Play." in `greetingAccent` gator-green, centered under the header; sign-in: "Let's Play." alone under the header |
| Spacing / radius | `Brand.Spacing.pageMargin` 24, `Brand.Radius.lg` 28 / `md` 16 / `sm` 8; web tokens the same |
| Text green | `Brand.courtText` `#446A30` for green **text** ("Let's Play." on Home and sign-in, the active tab's label); `Brand.court` `#4F7A38` stays for the header's line, the logo and every fill (Kat, 2026-10-01, decision 0036) |

## Kat's calls, answered (decision 0036, 2026-10-01)

Her three answers to the places the code could not follow the guide:
*"1. Keep it. 2. Use the darker green 3. I prefer the green line tbh"*.

1. **Tab bar: the system's.** iOS 26 draws the tab bar as floating glass and
   ignores a solid navy fill. It stays the system bar: outlined icon and
   label, green for the active tab, navy for the rest.
2. **Green text: the darker green.** Her gator-green `#4F7A38` measures
   4.42:1 on porcelain, under the 4.5:1 floor for small text, so text uses
   `Brand.courtText` `#446A30` (5.51:1 on porcelain, recomputed 2026-10-12
   with the WCAG formula); fills keep `#4F7A38`.
3. **The green line under the navy header stays**, straight, 4 points, under
   every page's banner (decision 0033). The arch was rejected on 2026-09-26
   by Alex and Kat.

Not set explicitly: line heights and the 0.2px tab-label tracking (the
fonts' own metrics apply). Tara's cream-to-warmer-cream gradient stays on top
of the guide (`Brand.surfaceGradient`, ending at `Brand.surfaceWarm`
`#EAE6DF`); a flat porcelain page would be one token. The status bar is white
on every screen since 2026-09-29 (`INFOPLIST_KEY_UIStatusBarStyle` in
`project.yml`).

## Status colours and accessibility

Folded in from `docs/archive/design-system.md` on 2026-10-12 and re-derived
from `FXETennis/Resources/Brand.swift` (`Brand.Status`, `StatusChip`). This
file owns them now.

**Status is never conveyed by colour alone.** Every status carries its
locked label and an SF Symbol, and the only way to draw one is `StatusChip`,
which renders the symbol, the label and the colours together and reads one
VoiceOver label. Reading `Status.ink` to tint a bare dot is the failure this
type exists to prevent. The chip wraps rather than truncates, so "Response
Needed" survives the largest Larger Text size.

| Status (locked label) | Symbol | Ink | Tint | Ink on tint | Ink on porcelain | VoiceOver |
|---|---|---|---|---|---|---|
| You're In! | `checkmark.circle.fill` | `#2C5A3E` forest | `#E7F0E7` | 6.83:1 | 6.99:1 | "Status: you're in" |
| Player Pool | `hourglass` | `#7A5E24` brass | `#F5EBD8` | 5.14:1 | 5.34:1 | "Status: in the Player Pool" |
| Response Needed | `exclamationmark.circle.fill` | `#1F4E5A` deep teal | `#DDEEF0` | 7.65:1 | 8.04:1 | "Status: response needed" |
| Canceled | `xmark.circle.fill` | `#992E22` brick red | `#F6DED9` | 5.91:1 | 6.66:1 | "Status: canceled" |

Ratios computed 2026-10-12 with the WCAG 2.1 relative-luminance formula; every
pair clears 4.5:1. `CLAUDE.md`'s "Visual direction" names the intent (green,
orange, yellow, red). The code keeps green and red, makes orange a brass dark
enough to read, and makes Response Needed deep teal rather than yellow,
because no yellow ink reaches 4.5:1 on a light ground and teal never reads as
the same hue as the brass. The symbol shapes (check, hourglass, exclamation,
cross) carry the meaning for anyone who cannot tell the hues apart.

The other accessibility rules the code follows:

- **Tap targets**: `Brand.Layout.minTapTarget` 44 points is a floor;
  `comfortableTapTarget` 52 for primary actions (the app is used standing on
  a court). Nav rows are 56 tall.
- **Larger Text**: every type style grows with the iPhone's setting
  (`.brandFont`, corrected 2026-09-27). Spacing does not scale, on purpose;
  wrap a gap in `@ScaledMetric` where it must track the text.
- **Icons always beside a text label**, never alone.
- **Apple's accessibility audit runs as a UI test** on the player's, Tara's
  and the pro's main screens (decision 0023); `scripts/measure-contrast.py`
  measures a finding from the screenshot before it is accepted.
- **Light mode only.** No dark tokens exist, and the app locks the light
  appearance (`INFOPLIST_KEY_UIUserInterfaceStyle` in `project.yml`). New
  colours go into `Brand.swift` and `web/tokens.css` together, never as a
  call-site literal.

## When the guide changes

Paste the new version above, dated; change `Brand.swift` first, then
`web/tokens.css`; open one PR with screenshots of every screen it touches;
re-run the copy gate (the wordmark's "TENNIS" is a string) and the UI suite.
