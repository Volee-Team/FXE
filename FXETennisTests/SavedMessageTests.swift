import XCTest
@testable import FXETennis

/// Decision 0030: "Save this message" is on exactly when the server would keep
/// the text (1 to 1000 characters after trimming, counted as Postgres counts),
/// and the RPC's rows decode. Expected values are worked out from the rule.
final class SavedMessageTests: XCTestCase {
    func testEmptyAndBlankAreNotSavable() {
        XCTAssertNil(SavedMessageRule.savable(""))
        XCTAssertNil(SavedMessageRule.savable("  \n\t "))
    }

    func testTheEndsAreTrimmedAndTheMiddleIsKept() {
        XCTAssertEqual(SavedMessageRule.savable("  See you at 9.\n\nBring water. \n"), "See you at 9.\n\nBring water.")
    }

    func testOneThousandIsTheEdge() {
        XCTAssertNotNil(SavedMessageRule.savable(String(repeating: "x", count: 1000)))
        XCTAssertNil(SavedMessageRule.savable(String(repeating: "x", count: 1001)))
        // Whitespace around 1000 characters does not count.
        XCTAssertNotNil(SavedMessageRule.savable(" " + String(repeating: "x", count: 1000) + "\n"))
    }

    func testTheLimitCountsWhatPostgresCounts() {
        // 👍🏽 is one character to a person and to String.count, two to
        // Postgres length() (U+1F44D U+1F3FD). 500 of them are 1000 for the
        // server: kept. 501 are 1002: the server would refuse, so the button is off.
        XCTAssertEqual("👍🏽".count, 1)
        XCTAssertNotNil(SavedMessageRule.savable(String(repeating: "👍🏽", count: 500)))
        XCTAssertNil(SavedMessageRule.savable(String(repeating: "👍🏽", count: 501)))
        // é as one scalar: 1000 kept, 1001 not.
        XCTAssertNotNil(SavedMessageRule.savable(String(repeating: "\u{E9}", count: 1000)))
        XCTAssertNil(SavedMessageRule.savable(String(repeating: "\u{E9}", count: 1001)))
    }

    func testARowFromTheServerDecodes() throws {
        let json = #"[{"id":"5f0c7d8e-1b2a-4c3d-9e8f-0a1b2c3d4e5f","body":"Courts 1 and 2 today.","created_at":"2026-09-28T20:00:00.123456+00:00","archived_at":null}]"#
        let rows = try JSONDecoder().decode([SavedMessage].self, from: Data(json.utf8))
        XCTAssertEqual(rows.map(\.body), ["Courts 1 and 2 today."])
    }
}
