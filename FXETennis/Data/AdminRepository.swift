//
//  AdminRepository.swift
//  FXETennis
//
//  Tara's side of the app. Same convention as Repositories.swift: stateless
//  enums of static async funcs, and views never touch the client directly.
//
//  WHY THIS EXISTS AND WHY IT IS ONLY UI
//  -------------------------------------
//  An audit on 2026-08-13 walked Tara's weekly workflow and found 1 of 11 steps
//  supported. Of the 10 that were not, EIGHT needed no backend at all: the RPCs
//  already existed, were granted to `authenticated`, and were covered by the SQL
//  probes. There was simply no screen calling them. So this file is deliberately
//  thin: it wires existing, already-tested server functions to a UI.
//
//  SECURITY NOTE. Nothing here is a privilege boundary. `is_admin()` is checked
//  server-side inside every one of these RPCs via `require_admin()`, and the
//  `clinics_admin` / `registrations_admin` views return ZERO ROWS to a
//  non-admin rather than raising. Hiding the tab is a courtesy to players, not
//  a control: a non-admin who reached these screens would see an empty list and
//  get an error from every action. Never let a UI check become the only check.
//

import Foundation
import Supabase

// MARK: - RPC parameter encodables

private struct RegistrationParam: Encodable { let p_registration: UUID }
private struct SetPaidParams: Encodable {
    let p_registration: UUID
    let p_paid: Bool
}
private struct MessageParams: Encodable {
    let p_clinic: UUID
    let p_audience: String
    let p_body: String
}
private struct PlacePlayerParams: Encodable {
    let p_clinic: UUID
    let p_player: UUID
    let p_status: String
}
private struct SearchParams: Encodable {
    let p_query: String
    let p_include_inactive: Bool
}

// MARK: - Models the admin screens need

/// A clinic as Tara sees it: everything, including the two things players are
/// never shown (`internal_capacity` and any count).
struct ClinicAdmin: Codable, Identifiable, Sendable {
    let id: UUID
    let name: String
    let audience: String
    let category: String?
    let startsAt: Date
    let endsAt: Date
    let status: String
    let internalCapacity: Int?
    let memberPriceCents: Int?
    let nonmemberPriceCents: Int?

    enum CodingKeys: String, CodingKey {
        case id, name, audience, category, status
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case internalCapacity = "internal_capacity"
        case memberPriceCents = "member_price_cents"
        case nonmemberPriceCents = "nonmember_price_cents"
    }

    var isCanceled: Bool { status == "canceled" }
    var isDraft: Bool { status == "draft" }
}

/// One registration row on Tara's roster.
struct RegistrationAdmin: Codable, Identifiable, Sendable {
    let id: UUID
    let clinicId: UUID
    let playerId: UUID
    let status: RegistrationStatus
    let paid: Bool
    let courtNumber: Int?
    let registeredAt: Date
    let invitedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id, status, paid
        case clinicId = "clinic_id"
        case playerId = "player_id"
        case courtNumber = "court_number"
        case registeredAt = "registered_at"
        case invitedAt = "invited_at"
    }
}

/// A registration joined to the person it belongs to. The roster is useless
/// without names, and `registrations_admin` carries only ids.
struct RosterEntry: Identifiable, Sendable {
    let registration: RegistrationAdmin
    let player: PlayerProfile?

    var id: UUID { registration.id }

    var displayName: String {
        guard let p = player else { return "Unknown player" }
        return "\(p.firstName) \(p.lastName)"
    }

    /// "3.5 · Member" — the two things Tara needs beside a name when she is
    /// choosing who to invite.
    var subtitle: String {
        guard let p = player else { return "" }
        var parts: [String] = []
        if let r = p.adultRating, let bucket = NTRPRating(rating: r) { parts.append(bucket.label) }
        parts.append(p.isMember ? "Member" : "Non-member")
        return parts.joined(separator: " · ")
    }
}

/// Who a clinic message goes to. Mirrors the `message_audience` enum.
enum MessageAudience: String, CaseIterable, Identifiable, Sendable {
    case everyone
    case in_ = "in"
    case pool
    case responseNeeded = "response_needed"
    case unpaid

