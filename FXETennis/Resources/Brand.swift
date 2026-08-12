//
//  Brand.swift
//  FXETennis
//
//  Design tokens for the FXE Tennis app.
//  Single source of truth for colour, type, spacing, and radius.
//  The web admin mirrors this file at web/tokens.css. Change one, change both.
//
//  ============================================================================
//  SOURCE OF TRUTH: TARA'S PALETTE SHEETS (2026-08-02)
//  ============================================================================
//
//  Every colour below is either one of Tara's supplied hex values, a shade of
//  one of them, or an explicitly flagged addition. Nothing else was invented.
//
//  Supplied, palette "FXE 2":
//    #0E1239  deep navy        primary brand colour
//    #6DBE45  green            the gator green
//    #D5DF24  yellow-green     tennis ball accent
//    #FFFFFF  white
//
//  Supplied, palette "FXE 1":
//    #6F6E6F  grey, dark
//    #9E9F9F  grey, mid
//    #BBBBBB  grey, light
//
//  Token to source hex map:
//    Brand.navy            #0E1239   supplied
//    Brand.court           #6DBE45   supplied
//    Brand.accent          #D5DF24   supplied
//    Brand.surfaceRaised   #FFFFFF   supplied
//    Brand.textPrimary     #0E1239   supplied (navy)
//    Brand.textSecondary   #6F6E6F   supplied (grey, dark)
//    Brand.textOnNavy      #FFFFFF   supplied
//    Brand.textOnNavyMuted #BBBBBB   supplied (grey, light)
//    Brand.textOnCourt     #0E1239   supplied (navy)
//    Brand.textOnAccent    #0E1239   supplied (navy)
//    Brand.border          #6F6E6F   supplied (grey, dark)
//    Brand.hairline        #BBBBBB   supplied (grey, light)
//    Brand.disabled        #9E9F9F   supplied (grey, mid)
//    Brand.surface         #FAF7F1   >>> OUR CHOICE, NOT TARA'S <<<  see below
//    Status inks and tints           shades of the supplied greens, plus two
//                                    additions flagged in the STATUS section
//
//  ============================================================================
//  >>> OPEN ITEM FOR TARA: THE BACKGROUND COLOUR <<<
//  ============================================================================
//
//  The Developer Guide asks for cream or warm-white backgrounds. Tara's two
//  palette sheets contain no cream. Her only light value is pure #FFFFFF.
//
//  We chose #FAF7F1 and it is OUR choice, pending her approval. Reasoning:
//    1. It is warm without reading as beige. R 250, G 247, B 241 is a three
//       point drift toward amber, enough to soften the page under sunlight,
//       small enough that the navy still reads as the dominant colour.
//    2. It keeps #6F6E6F legible as secondary text at 4.75:1. Any darker warm
//       cream, for example #F7F4ED at 4.62:1, sits closer to the 4.5:1 floor
//       than is comfortable, and a warmer cream such as #F5F0E4 drops #6F6E6F
//       to roughly 4.4:1 and fails.
//    3. Navy on it lands at 16.87:1, so headings stay crisp on a phone held at
//       arm's length on a bright court.
//  If Tara supplies a cream of her own, replace this one constant and re-run
//  the contrast table in the ACCESSIBILITY section. Nothing else changes.
//
//  ============================================================================
//  APPEARANCE
//  ============================================================================
//
//  These tokens define the LIGHT appearance only. A dark palette would require
//  inventing surface colours Tara has not supplied, so the root view should set
//  .preferredColorScheme(.light) until she signs off on a dark set.
//  Flagged as an open item, not an oversight.
//

import SwiftUI

// MARK: - Colour

public enum Brand {

    // Brand core — PALETTE B, "full country club" (Tara, 2026-08-12: "lets do b for now").
    // Softer navy, forest green, a brass accent, a cream ground. The gator mark
    // is being redrawn in this palette to match. Palette A (her raw file colours)
    // lives in git history if she ever reverts.

    /// Primary brand colour. Bars, headings, primary buttons, body text.
    /// #16264C on the cream surface is ~13.6:1 — headings stay crisp in sunlight.
    public static let navy = Color(hex: 0x16264C)

