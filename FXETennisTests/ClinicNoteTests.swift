import XCTest
@testable import FXETennis

/// The note for Tara (decision 0039). Expected values from the rule: shown
/// beside Register and on a live spot before the start, never on a canceled
/// clinic or after the start; trimmed, blank is none; 300 characters as the
/// server counts them.
final class ClinicNoteTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private var tomorrow: Date { now.addingTimeInterval(86_400) }

    func testOfferedBesideRegister() {
        XCTAssertTrue(ClinicNote.offered(status: nil, door: .register, isCanceled: false, startsAt: tomorrow, now: now))
    }

    func testNotOfferedBeforeRegistrationOpensOrAfterItCloses() {
        XCTAssertFalse(ClinicNote.offered(status: nil, door: .opens(tomorrow), isCanceled: false, startsAt: tomorrow, now: now))
        XCTAssertFalse(ClinicNote.offered(status: nil, door: .askTara, isCanceled: false, startsAt: tomorrow, now: now))
        XCTAssertFalse(ClinicNote.offered(status: nil, door: .none, isCanceled: false, startsAt: tomorrow, now: now))
    }

    func testOfferedOnEveryLiveSpot() {
        for status in [RegistrationStatus.in_, .pool, .responseNeeded] {
            XCTAssertTrue(ClinicNote.offered(status: status, door: .none, isCanceled: false, startsAt: tomorrow, now: now), "\(status)")
        }
    }

    func testNotOfferedOnACanceledSpot() {
        XCTAssertFalse(ClinicNote.offered(status: .canceled, door: .register, isCanceled: false, startsAt: tomorrow, now: now))
    }

    func testNotOfferedOnACanceledClinic() {
        XCTAssertFalse(ClinicNote.offered(status: .in_, door: .none, isCanceled: true, startsAt: tomorrow, now: now))
    }

    func testGoneAtTheStartToTheSecond() {
        XCTAssertTrue(ClinicNote.offered(status: .in_, door: .none, isCanceled: false, startsAt: now.addingTimeInterval(1), now: now))
        XCTAssertFalse(ClinicNote.offered(status: .in_, door: .none, isCanceled: false, startsAt: now, now: now))
    }

    func testCleanedTrimsAndBlankIsNone() {
        XCTAssertEqual(ClinicNote.cleaned("  please put me on court with my friend Jane\n"), "please put me on court with my friend Jane")
        XCTAssertNil(ClinicNote.cleaned("   \n "))
        XCTAssertNil(ClinicNote.cleaned(""))
    }

    func testLimitIsThreeHundredScalars() {
        XCTAssertEqual(ClinicNote.limited(String(repeating: "a", count: 300)).count, 300)
        XCTAssertEqual(ClinicNote.limited(String(repeating: "a", count: 301)).count, 300)
    }

    func testAnEmojiIsNeverCutInHalf() {
        // The family emoji is 7 scalars (4 people, 3 joiners).
        let family = "👨‍👩‍👧‍👦"
        XCTAssertEqual(family.unicodeScalars.count, 7)
        let text = String(repeating: "a", count: 296) + family
        let out = ClinicNote.limited(text)
        XCTAssertEqual(out, String(repeating: "a", count: 296))
        XCTAssertLessThanOrEqual(out.unicodeScalars.count, 300)
    }

    func testReturnEndsTheNoteAndIsNotKept() {
        let (text, finished) = ClinicNote.edited("with Jane\n")
        XCTAssertEqual(text, "with Jane")
        XCTAssertTrue(finished)
        let (same, typing) = ClinicNote.edited("with Ja")
        XCTAssertEqual(same, "with Ja")
        XCTAssertFalse(typing)
    }

    func testMyRegistrationDecodesTheNote() throws {
        let json = """
        {"id":"\(UUID())","clinic_id":"\(UUID())","player_id":"\(UUID())","status":"pool","paid":false,
         "registered_at":null,"invited_at":null,"responded_at":null,"canceled_at":null,
         "late_cancel":false,"courtesy_used":false,"player_note":"with Tammy please"}
        """
        let reg = try JSONDecoder().decode(MyRegistration.self, from: Data(json.utf8))
        XCTAssertEqual(reg.playerNote, "with Tammy please")
    }

    func testMyRegistrationWithoutTheColumnStillDecodes() throws {
        let json = """
        {"id":"\(UUID())","clinic_id":"\(UUID())","player_id":"\(UUID())","status":"in","paid":false,
         "registered_at":null,"invited_at":null,"responded_at":null,"canceled_at":null}
        """
        let reg = try JSONDecoder().decode(MyRegistration.self, from: Data(json.utf8))
        XCTAssertNil(reg.playerNote)
    }
}
