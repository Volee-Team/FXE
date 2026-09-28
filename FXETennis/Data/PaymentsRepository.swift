//
//  PaymentsRepository.swift
//  FXETennis
//
//  The app's side of decision 0009. It asks the stripe-setup-intent edge
//  function for what PaymentSheet needs, and that is all: the card is entered
//  into Stripe's sheet, the webhook records the summary, and the app never
//  sees a card number. Charging is Tara's, through her surfaces and the
//  stripe-charge function; there is no charge call here on purpose.
//

import Foundation
import Supabase

struct SetupIntentPayload: Decodable, Sendable {
    let setupIntentClientSecret: String
    let ephemeralKeySecret: String
    let customerId: String
    let publishableKey: String?
}

enum PaymentsError: Error {
    /// The function answered 503 stripe_not_configured: keys not in place yet.
    case notConfigured
    /// 409 card_consent_required: no permission recorded for the current words.
    case consentRequired
    case failed(String)
}

/// The permission box's words, exactly as Kat and Tara wrote them in the
/// Final Updates (2026-09-26). The server stores its own copy
/// (app_settings.card_consent_text) with each consent; card_consent.sql and
/// CardConsentTests pin the two to the same sentence.
enum CardConsent {
    static let words = "I give permission for my card to be charged"
}

enum PaymentsRepository {
    static func setupIntent() async throws -> SetupIntentPayload {
        do {
            return try await supabase.functions.invoke("stripe-setup-intent", options: .init(method: .post))
        } catch let error as FunctionsError {
            if case .httpError(let code, let data) = error {
                let body = String(data: data, encoding: .utf8) ?? ""
                if code == 503 || body.contains("stripe_not_configured") { throw PaymentsError.notConfigured }
                if code == 409 || body.contains("card_consent_required") { throw PaymentsError.consentRequired }
                throw PaymentsError.failed(body)
            }
            throw PaymentsError.failed(error.localizedDescription)
        }
    }

    /// Records the permission for the signed-in account (the server stores its
    /// own copy of the words, the time and this build). Decision 0015 §7.
    static func recordCardConsent() async throws {
        struct Params: Encodable { let p_app_version: String }
        _ = try await supabase.rpc("record_card_consent", params: Params(p_app_version: ProfileView.versionLine)).execute()
    }

    /// Whether the signed-in account has consented to the current words.
    static func myCardConsent() async throws -> Bool {
        try await supabase.rpc("my_card_consent").execute().value
    }

    /// Payments are switched on (app_settings.payments_enabled). Profile shows
    /// the card section only then. Tara, round two (decision 0016), against
    /// "Cards aren't set up yet.": "Let's only do if stripe is connected".
    static func paymentsEnabled() async throws -> Bool {
        struct Row: Decodable { let value: String }
        let rows: [Row] = try await supabase.from("app_settings").select("value")
            .eq("key", value: "payments_enabled").execute().value
        return rows.first?.value == "true"
    }

    /// Cards are required right now: payments are switched on and the club
    /// requires a card (both app_settings, readable by any signed-in user).
    /// The same two switches register_for_clinic reads.
    static func cardStepRequired() async throws -> Bool {
        struct Row: Decodable { let key: String; let value: String }
        let rows: [Row] = try await supabase.from("app_settings").select("key, value")
            .in("key", values: ["payments_enabled", "card_required"]).execute().value
        let on = Dictionary(uniqueKeysWithValues: rows.map { ($0.key, $0.value == "true") })
        return (on["payments_enabled"] ?? false) && (on["card_required"] ?? false)
    }
}
