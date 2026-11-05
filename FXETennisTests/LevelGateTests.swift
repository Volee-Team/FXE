//
//  LevelGateTests.swift
//  Decision 0048: what the clinic page offers a player at a clinic's level.
//  Expected values written from Tara's rule, not read off the code.
//

import XCTest
@testable import FXETennis

final class LevelGateTests: XCTestCase {
    private let player = UUID()
    private func row(_ level: Double, _ status: String) -> LevelApproval {
        LevelApproval(playerId: player, level: level, status: status)
    }

    func testTwoFiveMustAskForThreeOh() {
        XCTAssertEqual(LevelGate.state(rating: 2.5, minRating: 3.0, approvals: []), .mustAsk)
    }

    func testThreeFiveMustAskForFourOh() {
        XCTAssertEqual(LevelGate.state(rating: 3.5, minRating: 4.0, approvals: []), .mustAsk)
    }

    func testAtTheLevelIsOpen() {
        XCTAssertEqual(LevelGate.state(rating: 3.0, minRating: 3.0, approvals: []), .open)
    }

    func testNoLevelOrNoRatingIsOpen() {
        XCTAssertEqual(LevelGate.state(rating: 2.5, minRating: nil, approvals: []), .open)
        XCTAssertEqual(LevelGate.state(rating: nil, minRating: 3.0, approvals: []), .open)
    }

    func testAskedIsAsked() {
        XCTAssertEqual(LevelGate.state(rating: 2.5, minRating: 3.0, approvals: [row(3.0, "requested")]), .asked)
    }

    func testApprovedOnceIsOpenForGood() {
        XCTAssertEqual(LevelGate.state(rating: 2.5, minRating: 3.0, approvals: [row(3.0, "approved")]), .open)
    }

    func testApprovalCoversLowerNotHigher() {
        XCTAssertEqual(LevelGate.state(rating: 2.5, minRating: 3.5, approvals: [row(4.0, "approved")]), .open)
        XCTAssertEqual(LevelGate.state(rating: 2.5, minRating: 3.5, approvals: [row(3.0, "approved")]), .mustAsk)
    }

    func testTarasWordsVerbatim() {
        let label = LevelGate.label(level: 3.0, gender: "female")
        XCTAssertEqual(label, "Ladies 3.0+")
        XCTAssertEqual(LevelGate.prompt(rating: 2.5, label: label),
                       "You're currently rated 2.5. You can request approval from Tara to attend Ladies 3.0+ clinics. Once approved, you can sign up without requesting again.")
        XCTAssertEqual(LevelGate.buttonTitle(label: label), "Request Approval for Ladies 3.0+")
        XCTAssertEqual(LevelGate.approvedLine(label: LevelGate.label(level: 3.0, gender: "male")),
                       "Approved to attend: Men's 3.0+")
        XCTAssertEqual(LevelGate.label(level: 4.0, gender: nil), "4.0+")
    }
}
