//
//  Repositories.swift
//  FXETennis
//
//  Every Supabase read and write goes through here. Views do not call the
//  client directly. Two reasons: one place to change if a view or RPC changes,
//  and one place a reviewer can confirm the client never touches a hidden table.
//
//  Convention: repositories are stateless enums of `static` async funcs. State
//  lives in view models.
//

import Foundation
import Supabase

// MARK: - RPC parameter encodables

private struct ClinicPlayerParams: Encodable {
    let p_clinic: UUID
    let p_player: UUID
}
private struct RegistrationParam: Encodable {
    let p_registration: UUID
}
private struct RespondParams: Encodable {
    let p_registration: UUID
    let p_accept: Bool
}

// MARK: - Clinics

enum ClinicRepository {

    /// Every published or canceled clinic, soonest first. The month-ahead
    /// schedule filters this list by date in the view model; the server sends
    /// the whole published set, which is small.
    static func upcoming() async throws -> [ClinicPublic] {
        try await supabase
            .from("clinics_public")
            .select()
            .order("starts_at", ascending: true)
            .execute()
            .value
    }

    static func messages(clinicId: UUID) async throws -> [ClinicMessage] {
        try await supabase
            .from("my_clinic_messages")
            .select()
            .eq("clinic_id", value: clinicId)
            .order("sent_at", ascending: true)
            .execute()
            .value
    }
}

// MARK: - Registrations

enum RegistrationRepository {

    static func mine() async throws -> [MyRegistration] {
        try await supabase
            .from("my_registrations")
            .select()
            .execute()
            .value
    }

    /// Register the given player for a clinic. The server decides You're In! vs
    /// Player Pool vs rejection; we just relay the outcome.
    @discardableResult
    static func register(clinicId: UUID, playerId: UUID) async throws -> MyRegistration {
        try await supabase
            .rpc("register_for_clinic", params: ClinicPlayerParams(p_clinic: clinicId, p_player: playerId))
            .single()
            .execute()
            .value
    }

    static func cancelRegistration(registrationId: UUID) async throws {
        try await supabase
            .rpc("cancel_registration", params: RegistrationParam(p_registration: registrationId))
            .execute()
    }

    static func leavePool(registrationId: UUID) async throws {
        try await supabase
            .rpc("leave_pool", params: RegistrationParam(p_registration: registrationId))
            .execute()
    }

    /// Ask Tara to fit a player into a clinic whose registration has closed.
    ///
    /// Returns a `late_requests` row, not a registration. The server enforces
    /// every clause of Tara's condition ("assuming there is space and it isn't
    /// full"): inside the closed window, before the clinic starts, not full, and
    /// the caller owns the player. See `20260827000002_late_requests.sql`.
    @discardableResult
    static func requestLateSpot(clinicId: UUID, playerId: UUID, message: String?) async throws -> UUID {
        struct P: Encodable {
            let p_clinic: UUID
            let p_player: UUID
            let p_message: String?
        }
        struct Row: Decodable { let id: UUID }
        let row: Row = try await supabase
            .rpc("request_late_spot", params: P(p_clinic: clinicId, p_player: playerId, p_message: message))
            .single()
            .execute()
            .value
        return row.id
    }

    static func respondToInvitation(registrationId: UUID, accept: Bool) async throws {
        try await supabase
            .rpc("respond_to_invitation", params: RespondParams(p_registration: registrationId, p_accept: accept))
            .execute()
    }
}

// MARK: - News

enum NewsRepository {
    static func all() async throws -> [NewsPost] {
        try await supabase
            .from("my_news")
            .select()
            .order("published_at", ascending: false)
            .execute()
            .value
    }

    static func markRead(newsId: UUID) async throws {
        struct P: Encodable { let p_news: UUID }
        try await supabase.rpc("mark_news_read", params: P(p_news: newsId)).execute()
    }
}

// MARK: - Profile

enum ProfileRepository {