    var id: String { rawValue }

    /// Locked terminology. These are the words Tara uses, and CLAUDE.md forbids
    /// substituting synonyms.
    var label: String {
        switch self {
        case .everyone: return "Everyone"
        case .in_: return "You're In!"
        case .pool: return "Player Pool"
        case .responseNeeded: return "Response Needed"
        case .unpaid: return "Unpaid"
        }
    }
}

// MARK: - Repository

enum AdminRepository {

    /// Every clinic, soonest first, including drafts. Returns zero rows to a
    /// non-admin because `clinics_admin` is `where is_admin()`.
    static func allClinics() async throws -> [ClinicAdmin] {
        try await supabase
            .from("clinics_admin")
            .select("id,name,audience,category,starts_at,ends_at,status,internal_capacity,member_price_cents,nonmember_price_cents")
            .order("starts_at", ascending: true)
            .execute()
            .value
    }

    /// Every registration on one clinic, canceled ones included.
    ///
    /// Canceled rows are deliberately fetched rather than filtered server-side:
    /// hard rule 4 is archive-never-delete, and the Developer Guide's Screen 14
    /// says "Keep canceled players visible to Tara. Show cancellation
    /// timestamp." The view decides what to show; the query does not decide for
    /// it.
    static func registrations(clinic: UUID) async throws -> [RegistrationAdmin] {
        try await supabase
            .from("registrations_admin")
            .select()
            .eq("clinic_id", value: clinic)
            .order("registered_at", ascending: true)
            .execute()
            .value
    }

    /// The player rows behind a set of registrations.
    ///
    /// One query for the whole roster rather than one per row: a 12-player
    /// clinic would otherwise be 12 round trips on a phone at a tennis court.
    /// An admin can read every player (`players_own` is
    /// `account_id = auth.uid() OR is_admin()`).
    static func players(ids: [UUID]) async throws -> [PlayerProfile] {
        guard !ids.isEmpty else { return [] }
        return try await supabase
            .from("players")
            .select()
            .in("id", values: ids)
            .execute()
            .value
    }

    /// Roster for one clinic, names attached, ordered the way Tara reads it:
    /// registration order, which is what makes Player Pool fair.
    static func roster(clinic: UUID) async throws -> [RosterEntry] {
        let regs = try await registrations(clinic: clinic)
        let people = try await players(ids: Array(Set(regs.map(\.playerId))))
        let byId = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
        return regs.map { RosterEntry(registration: $0, player: byId[$0.playerId]) }
    }

    // MARK: - Actions. Every one of these is an existing, probe-covered RPC.

    /// Invite one Player Pool entry. Moves them to Response Needed and notifies
    /// them. Never auto-promotes anyone else: hard rule 2, and the guide is
    /// explicit that "the app never invites the next player automatically".
    static func invite(registration: UUID) async throws {
        _ = try await supabase
            .rpc("invite_from_pool", params: RegistrationParam(p_registration: registration))
            .execute()
    }

    /// Withdraw an outstanding invitation, returning the player to Player Pool.
    static func cancelInvitation(registration: UUID) async throws {
        _ = try await supabase
            .rpc("cancel_invitation", params: RegistrationParam(p_registration: registration))
            .execute()
    }

    /// Toggle the Paid checkbox. The app tracks payment, it never moves money
    /// (decision 0003).
    static func setPaid(registration: UUID, paid: Bool) async throws {
        _ = try await supabase
            .rpc("set_paid", params: SetPaidParams(p_registration: registration, p_paid: paid))
            .execute()
    }

    /// Put a player straight into a clinic without them using the app.
    ///
    /// Tara asked for this in `for-tara.md` question 3: "Someone calls you, or
    /// grabs you at the club." Answer was yes, and she wanted it in week one.
    static func place(clinic: UUID, player: UUID, status: RegistrationStatus = .in_) async throws {
        _ = try await supabase
            .rpc("place_player", params: PlacePlayerParams(
                p_clinic: clinic, p_player: player, p_status: status.rawValue
            ))
            .execute()
    }

