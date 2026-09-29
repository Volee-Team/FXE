//
//  CoreModels.swift
//  FXETennis
//
//  Codable models mapped EXACTLY to the Postgres views and tables, verified
//  against the live schema on 2026-08-12. If a column changes, change it here in
//  the same pass. Property names are camelCase with explicit CodingKeys so the
//  mapping is legible and does not depend on a decoder strategy.
//
//  What is deliberately absent is as important as what is present: no capacity,
//  no counts, no other players. Those columns are not in the views the client
//  reads (hard rule 1), so they cannot be modelled here even by accident.
//

import Foundation

// MARK: - Registration status

/// Mirrors the Postgres `registration_status` enum. Raw values are the exact DB
/// strings. Maps to Brand.Status for display so the locked wording and the
/// accessibility contract stay in one place.
enum RegistrationStatus: String, Codable, Sendable {
    case in_ = "in"
    case pool
    case responseNeeded = "response_needed"
    case canceled

    var display: Brand.Status {
        switch self {
        case .in_: return .youreIn
        case .pool: return .playerPool
        case .responseNeeded: return .responseNeeded
        case .canceled: return .canceled
        }
    }
}

// MARK: - Clinic (from clinics_public)

/// A published clinic as a player may see it. Carries both published rates; the
/// UI picks one via `price(forMember:)`. Never carries capacity or any count.
struct ClinicPublic: Codable, Identifiable, Sendable, Hashable {
    let id: UUID
    let name: String
    let audience: String
    let category: String?
    let description: String?
    let startsAt: Date
    let endsAt: Date
    let memberOpensAt: Date?
    let publicOpensAt: Date?
    let closesAt: Date?
    let status: String
    let canceledAt: Date?
    let memberPriceCents: Int?
    let nonmemberPriceCents: Int?
    let durationMinutes: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, audience, category, description, status
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case memberOpensAt = "member_opens_at"
        case publicOpensAt = "public_opens_at"
        case closesAt = "closes_at"
        case canceledAt = "canceled_at"
        case memberPriceCents = "member_price_cents"
        case nonmemberPriceCents = "nonmember_price_cents"
        case durationMinutes = "duration_minutes"
    }

    /// The cents this viewer would pay, given their membership.
    func priceCents(forMember isMember: Bool) -> Int? {
        isMember ? memberPriceCents : nonmemberPriceCents
    }

    var isCanceled: Bool { status == "canceled" }

    /// Open for registration to this player at `now`: past their opening
    /// moment (members Thursday 8:00, everyone Friday 8:00, per service week,
    /// stored on the row) and before the close (3 hours before start by
    /// default). Display only: `register_for_clinic` decides for real. Home
    /// uses it to list what can be signed up for today (Final Updates p.1).
    func isOpenForRegistration(isMember: Bool, now: Date = .now) -> Bool {
        if isCanceled { return false }
        let opens = isMember ? memberOpensAt : publicOpensAt
        if let opens, now < opens { return false }
        if let closesAt, now >= closesAt { return false }
        return now < startsAt
    }
}

// MARK: - Registration (from my_registrations)

/// The current player's own registration row. Only their own; RLS guarantees it.
/// Note it carries `clinicId` only — join to `ClinicPublic` in the view model to
/// show a name and time.
struct MyRegistration: Codable, Identifiable, Sendable {
    let id: UUID
    let clinicId: UUID
    let playerId: UUID
    let status: RegistrationStatus
    let paid: Bool
    let registeredAt: Date?
    let invitedAt: Date?
    let respondedAt: Date?
    let canceledAt: Date?
    /// Canceled inside the cutoff with a note (decision 0010). Optional so
    /// a row from before the column existed still decodes.
    let lateCancel: Bool?
    /// This late cancel used the one courtesy per 90 days (decision 0012).
    let courtesyUsed: Bool?

    enum CodingKeys: String, CodingKey {
        case id, status, paid
        case clinicId = "clinic_id"
        case playerId = "player_id"
        case lateCancel = "late_cancel"
        case courtesyUsed = "courtesy_used"
        case registeredAt = "registered_at"
        case invitedAt = "invited_at"
        case respondedAt = "responded_at"
        case canceledAt = "canceled_at"
    }
}

