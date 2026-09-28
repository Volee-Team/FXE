//
//  StatusChipMotion.swift
//  FXETennis
//
//  The status chip changes over about a third of a second (2026-09-28):
//  Register to You're In!, Response Needed to You're In!, into the Pool.
//  Optional polish in the sense CLAUDE.md gives micro-animations: it never
//  delays a tap (SwiftUI animates while the screen stays live), and a static
//  chip would be just as correct.
//
//    * A chip appearing fades in and grows slightly; with Reduce Motion on,
//      it only fades (a crossfade is the replacement Apple's guidance asks
//      for, not no feedback at all).
//    * A chip changing status stays ONE chip: its colours and words
//      crossfade in place, so a screen reader and a UI test never find two.
//    * A chip going away (a cancel) leaves at once, unanimated.
//
//  The decisions are unit-tested (PlayerFeelTests).
//

import SwiftUI

enum StatusChipMotion {
    static let duration = 0.35

    enum Style: Equatable { case fadeAndScale, fadeOnly }

    static func style(reduceMotion: Bool) -> Style {
        reduceMotion ? .fadeOnly : .fadeAndScale
    }

    /// The animation for a change to `status`: none when the chip goes away.
    static func animation(to status: RegistrationStatus?) -> Animation? {
        status == nil ? nil : .easeInOut(duration: duration)
    }

    static func transition(_ style: Style) -> AnyTransition {
        switch style {
        case .fadeOnly: return .opacity
        case .fadeAndScale: return .opacity.combined(with: .scale(scale: 0.85))
        }
    }
}

private struct ChipMotion: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .transition(StatusChipMotion.transition(StatusChipMotion.style(reduceMotion: reduceMotion)))
            .contentTransition(.opacity)
    }
}

extension View {
    /// On the chip itself: how it enters, and how its words change.
    func statusChipMotion() -> some View {
        modifier(ChipMotion())
    }

    /// On the chip's container: animates a change of status (StatusChipMotion.animation).
    func animatesStatusChip(_ status: RegistrationStatus?) -> some View {
        animation(StatusChipMotion.animation(to: status), value: status)
    }
}
