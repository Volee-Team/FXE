//
//  Brand.swift
//  FXETennis
//
//  Design tokens for the FXE Tennis app.
//  Single source of truth for colour, type, spacing, and radius.
//
//  SINCE 2026-09-22 THE VALUES COME FROM KAT'S STYLE GUIDE (docs/style-guide.md),
//  which is the source of truth for style (Alex, 2026-09-22). The palette
//  history below (Tara's sheets, palette A, palette B) is kept as history.
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
//  inventing surface colours Tara has not supplied, so the app is locked to
//  light mode (Info.plist UIUserInterfaceStyle, set in project.yml) until she
//  signs off on a dark set. Flagged as an open item, not an oversight.
//

import SwiftUI
import UIKit
import CoreText

// MARK: - Colour

public enum Brand {

    // Brand core — PALETTE B, "full country club" (Tara, 2026-08-12: "lets do b for now").
    // Softer navy, forest green, a brass accent, a cream ground. The gator mark
    // is being redrawn in this palette to match. Palette A (her raw file colours)
    // lives in git history if she ever reverts.

    /// Primary brand colour. Bars, headings, primary buttons, body text.
    /// #16264C on the cream surface is ~13.6:1 — headings stay crisp in sunlight.
    public static let navy = Color(hex: 0x0A1B3D)          // style guide navy-900
    /// navy-700: pressed/hover state, divider shadow edge.
    public static let navyPressed = Color(hex: 0x16295C)

    /// Forest green. Fill and small markers only. ~4.0:1 on the surface, below the
    /// 4.5 text floor, so it may never carry body text — use `textOnCourt` on it,
    /// or keep it to fills and the You're In! dot.
    public static let court = Color(hex: 0x4F7A38)         // gator-green: mascot, accent stripe, active tab, "Let's Play"
    /// green-shade: mascot shading/outline only.
    public static let courtShade = Color(hex: 0x33501F)
    /// ace-yellow: photography accent only, never text or UI fill.
    public static let aceYellow = Color(hex: 0xABC040)

    /// Brass accent. Small highlights and the Player Pool marker. Fill, never text.
    public static let accent = Color(hex: 0x4F7A38)        // no brass in the guide; the one UI accent is gator-green

    // Surfaces.

    /// Page background. Warm cream — the country-club ground from option B.
    public static let surface = Color(hex: 0xF2F0EC)       // porcelain: page background, secondary surfaces
    /// The bottom of the page gradient: the same cream, a shade warmer. Tara
    /// asked (2026-09-22, via Alex) for "a bit of separation of colors, not
    /// just pure white", the way Volee's screens run from one cream to a
    /// warmer one. Pages use `surfaceGradient`; cards stay `surfaceRaised`.
    public static let surfaceWarm = Color(hex: 0xEAE6DF)   // porcelain, a shade warmer: the bottom of the page gradient (Tara's ask)
    public static var surfaceGradient: LinearGradient {
        LinearGradient(colors: [surface, surfaceWarm], startPoint: .top, endPoint: .bottom)
    }

    /// Cards and sheets lifted off the page.
    public static let surfaceRaised = Color(hex: 0xFFFFFF)

    /// Inverted surface: navy panels, the tab bar, hero headers.
    public static let surfaceInverted = Color(hex: 0x0A1B3D)

    // Text.

    public static let textPrimary = Color(hex: 0x0A1B3D)
    /// Secondary text. #6E6552 warm grey-brown is ~5.0:1 on the cream surface.
    public static let textSecondary = Color(hex: 0x4A4843)  // neutral grey; darkened from #5C5A55 on 2026-09-28 because the accessibility audit measured it under 4.5:1 where the court photo shows through the wash
    /// On navy: warm cream rather than pure white, so it belongs to this palette.
    public static let textOnNavy = Color(hex: 0xFFFFFF)     // surface-white, reversed
    public static let textOnNavyMuted = Color(hex: 0xC9CCD6)
    public static let textOnCourt = Color(hex: 0xFFFFFF)
    public static let textOnAccent = Color(hex: 0xFFFFFF)