    /// Forest green. Fill and small markers only. ~4.0:1 on the surface, below the
    /// 4.5 text floor, so it may never carry body text — use `textOnCourt` on it,
    /// or keep it to fills and the You're In! dot.
    public static let court = Color(hex: 0x3E7C55)

    /// Brass accent. Small highlights and the Player Pool marker. Fill, never text.
    public static let accent = Color(hex: 0xB08D57)

    // Surfaces.

    /// Page background. Warm cream — the country-club ground from option B.
    public static let surface = Color(hex: 0xF7F4EC)

    /// Cards and sheets lifted off the page.
    public static let surfaceRaised = Color(hex: 0xFFFFFF)

    /// Inverted surface: navy panels, the tab bar, hero headers.
    public static let surfaceInverted = Color(hex: 0x16264C)

    // Text.

    public static let textPrimary = Color(hex: 0x16264C)
    /// Secondary text. #6E6552 warm grey-brown is ~5.0:1 on the cream surface.
    public static let textSecondary = Color(hex: 0x6E6552)
    /// On navy: warm cream rather than pure white, so it belongs to this palette.
    public static let textOnNavy = Color(hex: 0xF6F3EA)
    public static let textOnNavyMuted = Color(hex: 0xCFC9BC)
    public static let textOnCourt = Color(hex: 0xFFFFFF)
    public static let textOnAccent = Color(hex: 0x231A0C)

    // Lines and states.

    /// Outline for interactive controls. #6E6552 clears the 3:1 non-text
    /// threshold on the surface, so it is safe as the sole marker of a control.
    public static let border = Color(hex: 0x6E6552)

    /// Decorative separators between rows inside an already bounded card.
    /// Warm and low-contrast by design; WCAG 1.4.11 exempts purely decorative
    /// graphics. Never use it to outline a control.
    public static let hairline = Color(hex: 0xE3DCCB)

    /// Disabled controls. WCAG exempts inactive components from contrast.
    /// Always pair a disabled control with visible helper text explaining why.
    public static let disabled = Color(hex: 0xB7B0A2)

    /// Focus and selection ring. Navy, for ~13.6:1 against the surface.
    public static let focusRing = Color(hex: 0x16264C)
}

// MARK: - Status

/// The four registration states. Terminology is locked in CLAUDE.md: do not
/// substitute synonyms for the `label` strings.
///
/// Accessibility contract, non-negotiable:
/// status is NEVER conveyed by colour alone. Every case carries a `label` and
/// an SF Symbol `symbolName`, and the only supported way to render a status is
/// `StatusChip`, which draws all three. If you find yourself reading `.ink`
/// directly to tint a bare dot, stop: that is the failure mode this type exists
/// to prevent.
public extension Brand {

    enum Status: String, CaseIterable, Sendable {
        case youreIn
        case playerPool
        case responseNeeded
        case canceled

        /// Visible text. Locked wording.
        public var label: String {
            switch self {
            case .youreIn: return "You're In!"
            case .playerPool: return "Player Pool"
            case .responseNeeded: return "Response Needed"
            case .canceled: return "Canceled"
            }
        }

        /// SF Symbol drawn beside the label. Shape carries the meaning for
        /// anyone who cannot separate these hues: filled check, hourglass,
        /// exclamation, cross. All four silhouettes differ at 16pt.
        public var symbolName: String {
            switch self {
            case .youreIn: return "checkmark.circle.fill"
            case .playerPool: return "hourglass"
            case .responseNeeded: return "exclamationmark.circle.fill"
            case .canceled: return "xmark.circle.fill"
            }
        }

        /// Text and icon colour. Also the only approved colour for a status
        /// marker of any kind, because the saturated hues fail 3:1 on light.
        public var ink: Color {
            switch self {
            case .youreIn: return Color(hex: 0x2C5A3E)         // forest, ~6.3:1 on its tint
            case .playerPool: return Color(hex: 0x7A5E24)      // brass, ~5.3:1 on its tint
            case .responseNeeded: return Color(hex: 0x1F4E5A)  // deep teal, distinct from both, ~7:1
            case .canceled: return Color(hex: 0x992E22)        // brick red, ~6.5:1
            }
        }

