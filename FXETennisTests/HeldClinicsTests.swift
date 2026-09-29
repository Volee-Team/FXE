//
//  HeldClinicsTests.swift
//  FXETennisTests
//
//  The clinic list stops five weeks out, but a clinic the player holds a spot
//  in is theirs and stays on Home, Clinics and My Clinics wherever it falls
//  (2026-09-28: Maria's Evening Coed, six weeks out, was missing from Home).
//  Expected values from that rule: every held clinic appears exactly once,
//  soonest first, and nothing is fetched twice.
//

import XCTest
@testable import FXETennis

final class HeldClinicsTests: XCTestCase {

    private func clinic(_ name: String, daysAhead: Double) -> ClinicPublic {
        let start = ISO8601DateFormatter().date(from: "2026-10-01T22:00:00Z")!
            .addingTimeInterval(daysAhead * 86_400)
        return ClinicPublic(id: UUID(), name: name, audience: "coed", category: nil,
                            description: nil, startsAt: start, endsAt: start.addingTimeInterval(5400),
                            memberOpensAt: nil, publicOpensAt: nil, closesAt: nil,
                            status: "published", canceledAt: nil,
                            memberPriceCents: 2200, nonmemberPriceCents: 2800, durationMinutes: 90)
    }

    func testOnlyHeldClinicsMissingFromTheListAreFetched() {
        let soon = clinic("Tuesday Ladies", daysAhead: 2)
        let farHeld = UUID()
        let held = [soon.id, farHeld, farHeld]           // one spot listed, one beyond, a duplicate id
        XCTAssertEqual(ClinicsViewModel.heldBeyondList([soon], held: held), [farHeld])
    }

    func testNothingIsFetchedWhenEveryHeldClinicIsListed() {
        let a = clinic("A", daysAhead: 1), b = clinic("B", daysAhead: 3)
        XCTAssertEqual(ClinicsViewModel.heldBeyondList([a, b], held: [b.id, a.id]), [])
        XCTAssertEqual(ClinicsViewModel.heldBeyondList([a, b], held: []), [])
    }

    func testTheMergedListIsSoonestFirstWithEachClinicOnce() {
        let week1 = clinic("Week 1", daysAhead: 1)
        let week3 = clinic("Week 3", daysAhead: 15)
        let week6 = clinic("Evening Coed, six weeks out", daysAhead: 40)
        // Out of order on purpose, with a clinic in both lists: a merge that
        // only concatenates reads Week 3, Week 1, six weeks (verified red).
        let merged = ClinicsViewModel.merged([week3, week1], [week6, week1])
        XCTAssertEqual(merged.map(\.name), ["Week 1", "Week 3", "Evening Coed, six weeks out"])
    }
}
