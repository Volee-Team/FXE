//
//  OpenForRegistrationTests.swift
//  FXETennisTests
//
//  Home lists what is "open for registration" for THIS player (Final Updates,
//  2026-09-26). Expected values from the rule, not the code: members from
//  their opening moment, everyone else from the public one, until the close,
//  never once started or canceled. Times are fixed so the test never depends
//  on the day it runs.
//

import XCTest
@testable import FXETennis

final class OpenForRegistrationTests: XCTestCase {

    // Week of Sunday 2026-10-04: members Thu 10-01 08:00 EDT, public Fri 10-02 08:00 EDT.
    private let memberOpens = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!
    private let publicOpens = ISO8601DateFormatter().date(from: "2026-10-02T12:00:00Z")!
    // A Tuesday 18:00 EDT clinic, closing 3 hours before.
    private let starts = ISO8601DateFormatter().date(from: "2026-10-06T22:00:00Z")!
    private var closes: Date { starts.addingTimeInterval(-3 * 3600) }

    private func clinic(status: String = "published", closesAt: Date?? = .none) -> ClinicPublic {
        ClinicPublic(id: UUID(), name: "Tuesday Ladies 3.0+", audience: "ladies", category: nil,
                     description: nil, startsAt: starts, endsAt: starts.addingTimeInterval(3600),
                     memberOpensAt: memberOpens, publicOpensAt: publicOpens,
                     closesAt: closesAt ?? closes, status: status, canceledAt: nil,
                     memberPriceCents: 1800, nonmemberPriceCents: 2300, durationMinutes: 60)
    }

    func testBeforeTheMemberOpeningNobodySeesIt() {
        let t = memberOpens.addingTimeInterval(-60)
        XCTAssertFalse(clinic().isOpenForRegistration(isMember: true, now: t))
        XCTAssertFalse(clinic().isOpenForRegistration(isMember: false, now: t))
    }

    func testMemberHeadStartIsTheMembersOnly() {
        let t = memberOpens.addingTimeInterval(60)          // Thursday 08:01
        XCTAssertTrue(clinic().isOpenForRegistration(isMember: true, now: t))
        XCTAssertFalse(clinic().isOpenForRegistration(isMember: false, now: t))
    }

    func testFromThePublicOpeningEveryoneSeesIt() {
        let t = publicOpens.addingTimeInterval(60)          // Friday 08:01
        XCTAssertTrue(clinic().isOpenForRegistration(isMember: true, now: t))
        XCTAssertTrue(clinic().isOpenForRegistration(isMember: false, now: t))
    }

    func testTheCloseEndsIt() {
        XCTAssertTrue(clinic().isOpenForRegistration(isMember: true, now: closes.addingTimeInterval(-1)))
        XCTAssertFalse(clinic().isOpenForRegistration(isMember: true, now: closes))
    }

    func testNoCloseStillEndsAtTheStart() {
        let open = clinic(closesAt: .some(nil))
        XCTAssertTrue(open.isOpenForRegistration(isMember: true, now: starts.addingTimeInterval(-1)))
        XCTAssertFalse(open.isOpenForRegistration(isMember: true, now: starts))
    }

    func testCanceledIsNeverOpen() {
        let t = publicOpens.addingTimeInterval(60)
        XCTAssertFalse(clinic(status: "canceled").isOpenForRegistration(isMember: true, now: t))
    }

    func testTheCardLabelShowsOnlyTheLastFourDigits() throws {
        // Final Updates p.2 item 2: "only show the last 4 digits of the card".
        let json = #"{"id":"22222222-2222-2222-2222-222222222222","first_name":"Maria","last_name":"Alvarez","email":"m@x.test","phone":null,"account_type":"adult","role":"member","card_brand":"visa","card_last4":"4242"}"#
        let account = try JSONDecoder().decode(Account.self, from: Data(json.utf8))
        XCTAssertEqual(account.cardLabel, "•••• 4242")
        XCTAssertFalse(account.cardLabel?.lowercased().contains("visa") ?? true)
    }

    // MARK: what the clinic page offers someone not registered (review, 2026-09-27)
    //
    // The rule: before this player's opening, "Registration opens <when>";
    // from it until the close, Register; from the close until the start, the
    // late request to Tara; from the start, nothing. Canceled: nothing.

    func testTheDoorAtTheOpening() {
        XCTAssertEqual(clinic().door(isMember: true, now: memberOpens.addingTimeInterval(-1)), .opens(memberOpens))
        XCTAssertEqual(clinic().door(isMember: true, now: memberOpens), .register)
        XCTAssertEqual(clinic().door(isMember: false, now: memberOpens), .opens(publicOpens))
        XCTAssertEqual(clinic().door(isMember: false, now: publicOpens), .register)
    }

    func testTheDoorAtTheClose() {
        XCTAssertEqual(clinic().door(isMember: true, now: closes.addingTimeInterval(-1)), .register)
        XCTAssertEqual(clinic().door(isMember: true, now: closes), .askTara)
        XCTAssertEqual(clinic().door(isMember: false, now: starts.addingTimeInterval(-1)), .askTara)
    }

    func testTheDoorAtTheStartIsShut() {
        XCTAssertEqual(clinic().door(isMember: true, now: starts), .none)
        XCTAssertEqual(clinic().door(isMember: true, now: starts.addingTimeInterval(1800)), .none)
        // With no close stored, Register still ends at the start.
        XCTAssertEqual(clinic(closesAt: .some(nil)).door(isMember: true, now: starts.addingTimeInterval(-1)), .register)
        XCTAssertEqual(clinic(closesAt: .some(nil)).door(isMember: true, now: starts), .none)
    }

    func testACanceledClinicHasNoDoor() {
        XCTAssertEqual(clinic(status: "canceled").door(isMember: true, now: publicOpens.addingTimeInterval(60)), .none)
    }

    /// Home's list and the page agree: open exactly when the door is Register.
    func testOpenMeansTheRegisterDoor() {
        for t in [memberOpens.addingTimeInterval(-1), memberOpens, publicOpens, closes, starts] {
            XCTAssertEqual(clinic().isOpenForRegistration(isMember: true, now: t),
                           clinic().door(isMember: true, now: t) == .register, "at \(t)")
        }
    }
}
