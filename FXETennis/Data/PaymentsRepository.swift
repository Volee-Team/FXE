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
    case failed(String)
}

enum PaymentsRepository {
    static func setupIntent() async throws -> SetupIntentPayload {
        do {
            return try await supabase.functions.invoke("stripe-setup-intent", options: .init(method: .post))
        } catch let error as FunctionsError {
            if case .httpError(let code, let data) = error {
                let body = String(data: data, encoding: .utf8) ?? ""
                if code == 503 || body.contains("stripe_not_configured") { throw PaymentsError.notConfigured }
                throw PaymentsError.failed(body)
            }
            throw PaymentsError.failed(error.localizedDescription)
        }
    }
}