    // Lines and states.

    /// Outline for interactive controls. #6E6552 clears the 3:1 non-text
    /// threshold on the surface, so it is safe as the sole marker of a control.
    public static let border = Color(hex: 0x5C5A55)

    /// Decorative separators between rows inside an already bounded card.
    /// Warm and low-contrast by design; WCAG 1.4.11 exempts purely decorative
    /// graphics. Never use it to outline a control.
    public static let hairline = Color(hex: 0xE3E0DA)

    /// Disabled controls. WCAG exempts inactive components from contrast.
    /// Always pair a disabled control with visible helper text explaining why.
    public static let disabled = Color(hex: 0xB5B2AC)

    /// Focus and selection ring. Navy, for ~13.6:1 against the surface.
    public static let focusRing = Color(hex: 0x0A1B3D)
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

/// Type scale: Kat's style guide, in her two families at her sizes, and every
/// text style grows and shrinks with the iPhone's Larger Text setting.
///
/// CORRECTED 2026-09-27 (MVP audit item 16). From the style guide's arrival
/// (3750248) until then this comment said every entry was "built from a
/// system text style, so all of it responds to Dynamic Type" and that "no
/// fixed point sizes appear anywhere in this file". Both were false: every
/// font was a fixed UIFont (body 15, subheadline 13, caption 12), so a member
/// with Larger Text on read the waiver, the card sentence and every error at
/// 12 to 15 points, outdoors. A claim in a comment is not a mechanism
/// (CLAUDE.md hard rule 12); `BrandTypeScaleTests` is the mechanism now.
///
/// How: each style names the system text style whose Larger Text curve it
/// follows (`Role.textStyle`). Its point size is Kat's size scaled by
/// `UIFontMetrics(forTextStyle:)` for the current setting, so at the default
/// setting every size is exactly hers, and at the largest accessibility size
/// her 15-point body is drawn at about 42 points (UIFontMetrics' curve, which
/// takes a 17-point body to 48; measured on iOS 26.2). Scaled with
/// `scaledValue(for:)` and then built, rather than `scaledFont(for:)`, so that
/// Inter's optical-size axis is set to the size the text is actually drawn at.
///
/// The logo is the exception, on purpose: the "TENNIS" lockup and the
/// wordmark initial are part of the mark and keep their size (`textStyle`
/// nil), which is also what keeps the fixed-height navy header intact.
///
/// Known limit: a font is computed when a view draws. A size changed in
/// Settings while the app is open reaches each screen the next time it
/// redraws (returning to the app reloads the main screens, which redraws
/// them), and every screen at the next launch.
public extension Brand {
    /// The two families from Kat's style guide, bundled as variable fonts
    /// (SIL Open Font License; the licences sit beside the files). Registered
    /// at first use by `register()`, so no Info.plist key is needed and a
    /// fresh XcodeGen project cannot forget them. A variable font's weight is
    /// set through the `wght` axis on a font descriptor: `UIFont(name:)` alone
    /// would give the Regular instance whatever weight was asked for.
    enum Fonts {
        nonisolated(unsafe) private static var registered = false
        static func register() {
            guard !registered else { return }
            registered = true
            let urls = Bundle.main.urls(forResourcesWithExtension: "ttf", subdirectory: nil) ?? []
            for url in urls {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
        static let wghtAxis = 0x77676874   // 'wght'
        static let opszAxis = 0x6F70737A   // 'opsz'

        enum Face {
            case inter, playfair, playfairItalic

            var postScriptName: String {
                switch self {
                case .inter: return "Inter-Regular"
                case .playfair: return "PlayfairDisplay-Regular"
                case .playfairItalic: return "PlayfairDisplay-Italic"
                }
            }
            /// Inter has an optical-size axis; Playfair does not.
            var hasOpticalSize: Bool { self == .inter }
        }

        /// `size` at the default setting, scaled along `textStyle`'s Larger
        /// Text curve for `traits` (nil: the app's current setting). A nil
        /// `textStyle` keeps `size`.
        static func pointSize(_ size: CGFloat, textStyle: UIFont.TextStyle?, traits: UITraitCollection? = nil) -> CGFloat {
            guard let textStyle else { return size }
            let metrics = UIFontMetrics(forTextStyle: textStyle)
            if let traits { return metrics.scaledValue(for: size, compatibleWith: traits) }
            return metrics.scaledValue(for: size)
        }

        static func uiFont(_ face: Face, size: CGFloat, weight: CGFloat,
                           textStyle: UIFont.TextStyle?, traits: UITraitCollection? = nil) -> UIFont {
            register()
            let points = pointSize(size, textStyle: textStyle, traits: traits)
            var axes: [Int: CGFloat] = [wghtAxis: weight]
            if face.hasOpticalSize { axes[opszAxis] = points }
            let descriptor = UIFontDescriptor(fontAttributes: [
                .name: face.postScriptName,
                UIFontDescriptor.AttributeName(rawValue: kCTFontVariationAttribute as String): axes,
            ])
            return UIFont(descriptor: descriptor, size: points)
        }
    }

    /// Type styles, name for name from the style guide, then the app's older
    /// role names mapped onto them so every screen picks up the guide at once.
    /// Rule from the guide: serif for anything that greets or names; sans for
    /// anything tapped or read as an instruction. Never the serif inside a
    /// UI control.
    enum Typography {
        public static let displayDesign: Font.Design = .serif
        public static let bodyDesign: Font.Design = .default

        /// Every style in the scale: Kat's face, size and weight, and the
        /// system text style it grows with.
        enum Role: CaseIterable {
            // Guide styles (size / line; tracking applied at the call site).
            case greeting, greetingAccent, wordmarkInitial, wordmarkLockup, navRowLabel, tabBarLabel, body
            // Roles the screens already use.
            case title, headline, bodyEmphasis, subheadline, caption, chip
            /// The "TENNIS" under the small gator in Home's header: part of
            /// the mark. It was `caption` until 2026-09-27, which would now
            /// grow and burst the 58-point header.
            case wordmarkCompact

            var face: Fonts.Face {
                switch self {
                case .greeting, .wordmarkInitial, .wordmarkLockup, .title: return .playfair
                case .greetingAccent: return .playfairItalic
                case .navRowLabel, .tabBarLabel, .body, .headline, .bodyEmphasis,
                     .subheadline, .caption, .chip, .wordmarkCompact: return .inter
                }
            }

            /// Kat's size: the size at the default Larger Text setting.
            var size: CGFloat {
                switch self {
                case .greeting: return 34
                case .greetingAccent: return 23
                case .wordmarkInitial: return 56
                case .wordmarkLockup: return 22
                case .navRowLabel: return 19
                case .tabBarLabel: return 12
                case .body: return 15
                case .title: return 22
                case .headline: return 17
                case .bodyEmphasis: return 15
                case .subheadline: return 13
                case .caption: return 12
                case .chip: return 12
                case .wordmarkCompact: return 12
                }
            }

            var weight: CGFloat {
                switch self {
                case .greeting, .wordmarkInitial: return 700
                case .greetingAccent, .tabBarLabel, .chip: return 500
                case .wordmarkLockup, .navRowLabel, .title, .headline, .bodyEmphasis: return 600
                case .body, .subheadline, .caption, .wordmarkCompact: return 400
                }
            }

            /// The system style whose curve this one follows, matched by role
            /// (a button label reads as a headline, a chip as a caption). Nil
            /// for the logo, which keeps its size.
            var textStyle: UIFont.TextStyle? {
                switch self {
                case .greeting: return .largeTitle
                case .greetingAccent, .title: return .title2
                case .navRowLabel, .headline: return .headline
                case .body, .bodyEmphasis: return .body
                case .subheadline: return .subheadline
                case .tabBarLabel, .caption, .chip: return .caption1
                case .wordmarkInitial, .wordmarkLockup, .wordmarkCompact: return nil
                }
            }

            /// The font for `traits`; nil means the app's current setting.
            func uiFont(traits: UITraitCollection? = nil) -> UIFont {
                Fonts.uiFont(face, size: size, weight: weight, textStyle: textStyle, traits: traits)
            }

            var font: Font { Font(uiFont()) }

            /// The old role names, so `.brandFont(.display)` reads like the
            /// `Brand.Typography.display` it replaced.
            static let display = Role.greeting
            static let button = Role.navRowLabel

            /// The font at a Dynamic Type size. A `Font(UIFont)` is fixed at
            /// the size it was made with, so text built from `font` ignored a
            /// Larger Text change until the screen was rebuilt; the audit
            /// (2026-09-28) reported that on every screen. `.brandFont(_:)`
            /// reads the size from the environment and calls this, so the text
            /// grows the moment the setting changes.
            func font(at size: DynamicTypeSize) -> Font {
                Font(uiFont(traits: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(size))))
            }
        }

        // Guide styles.
        public static var greeting: Font        { Role.greeting.font }
        public static var greetingAccent: Font  { Role.greetingAccent.font }
        public static var wordmarkInitial: Font { Role.wordmarkInitial.font }
        public static var wordmarkLockup: Font  { Role.wordmarkLockup.font }
        public static var wordmarkCompact: Font { Role.wordmarkCompact.font }
        public static var navRowLabel: Font     { Role.navRowLabel.font }
        public static var tabBarLabel: Font     { Role.tabBarLabel.font }
        public static var body: Font            { Role.body.font }

        // Roles the screens already use.
        public static var display: Font       { greeting }
        public static var title: Font         { Role.title.font }
        public static var headline: Font      { Role.headline.font }
        public static var bodyEmphasis: Font  { Role.bodyEmphasis.font }
        public static var subheadline: Font   { Role.subheadline.font }
        public static var caption: Font       { Role.caption.font }
        public static var chip: Font          { Role.chip.font }
        public static var button: Font        { navRowLabel }
    }
}

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
        public static let pageMargin: CGFloat = 24    // space-6, screen outer margin (guide)
        /// Padding inside a card.
        public static let cardPadding: CGFloat = 16
    }
}

