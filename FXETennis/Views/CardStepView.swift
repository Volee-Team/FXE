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
//  The same step opens after Register or Accept is refused for a declined
//  card (decision 0024, SessionStore.cardChangeRequested), showing the card,
//  its decline and Change card. That one has a Close: the player still has
//  a card on file and the rest of the app works; only a spot needs a new
//  card. It closes itself once the webhook has recorded one.
//

import SwiftUI

struct CardStepView: View {
    /// Opened for a declined card rather than a missing one: it can be closed.
    var canClose = false
    @Environment(SessionStore.self) private var session

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
            .navigationTitle("Add a card")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if canClose {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Close") { session.cardChangeRequested = false }
                            .accessibilityIdentifier("cardStep.close")
                    }
                }
            }
        }
        .interactiveDismissDisabled(!canClose)
    }
}

/// Presents the card step over the app after the waiver while a card is due.
private struct CardGate: ViewModifier {
    @Environment(SessionStore.self) private var session

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { session.waiverAccepted == true && session.cardStepShown },
                // Only the declined-card step can be swiped away (canClose).
                set: { if !$0 { session.cardChangeRequested = false } }
            )) { CardStepView(canClose: !session.cardStepDue) }
    }
}

extension View {
    func cardGate() -> some View { modifier(CardGate()) }
}