        /// Chip background. Pale enough that `ink` clears 4.5:1 on top of it.
        public var tint: Color {
            switch self {
            case .youreIn: return Color(hex: 0xE7F0E7)
            case .playerPool: return Color(hex: 0xF5EBD8)
            case .responseNeeded: return Color(hex: 0xDDEEF0)
            case .canceled: return Color(hex: 0xF6DED9)
            }
        }

        /// Read aloud by VoiceOver. Spelled out so the screen reader does not
        /// have to interpret an exclamation mark or a bare noun phrase.
        public var accessibilityLabel: String {
            switch self {
            case .youreIn: return "Status: you're in"
            case .playerPool: return "Status: in the Player Pool"
            case .responseNeeded: return "Status: response needed"
            case .canceled: return "Status: canceled"
            }
        }
    }
}

// MARK: - Typography

/// Type scale. Every entry is built from a system text style, so all of it
/// responds to Dynamic Type including the accessibility sizes. No fixed point
/// sizes appear anywhere in this file.
///
/// `display` and `title` use the serif design on purpose: New York gives the
/// country club register Tara asked for, while the body stays in SF for
/// legibility outdoors. Flip `displayDesign` to `.default` to undo that in one
/// place if she dislikes it.
public extension Brand {

    enum Typography {

        public static let displayDesign: Font.Design = .serif
        public static let bodyDesign: Font.Design = .default

        /// Screen hero, one per screen at most.
        public static let display = Font.system(.largeTitle, design: displayDesign, weight: .bold)
        /// Section heading.
        public static let title = Font.system(.title2, design: displayDesign, weight: .semibold)
        /// Card heading, for example a clinic name.
        public static let headline = Font.system(.headline, design: bodyDesign, weight: .semibold)
        /// Default reading size.
        public static let body = Font.system(.body, design: bodyDesign)
        /// Emphasised body, for example a date inside a card.
        public static let bodyEmphasis = Font.system(.body, design: bodyDesign, weight: .semibold)
        /// Supporting line under a heading.
        public static let subheadline = Font.system(.subheadline, design: bodyDesign)
        /// Metadata, timestamps.
        public static let caption = Font.system(.caption, design: bodyDesign)
        /// Status chips and small pills. Semibold because it is set small.
        public static let chip = Font.system(.caption, design: bodyDesign, weight: .semibold)
        /// Button text. Never smaller than body: these are pressed outdoors.
        public static let button = Font.system(.body, design: bodyDesign, weight: .semibold)
    }
}

// MARK: - Spacing

/// Four point base grid. These are raw points and do NOT scale with Dynamic
/// Type by design: scaling both text and gaps double-counts and pushes content
/// off screen at the accessibility sizes. Where a gap must track the text, wrap
/// it locally: `@ScaledMetric(relativeTo: .body) var gap = Brand.Spacing.md`.
public extension Brand {

    enum Spacing {
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 24
        public static let xl: CGFloat = 32
        public static let xxl: CGFloat = 48

        /// Standard page gutter.
        public static let pageMargin: CGFloat = 20
        /// Padding inside a card.
        public static let cardPadding: CGFloat = 16
    }
}

// MARK: - Radius and layout

public extension Brand {

    enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 10
        /// Default for cards.
        public static let md: CGFloat = 14
        /// Sheets and hero panels.
        public static let lg: CGFloat = 20
        /// Fully rounded. Status chips and pills.
        public static let pill: CGFloat = 999
    }

    enum Layout {
        /// Apple's minimum. Treat as a floor, not a target: this app is used
        /// standing on a court, often one handed.
        public static let minTapTarget: CGFloat = 44
        /// Preferred tap target for primary actions.
        public static let comfortableTapTarget: CGFloat = 52
        public static let hairlineWidth: CGFloat = 1
        public static let borderWidth: CGFloat = 1.5
    }
}

// MARK: - Status chip

/// The only approved way to render a status.
///
/// Draws the symbol, the locked label, and the tint together, so a status can
/// never ship as a bare coloured dot. Truncation is disabled: "Response Needed"
/// must survive the largest Dynamic Type sizes, which is why the chip wraps
/// rather than shrinks.
public struct StatusChip: View {

