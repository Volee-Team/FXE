import XCTest
@testable import FXETennis

/// A pro's Today tab (decision 0025): the pure rules, from the rule. Tara:
/// "Let the pros see who is coming to the clinics that day ... See anything
/// financial at all" (she means: not see).
final class ProTodayTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let early = UUID(uuidString: "00000000-0000-0000-0000-00000000000A")!
    private let late = UUID(uuidString: "00000000-0000-0000-0000-00000000000B")!

    private func row(_ clinic: UUID, _ name: String, startsIn hours: Double,
                     reg: UUID? = UUID(), first: String? = "Ann", last: String? = "Lee",
                     court: Int? = nil, noShow: Bool? = false) -> ProTodayRow {
        ProTodayRow(clinicId: clinic, clinicName: name,
                    startsAt: now.addingTimeInterval(hours * 3600),
                    endsAt: now.addingTimeInterval(hours * 3600 + 3600),
                    registrationId: reg, firstName: reg == nil ? nil : first, lastName: reg == nil ? nil : last,
                    courtNumber: reg == nil ? nil : court, noShow: reg == nil ? nil : noShow,
                    lateCancel: reg == nil ? nil : false)
    }

    // MARK: - grouping

    func testRowsGroupIntoClinicsEarliestFirst() {
        let clinics = ProToday.group([
            row(late, "Evening", startsIn: 6, first: "Bo", last: "Diaz"),
            row(early, "Morning", startsIn: -2, first: "Cy", last: "Ng"),
            row(late, "Evening", startsIn: 6, first: "Al", last: "Fox"),
        ])
        XCTAssertEqual(clinics.map(\.name), ["Morning", "Evening"])
        XCTAssertEqual(clinics.map { $0.players.count }, [1, 2])
    }

    func testAClinicNobodyIsInYetIsStillListed() {
        // pro_today() sends such a clinic as one row with no registration.
        let clinics = ProToday.group([row(early, "Morning", startsIn: 1, reg: nil)])
        XCTAssertEqual(clinics.count, 1)
        XCTAssertEqual(clinics.first?.players, [])
    }

    func testPlayersInCourtOrderNoCourtLast() {
        let clinics = ProToday.group([
            row(early, "Morning", startsIn: 1, first: "Zed", last: "Adams", court: nil),
            row(early, "Morning", startsIn: 1, first: "Amy", last: "Young", court: 3),
            row(early, "Morning", startsIn: 1, first: "Bea", last: "Moss", court: 1),
        ])
        XCTAssertEqual(clinics.first?.players.map(\.name), ["Bea Moss", "Amy Young", "Zed Adams"])
    }

    func testSameCourtByLastNameThenFirstName() {
        let clinics = ProToday.group([
            row(early, "Morning", startsIn: 1, first: "Sam", last: "Lee", court: 2),
            row(early, "Morning", startsIn: 1, first: "Ana", last: "Lee", court: 2),
            row(early, "Morning", startsIn: 1, first: "Kim", last: "Cho", court: 2),
        ])
        XCTAssertEqual(clinics.first?.players.map(\.name), ["Kim Cho", "Ana Lee", "Sam Lee"])
    }

    func testTheSameRegistrationTwiceIsOnePlayer() {
        let reg = UUID()
        let clinics = ProToday.group([
            row(early, "Morning", startsIn: 1, reg: reg),
            row(early, "Morning", startsIn: 1, reg: reg),
        ])
        XCTAssertEqual(clinics.first?.players.count, 1)
    }

    func testTheNoShowFlagTravels() {
        let clinics = ProToday.group([row(early, "Morning", startsIn: -1, noShow: true)])
        XCTAssertEqual(clinics.first?.players.first?.noShow, true)
    }

    /// The column names are the contract with pro_today(); a rename on either
    /// side must fail here, not on Tara's pros at the courts.
    func testDecodesTheServerRowIncludingAnEmptyClinic() throws {
        let json = """
        [{"clinic_id":"00000000-0000-0000-0000-00000000000A","clinic_name":"Today Drill",
          "starts_at":"2026-09-28T04:30:00Z","ends_at":"2026-09-28T05:30:00Z",
          "registration_id":"00000000-0000-0000-0000-0000000000C1","first_name":"Lena","last_name":"Brooks",
          "court_number":1,"no_show":false,"late_cancel":false},
         {"clinic_id":"00000000-0000-0000-0000-00000000000B","clinic_name":"Nobody Yet",
          "starts_at":"2026-09-28T16:00:00Z","ends_at":"2026-09-28T17:00:00Z",
          "registration_id":null,"first_name":null,"last_name":null,
          "court_number":null,"no_show":null,"late_cancel":null}]
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let rows = try decoder.decode([ProTodayRow].self, from: Data(json.utf8))
        let clinics = ProToday.group(rows)
        XCTAssertEqual(clinics.map(\.name), ["Today Drill", "Nobody Yet"])
        XCTAssertEqual(clinics[0].players.map(\.name), ["Lena Brooks"])
        XCTAssertEqual(clinics[0].players.first?.court, 1)
        XCTAssertEqual(clinics[1].players, [])
    }

    // MARK: - Late cancel, where the server would accept it

    func testLateCancelNotOfferedBeforeTheCutoff() {
        XCTAssertFalse(ProToday.canLateCancel(startsAt: now.addingTimeInterval(3 * 3600), cutoffHours: 3, now: now))
    }

    func testLateCancelOfferedInsideTheCutoff() {
        XCTAssertTrue(ProToday.canLateCancel(startsAt: now.addingTimeInterval(3 * 3600 - 1), cutoffHours: 3, now: now))
    }

    func testLateCancelOfferedAfterTheStart() {
        // Tara may record it afterwards; so may a pro, the same day.
        XCTAssertTrue(ProToday.canLateCancel(startsAt: now.addingTimeInterval(-2 * 3600), cutoffHours: 3, now: now))
    }

    // MARK: - refusals, in words

    func testTheServersRefusalsInWords() {
        XCTAssertEqual(ProToday.message(forDescription: "clinic_locked"), "Only Tara can change this.")
        XCTAssertEqual(ProToday.message(forDescription: "not_late_yet"), "Not late yet.")
        XCTAssertEqual(ProToday.message(forDescription: "clinic_canceled"), "That clinic is canceled.")
        XCTAssertEqual(ProToday.message(forDescription: "registration_not_in"), "That just changed. Here's the latest.")
        XCTAssertEqual(ProToday.message(forDescription: "not_today"), "That just changed. Here's the latest.")
        XCTAssertEqual(ProToday.message(forDescription: "The network connection was lost."),
                       "That didn't go through. Check your connection and try again.")
    }

    /// Whatever the server says, a pro is never told a player was charged.
    func testAProIsNeverToldAboutMoney() {
        for code in ["charged_refund_first", "clinic_locked", "already_charged", "payments_disabled",
                     "not_authorized", "no_card_on_file", "something else"] {
            let words = ProToday.message(forDescription: code).lowercased()
            for money in ["charge", "refund", "fee", "paid", "card", "$"] {
                XCTAssertFalse(words.contains(money), "\(code) became \"\(words)\", which mentions \(money)")
            }
        }
        XCTAssertEqual(ProToday.message(forDescription: "charged_refund_first"), "Only Tara can change this.")
    }

    // MARK: - who gets the tab

    private func account(_ role: String) -> Account {
        Account(id: UUID(), firstName: "A", lastName: "B", email: nil, phone: nil,
                accountType: "adult", role: role, cardBrand: nil, cardLast4: nil)
    }

    func testOnlyAProIsAPro() {
        XCTAssertTrue(account("pro").isPro)
        XCTAssertFalse(account("pro").isAdmin)
        XCTAssertFalse(account("admin").isPro)
        XCTAssertTrue(account("admin").isAdmin)
        XCTAssertFalse(account("member").isPro)
        XCTAssertFalse(account("member").isAdmin)
    }
}
