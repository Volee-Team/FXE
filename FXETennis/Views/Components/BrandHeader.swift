//
//  BrandHeader.swift
//  FXETennis
//
//  The navy header at the top of the front screens. Kat's style guide
//  (2026-09-22) drew it arching into the page with a green hairline along the
//  arch; built that way, it was rejected twice on 2026-09-23 (Alex: "legit
//  ugly"; a rounded-corner version, "even uglier"), and on 2026-09-26 Kat
//  settled it: "I'm not wild about the swoopy thing. I think I just like the
//  straight line across." So: navy, straight across, and the guide's single
//  gator-green line kept, straight, because the same message asked for "more
//  color". Tara's mockup of the front page (2026-09-26) has the same straight
//  edge.
//

import SwiftUI

struct BrandHeader<Content: View>: View {
    var height: CGFloat = 320
    /// The gator-green line along the bottom edge (style guide: one hairline).
    var lineWidth: CGFloat = 4
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            Brand.navy
            content()
        }
        .frame(height: height)
        .overlay(alignment: .bottom) {
            Brand.court.frame(height: lineWidth)
        }
        // The caller extends its own container under the status bar and pads
        // the content; doing it here leaked a safe-area inset into the scroll
        // view below (a dead band between the header and the greeting).
        .accessibilityElement(children: .contain)
    }
}

/// The wordmark, reversed to surface-white: the gator (whose artwork already
/// carries the flanking F and E, so no letters are set beside it) over the
/// "TENNIS" lockup. Tara, 2026-09-29: *"Can 'tennis' be smaller, logo bit
/// larger. So other way around"*, so the mark leads and the word sits small
/// under it (was 34/104 points of mark over 12/22 point type).
struct Wordmark: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : Brand.Spacing.xxs) {
            Image("gator-x")
                .resizable().scaledToFit()
                .frame(width: compact ? 50 : 150, height: compact ? 50 : 150)
            // Logo styles, which keep their size under Larger Text: the
            // header this sits in has a fixed height (Brand.swift, Typography).
            Text("TENNIS")
                .font(compact ? Brand.Typography.wordmarkCompact : Brand.Typography.wordmarkLockup)
                .tracking(compact ? 2 : 4)
        }
        .foregroundStyle(Brand.textOnNavy)
        // One element read as the logo it is. `.combine` still let the audit
        // reach "TENNIS" as text and report that it does not grow with
        // Larger Text, which is on purpose for a logo (2026-09-28).
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("FXE Tennis")
        .accessibilityAddTraits(.isImage)
        .accessibilityIdentifier("brand.wordmark")
    }
}

/// A tappable row from the guide: radius-lg, full width, 56 points tall,
/// leading icon slot, label, trailing chevron. `navy` alternates with white
/// row to row; it is not a primary/secondary hierarchy.
///
/// 56 is the height at the default text size, not a cap: with Larger Text
/// the label grows (Brand.Typography) and wraps, and the row grows with it.
/// Until 2026-09-27 the height was fixed and the label held to one line, so
/// at the accessibility sizes "View Open Clinics" was cut off.
struct NavRowLabel: View {
    let title: String
    var icon: String? = nil
    var navy: Bool = true

    var body: some View {
        HStack(spacing: Brand.Spacing.xs) {
            Group {
                if let icon {
                    Image(systemName: icon).font(.system(size: 20, weight: .regular))
                } else {
                    Color.clear
                }
            }
            .frame(width: 28, height: 28)
            Text(title)
                .brandFont(.navRowLabel)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: Brand.Spacing.xs)
            Image(systemName: "chevron.right").font(.system(size: 17, weight: .regular))
        }
        .foregroundStyle(navy ? Brand.textOnNavy : Brand.navy)
        .padding(.horizontal, Brand.Spacing.md)
        .padding(.vertical, Brand.Spacing.xs)
        .frame(maxWidth: .infinity)
        .frame(minHeight: 56)
        .background(navy ? Brand.navy : Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(navy ? Color.clear : Brand.hairline))
    }
}