    private let status: Brand.Status

    public init(_ status: Brand.Status) {
        self.status = status
    }

    public var body: some View {
        HStack(spacing: Brand.Spacing.xxs) {
            Image(systemName: status.symbolName)
                .imageScale(.small)
            Text(status.label)
                .fixedSize(horizontal: false, vertical: true)
        }
        .font(Brand.Typography.chip)
        .foregroundStyle(status.ink)
        .padding(.horizontal, Brand.Spacing.xs)
        .padding(.vertical, Brand.Spacing.xxs)
        .background(status.tint, in: Capsule())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(status.accessibilityLabel)
    }
}

// MARK: - Hex helper

private extension Color {
    /// 0xRRGGBB. Kept private so no call site can smuggle in a colour that is
    /// not one of the tokens above.
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255.0,
            green: Double((hex >> 8) & 0xFF) / 255.0,
            blue: Double(hex & 0xFF) / 255.0,
            opacity: 1.0
        )
    }
}
//  ============================================================================
//  ACCESSIBILITY: MEASURED WCAG 2.1 CONTRAST RATIOS  (PALETTE B)
//  ============================================================================
//
//  Recomputed for palette B with the WCAG relative-luminance formula, sRGB,
//  2026-08-12 (script in the commit that introduced palette B). Thresholds:
//  4.5:1 body text, 3:1 large text and non-text UI components (1.4.3, 1.4.11).
//  Every pair below PASSES.
//
//  Foreground              Background              Ratio    Need  Result
//  ----------------------------------------------------------------------------
//  textPrimary   #16264C   surface       #F7F4EC   13.50:1  4.5   PASS
//  textPrimary   #16264C   surfaceRaised #FFFFFF   14.83:1  4.5   PASS
//  textSecondary #6E6552   surface       #F7F4EC    5.24:1  4.5   PASS
//  textSecondary #6E6552   surfaceRaised #FFFFFF    5.76:1  4.5   PASS
//  textOnNavy    #F6F3EA   navy          #16264C   13.37:1  4.5   PASS
//  textOnNavyMut #CFC9BC   navy          #16264C    8.99:1  4.5   PASS
//  textOnCourt   #FFFFFF   court         #3E7C55    4.98:1  4.5   PASS
//  textOnAccent  #231A0C   accent        #B08D57    5.55:1  4.5   PASS
//  border        #6E6552   surface       #F7F4EC    5.24:1  3.0   PASS
//
//  Status, ink on its own chip tint
//  youreIn        #2C5A3E on #E7F0E7                6.83:1  4.5   PASS
//  playerPool     #7A5E24 on #F5EBD8                5.14:1  4.5   PASS
//  responseNeeded #1F4E5A on #DDEEF0                7.65:1  4.5   PASS
//  canceled       #992E22 on #F6DED9                5.91:1  4.5   PASS
//
//  Status, ink on the page surface #F7F4EC
//  youreIn        #2C5A3E                           7.24:1  4.5   PASS
//  playerPool     #7A5E24                           5.53:1  4.5   PASS
//  responseNeeded #1F4E5A                           8.32:1  4.5   PASS
//  canceled       #992E22                           6.90:1  4.5   PASS
//
//  ----------------------------------------------------------------------------
//  FILL-ONLY COLOURS  (must never carry text or act as a status marker)
//  ----------------------------------------------------------------------------
//  court  #3E7C55 on surface #F7F4EC   4.53:1  — as a FILL it is fine; text on
//         it uses textOnCourt (white, 4.98:1). Never set body text in court green.
//  accent #B08D57 on surface #F7F4EC   2.81:1  — brass fill only. Never text.
//
//  Status markers use Status.ink (all >= 5:1 above), never court or accent,
//  which is why ink and tint are separate properties.
//
//  ----------------------------------------------------------------------------
//  PALETTE HISTORY
//  ----------------------------------------------------------------------------
//  Palette A (Tara's raw file colours: navy #0E1239, green #6DBE45, yellow
//  #D5DF24) shipped first and is in git history. Tara chose palette B ("full
//  country club") on 2026-08-12. If she reverts, the A ratios are in that
//  file's history.
