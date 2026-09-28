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
//  After Stripe's sheet reports the card saved, the summary still has to
//  arrive by webhook. This used to wait 2 seconds once; a slower webhook left
//  a new member on the card step reading "No card on file" with only Add a
//  card and Sign out (MVP audit 2026-09-27, item 4). Now it asks again every
//  2 seconds for about 30 (CardSavePoll), and the card step closes itself the
//  moment the card is there. After that a Refresh button asks once more.
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
    /// Stripe said the card was saved; the webhook's summary is being waited for.
    @State private var polling = false
    /// The wait ran out before the summary arrived: offer Refresh.
    @State private var waitingForCard = false

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text("Payment method")
                .brandFont(.bodyEmphasis)
                .foregroundStyle(Brand.textPrimary)
            // Tara's sentence, verbatim, as she edited it on 2026-09-22 (decision 0016).
            Text("Your card will only be charged after a clinic you attended, a late cancellation or no-show. Cancel at least 3 hours before clinic and you will not be charged.")
                .brandFont(.caption)
                .foregroundStyle(Brand.textSecondary)

            // Their words, verbatim. A real Button so the element is a
            // button with this identifier to XCUITest and VoiceOver.
            Button { permission.toggle() } label: {
                HStack(alignment: .top, spacing: Brand.Spacing.sm) {
                    Image(systemName: permission ? "checkmark.square.fill" : "square")
                        .font(.title3)
                        .foregroundStyle(permission ? Brand.navy : Brand.textSecondary)
                    Text(CardConsent.words)
                        .brandFont(.body)
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
                    .brandFont(.body)
                    .foregroundStyle(session.account?.hasCard == true ? Brand.textPrimary : Brand.textSecondary)
                    .accessibilityIdentifier("profile.cardLabel")
                Spacer()
                Button {
                    Task { await startAddingCard() }
                } label: {
                    Text(session.account?.hasCard == true ? "Change card" : "Add a card")
                        .brandFont(.chip)
                        .foregroundStyle(Brand.navy)
                        .frame(minHeight: Brand.Layout.minTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(busy || polling || !permission)
                .opacity(permission ? 1 : 0.4)
                .accessibilityIdentifier("profile.addCard")
            }
            .padding(Brand.Spacing.cardPadding)
            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))

            if let note {
                HStack(spacing: Brand.Spacing.xs) {
                    if polling { ProgressView() }
                    Text(note)
                        .brandFont(.caption)
                        .foregroundStyle(Brand.textSecondary)
                        .accessibilityIdentifier("profile.cardNote")
                }
            }
            if waitingForCard && !polling {
                Button {
                    Task { await refreshOnce() }
                } label: {
                    Text("Refresh")
                        .brandFont(.chip)
                        .foregroundStyle(Brand.navy)
                        .frame(minHeight: Brand.Layout.minTapTarget)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("profile.cardRefresh")
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
            note = "Check the box to continue" // Tara, 2026-09-28 (decision 0024), verbatim
        } catch {
            note = "That didn't work. Check your connection and try again."
        }
    }

    private func finished(_ result: PaymentSheetResult) async {
        switch result {
        case .completed:
            // The webhook writes the summary; ask until it is there.
            polling = true
            waitingForCard = false
            note = "Saved. It may take a moment to show here."
            let arrived = await CardSavePoll.waitForCard { try await refreshAccount() }
            polling = false
            waitingForCard = !arrived
            note = arrived ? "Saved." : "Saved. It may take a moment to show here."
        case .canceled:
            break
        case .failed(let error):
            note = "That didn't work. \(error.localizedDescription)"
        }
    }

    private func refreshOnce() async {
        polling = true
        let arrived = (try? await refreshAccount()) == true
        polling = false
        if arrived {
            waitingForCard = false
            note = "Saved."
        }
    }

    /// Re-reads the account row alone and swaps it in only on success.
    /// loadProfile() blanks the whole session on any failed read, and one
    /// bar of signal at the courts is exactly when this runs.
    private func refreshAccount() async throws -> Bool {
        guard let fresh = try await ProfileRepository.myAccount() else { return false }
        session.account = fresh
        return fresh.hasCard
    }
}

/// How long the app waits for a saved card to show (MVP audit 2026-09-27,
/// item 4). Stripe's sheet knows the card is saved before we do: the summary
/// (last four digits) reaches the account only through the webhook, usually
/// within seconds and with no promise. So: ask every 2 seconds, about 30
/// seconds in all, and stop the moment it is there. A read that fails (bad
/// signal) is one missed tick, not the end of the wait.
enum CardSavePoll {
    static let interval: Duration = .seconds(2)
    static let attempts = 15   // 15 x 2 s = 30 s

    /// True as soon as `hasCard` says so; false once every attempt is spent
    /// or the wait is cancelled.
    static func waitForCard(
        attempts: Int = attempts,
        sleep: (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        hasCard: () async throws -> Bool
    ) async -> Bool {
        for _ in 0..<attempts {
            do { try await sleep(interval) } catch { return false }
            if (try? await hasCard()) == true { return true }
        }
        return false
    }
}
