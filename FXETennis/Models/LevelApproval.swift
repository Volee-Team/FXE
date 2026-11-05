//
//  LevelApproval.swift
//  FXETennis
//
//  Decision 0048. A clinic's level is the NTRP number in its name
//  (`clinics.min_rating`). A player rated below it asks Tara once; her
//  approval lasts until she removes it, and their rating never moves.
//  The server decides (`level_approval_required`); this only chooses what the
//  page shows, so a player is offered Tara's request button instead of a
//  Register the server would refuse.
//

import Foundation

/// One row of `level_approvals`, as its player reads it.
struct LevelApproval: Codable, Hashable, Sendable {
    let playerId: UUID
    let level: Double
    let status: String

    var isApproved: Bool { status == "approved" }

    enum CodingKeys: String, CodingKey {
        case level, status
        case playerId = "player_id"
    }
}

enum LevelGate {
    /// What the clinic page offers a player at this clinic's level.
    enum State: Equatable {
        /// No level, no rating, rated at or above it, or approved: as before.
        case open
        /// Below the level, not asked yet: Tara's sentence and button.
        case mustAsk
        /// Asked, Tara has not answered.
        case asked
    }

    static func state(rating: Double?, minRating: Double?, approvals: [LevelApproval]) -> State {
        guard let minRating, let rating, rating < minRating else { return .open }
        if approvals.contains(where: { $0.isApproved && $0.level >= minRating }) { return .open }
        if approvals.contains(where: { !$0.isApproved && $0.level == minRating }) { return .asked }
        return .mustAsk
    }

    /// "3.0", the way Tara writes a level.
    static func number(_ level: Double) -> String { String(format: "%.1f", level) }

    /// Tara's two examples were "Ladies 3.0+" and "Men's 3.0+": the player's
    /// own gender picks the word (the server's level_approval_label agrees).
    static func label(level: Double, gender: String?) -> String {
        switch gender {
        case "female": return "Ladies \(number(level))+"
        case "male": return "Men's \(number(level))+"
        default: return "\(number(level))+"
        }
    }

    /// Tara's sentence, verbatim (email of 2026-10-15), with the player's
    /// rating and the clinic's label.
    static func prompt(rating: Double, label: String) -> String {
        "You're currently rated \(number(rating)). You can request approval from Tara to attend \(label) clinics. Once approved, you can sign up without requesting again."
    }

    /// Tara's button, verbatim.
    static func buttonTitle(label: String) -> String { "Request Approval for \(label)" }

    /// Tara's profile line, verbatim.
    static func approvedLine(label: String) -> String { "Approved to attend: \(label)" }
}
