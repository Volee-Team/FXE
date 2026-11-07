//
//  ProRepository.swift
//  FXETennis
//
//  A pro's calls (decision 0025, migration 20260928600001; the week and
//  courts, 20261107000002). Same
//  convention as AdminRepository: a stateless enum; views never touch the
//  client directly.
//
//  SECURITY NOTE. Nothing here is a privilege boundary. pro_today(),
//  pro_set_no_show() and pro_mark_late_cancel() each ask is_pro() in the
//  database and refuse anyone else, and the two writes refuse any clinic that
//  is not today's in New York. A pro's account calling Tara's RPCs gets
//  not_authorized from every one of them (tests/sql/pro_role.sql, r4).
//
//  The two writes return nothing on purpose: Tara's versions return the whole
//  registrations row, which carries the price and the paid flag.
//

import Foundation
import Supabase

enum ProRepository {

    /// Today's published clinics and who is You're In! in each.
    static func today() async throws -> [ProTodayClinic] {
        let rows: [ProTodayRow] = try await supabase.rpc("pro_today").execute().value
        return ProToday.group(rows)
    }

    /// Today and the six days after it (pro_week, 20261107000002): the same
    /// columns as pro_today.
    static func week() async throws -> [ProTodayRow] {
        try await supabase.rpc("pro_week").execute().value
    }

    /// Court 1 to 5, or none, on a You're In! row of one of the week's
    /// clinics. Returns nothing, like the two marks below.
    static func assignCourt(registration: UUID, court: Int?) async throws {
        struct P: Encodable {
            let p_registration: UUID
            let p_court: Int?
            enum CodingKeys: String, CodingKey { case p_registration, p_court }
            // An explicit null for "No court" (AdminRepository.AssignCourtParams).
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_registration, forKey: .p_registration)
                if let n = p_court { try c.encode(n, forKey: .p_court) } else { try c.encodeNil(forKey: .p_court) }
            }
        }
        try await supabase
            .rpc("pro_assign_court", params: P(p_registration: registration, p_court: court))
            .execute()
    }

    /// Came / No-show on a registration in one of today's clinics.
    static func setNoShow(registration: UUID, noShow: Bool) async throws {
        struct P: Encodable { let p_registration: UUID; let p_no_show: Bool }
        try await supabase
            .rpc("pro_set_no_show", params: P(p_registration: registration, p_no_show: noShow))
            .execute()
    }

    /// A late cancellation, with an optional note that only Tara reads.
    static func markLateCancel(registration: UUID, note: String?) async throws {
        struct P: Encodable {
            let p_registration: UUID
            let p_note: String?
            enum CodingKeys: String, CodingKey { case p_registration, p_note }
            // An explicit null, never an omitted key: PostgREST picks the
            // function by argument names (AdminRepository.AssignCourtParams).
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_registration, forKey: .p_registration)
                if let n = p_note { try c.encode(n, forKey: .p_note) } else { try c.encodeNil(forKey: .p_note) }
            }
        }
        let trimmed = note?.trimmingCharacters(in: .whitespacesAndNewlines)
        try await supabase
            .rpc("pro_mark_late_cancel",
                 params: P(p_registration: registration, p_note: (trimmed?.isEmpty ?? true) ? nil : trimmed))
            .execute()
    }
}