    /// Message one audience on a clinic. Push only, never a duplicate email,
    /// and the message stays on the clinic page for that audience
    /// (decision 0005).
    static func sendMessage(clinic: UUID, audience: MessageAudience, body: String) async throws {
        _ = try await supabase
            .rpc("send_clinic_message", params: MessageParams(
                p_clinic: clinic, p_audience: audience.rawValue, p_body: body
            ))
            .execute()
    }

    /// Forgiving name search. "Ann" returns Anna, Ann, Annette and Joann, per
    /// the guide's Screen 19.
    static func searchPlayers(_ query: String, includeInactive: Bool = false) async throws -> [PlayerSearchResult] {
        try await supabase
            .rpc("search_players", params: SearchParams(p_query: query, p_include_inactive: includeInactive))
            .execute()
            .value
    }
}

/// A player's "can I still get in?" ask, waiting on Tara (20260827000002).
struct LateRequest: Codable, Identifiable, Sendable {
    let id: UUID
    let clinicId: UUID
    let playerId: UUID
    let message: String?
    let status: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, message, status
        case clinicId = "clinic_id"
        case playerId = "player_id"
        case createdAt = "created_at"
    }
}

/// One unread thing addressed to the admin: a cancellation, a decline, an
/// acceptance. The body is written server-side and already names the player.
struct AdminNotice: Codable, Identifiable, Sendable {
    let id: UUID
    let type: String
    let body: String
    let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case id, type, body
        case createdAt = "created_at"
    }
}

extension AdminRepository {

    /// Pending late requests, oldest first, optionally for one clinic.
    static func pendingLateRequests(clinic: UUID? = nil) async throws -> [LateRequest] {
        var q = supabase.from("late_requests").select().eq("status", value: "pending")
        if let clinic { q = q.eq("clinic_id", value: clinic) }
        return try await q.order("created_at", ascending: true).execute().value
    }

    /// Tara answers a late request. Approving places the player via
    /// place_player after the server re-checks capacity.
    static func resolveLateRequest(id: UUID, approve: Bool) async throws {
        struct P: Encodable { let p_request: UUID; let p_approve: Bool }
        _ = try await supabase
            .rpc("resolve_late_request", params: P(p_request: id, p_approve: approve))
            .execute()
    }

    /// Unread admin notices. RLS scopes rows to the signed-in account, so a
    /// non-admin simply sees their own (player) notifications here.
    static func unreadNotices() async throws -> [AdminNotice] {
        try await supabase
            .from("notifications")
            .select("id,type,body,created_at")
            .is("read_at", value: nil)
            .in("type", values: ["player_canceled", "invitation_declined", "invitation_accepted"])
            .order("created_at", ascending: false)
            .limit(30)
            .execute()
            .value
    }

    /// Mark one notice read. Column-scoped grant: read_at is the only field a
    /// recipient may touch (20260901000001).
    static func markRead(notice: UUID) async throws {
        struct U: Encodable { let read_at: Date }
        _ = try await supabase
            .from("notifications")
            .update(U(read_at: Date()))
            .eq("id", value: notice)
            .execute()
    }
}

/// A row from `search_players`. Flatter than `PlayerProfile`: the RPC returns a
/// table shaped for the directory, including a derived `age` for juniors and a
/// `has_notes` flag so Tara can see who she has written about without exposing
/// the note itself.
struct PlayerSearchResult: Codable, Identifiable, Sendable {
    let id: UUID
    let firstName: String
    let lastName: String
    let kind: String
    let age: Int?
    let adultRating: Double?
    let isMember: Bool
    let isActive: Bool
    let hasNotes: Bool

    enum CodingKeys: String, CodingKey {
        case id, kind, age
        case firstName = "first_name"
        case lastName = "last_name"
        case adultRating = "adult_rating"
        case isMember = "is_member"
        case isActive = "is_active"
        case hasNotes = "has_notes"
    }

    var displayName: String { "\(firstName) \(lastName)" }
}
