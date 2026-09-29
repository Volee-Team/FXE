//
//  LoadingPlaceholders.swift
//  FXETennis
//
//  Shapes of the list while its first load is out, instead of a spinner
//  (roadmap wow list, 2026-09-28). With instant open (decision 0028) this is
//  only ever seen on a first sign-in or a phone with no snapshot yet, which
//  is exactly the first impression. No words, no data: grey bars where the
//  name and the times will be. A slow breathing fade, off under Reduce Motion
//  (a static state is always acceptable). VoiceOver hears one "Loading".
//

import SwiftUI

/// Grey bars in the proportions of a ClinicCard.
struct PlaceholderClinicCards: View {
    var count = 3

    var body: some View {
        VStack(spacing: Brand.Spacing.md) {
            ForEach(0..<count, id: \.self) { i in
                VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
                    PlaceholderBar(widthFraction: i % 2 == 0 ? 0.62 : 0.5, height: 20)
                    PlaceholderBar(widthFraction: 0.48, height: 14)
                    PlaceholderBar(widthFraction: 0.32, height: 14)
                    PlaceholderBar(widthFraction: 0.36, height: 14)
                }
                .padding(Brand.Spacing.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
            }
        }
        .breathing()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

/// Grey bars in the proportions of Home's rows: a name, then a day and time.
struct PlaceholderRows: View {
    var count = 3

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
            ForEach(0..<count, id: \.self) { i in
                VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                    PlaceholderBar(widthFraction: i % 2 == 0 ? 0.58 : 0.46, height: 18)
                    PlaceholderBar(widthFraction: 0.36, height: 14)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .breathing()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Loading")
    }
}

private struct PlaceholderBar: View {
    let widthFraction: CGFloat
    let height: CGFloat

    var body: some View {
        GeometryReader { geo in
            Capsule()
                .fill(Brand.disabled.opacity(0.35))
                .frame(width: geo.size.width * widthFraction, height: height)
        }
        .frame(height: height)
    }
}

private struct Breathing: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(reduceMotion ? 1 : (dim ? 0.55 : 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true)) { dim = true }
            }
    }
}

private extension View {
    func breathing() -> some View { modifier(Breathing()) }
}
