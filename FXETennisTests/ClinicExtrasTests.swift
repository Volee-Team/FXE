import XCTest
@testable import FXETennis

/// Decision 0054 (Tara's items 8, 10, 11) and the guests and prices the phone
/// gained in 1.0.3 (decisions 0052, 0053). Expected values from her words, by
/// hand: "Round 1 / Coirt 1: player a,bc / player d,e,f", "If we get 45 mins
/// I would charge $14", "Warn me!".
final class ClinicExtrasTests: XCTestCase {

    private func spot(_ round: Int, _ court: Int, _ side: Int, _ slot: Int, _ first: String,
                      gone: Bool = false, guest: Bool = false) -> RoundSpot {
        RoundSpot(roundNumber: round, courtNumber: court, side: side, slot: slot, personId: UUID(),
                  firstName: first, lastName: "X", isGuest: guest, gone: gone)
    }

    // MARK: - Rounds

    func testA105IsNamedOrCategorised() {
        XCTAssertTrue(Rounds.is105(name: "Coed \"105\"", category: "Clinic"))
        XCTAssertTrue(Rounds.is105(name: "Sunday Coed", category: "105"))
        XCTAssertFalse(Rounds.is105(name: "Ladies 3.0+", category: "Clinic"))
        XCTAssertFalse(Rounds.is105(name: "All-Level Men's", category: nil))
    }

    func testACourtReadsHerWaySideBySide() {
        let spots = [spot(1, 1, 1, 1, "A"), spot(1, 1, 1, 2, "B"), spot(1, 1, 1, 3, "C"),
                     spot(1, 1, 2, 1, "D"), spot(1, 1, 2, 2, "E"), spot(1, 1, 2, 3, "F")]
        XCTAssertEqual(Rounds.line(spots, round: 1, court: 1), "A X, B X, C X / D X, E X, F X")
        XCTAssertNil(Rounds.line(spots, round: 1, court: 2), "An empty court has no line")
        XCTAssertNil(Rounds.line(spots, round: 2, court: 1), "Round 2 is its own")
    }

    func testTheSixSpotsAreInTheServersOrder() {
        let spots = [spot(2, 3, 2, 1, "D"), spot(2, 3, 1, 2, "B")]
        let six = Rounds.lineup(spots, round: 2, court: 3)
        XCTAssertEqual(six.count, 6)
        XCTAssertEqual(six.map { $0?.firstName }, [nil, "B", nil, "D", nil, nil])
    }

    func testAnEmptySideAndSomeoneWhoLeft() {
        let spots = [spot(1, 2, 1, 1, "A"), spot(1, 2, 1, 2, "B", gone: true)]
        XCTAssertEqual(Rounds.line(spots, round: 1, court: 2), "A X, B X (left) / open")
        XCTAssertFalse(Rounds.isEmpty(spots, round: 1))
        XCTAssertTrue(Rounds.isEmpty(spots, round: 3))
    }

    func testARoundSpotDecodesTheServersRow() throws {
        let id = UUID()
        let json = """
        [{"round_number":1,"court_number":2,"side":2,"slot":3,"person_id":"\(id.uuidString)",
          "first_name":"Pat","last_name":"Visitor","is_guest":true,"gone":false}]
        """
        let rows = try JSONDecoder().decode([RoundSpot].self, from: Data(json.utf8))
        XCTAssertEqual(rows.first?.personId, id)
        XCTAssertEqual(rows.first?.displayName, "Pat Visitor")
        XCTAssertEqual(rows.first?.isGuest, true)
    }

    // MARK: - One player's price

    func testDollarsAsSheTypesThem() {
        XCTAssertEqual(DollarsInput.cents("14"), 1400)
        XCTAssertEqual(DollarsInput.cents("$14"), 1400)
        XCTAssertEqual(DollarsInput.cents("14.5"), 1450)
        XCTAssertEqual(DollarsInput.cents(" 11.50 "), 1150)
        XCTAssertNil(DollarsInput.cents("0"), "A charge of nothing is refused")
        XCTAssertNil(DollarsInput.cents(""))
        XCTAssertNil(DollarsInput.cents("fourteen"))
        XCTAssertNil(DollarsInput.cents("14.555"))
        XCTAssertEqual(DollarsInput.text(1400), "14")
        XCTAssertEqual(DollarsInput.text(1150), "11.50")
        XCTAssertEqual(DollarsInput.text(nil), "")
    }

