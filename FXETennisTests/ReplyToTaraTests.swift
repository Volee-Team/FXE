//
//  ReplyToTaraTests.swift
//  FXETennisTests
//
//  The email Reply to Tara opens (2026-11-10): her address, a subject that
//  names the clinic, her message quoted, and nothing in it that a mail app
//  would read as the end of a field.
//

import XCTest
@testable import FXETennis

final class ReplyToTaraTests: XCTestCase {
    private func parts(_ url: URL?) -> (to: String, subject: String, body: String)? {
        guard let url, let c = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        let q = Dictionary(uniqueKeysWithValues: (c.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        return (c.path, q["subject"] ?? "", q["body"] ?? "")
    }

    func testAMessageFromThePlayersTabQuotesHerWords() {
        let p = parts(ReplyToTara.url(replyingTo: "Miguel can do 11:30 Wednesday"))
        XCTAssertEqual(p?.to, "fersctennispro@gmail.com")
        XCTAssertEqual(p?.subject, "Re: your message")
        XCTAssertEqual(p?.body, "\n\nYou wrote:\nMiguel can do 11:30 Wednesday")
    }

    func testAClinicMessageNamesTheClinic() {
        let p = parts(ReplyToTara.url(replyingTo: "Courts are wet.", clinic: "Coed 3.5 Drill"))
        XCTAssertEqual(p?.subject, "Re: Coed 3.5 Drill")
    }

    func testAmpersandsPlusesAndAccentsSurviveTheTrip() {
        let message = "Bring water & balls, 3+ cans. Café at 6? 100% on"
        let url = ReplyToTara.url(replyingTo: message, clinic: "Mixed & Match")
        XCTAssertNotNil(url)
        let raw = url!.absoluteString
        XCTAssertFalse(raw.contains("+"), "A mail app reads + as a space: \(raw)")
        XCTAssertEqual(raw.components(separatedBy: "&").count, 2, "Only the field separator may be a bare &: \(raw)")
        let p = parts(url)
        XCTAssertEqual(p?.subject, "Re: Mixed & Match")
        XCTAssertEqual(p?.body, "\n\nYou wrote:\n\(message)")
    }

    func testAnEmptyMessageLeavesTheBodyEmpty() {
        XCTAssertEqual(parts(ReplyToTara.url(replyingTo: "  \n"))?.body, "")
    }

    func testContactTaraIsTheSameAddress() {
        XCTAssertEqual(ReplyToTara.contactURL.absoluteString, "mailto:fersctennispro@gmail.com")
    }
}
