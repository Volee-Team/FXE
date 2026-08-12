# FXE Tennis Design System

Single source of truth: **`FXETennis/Resources/Brand.swift`**. This document
transcribes that file. If a value here disagrees with `Brand.swift`, the Swift
file wins and this document is stale. The web admin mirrors the same tokens at
`web/tokens.css` (Brand.swift header: "Change one, change both").

**Palette:** B, "full country club." Chosen by Tara on 2026-08-12 ("lets do b for
now"). Softer navy, forest green, a brass accent, a cream ground.

**Appearance:** light only. A dark palette would require inventing surface
colours Tara has not supplied, so the root view sets
`.preferredColorScheme(.light)`. Dark mode is a flagged open item, not an
oversight.

**The palette is closed.** The `Color(hex:)` initialiser is `private` inside
`Brand.swift` on purpose: "Kept private so no call site can smuggle in a colour
that is not one of the tokens above." Never introduce a raw hex at a call site.
If you need a colour that is not a token, that is a conversation with Tara, not a
local literal.

Swift literals are written `Color(hex: 0xRRGGBB)`. This document shows the same
values as `#RRGGBB`.

---

## Contents

1. [Colour tokens](#colour-tokens)
2. [The fill-only rule](#the-fill-only-rule)
3. [Status system](#status-system)
4. [Typography](#typography)
5. [Spacing](#spacing)
6. [Radius](#radius)
7. [Layout](#layout)
8. [Accessibility: measured WCAG contrast](#accessibility-measured-wcag-contrast)
9. [Brand mark (logo)](#brand-mark-logo)
10. [Locked terminology](#locked-terminology)
11. [Visual direction](#visual-direction)
12. [Watch-outs](#watch-outs)

---

## Colour tokens

Every hex below is transcribed from `Brand.swift`. All are opaque (`opacity: 1.0`).

### Brand core

| Token | Hex | Role |
|---|---|---|
| `Brand.navy` | `#16264C` | Primary brand colour. Bars, headings, primary buttons, body text. ~13.6:1 on the cream surface, so headings stay crisp in sunlight. |
| `Brand.court` | `#3E7C55` | Forest green. **Fill and small markers only.** ~4.0:1 on the surface, below the 4.5 text floor, so it may never carry body text: use `textOnCourt` on it, or keep it to fills and the You're In! dot. |
| `Brand.accent` | `#B08D57` | Brass accent. Small highlights and the Player Pool marker. **Fill, never text.** |

### Surfaces

| Token | Hex | Role |
|---|---|---|
| `Brand.surface` | `#F7F4EC` | Page background. Warm cream, the country-club ground from option B. |
| `Brand.surfaceRaised` | `#FFFFFF` | Cards and sheets lifted off the page. |
| `Brand.surfaceInverted` | `#16264C` | Navy panels, the tab bar, hero headers. (Same value as `navy`.) |

### Text

| Token | Hex | Role |
|---|---|---|
| `Brand.textPrimary` | `#16264C` | Primary text. (Same value as `navy`.) |
| `Brand.textSecondary` | `#6E6552` | Secondary text. Warm grey-brown, ~5.0:1 on the cream surface. |
| `Brand.textOnNavy` | `#F6F3EA` | Text on navy. Warm cream rather than pure white, so it belongs to this palette. |
| `Brand.textOnNavyMuted` | `#CFC9BC` | Muted text on navy. |
| `Brand.textOnCourt` | `#FFFFFF` | Text set on top of `court` green fills. |
| `Brand.textOnAccent` | `#231A0C` | Text set on top of `accent` brass fills. |

### Lines and states

| Token | Hex | Role |
|---|---|---|
| `Brand.border` | `#6E6552` | Outline for interactive controls. Clears the 3:1 non-text threshold on the surface, so it is safe as the sole marker of a control. (Same value as `textSecondary`.) |
| `Brand.hairline` | `#E3DCCB` | Decorative separators between rows inside an already bounded card. Warm and low-contrast by design; WCAG 1.4.11 exempts purely decorative graphics. **Never use it to outline a control.** |
| `Brand.disabled` | `#B7B0A2` | Disabled controls. WCAG exempts inactive components from contrast. **Always pair a disabled control with visible helper text explaining why.** |
| `Brand.focusRing` | `#16264C` | Focus and selection ring. Navy, for ~13.6:1 against the surface. (Same value as `navy`.) |

---

## The fill-only rule

`court` and `accent` are **fill colours**. They may never carry text and may
never act as a status marker.

| Token | Hex | On surface `#F7F4EC` | Verdict |
|---|---|---|---|
| `court` | `#3E7C55` | 4.53:1 | Fine as a **fill**. Text on it must use `textOnCourt` (white, 4.98:1). Never set body text in court green. |
| `accent` | `#B08D57` | 2.81:1 | **Brass fill only. Never text.** |

Status markers use `Status.ink` (all ≥ 5:1 measured, see below), never `court`
or `accent`. That separation is exactly why `ink` and `tint` are distinct
properties on `Status`.

---

## Status system

The four registration states. Terminology is locked (see
[Locked terminology](#locked-terminology)): **do not substitute synonyms for the
`label` strings.**

### The accessibility contract (non-negotiable)

> Status is **NEVER conveyed by colour alone.** Every case carries a `label` and
> an SF Symbol, and the **only supported way to render a status is
> `StatusChip`**, which draws the symbol, the locked label, and the tint
> together. If you find yourself reading `.ink` directly to tint a bare dot,
> stop: that is the failure mode this type exists to prevent.

`StatusChip` is a `Capsule`-shaped chip: symbol + label, `ink` foreground on a
`tint` background, with `.accessibilityLabel(status.accessibilityLabel)`.
Truncation is disabled so "Response Needed" survives the largest Dynamic Type
sizes; the chip wraps rather than shrinks.

### The four cases

| Case | `label` (locked) | SF Symbol | `ink` | `tint` |
|---|---|---|---|---|
| `youreIn` | **You're In!** | `checkmark.circle.fill` | `#2C5A3E` | `#E7F0E7` |
| `playerPool` | **Player Pool** | `hourglass` | `#7A5E24` | `#F5EBD8` |
| `responseNeeded` | **Response Needed** | `exclamationmark.circle.fill` | `#1F4E5A` | `#DDEEF0` |
| `canceled` | **Canceled** | `xmark.circle.fill` | `#992E22` | `#F6DED9` |

The symbol silhouettes are deliberately distinct at 16pt (filled check,
hourglass, exclamation, cross) so shape carries the meaning for anyone who
cannot separate the hues.

`ink` is also "the only approved colour for a status marker of any kind, because
the saturated hues fail 3:1 on light." Code descriptors for each ink: forest
(`youreIn`), brass (`playerPool`), deep teal (`responseNeeded`, deliberately
distinct from the other two), brick red (`canceled`). Authoritative measured
ratios are in the [contrast table](#accessibility-measured-wcag-contrast).

### VoiceOver labels

`StatusChip` collapses to one accessibility element reading `accessibilityLabel`,
spelled out so the screen reader does not have to interpret punctuation:

| Case | `accessibilityLabel` |
|---|---|
| `youreIn` | `Status: you're in` |
| `playerPool` | `Status: in the Player Pool` |
| `responseNeeded` | `Status: response needed` |
| `canceled` | `Status: canceled` |

---

## Typography

`Brand.Typography.*`. Every entry is built from a system text style, so all of it
responds to Dynamic Type including the accessibility sizes. **No fixed point
sizes appear anywhere in `Brand.swift`.**

Two design families, both flags at the top of the enum:

- `displayDesign = .serif` (New York). Used by `display` and `title` on purpose:
  the serif gives the country-club register Tara asked for.
- `bodyDesign = .default` (SF). Everything else, for legibility outdoors.

To undo the serif in one place, flip `displayDesign` to `.default`.

| Token | Text style | Design | Weight | Use |
|---|---|---|---|---|
| `display` | `.largeTitle` | serif | bold | Screen hero, one per screen at most. |
| `title` | `.title2` | serif | semibold | Section heading. |
| `headline` | `.headline` | default | semibold | Card heading, e.g. a clinic name. |
| `body` | `.body` | default | regular | Default reading size. |
| `bodyEmphasis` | `.body` | default | semibold | Emphasised body, e.g. a date inside a card. |
| `subheadline` | `.subheadline` | default | regular | Supporting line under a heading. |
| `caption` | `.caption` | default | regular | Metadata, timestamps. |
| `chip` | `.caption` | default | semibold | Status chips and small pills. Semibold because it is set small. |
| `button` | `.body` | default | semibold | Button text. Never smaller than body: these are pressed outdoors. |

---

## Spacing

`Brand.Spacing.*`. A four-point base grid.

**These are raw points and do NOT scale with Dynamic Type by design:** scaling
both text and gaps double-counts and pushes content off screen at the
accessibility sizes. Where a gap must track the text, wrap it locally:
`@ScaledMetric(relativeTo: .body) var gap = Brand.Spacing.md`.

| Token | Points |
|---|---|
| `xxs` | 4 |
| `xs` | 8 |
| `sm` | 12 |
| `md` | 16 |
| `lg` | 24 |
| `xl` | 32 |
| `xxl` | 48 |
| `pageMargin` | 20 (standard page gutter) |
| `cardPadding` | 16 (padding inside a card) |

---

## Radius

`Brand.Radius.*`.

| Token | Points | Use |
|---|---|---|
| `xs` | 6 | |
| `sm` | 10 | |
| `md` | 14 | Default for cards. |
| `lg` | 20 | Sheets and hero panels. |
| `pill` | 999 | Fully rounded. Status chips and pills. |

---

## Layout

`Brand.Layout.*`.

| Token | Value | Note |
|---|---|---|
| `minTapTarget` | 44 | Apple's minimum. Treat as a floor, not a target: this app is used standing on a court, often one-handed. |
| `comfortableTapTarget` | 52 | Preferred tap target for primary actions. |
| `hairlineWidth` | 1 | |
| `borderWidth` | 1.5 | |

---

## Accessibility: measured WCAG contrast

Reproduced verbatim from the `ACCESSIBILITY` block at the end of `Brand.swift`.
Recomputed for palette B with the WCAG 2.1 relative-luminance formula, sRGB,
2026-08-12. Thresholds: 4.5:1 body text, 3:1 large text and non-text UI
components (1.4.3, 1.4.11). **Every pair below PASSES.**

```
Foreground              Background              Ratio    Need  Result
----------------------------------------------------------------------------
textPrimary   #16264C   surface       #F7F4EC   13.50:1  4.5   PASS
textPrimary   #16264C   surfaceRaised #FFFFFF   14.83:1  4.5   PASS
textSecondary #6E6552   surface       #F7F4EC    5.24:1  4.5   PASS
textSecondary #6E6552   surfaceRaised #FFFFFF    5.76:1  4.5   PASS
textOnNavy    #F6F3EA   navy          #16264C   13.37:1  4.5   PASS
textOnNavyMut #CFC9BC   navy          #16264C    8.99:1  4.5   PASS
textOnCourt   #FFFFFF   court         #3E7C55    4.98:1  4.5   PASS
textOnAccent  #231A0C   accent        #B08D57    5.55:1  4.5   PASS
border        #6E6552   surface       #F7F4EC    5.24:1  3.0   PASS

Status, ink on its own chip tint
youreIn        #2C5A3E on #E7F0E7                6.83:1  4.5   PASS
playerPool     #7A5E24 on #F5EBD8                5.14:1  4.5   PASS
responseNeeded #1F4E5A on #DDEEF0                7.65:1  4.5   PASS
canceled       #992E22 on #F6DED9                5.91:1  4.5   PASS

Status, ink on the page surface #F7F4EC
youreIn        #2C5A3E                           7.24:1  4.5   PASS
playerPool     #7A5E24                           5.53:1  4.5   PASS
responseNeeded #1F4E5A                           8.32:1  4.5   PASS
canceled       #992E22                           6.90:1  4.5   PASS

----------------------------------------------------------------------------
FILL-ONLY COLOURS  (must never carry text or act as a status marker)
----------------------------------------------------------------------------
court  #3E7C55 on surface #F7F4EC   4.53:1  — as a FILL it is fine; text on
       it uses textOnCourt (white, 4.98:1). Never set body text in court green.
accent #B08D57 on surface #F7F4EC   2.81:1  — brass fill only. Never text.
```

Status markers use `Status.ink` (all ≥ 5:1 above), never `court` or `accent`,
which is why `ink` and `tint` are separate properties.

If Tara ever supplies a different cream, replace the single `surface` constant
and re-run this table. Nothing else changes.

> The short `~` estimates in the inline `Status.ink` comments (e.g. "~6.3:1") are
> hand approximations. The measured table above is the authority.

---

## Brand mark (logo)

Files:
- `FXETennis/Resources/Brand/gator-x.png` (raster)
- `FXETennis/Resources/Brand/gator-x.pdf` (vector source)

The mark Tara chose (decision 22, 2026-08-12): **the gator with crossed
racquets**, not the tennis-ball-only one. Composition in the current asset:

- A forward-facing gator head, centred.
- Two racquets crossed behind it forming an **X** (the "x" in `gator-x`).
- The letters **F** and **E** flanking left and right.
- A tennis ball at the gator's mouth.

**Palette status — read this before using the file.** The current
`gator-x.png` is still rendered in the **grey + yellow-green** treatment (grey
gator, grey racquets, grey F/E, a yellow-green ball). It is **not yet in palette
B.** `Brand.swift` states the mark "is being redrawn in this palette to match"
(present tense: in progress), and decisions 22 and 23 confirm the mark "gets
redrawn in whichever palette she picks" and palette B is that pick. Until the
redrawn asset lands, do not treat the shipped PNG as palette-accurate. When it is
redrawn, its colours should come from the tokens above (navy `#16264C`, court
`#3E7C55`, accent `#B08D57` on the cream ground), not new hexes.

---

## Locked terminology

Use these exact words in all UI copy. Do not substitute synonyms. (From
`CLAUDE.md`; the status `label` strings above are the same words and are locked
in `Brand.swift` too.)

| Term | Meaning |
|---|---|
| **You're In!** | The player has an active spot. Never "Confirmed", "Accepted", or "Registered". |
| **Player Pool** | Waiting for Tara's selection. Never "waitlist", "standby", or "reserve list". |
| **Response Needed** | Tara invited them; they must Accept or Decline. |
| **Canceled** | The registration or clinic is canceled. |
| **Action Needed** | Admin work requiring Tara's attention. |
| **My Clinics** | The player's upcoming registered clinics and Player Pool entries. |
| **Service week** | Sunday through Saturday, America/New_York. Internal vocabulary, not player-facing. |
| **Ladies / Men / Coed** | The three v1 audiences. Juniors return in the fall. |

---

## Visual direction

From `CLAUDE.md`. The principles the tokens serve:

- Navy country-club styling, **not** bright royal blue.
- Cream or warm-white backgrounds, clean cards, restrained green accents.
- **Large text and generous tap areas for outdoor use.**
- **Icons always paired with text labels.**
- Player screens must never feel like long blocks of writing.
- Micro-animations last about one second, never delay interaction, and are
  optional. A static reliable state is always acceptable.

**Status colours, always paired with text (never colour alone).** The plain-
language intent in `CLAUDE.md`:

| Intent colour | Status |
|---|---|
| Green | You're In! |
| Orange | Player Pool |
| Yellow | Response Needed |
| Red | Canceled |

The code realises this **accessibly**, which is why two of the four inks are not
the literal word:

- You're In! → forest green `#2C5A3E` (matches "green").
- Player Pool → brass `#7A5E24` (the amber/orange family, made dark enough to
  pass on light).
- Response Needed → deep teal `#1F4E5A`, **not yellow**: a yellow ink cannot
  reach 4.5:1 on light, and teal is deliberately distinct from the brass so the
  two never read as the same hue.
- Canceled → brick red `#992E22` (matches "red").

The hue is never the sole signal anyway: the symbol and the locked label carry
the meaning. See the [status contract](#the-accessibility-contract-non-negotiable).

---

## Watch-outs

Things that will trip a new reader of `Brand.swift`.

1. **The top-of-file header comment describes palette A, not B.** The header's
   "Token to source hex map" and its `surface #FAF7F1` note are the **palette A**
   narrative that predates the 2026-08-12 switch. The live constants (navy
   `#16264C`, court `#3E7C55`, accent `#B08D57`, surface `#F7F4EC`, …) are
   palette B and are what compiles. When the two disagree, the constants win.
   Do not transcribe values out of the header comment.
2. **Palette history.** Palette A (Tara's raw file colours: navy `#0E1239`,
   green `#6DBE45`, yellow `#D5DF24`) shipped first and lives in git history. If
   she ever reverts to A, its contrast table is in that file's history.
3. **Light only, for now.** No dark tokens exist. Do not add them without Tara
   supplying dark surface colours.
4. **The palette is closed.** `Color(hex:)` is private. New colours go through
   Tara, then into `Brand.swift` and `web/tokens.css` together, never as a call-
   site literal.
5. **Spacing does not scale with Dynamic Type**; type does. Wrap a gap in
   `@ScaledMetric` locally if it must track the text.
