//
//  RegistrationMomentsTests.swift
//  FXETennisTests
//
//  The rule (MVP audit item 8): a screen redraws at the moments a clinic's
//  registration changes on its own, for THIS viewer: members at their
//  Thursday 8:00 opening, everyone else at the Friday 8:00 one; then the
//  close; then the start. Expected dates are the week of Sunday 2026-10-04
//  worked by hand from the window rule (CLAUDE.md): members Thu 10-01 08:00
//  EDT = 12:00Z, public Fri 10-02 08:00 EDT = 12:00Z; a Tuesday 18:00 EDT
//  clinic starts 22:00Z and closes 3 hours before, 19:00Z.
//

import XCTest
@testable import FXETennis

final class RegistrationMomentsTests: XCTestCase {
    private let iso = ISO8601DateFormatter()
    private var memberOpens: Date { iso.date(from: "2026-10-01T12:00:00Z")! }
    private var publicOpens: Date { iso.date(from: "2026-10-02T12:00:00Z")! }
    private var closes: Date { iso.date(from: "2026-10-06T19:00:00Z")! }
    private var starts: Date { iso.date(from: "2026-10-06T22:00:00Z")! }

    private func clinic(status: String = "published") -> ClinicPublic {
        ClinicPublic(id: UUID(), name: "Tuesday Ladies 3.0+", audience: "ladies", category: nil,
                     description: nil, startsAt: starts, endsAt: starts.addingTimeInterval(3600),
                     memberOpensAt: memberOpens, publicOpensAt: publicOpens,
                     closesAt: closes, status: status, canceledAt: nil,
                     memberPriceCents: 1800, nonmemberPriceCents: 2300, durationMinutes: 60)
    }

    func testAMemberWaitingOnWednesdayRedrawsAtThursdayEight() {
        let wednesday = iso.date(from: "2026-09-30T16:00:00Z")!
        XCTAssertEqual(clinic().upcomingMoments(isMember: true, after: wednesday),
                       [memberOpens, closes, starts])
    }

    func testANonMemberRedrawsAtFridayEightNotThursday() {
        let wednesday = iso.date(from: "2026-09-30T16:00:00Z")!
        XCTAssertEqual(clinic().upcomingMoments(isMember: false, after: wednesday),
                       [publicOpens, closes, starts])
    }

    func testOnceOpenOnlyTheCloseAndStartRemain() {
        let fridayNoon = iso.date(from: "2026-10-02T16:00:00Z")!
        XCTAssertEqual(clinic().upcomingMoments(isMember: true, after: fridayNoon), [closes, starts])
        XCTAssertEqual(clinic().upcomingMoments(isMember: false, after: fridayNoon), [closes, starts])
    }

    func testTheOpeningMomentItselfHasPassed() {
        // At exactly 8:00 the opening is now, not upcoming: the screen that
        // redrew at it already shows Register.
        XCTAssertEqual(clinic().upcomingMoments(isMember: true, after: memberOpens), [closes, starts])
    }

    func testAfterTheStartNothingIsLeft() {
        XCTAssertEqual(clinic().upcomingMoments(isMember: true, after: starts), [])
    }

    func testACanceledClinicNeverRedraws() {
        let wednesday = iso.date(from: "2026-09-30T16:00:00Z")!
        XCTAssertEqual(clinic(status: "canceled").upcomingMoments(isMember: true, after: wednesday), [])
    }

    func testEachMomentGetsASecondRedrawOneSecondLater() {
        XCTAssertEqual(RedrawSchedule.at([memberOpens, closes]),
                       [memberOpens, memberOpens.addingTimeInterval(1), closes, closes.addingTimeInterval(1)])
        XCTAssertEqual(RedrawSchedule.at([]), [])
    }

    func testTheSameMomentFromTwoClinicsIsOneRedraw() {
        // Home redraws for every clinic in a service week, and they share an opening.
        XCTAssertEqual(RedrawSchedule.at([memberOpens, memberOpens]),
                       [memberOpens, memberOpens.addingTimeInterval(1)])
    }
}
