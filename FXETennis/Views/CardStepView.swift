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
//  webhook has recorded a card. CardOnFileView asks for the summary every 2
//  seconds for about 30 after Stripe's sheet says the card is saved (it used
//  to ask once, after 2), then offers Refresh, so a slow webhook no longer
//  looks like a card that failed. Sign out and Delete my account are the
//  exits (AccountExitFooter, as on the profile form and the waiver), so
//  nobody is stuck on a step they cannot finish (the CompleteProfileView
//  lesson, 2026-08-15).
//
//  While payments are off (today, until Stripe is connected) the step never
//  appears, because register_for_clinic does not require a card then either.
//

import SwiftUI

struct CardStepView: View {
    var body: some View {
        NavigationStack {
            ZStack {
                CourtBackdrop(strength: .front)
                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                        CardOnFileView()
                        AccountExitFooter(signOutID: "cardStep.signOut", deleteID: "cardStep.delete")
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
            }
            .crispTopEdge()
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
