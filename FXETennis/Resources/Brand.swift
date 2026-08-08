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

    // Brand core.

    /// Primary brand colour. Bars, headings, primary buttons, body text.
    public static let navy = Color(hex: 0x0E1239)

    /// The gator green. Fill only. See the hard rule in the ACCESSIBILITY block:
    /// this colour is 2.16:1 on the surface, so it may never carry text or an icon.
    public static let court = Color(hex: 0x6DBE45)

    /// Tennis ball yellow-green. Small highlights, active indicators, never text.
    public static let accent = Color(hex: 0xD5DF24)

    // Surfaces.

    /// Page background. Warm off-white. Our choice, see the note above.
    public static let surface = Color(hex: 0xFAF7F1)

    /// Cards and sheets lifted off the page.
    public static let surfaceRaised = Color(hex: 0xFFFFFF)

    /// Inverted surface: navy panels, the tab bar, hero headers.
    public static let surfaceInverted = Color(hex: 0x0E1239)

    // Text.

    public static let textPrimary = Color(hex: 0x0E1239)
    public static let textSecondary = Color(hex: 0x6F6E6F)
    public static let textOnNavy = Color(hex: 0xFFFFFF)
    public static let textOnNavyMuted = Color(hex: 0xBBBBBB)
    public static let textOnCourt = Color(hex: 0x0E1239)
    public static let textOnAccent = Color(hex: 0x0E1239)

    // Lines and states.

    /// Outline for interactive controls. Passes the 3:1 non-text threshold, so
    /// it is safe when the border is the only thing marking a control's bounds.
    public static let border = Color(hex: 0x6F6E6F)

    /// Decorative separators between rows inside an already bounded card.
    /// 1.80:1 against the surface, which is below 3:1. WCAG 1.4.11 exempts
    /// purely decorative graphics, so this is allowed, but only where removing
    /// the line would lose no information. Never use it to outline a control.
    public static let hairline = Color(hex: 0xBBBBBB)

    /// Disabled controls. WCAG exempts inactive components from contrast, which
    /// is why 2.48:1 is acceptable here and nowhere else. Always pair a disabled
    /// control with visible helper text explaining why it is unavailable.
    public static let disabled = Color(hex: 0x9E9F9F)

    /// Focus and selection ring. Navy, for 16.87:1 against the surface.
    public static let focusRing = Color(hex: 0x0E1239)
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
            case .youreIn: return Color(hex: 0x2C6318)
            case .playerPool: return Color(hex: 0xA9500A)
            case .responseNeeded: return Color(hex: 0x565B00)
            case .canceled: return Color(hex: 0x992018)
            }
        }

        /// Chip background. Pale enough that `ink` clears 4.5:1 on top of it.
        public var tint: Color {
            switch self {
            case .youreIn: return Color(hex: 0xE4F3DC)
            case .playerPool: return Color(hex: 0xFBE9D5)
            case .responseNeeded: return Color(hex: 0xF6F8CE)
            case .canceled: return Color(hex: 0xFADFDC)
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
//  ACCESSIBILITY: MEASURED WCAG 2.1 CONTRAST RATIOS
//  ============================================================================
//
//  Computed with the WCAG relative luminance formula, sRGB, 2026-08-02.
//  Thresholds: 4.5:1 body text, 3:1 large text (>= 18pt regular or 14pt bold)
//  and non-text UI components, per 1.4.3 and 1.4.11.
//
//  Foreground              Background              Ratio     Need   Result
//  ----------------------------------------------------------------------------
//  textPrimary   #0E1239   surface       #FAF7F1   16.87:1   4.5    PASS
//  textPrimary   #0E1239   surfaceRaised #FFFFFF   18.04:1   4.5    PASS
//  textSecondary #6F6E6F   surface       #FAF7F1    4.75:1   4.5    PASS
//  textSecondary #6F6E6F   surfaceRaised #FFFFFF    5.08:1   4.5    PASS
//  textOnNavy    #FFFFFF   navy          #0E1239   18.04:1   4.5    PASS
//  textOnNavyMut #BBBBBB   navy          #0E1239    9.40:1   4.5    PASS
//  textOnCourt   #0E1239   court         #6DBE45    7.82:1   4.5    PASS
//  textOnAccent  #0E1239   accent        #D5DF24   12.38:1   4.5    PASS
//  court         #6DBE45   navy          #0E1239    7.82:1   4.5    PASS
//  accent        #D5DF24   navy          #0E1239   12.38:1   4.5    PASS
//  border        #6F6E6F   surface       #FAF7F1    4.75:1   3.0    PASS
//  focusRing     #0E1239   surface       #FAF7F1   16.87:1   3.0    PASS
//
//  Status, ink on the page surface #FAF7F1
//  youreIn        #2C6318                           6.76:1   4.5    PASS
//  playerPool     #A9500A                           5.12:1   4.5    PASS
//  responseNeeded #565B00                           6.79:1   4.5    PASS
//  canceled       #992018                           7.63:1   4.5    PASS
//
//  Status, ink on its own chip tint
//  youreIn        #2C6318 on #E4F3DC                6.25:1   4.5    PASS
//  playerPool     #A9500A on #FBE9D5                4.62:1   4.5    PASS
//  responseNeeded #565B00 on #F6F8CE                6.65:1   4.5    PASS
//  canceled       #992018 on #FADFDC                6.47:1   4.5    PASS
//
//  Status, white on a solid ink fill (destructive buttons, banners)
//  #FFFFFF on canceled  #992018                     8.16:1   4.5    PASS
//  #FFFFFF on playerPool #A9500A                    5.47:1   4.5    PASS
//
//  ----------------------------------------------------------------------------
//  PAIRS THAT FAIL, AND WHAT WE DID ABOUT THEM
//  ----------------------------------------------------------------------------
//
//  #FFFFFF on court #6DBE45              2.31:1   FAILS 4.5:1.
//      Fixed by rule, not by recolouring: green buttons take navy text
//      (textOnCourt, 7.82:1). White on the gator green is banned. If you see it
//      in a mockup, it is a bug.
//
//  court #6DBE45 on surface #FAF7F1      2.16:1   FAILS 4.5:1 and 3:1.
//  accent #D5DF24 on surface #FAF7F1     1.36:1   FAILS 4.5:1 and 3:1.
//      Both are fill-only colours. Neither may carry text or an icon, and
//      neither may act as a status marker. Status markers use Status.ink, which
//      is why `ink` and `tint` are separate properties.
//
//  hairline #BBBBBB on surface #FAF7F1   1.80:1   below 3:1.
//      Kept, restricted to decorative row separators inside an already bounded
//      card, which 1.4.11 exempts. Controls use `border` #6F6E6F at 4.75:1.
//
//  disabled #9E9F9F on surface #FAF7F1   2.48:1   below 4.5:1.
//      Kept. WCAG exempts inactive controls. Always pair with helper text so
//      the reason is legible even though the control is not.
//
//  ----------------------------------------------------------------------------
//  TWO STATUS COLOURS ARE ADDITIONS, NOT TARA'S
//  ----------------------------------------------------------------------------
//
//  The guide fixes four status colours: green, orange, yellow, red. Tara's
//  palette contains a green and a yellow-green but no orange and no red.
//
//    You're In        #2C6318 ink / #E4F3DC tint   shade of her green #6DBE45
//    Response Needed  #565B00 ink / #F6F8CE tint   shade of her yellow #D5DF24
//    Player Pool      #A9500A ink / #FBE9D5 tint   ADDED, no orange supplied
//    Canceled         #992018 ink / #FADFDC tint   ADDED, no red supplied
//
//  Both additions are muted and earthy rather than signal-bright, so they read
//  as country club rather than traffic light next to #0E1239. They are
//  functional status colours, not brand colours, and they never appear outside
//  a status chip or a destructive control. Flagged for Tara's approval.
//
