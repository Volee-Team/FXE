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
/// `p_court` must be sent as an explicit JSON null when clearing a court.
/// Swift's synthesized Encodable OMITS a nil optional, which makes PostgREST
/// look for assign_court(p_registration) and answer 404 "function not found".
/// That 404 is indistinguishable from a missing deploy (see CLAUDE.md,
/// 2026-09-01), so the null is written by hand here.
private struct AssignCourtParams: Encodable {
    let p_registration: UUID
    let p_court: Int?

    enum CodingKeys: String, CodingKey { case p_registration, p_court }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(p_registration, forKey: .p_registration)
        if let court = p_court { try c.encode(court, forKey: .p_court) }
        else { try c.encodeNil(forKey: .p_court) }
    }
}
private struct PlayerParam: Encodable { let p_player: UUID }
private struct NoteParams: Encodable { let p_player: UUID; let p_body: String }
private struct MembershipParams: Encodable { let p_player: UUID; let p_is_member: Bool }
private struct ActiveParams: Encodable { let p_player: UUID; let p_active: Bool }

private struct CancelClinicParams: Encodable { let p_clinic: UUID }

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
    /// Decision 0012: Tara marks who did not come; the tap after the clinic
    /// charges them the full fee. Optional so older rows decode.
    let noShow: Bool?
    let lateCancel: Bool?
    let courtesyUsed: Bool?
    /// The note left with a late cancel, the player's own or Tara's.
    let cancelNote: String?
    /// The latest non-refund charge on this row (pending, processing,
    /// succeeded, failed), or nil when it was never charged.
    let chargeStatus: String?
    let hasCard: Bool?

    enum CodingKeys: String, CodingKey {
        case id, status, paid
        case clinicId = "clinic_id"
        case playerId = "player_id"
        case courtNumber = "court_number"
        case registeredAt = "registered_at"
        case invitedAt = "invited_at"
        case noShow = "no_show"
        case lateCancel = "late_cancel"
        case courtesyUsed = "courtesy_used"
        case cancelNote = "cancel_note"
        case chargeStatus = "charge_status"
        case hasCard = "has_card"
    }

    /// A charge that is pending, processing or went through. The server's rule
    /// also frees a fee refunded in full (20260927100001); a row like that
    /// just keeps its controls hidden here, and the server stays the judge.
    var hasLiveCharge: Bool {
        ["pending", "processing", "succeeded"].contains(chargeStatus ?? "")
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

    /// "3.5, Member", the two things Tara needs beside a name when she is
    /// choosing who to invite.
    var subtitle: String {
        guard let p = player else { return "" }
        var parts: [String] = []
        if let r = p.adultRating, let bucket = NTRPRating(rating: r) { parts.append(bucket.label) }
        parts.append(p.isMember ? "Member" : "Non-member")
        if let n = p.levelNote, !n.isEmpty { parts.append(n) }
        return parts.joined(separator: ", ")
    }

    /// A late cancel on the Canceled list reads the way the web roster reads
    /// it: "Late: fee applies", or "Late: courtesy" when the courtesy was
    /// used (switched off since decision 0013). Nil for any other row.
    var lateLabel: String? {
        guard registration.status == .canceled, registration.lateCancel == true else { return nil }
        return registration.courtesyUsed == true ? "Late: courtesy" : "Late: fee applies"
    }

    /// The note left with a late cancel, quoted, for the Canceled list.
    var lateNote: String? {
        guard lateLabel != nil, let n = registration.cancelNote?.trimmingCharacters(in: .whitespacesAndNewlines), !n.isEmpty else { return nil }
        return "“\(n)”"
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

    /// Cancel a clinic. The RPC flips status, stamps canceled_at, and notifies
    /// everyone in You're In!, the Player Pool and Response Needed; it raises
    /// already_canceled on a second call, so the UI never double-notifies.
    /// Archive, never delete (hard rule 4): the row and its registrations stay.
    static func cancelClinic(_ clinic: UUID) async throws {
        _ = try await supabase
            .rpc("cancel_clinic", params: CancelClinicParams(p_clinic: clinic))
            .execute()
    }

    /// Toggle the Paid checkbox. The app tracks payment, it never moves money
    /// (decision 0003).
    /// Decision 0012: only Tara marks a no-show, only on a You're In! row.
    static func setNoShow(registration: UUID, noShow: Bool) async throws {
        struct P: Encodable { let p_registration: UUID; let p_no_show: Bool }
        try await supabase.rpc("admin_set_no_show", params: P(p_registration: registration, p_no_show: noShow)).execute()
    }

    /// Her one tap per clinic (decision 0012): pending ledger rows for
    /// everyone who owes, then stripe-charge turns them into Stripe calls.
    ///
    /// Returns what Stripe answered for THIS clinic's fees, not how many rows
    /// were queued: the audit (2026-09-27) found "Charged 6" printed when all
    /// six declined. stripe-charge answers `{ processed: { payment id: status } }`
    /// for every pending row it took, from any clinic; the ledger names them.
    static func chargeClinic(_ clinic: UUID) async throws -> ChargeOutcome {
        struct P: Encodable { let p_clinic: UUID }
        let counts: [String: Int] = try await supabase.rpc("admin_charge_clinic", params: P(p_clinic: clinic)).execute().value
        let settled: StripeChargeAnswer = try await supabase.functions.invoke("stripe-charge", options: .init(method: .post))
        let statuses = Dictionary((settled.processed ?? [:]).compactMap { key, value in
            UUID(uuidString: key).map { ($0, value) }
        }, uniquingKeysWith: { first, _ in first })
        var fees: [ChargeOutcome.Fee] = []
        if !statuses.isEmpty {
            let rows: [LedgerOutcomeRow] = try await supabase
                .from("payments_ledger")
                .select("id,kind,clinic_id,first_name,last_name,failure_code")
                .in("id", values: Array(statuses.keys))
                .execute()
                .value
            fees = rows.filter { $0.clinicId == clinic && $0.kind != "refund" }.map {
                ChargeOutcome.Fee(id: $0.id,
                                  name: "\($0.firstName ?? "") \($0.lastName ?? "")".trimmingCharacters(in: .whitespaces),
                                  reason: DeclineReason.label($0.failureCode))
            }
        }
        return ChargeOutcome.tally(statuses: statuses, fees: fees,
                                   queued: counts["charged"] ?? 0,
                                   already: counts["already"] ?? 0,
                                   noCard: counts["no_card"] ?? 0)
    }

    /// Who on this clinic owes a fee right now (20261002000001): the rows
    /// that get a Charge button. Empty while payments are off, before the
    /// clinic ends, and once everyone is charged or removed.
    static func feesDue(clinic: UUID) async throws -> [FeeDue] {
        struct P: Encodable { let p_clinic: UUID }
        return try await supabase.rpc("admin_fees_due", params: P(p_clinic: clinic)).execute().value
    }

    /// Tara's tap on one name (decision 0037): one pending ledger row for
    /// what that person owes, then stripe-charge sends it to Stripe. Returns
    /// Stripe's status for this fee ("succeeded", "failed", ...), or nil if
    /// Stripe has not answered yet; the roster reload shows it either way.
    /// Only the queueing can fail the tap: once the fee is queued it is owed
    /// to Stripe, and a stripe-charge that cannot be reached leaves it
    /// pending for the next call, so the row reads Processing, not an error.
    @discardableResult
    static func chargePlayer(registration: UUID) async throws -> String? {
        struct P: Encodable { let p_registration: UUID }
        struct Queued: Decodable { let payment_id: UUID }
        let queued: Queued = try await supabase.rpc("admin_charge_player", params: P(p_registration: registration)).execute().value
        let settled: StripeChargeAnswer? = try? await supabase.functions.invoke("stripe-charge", options: .init(method: .post))
        return settled?.processed?[queued.payment_id.uuidString.lowercased()]
    }

    /// Tara records a late cancellation for someone who told her (a text an
    /// hour before). You're In! to Canceled, late, with an optional note; the
    /// server refuses before the cutoff, once charged, or on a canceled clinic
    /// (20260927100002). Tells nobody.
    static func markLateCancel(registration: UUID, note: String?) async throws {
        struct P: Encodable {
            let p_registration: UUID
            let p_note: String?
            enum CodingKeys: String, CodingKey { case p_registration, p_note }
            // An explicit null, never an omitted key: PostgREST picks the
            // function by argument names (see AssignCourtParams above).
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_registration, forKey: .p_registration)
                if let n = p_note { try c.encode(n, forKey: .p_note) } else { try c.encodeNil(forKey: .p_note) }
            }
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        _ = try await supabase
            .rpc("admin_mark_late_cancel", params: P(p_registration: registration, p_note: (trimmed?.isEmpty ?? true) ? nil : trimmed))
            .execute()
    }

    /// Whether charging exists yet (app_settings.payments_enabled).
    static func paymentsEnabled() async throws -> Bool {
        let value: Bool = try await supabase.rpc("payments_enabled").execute().value
        return value
    }

    /// Per clinic that ended (or took a fee): charged, declined, not charged
    /// yet, and how many of those have a card (20260927100003).
    static func moneyClinics() async throws -> [MoneyClinic] {
        try await supabase.rpc("admin_money_clinics").execute().value
    }

    /// Cards whose charge failed and has not gone through since, and that
    /// Tara has not marked Resolved (money_rows calls those 'resolved').
    static func moneyDeclined() async throws -> [MoneyDecline] {
        try await supabase.rpc("admin_money_declined").execute().value
    }

    /// Tara's Resolved on a declined card she will not chase (decision 0024,
    /// question 83): it leaves her Action Needed and the Declined figures,
    /// the ledger keeps the charge, and the player's card stays declined.
    /// Refused with decline_not_open if the charge went through, or was
    /// resolved, meanwhile (hard rule 3).
    static func resolveDecline(payment: UUID) async throws {
        struct P: Encodable { let p_payment: UUID }
        _ = try await supabase.rpc("admin_resolve_decline", params: P(p_payment: payment)).execute()
    }

    /// Open chargebacks on card payments (admin_money_disputes,
    /// 20260928200001), soonest respond-by first. Tara answers them in Stripe.
    static func moneyDisputes() async throws -> [MoneyDispute] {
        try await supabase.rpc("admin_money_disputes").execute().value
    }

    /// Whether the Zelle/Venmo path exists (app_settings.zelle_allowed).
    /// False since decision 0013: the card is the only way to pay, so the
    /// Paid toggle and the unpaid reminder are not rendered.
    static func zelleAllowed() async throws -> Bool {
        let value: Bool = try await supabase.rpc("zelle_allowed").execute().value
        return value
    }

    static func setPaid(registration: UUID, paid: Bool) async throws {
        _ = try await supabase
            .rpc("set_paid", params: SetPaidParams(p_registration: registration, p_paid: paid))
            .execute()
    }

    /// Court 1-5, or nil for no court. This is Tara's court sheet: the value
    /// is hers to change at any time and it is not a state transition, so the
    /// RPC is an unconditional last-write-wins update by design
    /// (docs/web-admin.md section 4).
    static func assignCourt(registration: UUID, court: Int?) async throws {
        _ = try await supabase
            .rpc("assign_court", params: AssignCourtParams(p_registration: registration, p_court: court))
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

    /// One tap, one reminder to everyone in You're In! who has not paid. The
    /// body is built from things Tara owns: the clinic name, its date, and her
    /// own payment line (`payment_instructions()`). The connective words are
    /// ours and sit in docs/copy-review.md until Alex ticks them. Audience
    /// 'unpaid' is resolved server-side, so the recipient list is the database's,
    /// not this screen's. Web admin sends the identical sentence.
    static func remindUnpaid(clinic: ClinicAdmin) async throws {
        // Tara's payment line has no closing period; give it one so the sentences read.
        var paymentLine = try await ProfileRepository.paymentInstructions().trimmingCharacters(in: .whitespacesAndNewlines)
        if let last = paymentLine.last, !".!?".contains(last) { paymentLine += "." }
        let when = clinic.startsAt.formatted(date: .abbreviated, time: .shortened)
        let body = "Just a reminder that \(clinic.name) (\(when)) hasn't been paid yet. \(paymentLine) Thanks!"
        try await sendMessage(clinic: clinic.id, audience: .unpaid, body: body)
    }

    // MARK: - Player directory (20260902000002)
    //
    // Everything Tara does to a PERSON rather than a registration. Notes are
    // one of the nine hidden facts: read and written only through admin-only
    // RPCs, never through a view a player could reach.

    static func playerNote(_ player: UUID) async throws -> String {
        try await supabase
            .rpc("admin_player_note", params: PlayerParam(p_player: player))
            .execute()
            .value
    }

    static func setPlayerNote(_ player: UUID, body: String) async throws {
        _ = try await supabase
            .rpc("admin_set_player_note", params: NoteParams(p_player: player, p_body: body))
            .execute()
    }

    /// Membership is self-reported at sign-up; this is Tara's correction
    /// (for-tara.md question 5). It decides the head-start window and the rate.
    static func setMembership(_ player: UUID, isMember: Bool) async throws {
        _ = try await supabase
            .rpc("admin_set_membership", params: MembershipParams(p_player: player, p_is_member: isMember))
            .execute()
    }

    static func setActive(_ player: UUID, isActive: Bool) async throws {
        _ = try await supabase
            .rpc("set_player_active", params: ActiveParams(p_player: player, p_active: isActive))
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

    // MARK: - Player history (20260928800001, decision 0027 §1)
    //
    // Admin only in Postgres: require_admin() is the first line of
    // admin_player_history, so a member gets not_authorized, never a count.

    /// The history of several players in ONE call: the Player Pool of one
    /// clinic. The function answers for every player; the filter on its
    /// result keeps the answer to the people on screen, far under
    /// PostgREST's row cap.
    static func playerHistory(players ids: [UUID]) async throws -> [PlayerHistory] {
        guard !ids.isEmpty else { return [] }
        return try await supabase
            .rpc("admin_player_history", params: HistoryParams(p_player: nil))
            .in("player_id", values: ids)
            .execute()
            .value
    }

    /// One player's history, for their page. Nil only for an id that is no player.
    static func playerHistory(player: UUID) async throws -> PlayerHistory? {
        let rows: [PlayerHistory] = try await supabase
            .rpc("admin_player_history", params: HistoryParams(p_player: player))
            .execute()
            .value
        return rows.first
    }
}

/// `p_player` is sent as an explicit JSON null for "every player", never an
/// omitted key: PostgREST picks the function by argument names (see
/// AssignCourtParams above).
private struct HistoryParams: Encodable {
    let p_player: UUID?

    enum CodingKeys: String, CodingKey { case p_player }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if let p = p_player { try c.encode(p, forKey: .p_player) } else { try c.encodeNil(forKey: .p_player) }
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
    /// The note the player wrote at level entry, only Tara reads it (0012/0013).
    let levelNote: String?
    /// Signed the current waiver (decision 0013 §4).
    let waiverAccepted: Bool?

    enum CodingKeys: String, CodingKey {
        case id, kind, age
        case firstName = "first_name"
        case lastName = "last_name"
        case adultRating = "adult_rating"
        case isMember = "is_member"
        case isActive = "is_active"
        case hasNotes = "has_notes"
        case levelNote = "level_note"
        case waiverAccepted = "waiver_accepted"
    }

    var displayName: String { "\(firstName) \(lastName)" }
}

// MARK: - Money (20260927100003)

/// One person who owes a fee now, from admin_fees_due (20261002000001).
struct FeeDue: Decodable, Sendable {
    let registrationId: UUID
    let kind: String
    let amountCents: Int
    /// "not_charged", or "declined" when an earlier try failed.
    let state: String
    let hasCard: Bool

    enum CodingKeys: String, CodingKey {
        case kind, state
        case registrationId = "registration_id"
        case amountCents = "amount_cents"
        case hasCard = "has_card"
    }
}

/// stripe-charge's answer: Stripe's status for every pending row it took.
struct StripeChargeAnswer: Decodable, Sendable {
    let processed: [String: String]?
}

/// The ledger's name for a payment stripe-charge just processed.
struct LedgerOutcomeRow: Decodable, Sendable {
    let id: UUID
    let kind: String
    let clinicId: UUID?
    let firstName: String?
    let lastName: String?
    let failureCode: String?

    enum CodingKeys: String, CodingKey {
        case id, kind
        case clinicId = "clinic_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case failureCode = "failure_code"
    }
}

/// One clinic's money, from admin_money_clinics. Admin only.
struct MoneyClinic: Decodable, Identifiable, Sendable {
    let clinicId: UUID
    let clinicName: String
    let startsAt: Date
    let canceled: Bool
    let chargedCents: Int
    let declinedCount: Int
    let notChargedCount: Int
    let notChargedCents: Int
    /// Not charged yet AND the player has a card: what one more Charge clinic
    /// would charge. Action Needed shows a clinic only while this is above 0.
    let chargeableCount: Int

    var id: UUID { clinicId }

    enum CodingKeys: String, CodingKey {
        case canceled
        case clinicId = "clinic_id"
        case clinicName = "clinic_name"
        case startsAt = "starts_at"
        case chargedCents = "charged_cents"
        case declinedCount = "declined_count"
        case notChargedCount = "not_charged_count"
        case notChargedCents = "not_charged_cents"
        case chargeableCount = "chargeable_count"
    }
}

/// A card whose charge failed and has not gone through since
/// (admin_money_declined). The name is the account holder's, the cardholder.
struct MoneyDecline: Decodable, Identifiable, Sendable {
    let registrationId: UUID
    let clinicId: UUID
    let clinicName: String
    let clinicStartsAt: Date
    let firstName: String?
    let lastName: String?
    let amountCents: Int?
    let failureCode: String?
    /// The account has since been deleted (20260927300001): nobody can fix
    /// that card, so Action Needed leaves the row out; the web Money tab keeps it.
    let accountDeleted: Bool?
    /// The failed charge the row shows: what Resolved stamps (20260928700001).
    /// Nil from a server without that migration, and then no Resolved.
    let paymentId: UUID?

    var id: UUID { registrationId }
    var displayName: String {
        let n = "\(firstName ?? "") \(lastName ?? "")".trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Unknown player" : n
    }

    enum CodingKeys: String, CodingKey {
        case registrationId = "registration_id"
        case clinicId = "clinic_id"
        case clinicName = "clinic_name"
        case clinicStartsAt = "clinic_starts_at"
        case firstName = "first_name"
        case lastName = "last_name"
        case amountCents = "amount_cents"
        case failureCode = "failure_code"
        case accountDeleted = "account_deleted"
        case paymentId = "payment_id"
    }
}

/// A card payment the cardholder's bank is taking back, still open
/// (admin_money_disputes, 20260928200001). Tara answers it in Stripe's
/// dashboard by the respond-by date; a lost one is subtracted from Charged.
struct MoneyDispute: Decodable, Identifiable, Sendable {
    let paymentId: UUID
    let clinicId: UUID
    let clinicName: String
    let clinicStartsAt: Date
    let firstName: String?
    let lastName: String?
    /// What the bank is taking back; can be less than the fee.
    let amountCents: Int
    let reason: String?
    let status: String
    let respondBy: Date?

    var id: UUID { paymentId }
    var displayName: String {
        let n = "\(firstName ?? "") \(lastName ?? "")".trimmingCharacters(in: .whitespaces)
        return n.isEmpty ? "Unknown player" : n
    }

    enum CodingKeys: String, CodingKey {
        case reason, status
        case paymentId = "payment_id"
        case clinicId = "clinic_id"
        case clinicName = "clinic_name"
        case clinicStartsAt = "clinic_starts_at"
        case firstName = "first_name"
        case lastName = "last_name"
        case amountCents = "amount_cents"
        case respondBy = "respond_by"
    }
}

/// Stripe's decline codes in words, the same words as the web admin's DECLINE
/// map (Tara, 2026-09-26: "reason codes ... (i.e. NSF, Card Expired, Etc)").
/// A code not listed shows as itself; no code shows nothing.
enum DeclineReason {
    static let labels: [String: String] = [
        "insufficient_funds": "Insufficient funds (NSF)",
        "expired_card": "Card expired",
        "card_declined": "Card declined",
        "generic_decline": "Card declined",
        "do_not_honor": "Card declined by bank",
        "incorrect_cvc": "Wrong security code",
        "incorrect_number": "Wrong card number",
        "lost_card": "Card reported lost",
        "stolen_card": "Card reported stolen",
        "authentication_required": "Needs the cardholder to approve",
        "processing_error": "Processing error, try again",
    ]

    static func label(_ code: String?) -> String? {
        guard let code, !code.isEmpty else { return nil }
        return labels[code] ?? code
    }
}