// MARK: - Clinic message (from my_clinic_messages)

struct ClinicMessage: Codable, Identifiable, Sendable {
    let id: UUID
    let clinicId: UUID
    let body: String
    let audience: String
    let sentAt: Date

    enum CodingKeys: String, CodingKey {
        case id, body, audience
        case clinicId = "clinic_id"
        case sentAt = "sent_at"
    }
}

// MARK: - News (from my_news)

struct NewsPost: Codable, Identifiable, Sendable {
    let id: UUID
    let title: String
    let body: String
    let audience: String
    let publishedAt: Date?
    let isRead: Bool

    enum CodingKeys: String, CodingKey {
        case id, title, body, audience
        case publishedAt = "published_at"
        case isRead = "is_read"
    }
}

// MARK: - Player (from players)

struct PlayerProfile: Codable, Identifiable, Sendable {
    let id: UUID
    let accountId: UUID
    let kind: String
    let firstName: String
    let lastName: String
    // Date-ONLY column ("1988-04-12"). The Supabase decoder handles timestamptz
    // but throws on a bare date, which silently broke the whole profile load
    // (caught on the simulator: "Hi, there" + non-member price for a member).
    // Kept as the raw string; adults never display it, and age derivation for
    // juniors (v1.1) parses it then.
    let dateOfBirth: String?
    let adultRating: Double?
    let isMember: Bool
    let isActive: Bool
    /// The player's own note about their level, read only by Tara (decision 0012).
    let levelNote: String?

    enum CodingKeys: String, CodingKey {
        case id, kind
        case accountId = "account_id"
        case levelNote = "level_note"
        case firstName = "first_name"
        case lastName = "last_name"
        case dateOfBirth = "date_of_birth"
        case adultRating = "adult_rating"
        case isMember = "is_member"
        case isActive = "is_active"
    }

    var fullName: String { "\(firstName) \(lastName)" }
}

// MARK: - Account (from accounts)

struct Account: Codable, Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let email: String?
    let phone: String?
    let accountType: String
    let role: String
    /// Display only ("Visa ···4242"); written by the Stripe webhook, never by
    /// the app. Nil until a card has been added (decision 0009).
    let cardBrand: String?
    let cardLast4: String?
    /// A charge on this card was declined and nothing has cleared it: no card
    /// saved since, no later charge through (decision 0024, Tara's question
    /// 78). The database writes both from Stripe's answer; the app only reads
    /// them (20260928700001). Defaults so an account made in code needs neither.
    var cardDeclinedAt: Date? = nil
    /// Stripe's reason code for that decline (insufficient_funds, ...).
    var cardDeclineCode: String? = nil

    enum CodingKeys: String, CodingKey {
        case id, email, phone, role
        case firstName = "first_name"
        case lastName = "last_name"
        case accountType = "account_type"
        case cardBrand = "card_brand"
        case cardLast4 = "card_last4"
        case cardDeclinedAt = "card_declined_at"
        case cardDeclineCode = "card_decline_code"
    }

    var isAdmin: Bool { role == "admin" }
    var hasCard: Bool { cardLast4 != nil }
    /// The card on file was declined: Register and Accept are refused until a
    /// card is saved again or a later charge goes through.
    var isCardDeclined: Bool { cardDeclinedAt != nil }
    /// "•••• 4242", or nil. Final Updates p.2 item 2: "If a card is on file,
    /// only show the last 4 digits of the card in the U/I." The brand is
    /// still stored (the webhook writes it) and simply not shown.
    var cardLabel: String? {
        guard let last4 = cardLast4 else { return nil }
        return "•••• \(last4)"
    }
}

// MARK: - Money formatting

extension Int {
    /// Cents to a display string. 1800 -> "$18". Whole dollars drop the ".00",
    /// which is how Tara writes her prices.
    var centsAsPrice: String {
        let dollars = Double(self) / 100.0
        if dollars == dollars.rounded() {
            return "$\(Int(dollars))"
        }
        return String(format: "$%.2f", dollars)
    }
}
