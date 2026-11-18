//
//  JuniorsRepository.swift
//  FXETennis
//
//  Juniors phase 1 (decision 0061). Every call is a security-definer RPC that
//  reads the account from auth.uid(); no table is read directly (the three
//  juniors tables grant nothing to a client). Children never come from
//  `players`: the server keeps that view adults-only for the apps already on
//  phones (decision 0057).
//

import Foundation
import Supabase

enum JuniorsRepository {
    /// The caller's active children, with age and waiver status.
    static func myChildren() async throws -> [Child] {
        try await supabase.rpc("my_children").execute().value
    }

    /// Adds a child. Refuses child_exists, name_required, invalid_birthday,
    /// too_many_children.
    static func addChild(firstName: String, lastName: String, dateOfBirth: String) async throws {
        struct P: Encodable { let p_first_name: String; let p_last_name: String; let p_date_of_birth: String }
        _ = try await supabase
            .rpc("add_my_child", params: P(p_first_name: firstName, p_last_name: lastName, p_date_of_birth: dateOfBirth))
            .execute()
    }

    /// Edits the caller's own child. Refuses not_your_child, child_locked
    /// (approved, declined or signed: only Tara may change name or birthday),
    /// and the same field refusals as adding.
    static func updateChild(id: UUID, firstName: String, lastName: String, dateOfBirth: String) async throws {
        struct P: Encodable { let p_child: UUID; let p_first_name: String; let p_last_name: String; let p_date_of_birth: String }
        _ = try await supabase
            .rpc("update_my_child", params: P(p_child: id, p_first_name: firstName, p_last_name: lastName, p_date_of_birth: dateOfBirth))
            .execute()
    }

    /// Archives the child. Refuses child_has_upcoming while a spot or a late
    /// request is still to come.
    static func removeChild(id: UUID) async throws {
        struct P: Encodable { let p_child: UUID }
        _ = try await supabase.rpc("remove_my_child", params: P(p_child: id)).execute()
    }

    /// The current parent/guardian text, or nil while none is published.
    static func currentWaiver() async throws -> Waiver? {
        let rows: [Waiver] = try await supabase.rpc("current_junior_waiver").execute().value
        return rows.first
    }

    /// The parent signs for one child: version, the parent's typed legal
    /// name, the build. Email and time are recorded by the server.
    static func acceptWaiver(child: UUID, version: String, legalName: String, appVersion: String) async throws {
        struct P: Encodable { let p_child: UUID; let p_version: String; let p_legal_name: String; let p_app_version: String }
        _ = try await supabase
            .rpc("accept_child_waiver", params: P(p_child: child, p_version: version, p_legal_name: legalName, p_app_version: appVersion))
            .execute()
    }

    /// Tara's active programs, in her order.
    static func programs() async throws -> [JuniorProgram] {
        try await supabase.rpc("list_junior_programs").execute().value
    }

    /// Every approval row for the caller's children.
    static func myApprovals() async throws -> [ProgramApproval] {
        try await supabase.rpc("my_program_approvals").execute().value
    }

    /// Asks Tara to approve this child for a program that needs it. A second
    /// tap changes nothing. Refuses approval_declined, approval_not_needed.
    static func requestApproval(child: UUID, program: UUID) async throws {
        struct P: Encodable { let p_child: UUID; let p_program: UUID }
        _ = try await supabase.rpc("request_program_approval", params: P(p_child: child, p_program: program)).execute()
    }
}
