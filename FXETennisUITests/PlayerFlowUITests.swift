//
//  PlayerFlowUITests.swift
//  FXETennisUITests
//
//  The whole player journey, driven the way a person drives it: real taps, real
//  typing, real network to the LOCAL seeded database. This is the automation of
//  the manual walkthrough on 2026-08-12 that caught two bugs nothing else could
//  see — a profile decode failure (member shown non-member prices) and a broken
//  real sign-in. Both were invisible to the compiler and to all 143 SQL probes.
//
//  WHAT THIS CATCHES THAT NOTHING ELSE DOES
//    * decode failures between Postgres and Swift (date-only columns, enums)
//    * anything that only breaks once a real JWT is attached
//    * the wiring between a tap and the RPC it is supposed to call
//    * a screen that renders but shows the wrong person's data
//
//  PRECONDITIONS
//    supabase start && supabase db reset      (seed users + dev clinics exist)
//    DEBUG build, which points at http://localhost:54321
//
//  Run:
//    xcodebuild -project FXETennis.xcodeproj -scheme FXETennis \
//      -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
//
//  Every wait uses an explicit expectation rather than sleep(). A sleep that is
//  too short is a flaky test; a sleep that is long enough is a slow one.
//

import XCTest

final class PlayerFlowUITests: XCTestCase {

    /// Seeded member. See supabase/seed.sql.
    private let memberEmail = "maria@fxe.test"
    /// Seeded NON-member, used to prove pricing differs by membership.
    private let nonMemberEmail = "rob@fxe.test"
    private let seedPassword = "password"

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        // Signals the app to start signed out so each test controls its own
        // session, and suppresses the iOS "Save Password?" system sheet which
        // otherwise covers the UI mid-flow.
        app.launchArguments += ["-UITestMode", "-AppleKeyboardsAutocorrection", "0"]
        app.launchEnvironment["UITEST_SIGNED_OUT"] = "1"
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - the money path

    /// Sign in as a member, land on Home, open a clinic, register, and confirm
    /// the status and the primary action both change. This is the flow Tara's
    /// players will do every week; if only one test ever runs, it is this one.
    func testMemberCanSignInBrowseAndRegister() {
        app.launch()
        signIn(as: memberEmail)

        // Home greets the actual person. "Hi, there" here means the profile
        // failed to decode — the exact bug found by hand on 2026-08-12.
        let greeting = app.staticTexts["home.greeting"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 20),
                      "Home never appeared after sign-in")
        XCTAssertTrue(greeting.label.contains("Maria"),
                      "Greeting was '\(greeting.label)'. 'Hi, there' means the profile did not load.")

        // Open the first available clinic.
        let card = app.buttons.matching(identifier: "clinic.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "No clinic cards rendered")
        XCTAssertTrue(tapWhenReady(card), "Clinic card never became tappable")

        // Start from a known state rather than assuming a fresh database.
        ensureNotRegistered()

        let register = app.buttons["clinic.primaryAction"]
        XCTAssertTrue(register.waitForExistence(timeout: 10), "Clinic detail did not open")
        XCTAssertEqual(register.label, "Register", "Expected Register as the primary action")

        XCTAssertTrue(tapWhenReady(register), "Register never became tappable")

        // The server decides the resulting status; the app must reflect it.
        // Either outcome is legitimate depending on the window, so assert the
        // TRANSITION happened rather than hard-coding one status.
        let status = app.descendants(matching: .any).matching(identifier: "clinic.statusChip").firstMatch
        XCTAssertTrue(status.waitForExistence(timeout: 15),
                      "No status appeared after registering — the RPC may not have been called")
        XCTAssertTrue(["You're In!", "Player Pool"].contains(status.label),
                      "Unexpected status after register: '\(status.label)'")

        // And the single primary action must have followed the status.
        let after = app.buttons["clinic.primaryAction"]
        XCTAssertTrue(after.waitForExistence(timeout: 10))
        XCTAssertTrue(["Cancel Registration", "Leave Player Pool"].contains(after.label),
                      "Action did not follow status; got '\(after.label)'")
    }

