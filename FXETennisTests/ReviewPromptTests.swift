//
//  ReviewPromptTests.swift
//  When Apple's rating popup is asked for: the second You're In! or later,
//  once per app version. Expected values from the rule, by hand.
//

import XCTest
@testable import FXETennis

final class ReviewPromptTests: XCTestCase {
    private var defaults: UserDefaults!

    override func setUp() {
        defaults = UserDefaults(suiteName: "ReviewPromptTests")
        defaults.removePersistentDomain(forName: "ReviewPromptTests")
    }

    func testFirstLandingNeverAsks() {
        XCTAssertFalse(ReviewPrompt.recordYoureIn(defaults: defaults, version: "1.0.2 (15)"))
    }

    func testSecondLandingAsksOnce() {
        _ = ReviewPrompt.recordYoureIn(defaults: defaults, version: "1.0.2 (15)")
        XCTAssertTrue(ReviewPrompt.recordYoureIn(defaults: defaults, version: "1.0.2 (15)"))
        XCTAssertFalse(ReviewPrompt.recordYoureIn(defaults: defaults, version: "1.0.2 (15)"),
                       "Asked twice in one version")
    }

    func testANewVersionMayAskAgain() {
        _ = ReviewPrompt.recordYoureIn(defaults: defaults, version: "1.0.2 (15)")
        _ = ReviewPrompt.recordYoureIn(defaults: defaults, version: "1.0.2 (15)")
        XCTAssertTrue(ReviewPrompt.recordYoureIn(defaults: defaults, version: "1.0.3 (16)"))
    }

    func testPureRule() {
        XCTAssertFalse(ReviewPrompt.shouldAsk(youreInCount: 1, lastAskedVersion: nil, currentVersion: "1"))
        XCTAssertTrue(ReviewPrompt.shouldAsk(youreInCount: 2, lastAskedVersion: nil, currentVersion: "1"))
        XCTAssertFalse(ReviewPrompt.shouldAsk(youreInCount: 9, lastAskedVersion: "1", currentVersion: "1"))
    }
}