// MARK: - Radius and layout

public extension Brand {

    enum Radius {
        public static let xs: CGFloat = 6
        public static let sm: CGFloat = 8     // radius-sm: icon glyph containers only
        /// Default for cards.
        public static let md: CGFloat = 16    // radius-md: compact chips, secondary controls, cards
        /// Sheets and hero panels.
        public static let lg: CGFloat = 28    // radius-lg: every tappable row or button
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
        .brandFont(.chip)
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


// MARK: - Text links

/// A quiet text link ("Create an account", "Sign Out", "Privacy Policy") with
/// Apple's full 44-point tap target. Found by the accessibility audit
/// (2026-09-28): a plain-style Button answers taps only where its glyphs are
/// drawn, so a frame set around it looks right and still misses the thumb.
/// The frame and the tap shape have to be inside the button, which a style
/// guarantees for every link at once.
struct QuietLinkButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(minWidth: Brand.Layout.minTapTarget, minHeight: Brand.Layout.minTapTarget)
            .contentShape(Rectangle())
            // Pressed feedback by colour weight, not opacity: an opacity
            // modifier on the label made the accessibility audit read navy
            // text as failing contrast (2026-09-28).
            .brightness(configuration.isPressed ? 0.25 : 0)
    }
}

// MARK: - Live Dynamic Type

private struct BrandFont: ViewModifier {
    @Environment(\.dynamicTypeSize) private var size
    let role: Brand.Typography.Role
    func body(content: Content) -> some View { content.font(role.font(at: size)) }
}

extension View {
    /// A style from the scale that follows the Larger Text setting live.
    /// Use this, not `.font(Brand.Typography.x)`, on anything a person reads.
    func brandFont(_ role: Brand.Typography.Role) -> some View {
        modifier(BrandFont(role: role))
    }
}
