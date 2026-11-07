import XCTest
@testable import FXETennis

/// Tara, 2026-11-06, item 5: "clinic is 25/25. I invite someone, a message
/// comes up that says 'are you sure you want to invite ___ your clinic is
/// full.'" Expected values from her sentence, by hand.
final class ClinicFullTests: XCTestCase {
    func testFullAtCapacityNotBefore() {
        XCTAssertTrue(ClinicFull.isFull(inCount: 25, capacity: 25))
        XCTAssertTrue(ClinicFull.isFull(inCount: 26, capacity: 25))
        XCTAssertFalse(ClinicFull.isFull(inCount: 24, capacity: 25))
        XCTAssertFalse(ClinicFull.isFull(inCount: 40, capacity: nil), "No capacity is no limit")
    }

    func testTheQuestionNamesThePlayerAndTheCount() {
        XCTAssertEqual(ClinicFull.question(.invite, name: "Jane Doe", inCount: 25, capacity: 25),
                       "Are you sure you want to invite Jane Doe? Your clinic is full (25/25).")
        XCTAssertEqual(ClinicFull.question(.moveIn, name: "Jane Doe", inCount: 26, capacity: 25),
                       "Are you sure you want to move Jane Doe in? Your clinic is full (26/25).")
    }

    func testInviteRefusalsInWords() {
        struct E: Error, CustomStringConvertible { let description: String }
        XCTAssertEqual(ClinicFull.inviteError(E(description: "already_registered"), name: "Ken Whitfield"),
                       "Ken Whitfield is already on this clinic.")
        XCTAssertEqual(ClinicFull.inviteError(E(description: "clinic_not_published"), name: "x"), "Publish the clinic first.")
        XCTAssertEqual(ClinicFull.inviteError(E(description: "waiver_required"), name: "Theo Grant"),
                       "Theo Grant hasn't signed the waiver yet.")
        XCTAssertEqual(ClinicFull.inviteError(E(description: "offline"), name: "x"),
                       "That didn't go through. Check your connection and try again.")
    }
}
