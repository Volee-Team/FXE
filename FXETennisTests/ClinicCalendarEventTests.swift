//
//  ClinicCalendarEventTests.swift
//  FXETennisTests
//
//  "Add to Calendar" (2026-09-28). The rules:
//    * offered to a player holding You're In! for a clinic that has not
//      started, and to nobody else (not the Pool, not Response Needed, not a
//      canceled clinic);
//    * the entry is the clinic's name, its start and end, in America/New_York
//      (the club's zone, so a player travelling still reads the court time);
//    * hard rule 1: a calendar entry is player-facing, so NOTHING goes in its
//      location, URL or notes. Location is one of the nine hidden facts
//      (decision 10), and the description stays in the app.
//

import XCTest
import EventKit
@testable import FXETennis

final class ClinicCalendarEventTests: XCTestCase {
    private let iso = ISO8601DateFormatter()
    private func at(_ s: String) -> Date { iso.date(from: s)! }
    private var starts: Date { at("2026-10-06T22:00:00Z") }   // Tuesday 18:00 EDT
    private var ends: Date { at("2026-10-06T23:30:00Z") }     // 19:30 EDT

    private func clinic(status: String = "published") -> ClinicPublic {
        ClinicPublic(id: UUID(), name: "Tuesday Ladies 3.0+", audience: "ladies", category: "105",
                     description: "A fast-paced doubles format. Courts 1 to 4 behind the clubhouse.",
                     startsAt: starts, endsAt: ends,
                     memberOpensAt: at("2026-10-01T12:00:00Z"), publicOpensAt: at("2026-10-02T12:00:00Z"),
                     closesAt: at("2026-10-06T19:00:00Z"), status: status, canceledAt: nil,
                     memberPriceCents: 2200, nonmemberPriceCents: 2800, durationMinutes: 90)
    }

    // MARK: - who is offered it

    func testYoureInBeforeTheStartIsOffered() {
        XCTAssertTrue(ClinicCalendarEvent.offered(status: .in_, clinic: clinic(), now: at("2026-10-05T12:00:00Z")))
        XCTAssertTrue(ClinicCalendarEvent.offered(status: .in_, clinic: clinic(), now: starts.addingTimeInterval(-1)))
    }

    func testOnlyYoureInIsOffered() {
        let monday = at("2026-10-05T12:00:00Z")
        XCTAssertFalse(ClinicCalendarEvent.offered(status: .pool, clinic: clinic(), now: monday))
        XCTAssertFalse(ClinicCalendarEvent.offered(status: .responseNeeded, clinic: clinic(), now: monday))
        XCTAssertFalse(ClinicCalendarEvent.offered(status: .canceled, clinic: clinic(), now: monday))
        XCTAssertFalse(ClinicCalendarEvent.offered(status: nil, clinic: clinic(), now: monday))
    }

    func testAStartedClinicIsNotOffered() {
        XCTAssertFalse(ClinicCalendarEvent.offered(status: .in_, clinic: clinic(), now: starts))
        XCTAssertFalse(ClinicCalendarEvent.offered(status: .in_, clinic: clinic(), now: ends))
    }

    func testACanceledClinicIsNotOffered() {
        XCTAssertFalse(ClinicCalendarEvent.offered(status: .in_, clinic: clinic(status: "canceled"),
                                                   now: at("2026-10-05T12:00:00Z")))
    }

    // MARK: - what the entry holds

    /// The phone is in Los Angeles for this test: this Mac is in New York,
    /// where an entry left in the phone's own zone would pass by accident
    /// (it did, on the first red run).
    func testTheEntryIsTheNameAndTheTimesInTheClubsZone() throws {
        let home = NSTimeZone.default
        NSTimeZone.default = TimeZone(identifier: "America/Los_Angeles")!
        defer { NSTimeZone.default = home }
        let event = ClinicCalendarEvent.make(for: clinic(), in: EKEventStore())
        XCTAssertEqual(event.title, "Tuesday Ladies 3.0+")
        XCTAssertEqual(event.startDate, starts)
        XCTAssertEqual(event.endDate, ends)
        XCTAssertEqual(event.timeZone?.identifier, "America/New_York")
        XCTAssertFalse(event.isAllDay)
    }

    func testNothingHiddenGoesIntoTheEntry() {
        let event = ClinicCalendarEvent.make(for: clinic(), in: EKEventStore())
        XCTAssertTrue(event.location?.isEmpty ?? true, "location is hidden from players (hard rule 1)")
        XCTAssertNil(event.structuredLocation, "no map pin either")
        XCTAssertNil(event.url)
        XCTAssertTrue(event.notes?.isEmpty ?? true, "the description stays in the app")
    }
}
