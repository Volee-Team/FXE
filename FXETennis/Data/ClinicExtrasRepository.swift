//
//  ClinicExtrasRepository.swift
//  FXETennis
//
//  What Tara's clinic page gained in 1.0.3 beyond the roster itself, all on
//  existing, probe-covered RPCs:
//
//  * Guests (decision 0052, 20261107000003): a first and last name on one
//    clinic for someone who isn't in the app. Counted in You're In!'s total
//    (clinic_taken), never messaged, never charged by the app.
//  * The clinic's price and the rain half (decision 0053, 20261107000004).
//  * One player's price, typed by Tara (decision 0054, item 10).
//  * The 105 rounds (decision 0054, item 8): Tara writes them; a pro reads
//    them for a clinic in their week; players never.
//

import Foundation
import Supabase

// MARK: - Models

/// One of Tara's guests on a clinic.
struct ClinicGuest: Codable, Identifiable, Sendable, Equatable {
    let id: UUID
    let clinicId: UUID
    let firstName: String
    let lastName: String
    let courtNumber: Int?

    var displayName: String { "\(firstName) \(lastName)" }

    enum CodingKeys: String, CodingKey {
        case id
        case clinicId = "clinic_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case courtNumber = "court_number"
    }
}

/// One spot of one court of one round (clinic_rounds).
struct RoundSpot: Codable, Sendable, Equatable {
    let roundNumber: Int
    let courtNumber: Int
    let side: Int
    let slot: Int
    /// The registration's id or the guest's: what admin_set_round_court takes.
    let personId: UUID
    let firstName: String?
    let lastName: String?
    let isGuest: Bool
    /// They left You're In!, or the guest was removed, after being placed.
    let gone: Bool

    var displayName: String { [firstName, lastName].compactMap { $0 }.joined(separator: " ") }

    enum CodingKeys: String, CodingKey {
        case side, slot, gone
        case roundNumber = "round_number"
        case courtNumber = "court_number"
        case personId = "person_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case isGuest = "is_guest"
    }
}

/// Someone Tara can pick for a round: a You're In! player or a guest.
struct RoundPerson: Identifiable, Sendable, Equatable, Hashable {
    let id: UUID
    let name: String
    let isGuest: Bool
}

/// The rounds' shape and the arithmetic on it, kept out of the views so it
/// can be tested: up to 3 rounds, courts 1 to 5, two sides of up to 3.
enum Rounds {
    static let rounds = 1...3
    static let courts = 1...5
    static let perSide = 3

    /// Tara's own test for a 105, the same as the "?" explainer and the
    /// server's is_105: the name or the category says 105.
    static func is105(name: String, category: String?) -> Bool {
        name.localizedCaseInsensitiveContains("105") || (category?.localizedCaseInsensitiveContains("105") ?? false)
    }

    /// One court's six spots, side 1's three then side 2's: the order
    /// admin_set_round_court takes. Empty spots are nil.
    static func lineup(_ spots: [RoundSpot], round: Int, court: Int) -> [RoundSpot?] {
        var out = [RoundSpot?](repeating: nil, count: perSide * 2)
        for s in spots where s.roundNumber == round && s.courtNumber == court
            && (1...2).contains(s.side) && (1...perSide).contains(s.slot) {
            out[(s.side - 1) * perSide + (s.slot - 1)] = s
        }
        return out
    }

    /// "Ken Whitfield, Maria Alvarez / Rob Delgado", her own "a, b, c / d,
    /// e, f", or nil for an empty court. An empty side reads "open"; someone
    /// who has left reads "(left)".
    static func line(_ spots: [RoundSpot], round: Int, court: Int) -> String? {
        let six = lineup(spots, round: round, court: court)
        func side(_ part: ArraySlice<RoundSpot?>) -> String {
            part.compactMap { $0 }.map { $0.gone ? "\($0.displayName) (left)" : $0.displayName }.joined(separator: ", ")
        }
        let a = side(six[0..<perSide]), b = side(six[perSide..<(perSide * 2)])
        if a.isEmpty && b.isEmpty { return nil }
        return "\(a.isEmpty ? "open" : a) / \(b.isEmpty ? "open" : b)"
    }

    /// Whether a round has anyone in it.
    static func isEmpty(_ spots: [RoundSpot], round: Int) -> Bool {
        !spots.contains { $0.roundNumber == round }
    }
}