    func testTheRosterRowCarriesHerPrice() throws {
        let json = """
        {"id":"\(UUID().uuidString)","clinic_id":"\(UUID().uuidString)","player_id":"\(UUID().uuidString)",
         "status":"in","paid":false,"court_number":null,"registered_at":"2026-11-09T12:00:00Z","invited_at":null,
         "no_show":false,"late_cancel":false,"courtesy_used":false,"cancel_note":null,"charge_status":null,
         "has_card":true,"price_cents_charged":1400,"price_set_by_admin":true}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let row = try decoder.decode(RegistrationAdmin.self, from: Data(json.utf8))
        XCTAssertEqual(row.priceCentsCharged, 1400)
        XCTAssertEqual(row.priceSetByAdmin, true)
    }

    // MARK: - The phone on her Player page

    /// "Will def need this juniors bc if something happens need to text
    /// parents immediate": a junior's number is the parent's, and says so.
    func testWhoseNumberItIs() {
        XCTAssertEqual(PlayerPhone.label(kind: "adult", playerFirst: "Maria", playerLast: "Alvarez",
                                         holderFirst: "Maria", holderLast: "Alvarez"), "Phone")
        XCTAssertEqual(PlayerPhone.label(kind: "adult", playerFirst: "maria", playerLast: "alvarez",
                                         holderFirst: "Maria ", holderLast: "Alvarez"), "Phone")
        XCTAssertEqual(PlayerPhone.label(kind: "junior", playerFirst: "Sam", playerLast: "Lee",
                                         holderFirst: "Sarah", holderLast: "Lee"), "Parent's phone (Sarah Lee)")
        XCTAssertEqual(PlayerPhone.label(kind: "junior", playerFirst: "Sam", playerLast: "Lee",
                                         holderFirst: nil, holderLast: nil), "Parent's phone")
        XCTAssertEqual(PlayerPhone.label(kind: "adult", playerFirst: "Jo", playerLast: "Lee",
                                         holderFirst: "Sarah", holderLast: "Lee"), "Phone on Sarah Lee's account")
    }

    func testTextAndCallLinks() {
        XCTAssertEqual(PlayerPhone.textURL("704-555-0101")?.absoluteString, "sms:7045550101")
        XCTAssertEqual(PlayerPhone.callURL("(704) 555-0101")?.absoluteString, "tel:7045550101")
        XCTAssertEqual(PlayerPhone.callURL("+1 704 555 0101")?.absoluteString, "tel:+17045550101")
        XCTAssertNil(PlayerPhone.textURL(""))
        XCTAssertNil(PlayerPhone.callURL("n/a"))
        XCTAssertNil(PlayerPhone.callURL(nil))
    }

    func testTheAccountDecodesFromTheEmbed() throws {
        let json = #"[{"accounts":{"phone":"704-555-0101","last_name":"Alvarez","first_name":"Maria"}}]"#
        let rows = try JSONDecoder().decode([PlayerContact].self, from: Data(json.utf8))
        XCTAssertEqual(rows.first?.accounts?.phone, "704-555-0101")
        XCTAssertEqual(rows.first?.accounts?.firstName, "Maria")
    }

    // MARK: - Guests and the full question

    func testAGuestDecodes() throws {
        let json = """
        {"id":"\(UUID().uuidString)","clinic_id":"\(UUID().uuidString)","first_name":"Pat","last_name":"Visitor",
         "court_number":2,"added_at":"2026-11-09T12:00:00Z","removed_at":null}
        """
        let g = try JSONDecoder().decode(ClinicGuest.self, from: Data(json.utf8))
        XCTAssertEqual(g.displayName, "Pat Visitor")
        XCTAssertEqual(g.courtNumber, 2)
    }

    func testAddingAGuestToAFullClinicAsks() {
        XCTAssertEqual(ClinicFull.question(.add, name: "Pat Visitor", inCount: 25, capacity: 25),
                       "Are you sure you want to add Pat Visitor? Your clinic is full (25/25).")
    }

    func testRefusalsInWords() {
        struct E: Error, CustomStringConvertible { let description: String }
        XCTAssertEqual(ClinicExtrasError.message(E(description: "guest_already_added")), "That guest is already on this clinic.")
        XCTAssertEqual(ClinicExtrasError.message(E(description: "invalid_price")), "Enter a price above $0.")
        XCTAssertEqual(ClinicExtrasError.message(E(description: "already_paid")), "Already marked paid.")
        XCTAssertEqual(ClinicExtrasError.message(E(description: "not_in_clinic")), "That just changed. Here's the latest.")
        XCTAssertEqual(ClinicExtrasError.message(E(description: "offline")),
                       "That didn't go through. Check your connection and try again.")
    }
}
