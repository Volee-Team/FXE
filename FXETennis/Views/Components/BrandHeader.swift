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
/// "TENNIS" lockup, wordmark-lockup with 6pt tracking.
struct Wordmark: View {
    var compact = false

    var body: some View {
        VStack(spacing: compact ? 0 : Brand.Spacing.xs) {
            Image("gator-x")
                .resizable().scaledToFit()
                .frame(width: compact ? 34 : 104, height: compact ? 34 : 104)
            Text("TENNIS")
                .font(compact ? Brand.Typography.caption : Brand.Typography.wordmarkLockup)
                .tracking(compact ? 2.5 : 6)
        }
        .foregroundStyle(Brand.textOnNavy)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("FXE Tennis")
    }
}

/// A tappable row from the guide: radius-lg, full width, fixed height,
/// leading icon slot, label, trailing chevron. `navy` alternates with white
/// row to row; it is not a primary/secondary hierarchy.
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
                .font(Brand.Typography.navRowLabel)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
            Spacer(minLength: Brand.Spacing.xs)
            Image(systemName: "chevron.right").font(.system(size: 17, weight: .regular))
        }
        .foregroundStyle(navy ? Brand.textOnNavy : Brand.navy)
        .padding(.horizontal, Brand.Spacing.md)
        .frame(maxWidth: .infinity)
        .frame(height: 56)
        .background(navy ? Brand.navy : Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(navy ? Color.clear : Brand.hairline))
    }
}
