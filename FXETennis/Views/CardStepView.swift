//
//  CardStepView.swift
//  FXETennis
//
//  Onboarding step 2 of the Final Updates (2026-09-26): "1. Enter profile
//  data (name, rating, etc) 2. Enter CC information w/ disclosure check box
//  3. Then show available clinics." After the profile and the waiver, while
//  payments are on and a card is required, the app asks for the card before
//  Home. The screen is CardOnFileView (the permission box, Tara's sentence,
//  Stripe's sheet); this wraps it as a step that closes itself once the
//  webhook has recorded a card. Sign out is the one exit, so nobody is
//  stuck on a step they cannot finish (the CompleteProfileView lesson,
//  2026-08-15).
//
//  While payments are off (today, until Stripe is connected) the step never
//  appears, because register_for_clinic does not require a card then either.
//

import SwiftUI

struct CardStepView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        NavigationStack {
            ZStack {
                CourtBackdrop(strength: .front)
                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                        CardOnFileView()
                        Button("Sign out") { Task { await session.signOut() } }
                            .font(Brand.Typography.subheadline)
                            .foregroundStyle(Brand.textSecondary)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("cardStep.signOut")
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
            }
            .navigationTitle("Add a card")
            .navigationBarTitleDisplayMode(.inline)
        }
        .interactiveDismissDisabled()
    }
}

/// Presents the card step over the app after the waiver while a card is due.
private struct CardGate: ViewModifier {
    @Environment(SessionStore.self) private var session

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { session.waiverAccepted == true && session.cardStepDue },
                set: { _ in }
            )) { CardStepView() }
    }
}

extension View {
    func cardGate() -> some View { modifier(CardGate()) }
}
