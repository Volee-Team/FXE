//
//  PlayerHistory.swift
//  FXETennis
//
//  A player's history at a glance, beside the name in the Player Pool and on
//  the player's page (decision 0027 §1), so choosing who to invite takes one
//  look. Tara decides; this only shows her the record.
//
//  Every number is the database's (`admin_player_history`, 20260928800001,
//  admin only): played is You're In!, not a no-show, in a clinic that ended
//  and was not canceled; no-shows are the same rows she marked; late cancels
//  are canceled inside the cutoff in a clinic that was not canceled. This file
//  only words them, the same way the web admin's historyLine() does:
//
//    "12 played · 1 no-show · 2 late cancels"
//
//  After "played", only the parts that are not zero; "New" when there is no
//  history at all. Chrome, listed in docs/copy-review.md.
//

import Foundation

struct PlayerHistory: Decodable, Sendable, Equatable {
    let playerId: UUID
    let played: Int
    let noShows: Int
    let lateCancels: Int
    /// The start of the latest clinic played, or nil.
    let lastPlayedAt: Date?

    enum CodingKeys: String, CodingKey {
        case played
        case playerId = "player_id"
        case noShows = "no_shows"
        case lateCancels = "late_cancels"
        case lastPlayedAt = "last_played_at"
    }

    /// "12 played, 1 no-show, 2 late cancels", or "New".
    var line: String {
        if played == 0 && noShows == 0 && lateCancels == 0 { return "New" }
        var parts = ["\(played) played"]
        if noShows > 0 { parts.append(noShows == 1 ? "1 no-show" : "\(noShows) no-shows") }
        if lateCancels > 0 { parts.append(lateCancels == 1 ? "1 late cancel" : "\(lateCancels) late cancels") }
        return parts.joined(separator: ", ")
    }

    /// "Last played Sep 13, 2026", on the club's New York calendar; nil before
    /// the first clinic played.
    func lastPlayedLine(locale: Locale = .current,
                        timeZone: TimeZone = TimeZone(identifier: "America/New_York") ?? .current) -> String? {
        guard let lastPlayedAt else { return nil }
        var style = Date.FormatStyle(date: .abbreviated, time: .omitted, locale: locale)
        style.timeZone = timeZone
        return "Last played \(lastPlayedAt.formatted(style))"
    }
}
