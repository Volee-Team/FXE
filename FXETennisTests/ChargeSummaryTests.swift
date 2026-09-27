//
//  ChargeSummaryTests.swift
//  FXETennisTests
//
//  What Tara reads after Charge clinic (decision 0016: she marked the old
//  "Charged 6. Already charged 0. No card 1." as Change). Expected strings
//  written from the rule: plain sentences, singular and plural right, and a
//  zero count left out.
//
//  2026-09-27: "Charged" counts what Stripe ACCEPTED for this clinic, not how
//  many rows were queued (the audit found "Charged 6" printed when all six
//  declined), and each declined card is named with its reason. The tally is
//  asserted here from Stripe's answers worked out by hand. Two test functions
//  on purpose: the launch checklist pins the unit-test count.
//

import XCTest
@testable import FXETennis

final class ChargeSummaryTests: XCTestCase {
    func testTheCommonCase() {
        XCTAssertEqual(ChargeSummary.text(paid: 6, already: 0, noCard: 1),
                       "Charged 6 cards. 1 player has no card on file.")
        XCTAssertEqual(ChargeSummary.text(paid: 5, declined: [.init(name: "Maria Alvarez", reason: "Insufficient funds (NSF)")],
                                          already: 0, noCard: 1),
                       "Charged 5 cards. Maria Alvarez's card was declined: Insufficient funds (NSF). 1 player has no card on file.")

        // The tally, by hand. This tap queued 4 rows. Stripe answered for 3 of
        // them (Ken went through, Maria's card expired, Rob's is processing)
        // and for one row of ANOTHER clinic that stripe-charge also took; the
        // 4th of ours it has not answered yet. So: charged 1, declined Maria,
        // still processing 1 (Rob) + 1 (unanswered) = 2; the other clinic's
        // row is not this clinic's news.
        let ken = UUID(), maria = UUID(), rob = UUID(), elsewhere = UUID()
        let outcome = ChargeOutcome.tally(
            statuses: [ken: "succeeded", maria: "failed", rob: "processing", elsewhere: "succeeded"],
            fees: [.init(id: ken, name: "Ken Whitfield", reason: nil),
                   .init(id: maria, name: "Maria Alvarez", reason: "Card expired"),
                   .init(id: rob, name: "Rob Delgado", reason: nil)],
            queued: 4, already: 0, noCard: 1)
        XCTAssertEqual(ChargeSummary.text(outcome),
                       "Charged 1 card. Maria Alvarez's card was declined: Card expired. 2 are still processing. 1 player has no card on file.")
    }

    func testSingularsAndZeroes() {
        XCTAssertEqual(ChargeSummary.text(paid: 1, already: 1, noCard: 0),
                       "Charged 1 card. 1 was already charged.")
        XCTAssertEqual(ChargeSummary.text(paid: 0, already: 2, noCard: 3),
                       "Charged 0 cards. 2 were already charged. 3 players have no card on file.")
        XCTAssertEqual(ChargeSummary.text(paid: 0, processing: 1, already: 0, noCard: 0),
                       "Charged 0 cards. 1 is still processing.")
        // No reason from Stripe: the bare sentence, never "declined: ."
        XCTAssertEqual(ChargeSummary.text(paid: 0, declined: [.init(name: "Ken Whitfield", reason: nil)], already: 0, noCard: 0),
                       "Charged 0 cards. Ken Whitfield's card was declined.")

        // The audit's case: six queued, all six declined. Not "Charged 6".
        let six = (0..<6).map { _ in UUID() }
        let allDeclined = ChargeOutcome.tally(
            statuses: Dictionary(uniqueKeysWithValues: six.map { ($0, "failed") }),
            fees: six.map { .init(id: $0, name: "P", reason: nil) },
            queued: 6, already: 0, noCard: 0)
        XCTAssertEqual(allDeclined.paid, 0)
        XCTAssertEqual(allDeclined.declined.count, 6)
        XCTAssertEqual(allDeclined.processing, 0)
    }
}
