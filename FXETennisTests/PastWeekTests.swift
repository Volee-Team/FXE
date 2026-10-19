import XCTest
@testable import FXETennis

/// Tara's Past list holds the last 7 days only (2026-10-19). Expected
/// values written from her sentence, not from the function.
final class PastWeekTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    func hours(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

    func testEndedAnHourAgoIsShown() { XCTAssertTrue(PastWeek.contains(endsAt: hours(1), now: now)) }
    func testEndedSixDaysAgoIsShown() { XCTAssertTrue(PastWeek.contains(endsAt: hours(6 * 24), now: now)) }
    func testEndedEightDaysAgoIsHidden() { XCTAssertFalse(PastWeek.contains(endsAt: hours(8 * 24), now: now)) }
    func testNotYetEndedIsNotPast() { XCTAssertFalse(PastWeek.contains(endsAt: hours(-1), now: now)) }
}
