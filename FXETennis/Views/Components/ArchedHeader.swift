//
//  ArchedHeader.swift
//  FXETennis
//
//  The header from Kat's style guide (docs/style-guide.md, 2026-09-22):
//  navy-900, full width, arching into the porcelain body, with a single
//  gator-green hairline (about 6pt) that follows the arch. One instance per
//  screen, never a repeatable rule style.
//

import SwiftUI

/// A rectangle whose bottom edge bows downward into a shallow arch.
struct ArchedBottom: Shape {
    /// How far the arch drops below the straight edge, in points.
    var depth: CGFloat = 28

    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - depth),
                       control: CGPoint(x: rect.midX, y: rect.maxY + depth))
        p.closeSubpath()
        return p
    }

    /// Only the arched edge, for the hairline.
    func edge(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.maxX, y: rect.maxY - depth))
        p.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.maxY - depth),
                       control: CGPoint(x: rect.midX, y: rect.maxY + depth))
        return p
    }
}

struct ArchedHeader<Content: View>: View {
    var height: CGFloat = 320
    var depth: CGFloat = 28
    @ViewBuilder var content: () -> Content

    var body: some View {
        ZStack(alignment: .top) {
            GeometryReader { geo in
                let rect = CGRect(origin: .zero, size: geo.size)
                let shape = ArchedBottom(depth: depth)
                shape.fill(Brand.navy)
                shape.edge(in: rect).stroke(Brand.court, lineWidth: 6)
            }
            content()
        }
        .frame(height: height)
        // The caller extends its own container under the status bar and pads
        // the content; doing it here leaked a safe-area inset into the scroll
        // view below (a dead band between the arch and the greeting).
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
                .frame(width: compact ? 44 : 120, height: compact ? 44 : 120)
            Text("TENNIS")
                .font(compact ? Brand.Typography.chip : Brand.Typography.wordmarkLockup)
                .tracking(compact ? 3 : 6)
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
