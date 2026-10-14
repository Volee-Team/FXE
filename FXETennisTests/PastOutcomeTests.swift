import XCTest
import Supabase
@testable import FXETennis

/// What Past says (audit 2026-10-12): a clinic Tara canceled says Canceled
/// whatever the player held; otherwise played, no-show, or canceled (late).
final class PastOutcomeTests: XCTestCase {
    private func row(_ status: RegistrationStatus, noShow: Bool = false, late: Bool = false,
                     cents: Int? = 1800, clinicCanceled: Bool? = false) -> PastClinic {
        PastClinic(registrationId: UUID(), clinicId: UUID(), name: "Ladies 3.0+", startsAt: Date(), endsAt: Date(),
                   durationMinutes: 60, category: nil, status: status, noShow: noShow, lateCancel: late,
                   priceCentsCharged: cents, paid: false, clinicCanceled: clinicCanceled)
    }

    func testPlayed() {
        XCTAssertEqual(row(.in_).outcome, "Played, $18")
        XCTAssertTrue(row(.in_).outcomeIsPlayed)
    }

    func testAClinicTaraCanceledIsNotPlayed() {
        XCTAssertEqual(row(.in_, clinicCanceled: true).outcome, "Canceled")
        XCTAssertFalse(row(.in_, clinicCanceled: true).outcomeIsPlayed)
    }

    func testNoShowAndCancels() {
        XCTAssertEqual(row(.in_, noShow: true).outcome, "No-show")
        XCTAssertEqual(row(.canceled, late: true).outcome, "Canceled late")
        XCTAssertEqual(row(.canceled).outcome, "Canceled")
        XCTAssertFalse(row(.canceled, late: true).outcomeIsPlayed)
    }

    func testAnOlderServerStillReadsAsBefore() {
        XCTAssertEqual(row(.in_, clinicCanceled: nil).outcome, "Played, $18")
    }
}

/// Refusals that are not races say what happened (audit 2026-10-12).
final class RefusalWordsTests: XCTestCase {
    private func notice(_ message: String) -> String? {
        ClinicDetailModel.outcome(for: PostgrestError(code: "P0001", message: message)).notice
    }

    func testNotOpenYet() { XCTAssertEqual(notice("registration_not_open"), "Registration isn't open yet.") }
    func testFull() { XCTAssertEqual(notice("clinic_full"), "That clinic is full now.") }
    func testStarted() { XCTAssertEqual(notice("clinic_already_started"), "Registration has closed for this clinic.") }
    func testGone() { XCTAssertEqual(notice("clinic_not_found"), "That just changed. Here's the latest.") }
    func testARealRaceStillSaysSo() {
        XCTAssertEqual(notice("invitation_no_longer_available"), "Sorry, someone beat you to the punch. Here's the latest!")
    }
    func testAskingTwiceIsNotAnError() {
        XCTAssertTrue(ClinicDetailModel.isAlreadyAsked(PostgrestError(code: "23505", message: "duplicate key value violates unique constraint")))
        XCTAssertFalse(ClinicDetailModel.isAlreadyAsked(PostgrestError(code: "P0001", message: "clinic_full")))
    }
}
