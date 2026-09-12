import XCTest
@testable import FXETennis

/// The 4-hour line (decision 0010), checked at the edges.
final class CancelPolicyTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testFiveHoursOutIsFree() {
        XCTAssertFalse(CancelPolicy.isInsideCutoff(startsAt: now.addingTimeInterval(5 * 3600), cutoffHours: 4, now: now))
    }

    func testExactlyFourHoursOutIsStillFree() {
        XCTAssertFalse(CancelPolicy.isInsideCutoff(startsAt: now.addingTimeInterval(4 * 3600), cutoffHours: 4, now: now))
    }

    func testJustInsideFourHoursNeedsANote() {
        XCTAssertTrue(CancelPolicy.isInsideCutoff(startsAt: now.addingTimeInterval(4 * 3600 - 1), cutoffHours: 4, now: now))
    }

    func testAClinicThatAlreadyStartedIsInside() {
        XCTAssertTrue(CancelPolicy.isInsideCutoff(startsAt: now.addingTimeInterval(-600), cutoffHours: 4, now: now))
    }

    func testTheNumberComesFromTheSetting() {
        // 24 was our default before Tara said 4; the app must follow the setting, not a constant.
        XCTAssertTrue(CancelPolicy.isInsideCutoff(startsAt: now.addingTimeInterval(10 * 3600), cutoffHours: 24, now: now))
        XCTAssertFalse(CancelPolicy.isInsideCutoff(startsAt: now.addingTimeInterval(10 * 3600), cutoffHours: 4, now: now))
    }
}
