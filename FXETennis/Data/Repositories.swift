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
    static func myPlayers() async throws -> [PlayerProfile] {
        try await supabase
            .from("players")
            .select()
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
