//
//  CardOnFileView.swift
//  FXETennis
//
//  "Payment method" on Profile. Shows the card summary the webhook recorded,
//  or an Add a card button that opens Stripe's PaymentSheet in setup mode.
//  The sentence a player agrees to when adding a card is Tara's (Q37) and is
//  not here yet; until she writes it, only chrome shows.
//

import SwiftUI
import StripePaymentSheet

struct CardOnFileView: View {
    @Environment(SessionStore.self) private var session
    @State private var sheet: PaymentSheet?
    @State private var presenting = false
    @State private var busy = false
    @State private var note: String?

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text("Payment method")
                .font(Brand.Typography.bodyEmphasis)
                .foregroundStyle(Brand.textPrimary)

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
                .disabled(busy)
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
        .paymentSheet(isPresented: $presenting, paymentSheet: sheet ?? PaymentSheet(setupIntentClientSecret: "", configuration: .init())) { result in
            Task { await finished(result) }
        }
    }

    private func startAddingCard() async {
        busy = true; note = nil
        defer { busy = false }
        do {
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
