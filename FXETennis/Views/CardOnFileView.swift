//
//  CardOnFileView.swift
//  FXETennis
//
//  "Payment method" on Profile and in the onboarding card step. Shows the
//  card the webhook recorded (last four digits only, Final Updates p.2), or
//  an Add a card button that opens Stripe's PaymentSheet in setup mode.
//
//  The permission box (decision 0015 §7): "a check box that says I give
//  permission for my card to be charged and if deselected it does not let
//  them proceed." Ticking it and tapping Add a card records the consent on
//  the server first; the server refuses to start a card setup without one,
//  so the box is enforced by the database, not by this view.
//

import SwiftUI
import StripePaymentSheet

struct CardOnFileView: View {
    @Environment(SessionStore.self) private var session
    @State private var sheet: PaymentSheet?
    @State private var presenting = false
    @State private var busy = false
    @State private var note: String?
    @State private var permission = false

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text("Payment method")
                .font(Brand.Typography.bodyEmphasis)
                .foregroundStyle(Brand.textPrimary)
            // Tara's sentence, verbatim (2026-09-16, decision 0012), marked for her edit.
            Text("Your card will only be charged after the clinic you attended, late cancellations, or no-shows. Cancel at least 3 hours before clinic and you will not be charged.")
                .font(Brand.Typography.caption)
                .foregroundStyle(Brand.textSecondary)

            // Their words, verbatim. A real Button so the element is a
            // button with this identifier to XCUITest and VoiceOver.
            Button { permission.toggle() } label: {
                HStack(alignment: .top, spacing: Brand.Spacing.sm) {
                    Image(systemName: permission ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(permission ? Brand.navy : Brand.textSecondary)
                    Text(CardConsent.words)
                        .font(Brand.Typography.body)
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(permission ? [.isSelected] : [])
            .accessibilityIdentifier("card.permission")

            HStack {
                Text(session.account?.cardLabel ?? "No card on file")
                    .font(Brand.Typography.body)
                    .foregroundStyle(session.account?.hasCard == true ? Brand.textPrimary : Brand.textSecondary)
                    .accessibilityIdentifier("profile.cardLabel")
                Spacer()
                Button {
                    Task { await startAddingCard() }
                } label: {
                    Text(session.account?.hasCard == true ? "Change card" : "Add a card")
                        .font(Brand.Typography.chip)
                        .foregroundStyle(Brand.navy)
                        .frame(minHeight: Brand.Layout.minTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(busy || !permission)
                .opacity(permission ? 1 : 0.4)
                .accessibilityIdentifier("profile.addCard")
            }
            .padding(Brand.Spacing.cardPadding)
            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))

            if let note {
                Text(note)
                    .font(Brand.Typography.caption)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityIdentifier("profile.cardNote")
            }
        }
        .onAppear { if session.cardConsent == true { permission = true } }
        .paymentSheet(isPresented: $presenting, paymentSheet: sheet ?? PaymentSheet(setupIntentClientSecret: "", configuration: .init())) { result in
            Task { await finished(result) }
        }
    }

    private func startAddingCard() async {
        busy = true; note = nil
        defer { busy = false }
        guard permission else { return }
        do {
            if session.cardConsent != true {
                try await PaymentsRepository.recordCardConsent()
                session.cardConsent = true
            }
            let payload = try await PaymentsRepository.setupIntent()
            if let pk = payload.publishableKey { STPAPIClient.shared.publishableKey = pk }
            var config = PaymentSheet.Configuration()
            config.merchantDisplayName = "FXE Tennis"
            config.customer = .init(id: payload.customerId, ephemeralKeySecret: payload.ephemeralKeySecret)
            config.allowsDelayedPaymentMethods = false
            sheet = PaymentSheet(setupIntentClientSecret: payload.setupIntentClientSecret, configuration: config)
            presenting = true
        } catch PaymentsError.notConfigured {
            note = "Cards aren't set up yet."
        } catch PaymentsError.consentRequired {
            session.cardConsent = false
            note = "Tick the box to continue."
        } catch {
            note = "That didn't work. Check your connection and try again."
        }
    }

    private func finished(_ result: PaymentSheetResult) async {
        switch result {
        case .completed:
            // The webhook writes the summary; give it a moment, then reload.
            try? await Task.sleep(for: .seconds(2))
            await session.loadProfile()
            note = session.account?.hasCard == true ? "Saved." : "Saved. It may take a moment to show here."
        case .canceled:
            break
        case .failed(let error):
            note = "That didn't work. \(error.localizedDescription)"
        }
    }
}