extension View {
    /// White status bar text over a navy top (sign-in, launch, the load
    /// failure screen). SwiftUI sets the status bar only through a navigation
    /// bar's colour scheme, so the screen sits in a NavigationStack whose bar
    /// stays hidden. Home is already in one and sets the scheme itself. This
    /// works only because light mode is locked in Info.plist, not by
    /// `.preferredColorScheme(.light)`, which pinned the clock dark.
    func lightStatusBar() -> some View {
        NavigationStack {
            self
                .toolbar(.hidden, for: .navigationBar)
                .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}

extension View {
    /// The navy banner Kat kept asking for (2026-09-29: "dont forget the blue
    /// banner!"): the bar on navy with the gator-green line under it, the same
    /// ground and line as Home's header. The status bar is white app-wide
    /// (project.yml), not per screen: `toolbarColorScheme(.dark)` here turned
    /// iOS 26's back-button bubble pale blue under a white chevron (1.78:1).
    /// For a pushed screen or a sheet, whose title stays small and centred.
    ///
    /// SwiftUI's own toolbar modifiers, because iOS 26 drew a UIKit
    /// appearance's navy but not the large title on it (tried first, seen on
    /// the simulator). `scripts/check-title-edge.sh` fails the build on a
    /// titled screen without this or `bannerTitle`.
    func navyBanner() -> some View {
        self
            .safeAreaInset(edge: .top, spacing: 0) {
                Brand.court.frame(height: 4).accessibilityHidden(true)
            }
            .toolbarBackground(Brand.navy, for: .navigationBar)
            .toolbarBackground(.visible, for: .navigationBar)
    }

    /// A top-level page's title (Profile, Clinics, Today): the page name at
    /// the leading edge of the navy banner in the guide's serif, as in Kat's
    /// mockup. iOS 26 does not draw a large title under a solid bar, and its
    /// "inline large" title ignores the serif, so the name is a toolbar item
    /// and the system title is kept only for VoiceOver and the back button.
    /// On iOS 17, where the system title cannot be removed, the small centred
    /// title shows instead.
    func bannerTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .hidesBarTitle()
            .toolbar { BannerTitle(title: title) }
            .navyBanner()
    }

    /// A pushed screen's or a sheet's title: small and centred on the navy
    /// banner, white in the serif. Drawn as the bar's principal item because
    /// under SwiftUI's navy bar the system title ignored the appearance proxy
    /// and drew black (My Clinics, 2026-09-29).
    func navyTitle(_ title: String) -> some View {
        self
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { InlineBannerTitle(title: title) }
            .navyBanner()
    }
}

extension ToolbarContent {
    /// A bar button on the navy banner: white text (`.tint(Brand.textOnNavy)`
    /// on the button inside) and, on iOS 26, no glass bubble. The bubble turns
    /// light or dark by itself, so no one text colour read on both: navy
    /// "Done" vanished on a dark one, white on a light one (2026-09-29).
    /// Bare white on navy is what iOS 17 and 18 draw anyway.
    /// `scripts/check-title-edge.sh` fails on a ToolbarItem without it.
    @ToolbarContentBuilder func onNavy() -> some ToolbarContent {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            self.sharedBackgroundVisibility(.hidden)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// A banner title in the serif that grows with Larger Text as the setting
/// changes: the size is read from the environment, as `.brandFont` does,
/// because a `Font(UIFont)` stays at the size it was made (the audit failed
/// the first version of these titles on every screen, 2026-09-29).
private struct BannerTitleText: View {
    let title: String
    let size: CGFloat
    let textStyle: UIFont.TextStyle
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Text(title)
            .font(Font(Brand.Fonts.uiFont(.playfair, size: size, weight: 700, textStyle: textStyle,
                                          traits: UITraitCollection(preferredContentSizeCategory: UIContentSizeCategory(typeSize)))))
            .foregroundStyle(Brand.textOnNavy)
            .minimumScaleFactor(0.6)
            .accessibilityAddTraits(.isHeader)
    }
}

private struct InlineBannerTitle: ToolbarContent {
    let title: String

    var body: some ToolbarContent {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            item.sharedBackgroundVisibility(.hidden)
        } else {
            item
        }
        #else
        item
        #endif
    }

    private var item: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            BannerTitleText(title: title, size: 18, textStyle: .headline)
                .lineLimit(1)
        }
    }
}

private struct BannerTitle: ToolbarContent {
    let title: String

    var body: some ToolbarContent {
        if #available(iOS 18.0, *) {
            #if compiler(>=6.2)
            if #available(iOS 26.0, *) {
                // No glass capsule behind a title (iOS 26 gives every bar
                // item one).
                item.sharedBackgroundVisibility(.hidden)
            } else {
                item
            }
            #else
            item
            #endif
        }
    }

    private var item: some ToolbarContent {
        ToolbarItem(placement: .topBarLeading) {
            BannerTitleText(title: title, size: 30, textStyle: .largeTitle)
                .fixedSize()
        }
    }
}

extension View {
    /// iOS 26 fades content softly under a navigation bar. Under a large
    /// serif name that fade reads as a ghost behind the inline title (Profile,
    /// scrolled, seen 2026-09-28). A hard edge gives the bar a solid ground
    /// once content scrolls under it; earlier iOS versions already do this.
    func crispTopEdge() -> some View {
        modifier(CrispTopEdge())
    }

    /// Navy behind the status bar, for a screen that scrolls but has no
    /// navigation bar to cover the clock: without it the sign-up form's fields
    /// slid up under "9:41" (seen on the simulator, 2026-09-28). Navy, not the
    /// porcelain it was, since the clock is white app-wide (2026-09-29).
    /// Decoration only: no taps, nothing for VoiceOver.
    func statusBarScrim() -> some View {
        overlay(alignment: .top) {
            GeometryReader { geo in
                Brand.navy.frame(height: geo.safeAreaInsets.top)
                .ignoresSafeArea(edges: .top)
            }
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }
}

private struct CrispTopEdge: ViewModifier {
    func body(content: Content) -> some View {
        // The API exists only in the iOS 26 SDK (Xcode 26, Swift 6.2). CI's
        // runner built with an older Xcode and failed on the symbol itself, so
        // the compile-time guard comes first and #available second.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.scrollEdgeEffectStyle(.hard, for: .top)
        } else {
            content
        }
        #else
        content
        #endif
    }
}