    /// The players this account owns. For an adult that is one row (themselves).
    ///
    /// The `.eq("account_id", ...)` is LOAD-BEARING and must not be removed as
    /// redundant. RLS on `players` is
    /// `account_id = auth.uid() OR is_admin()`, so relying on the policy alone
    /// returns every player in the club **to an administrator**. This method
    /// feeds `SessionStore.activePlayer` via `players.first`, so without the
    /// filter Tara signs in and becomes an arbitrary other member: found on the
    /// simulator 2026-08-15, where signing in as tara@fxe.test produced "Good
    /// Morning, Maria!". She would have seen someone else's My Clinics and been
    /// able to register and cancel as them.
    ///
    /// The general shape, worth remembering: **an RLS policy written to also
    /// admit admins is not a substitute for a WHERE clause.** RLS bounds what a
    /// query *may* return, never what it *should*.
    static func myPlayers() async throws -> [PlayerProfile] {
        guard let uid = supabase.auth.currentUser?.id else { return [] }
        return try await supabase
            .from("players")
            .select()
            .eq("account_id", value: uid)
            .execute()
            .value
    }

    /// Create the caller's own `accounts` + adult `players` rows after auth
    /// sign-up, returning the new player id.
    ///
    /// This is the ONLY write path into `accounts`. `authenticated` has no
    /// INSERT on that table (revoked by 20260802000003) and there is no trigger
    /// on `auth.users`, both deliberately: see the header of
    /// `20260815000001_create_my_account.sql`. Until this existed, sign-up
    /// produced an auth user with no profile, and every downstream screen
    /// silently no-opped.
    ///
    /// Note what is NOT a parameter: the account id (it is `auth.uid()`), the
    /// email (read from `auth.users`), and the role (hard-coded to `member`).
    /// A client that could name any of those could impersonate or self-promote.
    /// Safe to call twice: the function is idempotent.
    static func createMyAccount(
        firstName: String,
        lastName: String,
        phone: String?,
        isMember: Bool,
        adultRating: Double?
    ) async throws -> UUID {
        struct Params: Encodable {
            let p_first_name: String
            let p_last_name: String
            let p_phone: String?
            let p_is_member: Bool
            let p_adult_rating: Double?
        }
        return try await supabase
            .rpc("create_my_account", params: Params(
                p_first_name: firstName,
                p_last_name: lastName,
                p_phone: phone,
                p_is_member: isMember,
                p_adult_rating: adultRating
            ))
            .execute()
            .value
    }

    /// The signed-in account row.
    static func myAccount() async throws -> Account? {
        guard let uid = supabase.auth.currentUser?.id else { return nil }
        let rows: [Account] = try await supabase
            .from("accounts")
            .select()
            .eq("id", value: uid)
            .execute()
            .value
        return rows.first
    }

    /// The club's payment line, from `payment_instructions()`. Tara's exact
    /// Zelle/Venmo wording, served from the DB so it changes without a release.
    static func paymentInstructions() async throws -> String {
        let value: String = try await supabase
            .rpc("payment_instructions")
            .execute()
            .value
        return value
    }
}

// MARK: - Notifications (the bell)

/// One row of `notifications`, as its owner sees it. The body was written by
/// the RPC that caused it (an invitation, a cancellation, a clinic message),
/// so the copy is already Tara's; this screen only lists it.
struct PlayerNotification: Codable, Identifiable, Sendable {
    let id: UUID
    let type: String
    let entityType: String?
    let entityId: UUID?
    let body: String
    let createdAt: Date
    let readAt: Date?

    var isUnread: Bool { readAt == nil }

    enum CodingKeys: String, CodingKey {
        case id, type, body
        case entityType = "entity_type"
        case entityId = "entity_id"
        case createdAt = "created_at"
        case readAt = "read_at"
    }
}

enum NotificationRepository {
    /// Newest first. RLS scopes the table to the caller's own rows, and the
    /// grant is SELECT plus UPDATE of `read_at` only (20260901000001).
    static func all(limit: Int = 50) async throws -> [PlayerNotification] {
        try await supabase
            .from("notifications")
            .select("id,type,entity_type,entity_id,body,created_at,read_at")
            .order("created_at", ascending: false)
            .limit(limit)
            .execute()
            .value
    }

    static func unreadCount() async throws -> Int {
        let rows: [PlayerNotification] = try await supabase
            .from("notifications")
            .select("id,type,entity_type,entity_id,body,created_at,read_at")
            .is("read_at", value: nil)
            .execute()
            .value
        return rows.count
    }

    private struct ReadStamp: Encodable { let read_at: Date }

    static func markRead(_ id: UUID) async throws {
        _ = try await supabase.from("notifications")
            .update(ReadStamp(read_at: Date()))
            .eq("id", value: id)
            .execute()
    }

    static func markAllRead() async throws {
        _ = try await supabase.from("notifications")
            .update(ReadStamp(read_at: Date()))
            .is("read_at", value: nil)
            .execute()
    }
}
