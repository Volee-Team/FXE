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
private struct CancelParams: Encodable {
    let p_registration: UUID
    let p_note: String?
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
    /// Published clinics from now to five weeks out. The view already drops
    /// finished clinics (the 2026-08-28 floor); this is the other edge, so a
    /// season Tara publishes in bulk does not become one endless scroll. Five
    /// weeks is this week plus a month, which is as far ahead as registration
    /// windows make anything actionable (decision 0001).
    /// One clinic, for a notification that names it. nil once it has ended:
    /// the view drops finished clinics, so there is nothing to open.
    static func clinic(id: UUID) async throws -> ClinicPublic? {
        let rows: [ClinicPublic] = try await supabase
            .from("clinics_public")
            .select()
            .eq("id", value: id)
            .execute()
            .value
        return rows.first
    }

    static func upcoming() async throws -> [ClinicPublic] {
        let horizon = Calendar.current.date(byAdding: .day, value: 35, to: .now) ?? .now
        return try await supabase
            .from("clinics_public")
            .select()
            .lte("starts_at", value: ISO8601DateFormatter().string(from: horizon))
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

/// One row of my_past_clinics: a clinic that has ended, with only this
/// player's own outcome on it (feature review 09-02, decision 0012 §10).
struct PastClinic: Codable, Identifiable, Sendable {
    let registrationId: UUID
    let clinicId: UUID
    let name: String
    let startsAt: Date
    let endsAt: Date
    let durationMinutes: Int
    let category: String?
    let status: RegistrationStatus
    let noShow: Bool?
    let lateCancel: Bool?
    let priceCentsCharged: Int?
    let paid: Bool

    var id: UUID { registrationId }

    enum CodingKeys: String, CodingKey {
        case name, category, status, paid
        case registrationId = "registration_id"
        case clinicId = "clinic_id"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case durationMinutes = "duration_minutes"
        case noShow = "no_show"
        case lateCancel = "late_cancel"
        case priceCentsCharged = "price_cents_charged"
    }
}

enum RegistrationRepository {

    /// Finished clinics I was part of, newest first.
    static func past() async throws -> [PastClinic] {
        try await supabase
            .from("my_past_clinics")
            .select()
            .order("starts_at", ascending: false)
            .limit(40)
            .execute()
            .value
    }

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

    /// `note` is the player's own concise message, required by the server
    /// inside the cutoff (decision 0010); nil otherwise.
    static func cancelRegistration(registrationId: UUID, note: String? = nil) async throws {
        try await supabase
            .rpc("cancel_registration", params: CancelParams(p_registration: registrationId, p_note: note))
            .execute()
    }

    /// Whether this player's one courtesy late cancellation per 90 days is
    /// still available (decision 0012). Decides which sentence the cancel
    /// sheet shows; the server applies it regardless of what the screen said.
    static func myCourtesyAvailable(player: UUID) async throws -> Bool {
        struct P: Encodable { let p_player: UUID }
        let value: Bool = try await supabase.rpc("my_courtesy_available", params: P(p_player: player)).execute().value
        return value
    }

    /// Hours before a clinic after which a cancellation needs a note.
    /// `app_settings.cancel_cutoff_hours`, 4 by Tara's word.
    static func cancelCutoffHours() async throws -> Int {
        let value: Int = try await supabase.rpc("cancel_cutoff_hours").execute().value
        return value
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

/// Tara's waiver text, one version at a time (decision 0013 §4).
struct Waiver: Codable, Sendable {
    let version: String
    let title: String
    let organizer: String
    let body: String

    struct Paragraph { let text: String; let isHeading: Bool }
    /// Her document is headings ("1  Activities and Released Parties") and
    /// paragraphs, stored blank-line separated. A heading is a short line
    /// starting with a number and two spaces, as she typed them.
    var paragraphs: [Paragraph] {
        body.components(separatedBy: "\n\n").map { raw in
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let heading = t.count < 60 && (t.range(of: "^[0-9]+  ", options: .regularExpression) != nil || t == "Participant Acknowledgment" || t.hasPrefix("IMPORTANT NOTICE"))
            return Paragraph(text: t, isHeading: heading)
        }.filter { !$0.text.isEmpty }
    }
}

enum ProfileRepository {
    /// The current waiver, or nil if none is published.
    static func currentWaiver() async throws -> Waiver? {
        let rows: [Waiver] = try await supabase.rpc("current_waiver").execute().value
        return rows.first
    }

    /// Whether this account has signed the current version.
    static func myWaiverAccepted() async throws -> Bool {
        let value: Bool = try await supabase.rpc("my_waiver_accepted").execute().value
        return value
    }

    /// The electronic signature: version, typed legal name, the build that
    /// showed the text. Email and time are recorded server-side.
    static func acceptWaiver(version: String, legalName: String, appVersion: String) async throws {
        struct P: Encodable { let p_version: String; let p_legal_name: String; let p_app_version: String }
        _ = try await supabase
            .rpc("accept_waiver", params: P(p_version: version, p_legal_name: legalName, p_app_version: appVersion))
            .execute()
    }

    /// Account deletion (decision 0013 §5, App Store 5.1.1(v)). The edge
    /// function scrubs the person through delete_my_account() and removes the
    /// sign-in through Supabase's admin API; history stays. The caller signs
    /// out afterwards.
    static func deleteMyAccount() async throws {
        _ = try await supabase.functions.invoke("delete-account")
    }


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
        adultRating: Double?,
        levelNote: String? = nil
    ) async throws -> UUID {
        struct Params: Encodable {
            let p_first_name: String
            let p_last_name: String
            let p_phone: String?
            let p_is_member: Bool
            let p_adult_rating: Double?
            let p_level_note: String?
        }
        return try await supabase
            .rpc("create_my_account", params: Params(
                p_first_name: firstName,
                p_last_name: lastName,
                p_phone: phone,
                p_is_member: isMember,
                p_adult_rating: adultRating,
                p_level_note: levelNote
            ))
            .execute()
            .value
    }

    /// Edit the caller's own name, phone and rating. Two narrow UPDATEs on the
    /// exact columns `authenticated` holds column-level UPDATE for
    /// (20260802000003): first_name, last_name, phone on `accounts`;
    /// first_name, last_name, adult_rating on `players`. RLS scopes both rows
    /// to the caller. Membership is deliberately NOT here: it decides pricing
    /// and the head-start window, and after sign-up it is Tara's to correct
    /// (for-tara.md q5, hard rule 2).
    static func updateMyProfile(firstName: String, lastName: String, phone: String?, adultRating: Double?, levelNote: String? = nil, player: UUID) async throws {
        guard let uid = supabase.auth.currentUser?.id else { return }
        struct AccountPatch: Encodable { let first_name: String; let last_name: String; let phone: String? }
        struct PlayerPatch: Encodable { let first_name: String; let last_name: String; let adult_rating: Double?; let level_note: String? }
        _ = try await supabase.from("accounts")
            .update(AccountPatch(first_name: firstName, last_name: lastName, phone: phone))
            .eq("id", value: uid)
            .execute()
        _ = try await supabase.from("players")
            .update(PlayerPatch(first_name: firstName, last_name: lastName, adult_rating: adultRating, level_note: levelNote))
            .eq("id", value: player)
            .execute()
    }

    /// Push address for THIS account on THIS phone (decision 0008). The
    /// account is auth.uid() inside the RPC; the token is the only argument.
    static func registerDevice(_ token: String) async throws {
        struct P: Encodable { let p_token: String; let p_platform: String }
        _ = try await supabase.rpc("register_device", params: P(p_token: token, p_platform: "ios")).execute()
    }

    static func unregisterDevice(_ token: String) async throws {
        struct P: Encodable { let p_token: String }
        _ = try await supabase.rpc("unregister_device", params: P(p_token: token)).execute()
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
    // `.minimal`, not the SDK's default `.representation`: returning the row
    // means RETURNING every column, and the push audit columns are not
    // client-readable (20260923000001), so the whole UPDATE would be refused.

    static func markRead(_ id: UUID) async throws {
        _ = try await supabase.from("notifications")
            .update(ReadStamp(read_at: Date()), returning: .minimal)
            .eq("id", value: id)
            .execute()
    }

    static func markAllRead() async throws {
        _ = try await supabase.from("notifications")
            .update(ReadStamp(read_at: Date()), returning: .minimal)
            .is("read_at", value: nil)
            .execute()
    }
}