/// Dollars as Tara types them ("14", "$14", "14.50") to cents; nil for
/// anything that is not a positive amount with at most two decimals.
enum DollarsInput {
    static func cents(_ text: String) -> Int? {
        var t = text.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("$") { t.removeFirst() }
        guard !t.isEmpty, t.range(of: #"^\d{1,4}(\.\d{1,2})?$"#, options: .regularExpression) != nil,
              let value = Decimal(string: t) else { return nil }
        let cents = NSDecimalNumber(decimal: value * 100).intValue
        return cents > 0 ? cents : nil
    }

    /// "14" or "14.50", for a field she is about to edit.
    static func text(_ cents: Int?) -> String {
        guard let cents else { return "" }
        return cents % 100 == 0 ? "\(cents / 100)" : String(format: "%d.%02d", cents / 100, cents % 100)
    }
}

// MARK: - Parameters

private struct ClinicsParam: Encodable { let p_clinics: [UUID] }
private struct ClinicIdParam: Encodable { let p_clinic: UUID }
private struct AddGuestParams: Encodable { let p_clinic: UUID; let p_first: String; let p_last: String }
private struct GuestParam: Encodable { let p_guest: UUID }
/// `p_court` and `p_cents` are sent as explicit JSON nulls when cleared: a
/// missing key makes PostgREST look for another function and answer 404
/// (AssignCourtParams, 2026-09-01).
private struct GuestCourtParams: Encodable {
    let p_guest: UUID
    let p_court: Int?
    enum CodingKeys: String, CodingKey { case p_guest, p_court }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_guest, forKey: .p_guest)
        if let court = p_court { try c.encode(court, forKey: .p_court) } else { try c.encodeNil(forKey: .p_court) }
    }
}
private struct RegistrationPriceParams: Encodable {
    let p_registration: UUID
    let p_cents: Int?
    enum CodingKeys: String, CodingKey { case p_registration, p_cents }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_registration, forKey: .p_registration)
        if let cents = p_cents { try c.encode(cents, forKey: .p_cents) } else { try c.encodeNil(forKey: .p_cents) }
    }
}
private struct ClinicPricesParams: Encodable { let p_clinic: UUID; let p_member_cents: Int; let p_nonmember_cents: Int }
private struct RainParams: Encodable { let p_clinic: UUID; let p_on: Bool }
/// Six ids, nil for an empty spot, each written out (a nil must reach the
/// server as null, not be dropped from the array).
private struct RoundCourtParams: Encodable {
    let p_clinic: UUID
    let p_round: Int
    let p_court: Int
    let p_people: [UUID?]
    enum CodingKeys: String, CodingKey { case p_clinic, p_round, p_court, p_people }
    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_clinic, forKey: .p_clinic)
        try c.encode(p_round, forKey: .p_round)
        try c.encode(p_court, forKey: .p_court)
        var list = c.nestedUnkeyedContainer(forKey: .p_people)
        for id in p_people {
            if let id { try list.encode(id) } else { try list.encodeNil() }
        }
    }
}

// MARK: - Calls

extension AdminRepository {

    /// One clinic as it is now: after a price change or the rain switch, the
    /// page shows the new numbers without going back to the list.
    static func clinic(_ id: UUID) async throws -> ClinicAdmin? {
        let rows: [ClinicAdmin] = try await supabase
            .from("clinics_admin")
            .select("id,name,audience,category,starts_at,ends_at,status,internal_capacity,member_price_cents,nonmember_price_cents,rain_half")
            .eq("id", value: id)
            .execute()
            .value
        return rows.first
    }

    static func guests(clinic: UUID) async throws -> [ClinicGuest] {
        try await supabase.rpc("admin_clinic_guests", params: ClinicsParam(p_clinics: [clinic])).execute().value
    }

    static func addGuest(clinic: UUID, first: String, last: String) async throws {
        _ = try await supabase.rpc("admin_add_guest", params: AddGuestParams(p_clinic: clinic, p_first: first, p_last: last)).execute()
    }

    static func removeGuest(_ guest: UUID) async throws {
        _ = try await supabase.rpc("admin_remove_guest", params: GuestParam(p_guest: guest)).execute()
    }

    static func setGuestCourt(_ guest: UUID, court: Int?) async throws {
        _ = try await supabase.rpc("admin_set_guest_court", params: GuestCourtParams(p_guest: guest, p_court: court)).execute()
    }

    /// The clinic's two prices; everyone on it not yet charged pays them.
    static func setClinicPrices(clinic: UUID, memberCents: Int, nonmemberCents: Int) async throws {
        _ = try await supabase.rpc("admin_set_clinic_prices",
                                   params: ClinicPricesParams(p_clinic: clinic, p_member_cents: memberCents, p_nonmember_cents: nonmemberCents)).execute()
    }

    static func setRainHalf(clinic: UUID, on: Bool) async throws {
        _ = try await supabase.rpc("admin_set_rain_half", params: RainParams(p_clinic: clinic, p_on: on)).execute()
    }

    /// One person's amount; nil puts the clinic's price back.
    static func setRegistrationPrice(_ registration: UUID, cents: Int?) async throws {
        _ = try await supabase.rpc("admin_set_registration_price",
                                   params: RegistrationPriceParams(p_registration: registration, p_cents: cents)).execute()
    }

    /// One court of one round, whole: six spots, side 1 then side 2.
    static func setRoundCourt(clinic: UUID, round: Int, court: Int, people: [UUID?]) async throws {
        _ = try await supabase.rpc("admin_set_round_court",
                                   params: RoundCourtParams(p_clinic: clinic, p_round: round, p_court: court, p_people: people)).execute()
    }
}

/// Read by Tara and, for a clinic in their week, a pro.
enum RoundsRepository {
    static func rounds(clinic: UUID) async throws -> [RoundSpot] {
        try await supabase.rpc("clinic_rounds", params: ClinicIdParam(p_clinic: clinic)).execute().value
    }
}

/// The server's refusals for guests, prices and rounds, in words. Anything
/// else is most likely the connection.
enum ClinicExtrasError {
    static func message(_ error: Error) -> String {
        let e = String(describing: error)
        if e.contains("guest_already_added") { return "That guest is already on this clinic." }
        if e.contains("name_required") { return "Enter a first and last name." }
        if e.contains("name_too_long") { return "That name is too long." }
        if e.contains("invalid_price") { return "Enter a price above $0." }
        if e.contains("already_paid") { return "Already marked paid." }
        if e.contains("charged_refund_first") { return "Already charged: refund it first." }
        if e.contains("clinic_canceled") { return "That clinic is canceled." }
        if e.contains("not_in_clinic") || e.contains("nothing_owed") || e.contains("guest_not_found")
            || e.contains("already_in_round") { return "That just changed. Here's the latest." }
        return "That didn't go through. Check your connection and try again."
    }
}
