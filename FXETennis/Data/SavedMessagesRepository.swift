//
//  SavedMessagesRepository.swift
//  FXETennis
//
//  Tara's saved messages (decision 0030). Three admin-only RPCs, each opening
//  with require_admin(); no client role can read the table itself.
//

import Foundation
import Supabase

enum SavedMessagesRepository {
    /// The live ones, newest first (the server orders them).
    static func list() async throws -> [SavedMessage] {
        try await supabase.rpc("admin_message_templates").execute().value
    }

    /// Keeps the text. The same text twice is kept once, server-side.
    static func save(_ body: String) async throws {
        struct P: Encodable { let p_body: String }
        _ = try await supabase.rpc("admin_save_message_template", params: P(p_body: body)).execute()
    }

    /// Remove: archived, never deleted (hard rule 4). A second Remove (the
    /// laptop got there first) answers false, and the reload shows it gone.
    static func remove(_ id: UUID) async throws {
        struct P: Encodable { let p_id: UUID }
        _ = try await supabase.rpc("admin_archive_message_template", params: P(p_id: id)).execute()
    }
}
