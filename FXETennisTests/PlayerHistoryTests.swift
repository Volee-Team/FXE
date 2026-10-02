//
//  PlayerHistoryTests.swift
//  FXETennisTests
//
//  The history line under a name in the Player Pool (decision 0027 §1).
//  Expected strings written from the rule, by hand: "N played" always, then
//  only the parts that are not zero, singular and plural right, and "New"
//  when there is no history at all. The web admin's historyLine() says the
//  same words (web/tests/tools.spec.mjs reads them off the page). The numbers
//  themselves are the database's, pinned by tests/sql/player_history.sql.
//

import XCTest
@testable import FXETennis

final class PlayerHistoryTests: XCTestCase {
    private func history(_ played: Int, _ noShows: Int, _ lateCancels: Int, last: Date? = nil) -> PlayerHistory {
        PlayerHistory(playerId: UUID(), played: played, noShows: noShows, lateCancels: lateCancels, lastPlayedAt: last)
    }

    func testTheLineFromTheRule() {
        XCTAssertEqual(history(0, 0, 0).line, "New")
        XCTAssertEqual(history(12, 1, 2).line, "12 played, 1 no-show, 2 late cancels")
        XCTAssertEqual(history(12, 0, 0).line, "12 played")
        XCTAssertEqual(history(1, 0, 1).line, "1 played, 1 late cancel")
        XCTAssertEqual(history(0, 2, 0).line, "0 played, 2 no-shows")
        XCTAssertEqual(history(3, 2, 1).line, "3 played, 2 no-shows, 1 late cancel")
    }

    func testTheRPCRowDecodesAndTheLastDayIsNewYorks() throws {
        // A row as PostgREST sends admin_player_history's answer.
        let json = """
        {"player_id":"c0000000-0000-0000-0000-0000000000f2","played":2,"no_shows":1,"late_cancels":2,
         "last_played_at":"2026-09-14T02:30:00Z"}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(PlayerHistory.self, from: Data(json.utf8))
        XCTAssertEqual(row.playerId, UUID(uuidString: "c0000000-0000-0000-0000-0000000000f2"))
        XCTAssertEqual(row.line, "2 played, 1 no-show, 2 late cancels")
        // 02:30 UTC on the 14th is 22:30 on the 13th in New York (EDT): the
        // club's calendar, not the phone's or UTC's.
        let us = Locale(identifier: "en_US")
        XCTAssertEqual(row.lastPlayedLine(locale: us), "Last played Sep 13, 2026")
        XCTAssertNil(history(0, 0, 0).lastPlayedLine(locale: us))
    }
}
