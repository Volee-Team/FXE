//
//  ReloadThrottleTests.swift
//  FXETennisTests
//
//  The rule (MVP audit item 8): coming back to the app reloads a screen,
//  unless it loaded less than 30 seconds ago. Times are fixed so the test
//  never depends on when it runs.
//

import XCTest
@testable import FXETennis

final class ReloadThrottleTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_800_000_000)

    func testTheFirstReturnReloads() {
        var throttle = ReloadThrottle()
        XCTAssertTrue(throttle.shouldReload(at: t0))
    }

    func testAReturnSoonAfterALoadDoesNot() {
        var throttle = ReloadThrottle()
        throttle.recordLoad(at: t0)
        XCTAssertFalse(throttle.shouldReload(at: t0.addingTimeInterval(10)))
        XCTAssertFalse(throttle.shouldReload(at: t0.addingTimeInterval(29.9)))
    }

    func testThirtySecondsLaterItDoes() {
        var throttle = ReloadThrottle()
        throttle.recordLoad(at: t0)
        XCTAssertTrue(throttle.shouldReload(at: t0.addingTimeInterval(30)))
    }

    func testAReloadCountsAsALoad() {
        var throttle = ReloadThrottle()
        XCTAssertTrue(throttle.shouldReload(at: t0))
        XCTAssertFalse(throttle.shouldReload(at: t0.addingTimeInterval(5)),
                       "Flicking between apps must not refetch every time")
        XCTAssertTrue(throttle.shouldReload(at: t0.addingTimeInterval(35)))
    }

    func testAClockSetBackStillReloads() {
        // The last load looks an hour in the future; waiting for the clock to
        // catch up would mean no reload for an hour.
        var throttle = ReloadThrottle()
        throttle.recordLoad(at: t0)
        XCTAssertTrue(throttle.shouldReload(at: t0.addingTimeInterval(-3600)))
    }

    func testTheIntervalIsThirtySecondsByDefault() {
        XCTAssertEqual(ReloadThrottle().interval, 30)
    }
}
