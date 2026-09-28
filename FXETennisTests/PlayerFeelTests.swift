//
//  PlayerFeelTests.swift
//  FXETennisTests
//
//  Haptics and the status chip's motion on the clinic page (2026-09-28).
//  The rules:
//    * a success haptic when the player's registration lands in You're In!
//      or the Player Pool (Register, Accept, Decline), read from the status
//      the reload shows, not from the tap;
//    * a warning haptic when an attempt to land one is refused or cannot
//      reach the server; nothing for a screen that went away, and nothing
//      for cancelling, leaving the Pool or the late request;
//    * the chip changes over about 0.35 s, a crossfade only with Reduce
//      Motion on, and a chip going away leaves at once (never two chips).
//

import XCTest
import SwiftUI
import Supabase
@testable import FXETennis

final class PlayerFeelTests: XCTestCase {

    private let race = ClinicDetailModel.FailureOutcome(
        notice: "Sorry, someone beat you to the punch. Here's the latest!", reopens: nil)
    private let offline = ClinicDetailModel.FailureOutcome(
        notice: "Couldn't reach the server. Check your connection.", reopens: nil)
    private let wentAway = ClinicDetailModel.FailureOutcome(notice: nil, reopens: nil)

    // MARK: - haptics

    func testLandingInYoureInOrThePoolIsASuccess() {
        XCTAssertEqual(ClinicDetailModel.haptic(landing: true, landedIn: .in_, failure: nil), .success)
        XCTAssertEqual(ClinicDetailModel.haptic(landing: true, landedIn: .pool, failure: nil), .success)
    }

    func testAnAnswerThatDidNotLandIsNoSuccess() {
        // The reload still shows Response Needed (it failed): nothing claimed.
        XCTAssertNil(ClinicDetailModel.haptic(landing: true, landedIn: .responseNeeded, failure: nil))
        XCTAssertNil(ClinicDetailModel.haptic(landing: true, landedIn: nil, failure: nil))
    }

    func testARefusedOrUnreachedAttemptIsAWarning() {
        XCTAssertEqual(ClinicDetailModel.haptic(landing: true, landedIn: nil, failure: race), .warning)
        XCTAssertEqual(ClinicDetailModel.haptic(landing: true, landedIn: nil, failure: offline), .warning)
    }

    func testAScreenThatWentAwayFeelsNothing() {
        XCTAssertNil(ClinicDetailModel.haptic(landing: true, landedIn: nil, failure: wentAway))
    }

    func testCancellingIsNotALanding() {
        // A cancel whose reload failed still shows the old You're In!.
        XCTAssertNil(ClinicDetailModel.haptic(landing: false, landedIn: .in_, failure: nil))
        XCTAssertNil(ClinicDetailModel.haptic(landing: false, landedIn: nil, failure: nil))
        XCTAssertNil(ClinicDetailModel.haptic(landing: false, landedIn: nil, failure: race))
    }

    // MARK: - the chip's motion

    func testReduceMotionIsACrossfadeOnly() {
        XCTAssertEqual(StatusChipMotion.style(reduceMotion: true), .fadeOnly)
        XCTAssertEqual(StatusChipMotion.style(reduceMotion: false), .fadeAndScale)
    }

    func testAChangeTakesAboutAThirdOfASecond() {
        XCTAssertEqual(StatusChipMotion.animation(to: .in_), .easeInOut(duration: 0.35))
        XCTAssertEqual(StatusChipMotion.animation(to: .pool), .easeInOut(duration: 0.35))
    }

    func testAChipGoingAwayLeavesAtOnce() {
        XCTAssertNil(StatusChipMotion.animation(to: nil))
    }
}