    /// Registering and then backing out must leave the player with no live
    /// registration — the undo half of the loop, and the path most likely to
    /// leave orphaned rows if the RPC is wired wrong.
    func testPlayerCanUndoTheirRegistration() {
        app.launch()
        signIn(as: memberEmail)

        let card = app.buttons.matching(identifier: "clinic.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertTrue(tapWhenReady(card))

        ensureNotRegistered()

        let action = app.buttons["clinic.primaryAction"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        if action.label == "Register" { XCTAssertTrue(tapWhenReady(action)) }

        let undo = app.buttons["clinic.primaryAction"]
        XCTAssertTrue(undo.waitForExistence(timeout: 15))
        XCTAssertTrue(["Cancel Registration", "Leave Player Pool"].contains(undo.label),
                      "Not in a registered state, cannot test undo")
        undo.tap()

        // Back to an offer to register, and the status chip is gone.
        let back = app.buttons["clinic.primaryAction"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertEqual(back.label, "Register",
                       "After undoing, the player should be able to register again")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "clinic.statusChip").firstMatch.exists,
                       "A status chip survived cancellation")
    }

    // MARK: - pricing, which is money and therefore worth a UI test

    /// The same clinic must quote different prices to a member and a non-member.
    /// A single price on both would mean the profile is not reaching the view —
    /// which is precisely how the 2026-08-12 decode bug presented.
    func testMemberAndNonMemberSeeDifferentPrices() {
        app.launch()
        signIn(as: memberEmail)
        let memberPrice = firstClinicPriceLabel()
        XCTAssertNotNil(memberPrice, "No price rendered for the member")

        signOut()
        signIn(as: nonMemberEmail)
        let nonMemberPrice = firstClinicPriceLabel()
        XCTAssertNotNil(nonMemberPrice, "No price rendered for the non-member")

        XCTAssertNotEqual(memberPrice, nonMemberPrice,
                          "Member and non-member saw the same price (\(memberPrice ?? "nil")). "
                          + "Tara's table is 60min $18/$23, 90min $22/$28.")
    }

    // MARK: - the safety rule, asserted from the outside

    /// Hard rule 1, checked at the only layer that ultimately matters: the
    /// glass. The database probes prove the data cannot be fetched; this proves
    /// no screen renders it anyway.
    func testPlayerNeverSeesHiddenInformation() {
        app.launch()
        signIn(as: memberEmail)

        let card = app.buttons.matching(identifier: "clinic.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        XCTAssertTrue(tapWhenReady(card))
        XCTAssertTrue(app.buttons["clinic.primaryAction"].waitForExistence(timeout: 10))

        let screen = app.descendants(matching: .any)
            .allElementsBoundByIndex
            .compactMap { $0.isHittable ? $0.label : nil }
            .joined(separator: " | ")
            .lowercased()

        for forbidden in ["spots left", "spots remaining", "max:", "capacity",
                          "court 1", "court 2", "court 3", "court 4", "court 5",
                          "registered", "waitlist", "foxcroft"] {
            XCTAssertFalse(screen.contains(forbidden),
                           "Player-facing screen leaked '\(forbidden)'. See hard rule 1.")
        }
    }


    /// Taps once the element is actually hittable. A card can exist while the
    /// scroll view is still settling; tapping then throws "not hittable".
    @discardableResult
    /// iOS offers to save the password after a successful sign-in. It is a
    /// SpringBoard sheet that covers the whole app, so every subsequent query
    /// finds nothing and the run dies with a misleading "not hittable" error.
    /// Diagnosed 2026-08-12 from the element dump, which contained exactly two
    /// buttons: 'Not Now' and 'Save'.
    private func dismissSavePasswordSheetIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for source in [app!, springboard] {
            let notNow = source.buttons["Not Now"]
            if notNow.waitForExistence(timeout: 3) {
                notNow.tap()
                return
            }
        }
    }

    private func tapWhenReady(_ element: XCUIElement, timeout: TimeInterval = 20) -> Bool {
        let hittable = NSPredicate(format: "isHittable == true")
        let exp = XCTNSPredicateExpectation(predicate: hittable, object: element)
        guard XCTWaiter().wait(for: [exp], timeout: timeout) == .completed else { return false }
        element.tap()
        return true
    }

    /// Leaves the open clinic with NO live registration, whatever state it was
    /// in. Tests must not depend on the database being freshly seeded — a
    /// previous run, or a human poking at the simulator, will have left rows
    /// behind. Each test brings the world to a known state itself.
    private func ensureNotRegistered() {
        let action = app.buttons["clinic.primaryAction"]
        guard action.waitForExistence(timeout: 15) else { return }
        if ["Cancel Registration", "Leave Player Pool"].contains(action.label) {
            tapWhenReady(action)
            let back = app.buttons["clinic.primaryAction"]
            _ = back.waitForExistence(timeout: 15)
        }
    }

    // MARK: - helpers

    private func signIn(as email: String) {
        let emailField = app.textFields["auth.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 20), "Sign-in screen never appeared")
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["auth.password"]
        passwordField.tap()
        passwordField.typeText(seedPassword)

        app.buttons["auth.submit"].tap()
        dismissSavePasswordSheetIfPresent()

        // A visible error here is usually the backend, not the app: an empty
        // local DB, or GoTrue rejecting a seeded user with null token columns.
        let error = app.staticTexts["auth.error"]
        if error.waitForExistence(timeout: 4) {
            XCTFail("Sign-in failed: \(error.label). Is `supabase db reset` current?")
        }
    }

    private func signOut() {
        // The save-password sheet can land late, after sign-in has already
        // returned. Clear it defensively before touching the tab bar.
        dismissSavePasswordSheetIfPresent()
        // SwiftUI's TabView replaces a tab item's accessibilityIdentifier with
        // the SF Symbol name ('person.fill'), so querying by identifier finds
        // nothing. The visible label is stable and is what a user reads.
        app.buttons["Profile"].tap()
        let out = app.buttons["profile.signOut"]
        XCTAssertTrue(out.waitForExistence(timeout: 10), "No sign-out control on Profile")
        out.tap()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 15),
                      "Sign-out did not return to the auth screen")
    }

    /// The price line on the first clinic card, e.g. "60 min · $18".
    private func firstClinicPriceLabel() -> String? {
        let price = app.staticTexts.matching(identifier: "clinic.price").firstMatch
        guard price.waitForExistence(timeout: 20) else { return nil }
        return price.label
    }
}
