//
//  CardSavePollTests.swift
//  FXETennisTests
//
//  After Stripe's sheet says a card is saved, the app waits for the webhook's
//  summary (MVP audit 2026-09-27, item 4). The rule, written out here and not
//  read back from CardSavePoll: ask every 2 seconds, about 30 seconds in all,
//  stop the moment the card is there, treat a failed read (bad signal) as one
//  missed tick, and stop at once when the wait is cancelled. The clock is a
//  fake, so these run instantly and never depend on the network.
//

import XCTest
@testable import FXETennis

final class CardSavePollTests: XCTestCase {

    /// Counts what the wait did, instead of sleeping for real.
    private final class Recorder {
        var slept: [Duration] = []
        var reads = 0
    }

    func testStopsTheMomentTheCardArrives() async {
        let r = Recorder()
        let arrived = await CardSavePoll.waitForCard(
            sleep: { r.slept.append($0) },
            hasCard: { r.reads += 1; return r.reads == 3 })
        XCTAssertTrue(arrived)
        XCTAssertEqual(r.reads, 3, "no read after the card is there")
        XCTAssertEqual(r.slept, [.seconds(2), .seconds(2), .seconds(2)])
    }

    func testGivesUpAfterAboutThirtySeconds() async {
        let r = Recorder()
        let arrived = await CardSavePoll.waitForCard(
            sleep: { r.slept.append($0) },
            hasCard: { r.reads += 1; return false })
        XCTAssertFalse(arrived)
        XCTAssertEqual(r.reads, 15)
        XCTAssertEqual(r.slept.reduce(Duration.zero, +), .seconds(30))
    }

    func testAFailedReadIsOneMissedTickNotTheEnd() async {
        struct NoSignal: Error {}
        let r = Recorder()
        let arrived = await CardSavePoll.waitForCard(
            sleep: { r.slept.append($0) },
            hasCard: {
                r.reads += 1
                if r.reads < 5 { throw NoSignal() }
                return true
            })
        XCTAssertTrue(arrived)
        XCTAssertEqual(r.reads, 5)
    }

    func testACancelledWaitStopsWithoutAnotherRead() async {
        let r = Recorder()
        let arrived = await CardSavePoll.waitForCard(
            sleep: { d in
                r.slept.append(d)
                if r.slept.count == 2 { throw CancellationError() }
            },
            hasCard: { r.reads += 1; return false })
        XCTAssertFalse(arrived)
        XCTAssertEqual(r.reads, 1, "the read after a cancelled sleep never happens")
    }
}
