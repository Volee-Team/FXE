//
//  CardConsentTests.swift
//  FXETennisTests
//
//  The permission box shows Kat and Tara's sentence, and the server stores
//  its own copy (app_settings.card_consent_text, pinned by card_consent.sql).
//  This pins the app's copy to the same literal from their document, so the
//  words a player ticks and the words on record cannot drift apart silently.
//

import XCTest
@testable import FXETennis

final class CardConsentTests: XCTestCase {
    func testTheBoxSaysTheirWordsExactly() {
        XCTAssertEqual(CardConsent.words, "I give permission for my card to be charged")
    }
}
