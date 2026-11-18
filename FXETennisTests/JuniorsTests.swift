//
//  JuniorsTests.swift
//  Juniors phase 1 (decision 0061): decoding the server's rows exactly as the
//  migration returns them, the approval state a child's page shows, every
//  refusal code reaching its own line, and birthdays that never move a day.
//  Expected values written from the migration and Tara's spec, not read off
//  the code.
//

import XCTest
@testable import FXETennis

final class JuniorsTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    // MARK: - decoding (the shapes in 20261118000001)

    func testMyChildrenRowDecodes() throws {
        let rows = try decode([Child].self, """
        [{"id":"0b5a1f1e-1111-4222-8333-444455556666","first_name":"Sam","last_name":"Lee",
          "date_of_birth":"2017-03-01","age":9,"waiver_status":"needed"}]
        """)
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0].fullName, "Sam Lee")
        XCTAssertEqual(rows[0].dateOfBirth, "2017-03-01", "a date-only value stays the string the server sent")
        XCTAssertEqual(rows[0].age, 9)
        XCTAssertEqual(rows[0].waiverStatus, .needed)
    }

    func testEveryWaiverStatusDecodes() throws {
        for (raw, want) in [("not_available", ChildWaiverStatus.notAvailable), ("needed", .needed), ("signed", .signed)] {
            let row = try decode(Child.self, """
            {"id":"0b5a1f1e-1111-4222-8333-444455556666","first_name":"A","last_name":"B",
             "date_of_birth":"2015-01-01","age":11,"waiver_status":"\(raw)"}
            """)
            XCTAssertEqual(row.waiverStatus, want, raw)
        }
    }

    /// An unknown status must not let a parent think a waiver is signed.
    func testUnknownWaiverStatusIsNotSigned() throws {
        let row = try decode(Child.self, """
        {"id":"0b5a1f1e-1111-4222-8333-444455556666","first_name":"A","last_name":"B",
         "date_of_birth":"2015-01-01","age":null,"waiver_status":"something_new"}
        """)
        XCTAssertNotEqual(row.waiverStatus, .signed)
        XCTAssertNil(row.age)
    }

    func testProgramRowDecodesWithEmptyDescription() throws {
        let rows = try decode([JuniorProgram].self, """
        [{"id":"0b5a1f1e-1111-4222-8333-444455556661","name":"Red Dot","description":"","age_guidance":"Ages 3-6",
          "needs_approval":false,"sort_order":1},
         {"id":"0b5a1f1e-1111-4222-8333-444455556662","name":"Elite","description":"","age_guidance":"",
          "needs_approval":true,"sort_order":5}]
        """)
        XCTAssertEqual(rows.map(\.name), ["Red Dot", "Elite"])
        XCTAssertEqual(rows[0].ageGuidance, "Ages 3-6")
        XCTAssertFalse(rows[0].needsApproval)
        XCTAssertTrue(rows[1].needsApproval)
    }

    func testApprovalRowDecodes() throws {
        let rows = try decode([ProgramApproval].self, """
        [{"player_id":"0b5a1f1e-1111-4222-8333-444455556666","child_first_name":"Sam",
          "program_id":"0b5a1f1e-1111-4222-8333-444455556662","program_name":"Elite","status":"approved",
          "requested_at":"2026-11-18T12:00:00+00:00","decided_at":null}]
        """)
        XCTAssertEqual(rows.first?.status, .approved)
    }

    // MARK: - what a child's page offers for a program

    private let child = UUID()
    private let other = UUID()
    private func program(needsApproval: Bool) -> JuniorProgram {
        JuniorProgram(id: UUID(), name: "Elite", description: "", ageGuidance: "", needsApproval: needsApproval, sortOrder: 5)
    }

    func testNoApprovalNeededOffersNothing() {
        XCTAssertEqual(ProgramApprovalState.state(program: program(needsApproval: false), child: child, approvals: []), .notNeeded)
    }

    func testNeedsApprovalNotAskedOffersRequest() {
        XCTAssertEqual(ProgramApprovalState.state(program: program(needsApproval: true), child: child, approvals: []), .canRequest)
    }

    func testEachStatusShows() {
        let p = program(needsApproval: true)
        for (status, want) in [(ProgramApprovalStatus.requested, ProgramApprovalState.requested),
                               (.approved, .approved), (.declined, .declined)] {
            let rows = [ProgramApproval(playerId: child, programId: p.id, status: status)]
            XCTAssertEqual(ProgramApprovalState.state(program: p, child: child, approvals: rows), want)
        }
    }

    /// A sibling's approval is not this child's (approvals are per child and
    /// per program, spec 01).
    func testASiblingsApprovalDoesNotCount() {
        let p = program(needsApproval: true)
        let rows = [ProgramApproval(playerId: other, programId: p.id, status: .approved)]
        XCTAssertEqual(ProgramApprovalState.state(program: p, child: child, approvals: rows), .canRequest)
    }

    func testAnotherProgramsApprovalDoesNotCount() {
        let p = program(needsApproval: true)
        let rows = [ProgramApproval(playerId: child, programId: UUID(), status: .approved)]
        XCTAssertEqual(ProgramApprovalState.state(program: p, child: child, approvals: rows), .canRequest)
    }

    // MARK: - refusals: every code the juniors RPCs raise reaches its own line

    func testEveryRefusalHasItsOwnLine() {
        let cases: [(String, String)] = [
            ("child_exists", JuniorCopy.childExistsLine),
            ("name_required", JuniorCopy.nameRequiredLine),
            ("invalid_birthday", JuniorCopy.invalidBirthdayLine),
            ("not_your_child", JuniorCopy.notYourChildLine),
            ("child_has_upcoming", JuniorCopy.childHasUpcomingLine),
            ("child_locked", JuniorCopy.childLockedLine),
            ("too_many_children", JuniorCopy.tooManyChildrenLine),
            ("approval_declined", JuniorCopy.approvalDeclinedLine),
            ("approval_not_needed", JuniorCopy.approvalNotNeededLine),
            ("program_not_found", JuniorCopy.programNotFoundLine),
            ("junior_waiver_not_available", JuniorCopy.waiverNotAvailableLine),
        ]
        for (code, line) in cases {
            // PostgREST puts the exception's message in the error's text.
            XCTAssertEqual(JuniorCopy.refusalLine(in: #"PostgrestError(code: "P0001", message: "\#(code)")"#), line, code)
        }
        XCTAssertEqual(Set(cases.map(\.1)).count, cases.count, "two refusals share a line")
    }

    func testAnUnknownRefusalHasNoLine() {
        XCTAssertNil(JuniorCopy.refusalLine(in: "something_else"))
    }

    // MARK: - lines

    func testWaiverLines() {
        XCTAssertEqual(JuniorCopy.waiverLine(.signed), "Waiver signed")
        XCTAssertEqual(JuniorCopy.waiverLine(.needed), "Waiver needed")
        XCTAssertEqual(JuniorCopy.waiverLine(.notAvailable), "Waiver not available yet")
    }

    func testApprovalLines() {
        XCTAssertNil(JuniorCopy.approvalLine(.notNeeded))
        XCTAssertNil(JuniorCopy.approvalLine(.canRequest))
        XCTAssertEqual(JuniorCopy.approvalLine(.requested), "Approval requested")
        XCTAssertEqual(JuniorCopy.approvalLine(.approved), "Approved")
        XCTAssertEqual(JuniorCopy.approvalLine(.declined), "Not approved")
    }

    // MARK: - birthdays never move a day

    func testDateOnlyRoundTripsInEveryTimeZone() {
        for zone in ["Pacific/Kiritimati", "America/New_York", "UTC", "Pacific/Pago_Pago"] {
            var cal = Calendar(identifier: .gregorian)
            cal.timeZone = TimeZone(identifier: zone)!
            let d = JuniorCopy.date(fromDateOnly: "2017-03-01", calendar: cal)
            XCTAssertNotNil(d, zone)
            XCTAssertEqual(JuniorCopy.dateOnly(d!, calendar: cal), "2017-03-01", zone)
        }
    }

    func testDateOnlyPadsMonthAndDay() {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "America/New_York")!
        let d = cal.date(from: DateComponents(year: 2019, month: 6, day: 5, hour: 9))!
        XCTAssertEqual(JuniorCopy.dateOnly(d, calendar: cal), "2019-06-05")
    }

    func testBadDateOnlyIsNil() {
        XCTAssertNil(JuniorCopy.date(fromDateOnly: ""))
        XCTAssertNil(JuniorCopy.date(fromDateOnly: "2017-03"))
    }
}
