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

/// Tara, 2026-11-08: "completed" next to clinics that have been completed,
/// and that clinic's action cleared. Expected values from her sentence.
final class ClinicCompletedTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_792_000_000)
    func hours(_ h: Double) -> Date { now.addingTimeInterval(-h * 3600) }

    func testEndedAMinuteAgoIsCompleted() {
        XCTAssertTrue(ClinicCompleted.isCompleted(endsAt: now.addingTimeInterval(-60), canceled: false, now: now))
    }
    func testStillRunningIsNotCompleted() {
        XCTAssertFalse(ClinicCompleted.isCompleted(endsAt: hours(-0.5), canceled: false, now: now))
    }
    func testCanceledIsNeverCompleted() {
        XCTAssertFalse(ClinicCompleted.isCompleted(endsAt: hours(3), canceled: true, now: now))
    }
}
