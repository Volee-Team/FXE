//
//  NextClinicTests.swift
//  FXETennisTests
//
//  "When's my next clinic?" The rule, from the question itself: the soonest
//  clinic the player holds a live spot in, not one that has ended, not one
//  Tara canceled, not one they canceled out of. The answer is the name, the
//  day and time in club time, and the locked status words, with nothing
//  about where. Times are fixed so the test never depends on the day it runs.
//

import XCTest
@testable import FXETennis

final class NextClinicTests: XCTestCase {

    // Sunday 2026-10-04 16:49 EDT is 20:49 UTC.
    private let sundayStart = ISO8601DateFormatter().date(from: "2026-10-04T20:49:00Z")!
    private let now = ISO8601DateFormatter().date(from: "2026-10-01T12:00:00Z")!

    private func clinic(_ name: String, startsAt: Date, status: String = "published") -> ClinicPublic {
        ClinicPublic(id: UUID(), name: name, audience: "coed", category: nil, description: nil,
                     startsAt: startsAt, endsAt: startsAt.addingTimeInterval(3600),
                     memberOpensAt: nil, publicOpensAt: nil, closesAt: nil, status: status,
                     canceledAt: status == "canceled" ? now : nil,
                     memberPriceCents: 1800, nonmemberPriceCents: 2300, durationMinutes: 60)
    }

    private func spot(_ clinic: ClinicPublic, _ status: RegistrationStatus) -> MyRegistration {
        MyRegistration(id: UUID(), clinicId: clinic.id, playerId: UUID(), status: status, paid: false,
                       registeredAt: nil, invitedAt: nil, respondedAt: nil, canceledAt: nil,
                       lateCancel: nil, courtesyUsed: nil)
    }

    func testTheSoonestHeldClinicIsTheAnswer() {
        let sunday = clinic("Saturday Members Only", startsAt: sundayStart)
        let later = clinic("Evening Coed", startsAt: sundayStart.addingTimeInterval(30 * 86_400))
        let notMine = clinic("Tuesday Ladies 3.0+", startsAt: now.addingTimeInterval(3600))
        let next = NextClinic.pick(clinics: [later, notMine, sunday],
                                   registrations: [spot(later, .in_), spot(sunday, .pool)], now: now)
        XCTAssertEqual(next?.clinic.name, "Saturday Members Only")
        XCTAssertEqual(next?.status, .pool)
    }

    func testEndedCanceledAndCanceledOutOfAreSkipped() {
        let ended = clinic("Yesterday", startsAt: now.addingTimeInterval(-86_400))
        let taraCanceled = clinic("Rained out", startsAt: now.addingTimeInterval(3600), status: "canceled")
        let leftIt = clinic("Left it", startsAt: now.addingTimeInterval(7200))
        let real = clinic("Evening Coed", startsAt: now.addingTimeInterval(86_400))
        let next = NextClinic.pick(clinics: [ended, taraCanceled, leftIt, real],
                                   registrations: [spot(ended, .in_), spot(taraCanceled, .in_),
                                                   spot(leftIt, .canceled), spot(real, .responseNeeded)],
                                   now: now)
        XCTAssertEqual(next?.clinic.name, "Evening Coed")
        XCTAssertEqual(next?.status, .responseNeeded)
    }

    func testNothingHeldIsNoAnswer() {
        XCTAssertNil(NextClinic.pick(clinics: [clinic("Open", startsAt: sundayStart)], registrations: [], now: now))
    }

    func testTheLineIsTheNameTheClubTimeAndTheStatusWords() {
        let sunday = clinic("Saturday Members Only", startsAt: sundayStart)
        XCTAssertEqual(NextClinic.line(for: sunday, status: .in_),
                       "Saturday Members Only, Sunday, Oct 4 at 4:49 PM. You're In!")
        XCTAssertEqual(NextClinic.line(for: sunday, status: .responseNeeded),
                       "Saturday Members Only, Sunday, Oct 4 at 4:49 PM. Response Needed")
    }
}
