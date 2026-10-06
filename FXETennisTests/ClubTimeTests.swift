//
//  ClubTimeTests.swift
//  FXETennisTests
//
//  Tara, 2026-10-04: clinic times are always Charlotte time, wherever the
//  phone is. From the rule: Tuesday 6 October 2026, 13:00 UTC is 9:00 AM in
//  Charlotte (EDT, UTC-4) and 8:00 AM in Wisconsin (CDT, UTC-5).
//
//  What this can check in a running process is Calendar and a DateFormatter
//  made after the change. `.formatted()` reads the zone through Foundation's
//  auto-updating time zone, which does not reliably follow a default changed
//  mid-process (the first draft of this test asserted on it and failed both
//  ways). In the app ClubTime.apply() runs in init, before anything formats;
//  that path is verified on a simulator launched in Central time.
//

import XCTest
@testable import FXETennis

final class ClubTimeTests: XCTestCase {
    private let nineInCharlotte = Date(timeIntervalSince1970: 1_791_291_600) // 2026-10-06T13:00:00Z
    private var saved: TimeZone!

    override func setUp() {
        super.setUp()
        saved = NSTimeZone.default
    }

    override func tearDown() {
        NSTimeZone.default = saved
        super.tearDown()
    }

    private func shortTime(_ date: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "h:mm a"
        return f.string(from: date)
    }

    /// A phone in Wisconsin, before and after the app applies club time.
    func testAPhoneInCentralTimeReadsCharlotteTime() {
        NSTimeZone.default = TimeZone(identifier: "America/Chicago")!
        XCTAssertEqual(Calendar.current.component(.hour, from: nineInCharlotte), 8, "the fixture: Central reads an hour early")
        XCTAssertEqual(shortTime(nineInCharlotte), "8:00 AM", "the fixture, by formatter")
        ClubTime.apply()
        XCTAssertEqual(Calendar.current.component(.hour, from: nineInCharlotte), 9)
        XCTAssertEqual(shortTime(nineInCharlotte), "9:00 AM")
    }

    /// The zone is Charlotte's, not a fixed offset: in January (EST) the
    /// same wall clock is 14:00 UTC.
    func testWinterIsStillNineInCharlotte() {
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        ClubTime.apply()
        let nineInJanuary = Date(timeIntervalSince1970: 1_799_330_400) // 2027-01-07T14:00:00Z
        XCTAssertEqual(shortTime(nineInJanuary), "9:00 AM")
    }
}
