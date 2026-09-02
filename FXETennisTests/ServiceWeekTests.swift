//
//  ServiceWeekTests.swift
//  FXETennisTests
//
//  The client-side service week must agree with `service_week_start` in the
//  database (Sunday, America/New_York). These pin the edges: a Saturday night
//  in New York is still that week; the same instant is already Sunday in UTC.
//

import XCTest
@testable import FXETennis

final class ServiceWeekTests: XCTestCase {
    private let ny = TimeZone(identifier: "America/New_York")!

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12, tz: TimeZone? = nil) -> Date {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = tz ?? ny
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testSundayIsItsOwnWeekStart() {
        // 2026-09-06 is a Sunday.
        XCTAssertEqual(ServiceWeek.start(of: date(2026, 9, 6)), date(2026, 9, 6, 0))
    }

    func testSaturdayBelongsToTheWeekThatStartedSixDaysEarlier() {
        // 2026-09-12 is a Saturday; its week began Sunday 09-06.
        XCTAssertEqual(ServiceWeek.start(of: date(2026, 9, 12, 23)), date(2026, 9, 6, 0))
    }

    func testLateSaturdayNewYorkIsNotNextWeekJustBecauseUTCSaysSunday() {
        // 23:30 Saturday in New York is 03:30 Sunday UTC. The database uses
        // New York, so the client must too, or the two disagree once a week.
        let lateSaturday = date(2026, 9, 12, 23)
        XCTAssertEqual(ServiceWeek.start(of: lateSaturday), date(2026, 9, 6, 0))
        XCTAssertNotEqual(ServiceWeek.start(of: lateSaturday), date(2026, 9, 13, 0))
    }

    func testLabelsReadThisWeekNextWeekThenDated() {
        let now = date(2026, 9, 8) // a Tuesday
        XCTAssertEqual(ServiceWeek.label(forWeekStarting: date(2026, 9, 6, 0), now: now), "This week")
        XCTAssertEqual(ServiceWeek.label(forWeekStarting: date(2026, 9, 13, 0), now: now), "Next week")
        XCTAssertEqual(ServiceWeek.label(forWeekStarting: date(2026, 9, 20, 0), now: now), "Week of Sep 20")
    }

    func testGroupingKeepsWeeksAscendingAndInputOrderWithinAWeek() {
        struct Item: Equatable { let name: String; let at: Date }
        let items = [
            Item(name: "tue", at: date(2026, 9, 8)),
            Item(name: "thu", at: date(2026, 9, 10)),
            Item(name: "next-mon", at: date(2026, 9, 14)),
            Item(name: "sat", at: date(2026, 9, 12, 23)),
        ]
        let groups = ServiceWeek.grouped(items, startsAt: \.at)
        XCTAssertEqual(groups.map(\.start), [date(2026, 9, 6, 0), date(2026, 9, 13, 0)])
        XCTAssertEqual(groups[0].items.map(\.name), ["tue", "thu", "sat"])
        XCTAssertEqual(groups[1].items.map(\.name), ["next-mon"])
    }
}
