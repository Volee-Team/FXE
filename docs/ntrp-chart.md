# NTRP Rating Chart

The rating scale FXE shows behind the tappable "?" button.

## Why this is copied, not written

Tara asked for the same scale and the same explanatory chart Volee already
uses. A player who uses both apps must read identical words in both. So this
copy is mirrored, verbatim, from the Volee repo.

Source files in `~/Documents/GITHUB/Volee`:

| What | File | Symbol |
|---|---|---|
| Level list and full descriptions | `Volee/Models/Profile+Adult.swift` | `enum NTRPDescriptions.selfRate` |
| Bucket values, labels, `5.0+` ceiling rule | `Volee/Models/Profile+Adult.swift` | `enum NTRP` |
| Short one-line blurbs | `Volee/Views/TutorialView.swift` | `TutorialNTRPPage.buckets` |

FXE implementation: `FXETennis/Models/NTRPRating.swift`.

**Change rule:** if the wording changes, change it in both repos in the same
pass. Editing one side alone is the failure mode this file exists to prevent.

## The seven levels

Seven buckets, 2.0 through 5.0+, in half-point steps. Display order is
ascending. 5.0 is the ceiling: anyone at or above 5.0 sits in that one row,
which is why it renders with a "+".

| Level | Short blurb | Full description |
|---|---|---|
| 2.0 | Very new | Very new player with minimal experience, learning basic strokes and struggling to sustain a rally |
| 2.5 | Beginner with limited consistency | Beginner with limited consistency, can rally slowly but lacks control, directional intent, and serve reliability |
| 3.0 | Developing player, short rallies | Developing player who can sustain short rallies with moderate pace, working on consistency, court positioning, and basic strategy |
| 3.5 | Intermediate, directional control | Intermediate player with improved consistency and directional control, can rally with pace, use some spin, and demonstrate basic match strategy |
| 4.0 | Solid, dependable strokes | Solid player with dependable strokes, can control depth and direction, handle pace, and execute point construction with moderate success |
| 4.5 | Advanced, dictates play | Advanced player with strong, consistent strokes, can dictate play, use spin and variety effectively, and compete with aggressive strategy |
| 5.0+ | High-level competitor | High-level player with excellent shot tolerance, power, and precision, capable of advanced tactics and competing at elite sectional/national levels |

Row headings in Volee read "USTA 3.5", not a bare number. `NTRPRating.displayName`
produces the same string.

## Levels below 2.0

Volee's scale starts at 2.0. Its own header comment mentions a wider 1.5 to 7.0
range for internal rating math, but the user-facing bucket list is 2.0 to 5.0
only, and there is no descriptive copy for 1.5 or for anything above 5.0. FXE
mirrors the user-facing list. No text was invented to fill the gap.

## Copy deliberately not carried over

Volee's tutorial page wraps the chart in ladder-specific framing: a subtitle
about beating someone above you to climb, and four month seasons with a soft
reset. That is Volee's competitive ladder, which FXE does not have. It was left
out on purpose. Only the per-level copy is shared.

Two other lines sit near the chart in Volee's onboarding and were also left out,
since they describe Volee's rating lock and settings screen rather than the
scale itself:

- "You won't be able to change your rating until next season."
- "Self-rated. You can change to a USTA-verified rating later in Settings."

## API

`NTRPRating` is a `Double`-backed enum. The raw value is the numeric rating,
matching what Volee stores, so a rating moves between systems with no
translation table.

- `displayOrder: Int`, ascending, 0 for 2.0.
- `displayOrdered: [NTRPRating]`, the render order for the chart.
- `label`, for example "3.5" or "5.0+".
- `displayName`, for example "USTA 3.5".
- `detail`, the full description for the chart.
- `summary`, the one-line blurb for compact rows.
- `init?(rating:)`, resolves a stored number to a bucket. Anything at or above
  5.0 collapses to the 5.0+ ceiling. Anything below 2.0 returns nil.
