//
//  ChargeSummaryTests.swift
//  FXETennisTests
//
//  What Tara reads after Charge clinic (decision 0016: she marked the old
//  "Charged 6. Already charged 0. No card 1." as Change). Expected strings
//  written from the rule: plain sentences, singular and plural right, and a
//  zero count left out.
//

import XCTest
@testable import FXETennis

final class ChargeSummaryTests: XCTestCase {
    func testTheCommonCase() {
        XCTAssertEqual(ChargeSummary.text(charged: 6, already: 0, noCard: 1),
                       "Charged 6 cards. 1 player has no card on file.")
    }
    func testSingularsAndZeroes() {
        XCTAssertEqual(ChargeSummary.text(charged: 1, already: 1, noCard: 0),
                       "Charged 1 card. 1 was already charged.")
        XCTAssertEqual(ChargeSummary.text(charged: 0, already: 2, noCard: 3),
                       "Charged 0 cards. 2 were already charged. 3 players have no card on file.")
    }
}
