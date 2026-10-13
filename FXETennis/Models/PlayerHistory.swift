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
//    "12 played, 5 canceled (2 late), 1 no-show"
//
//  Tara's own example (question 105, 2026-10-12: "Yes"): every cancel, late
//  ones in brackets. After "played", only the parts that are not zero; "New"
//  when there is no history at all.
//

import Foundation

struct PlayerHistory: Decodable, Sendable, Equatable {
    let playerId: UUID
    let played: Int
    let noShows: Int
    let lateCancels: Int
    /// The start of the latest clinic played, or nil.
    let lastPlayedAt: Date?
    /// Every cancel, late ones included (20261012000001). Nil from a server
    /// older than that, read as the late cancels alone.
    var canceled: Int? = nil

    enum CodingKeys: String, CodingKey {
        case played, canceled
        case playerId = "player_id"
        case noShows = "no_shows"
        case lateCancels = "late_cancels"
        case lastPlayedAt = "last_played_at"
    }

    /// "12 played, 5 canceled (2 late), 1 no-show", or "New".
    var line: String {
        let cancels = max(canceled ?? lateCancels, lateCancels)
        if played == 0 && noShows == 0 && cancels == 0 { return "New" }
        var parts = ["\(played) played"]
        if cancels > 0 { parts.append(lateCancels > 0 ? "\(cancels) canceled (\(lateCancels) late)" : "\(cancels) canceled") }
        if noShows > 0 { parts.append(noShows == 1 ? "1 no-show" : "\(noShows) no-shows") }
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
