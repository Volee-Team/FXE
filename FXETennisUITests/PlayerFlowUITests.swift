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

        // `StatusChip` deliberately collapses to ONE accessibility element and
        // publishes `status.accessibilityLabel`, spelled out for VoiceOver, so
        // `element.label` is that string and never the visible chip text. This
        // assertion previously compared against the visible words and failed on
        // a correct registration: it read 'Status: in the Player Pool' and
        // called it unexpected.
        //
        // Asserting the VoiceOver strings is the better test anyway. They are a
        // documented contract in docs/design-system.md, so this now pins the
        // accessibility behaviour as well as the state transition.
        XCTAssertTrue(
            ["Status: you're in", "Status: in the Player Pool"].contains(status.label),
            "Unexpected status after register: '\(status.label)'"
        )

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

        // First tap, then BACK OUT. Keeping the spot is the reason the dialog
        // exists, so it is asserted before the real cancellation.
        //
        // Verified on the simulator 2026-08-28: confirmationDialog presents as
        // a POPOVER anchored to the button here, which shows the destructive
        // choice but hides the cancel-role button — dismissal is tapping
        // anywhere outside. So the dialog-appeared assertion is the confirm
        // button, and backing out is an outside tap, not a "Keep my spot" tap.
        XCTAssertTrue(tapWhenReady(undo), "Undo button never became tappable")
        let confirmChoice = app.buttons["Yes, cancel my spot"].exists
            ? app.buttons["Yes, cancel my spot"] : app.buttons["Yes, leave the pool"]
        XCTAssertTrue(confirmChoice.waitForExistence(timeout: 6), "No confirmation dialog appeared")
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.12)).tap()
        XCTAssertTrue(app.buttons["clinic.primaryAction"].waitForExistence(timeout: 6))
        XCTAssertTrue(["Cancel Registration", "Leave Player Pool"].contains(
            app.buttons["clinic.primaryAction"].label),
            "Backing out of the dialog lost the registration")

        // Now do it for real.
        XCTAssertTrue(tapDestructiveAndConfirm(app.buttons["clinic.primaryAction"]),
                      "Confirmation flow did not complete")

        // Back to an offer to register, and the status chip is gone.
        let back = app.buttons["clinic.primaryAction"]
        XCTAssertTrue(back.waitForExistence(timeout: 15))
        XCTAssertEqual(back.label, "Register",
                       "After undoing, the player should be able to register again")
        XCTAssertFalse(app.descendants(matching: .any).matching(identifier: "clinic.statusChip").firstMatch.exists,
                       "A status chip survived cancellation")
    }

    // MARK: - sign-up, the flow that was a dead end until 2026-08-15

    /// A brand new person creates an account and reaches a working app.
    ///
    /// This is the regression test for the worst bug this project has had that
    /// was not a security hole: `auth.signUp` created an auth user and nothing
    /// else, so a new player landed on a Home that greeted them "Good Evening,
    /// there!", quoted every price at the non-member rate, and had a Register
    /// button that silently did nothing. Nothing failed. Nothing logged. The
    /// app simply did not work, and only for people who had just joined, which
    /// is every single one of Tara's members on day one.
    ///
    /// The assertions below are chosen so that the ORIGINAL bug fails them:
    /// the greeting must contain the name that was typed, and a price must
    /// render. A test that only checked "we reached Home" would have passed
    /// against the broken build.
    func testNewUserCanSignUpAndReachAWorkingApp() {
        app.launch()

        // Unique per run: the auth user survives in the local database, so a
        // fixed address would pass once and then fail with "already
        // registered" forever after. Tests must not depend on a fresh reset.
        let unique = UUID().uuidString.prefix(8).lowercased()
        let email = "newplayer-\(unique)@fxe.test"
        let firstName = "Testcase"

        let toSignUp = app.buttons["auth.toggleMode"]
        XCTAssertTrue(toSignUp.waitForExistence(timeout: 20), "Sign-in screen never appeared")
        toSignUp.tap()

        let emailField = app.textFields["auth.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 10))
        emailField.tap()
        emailField.typeText(email)

        let passwordField = app.secureTextFields["auth.password"]
        passwordField.tap()
        passwordField.typeText("testpassword123")
        dismissSavePasswordSheetIfPresent()

        app.buttons["auth.submit"].tap()
        dismissSavePasswordSheetIfPresent()

        // The profile screen must appear. Before the fix, sign-up went straight
        // to a broken Home, so reaching this screen at all is the fix working.
        let first = app.textFields["profile.firstName"]
        XCTAssertTrue(first.waitForExistence(timeout: 20),
                      "Profile screen never appeared after sign-up — the new user has no way to create an account")
        first.tap()
        first.typeText(firstName)

        let last = app.textFields["profile.lastName"]
        last.tap()
        last.typeText("Player")

        // Continue stays disabled until the membership question is answered,
        // because a silent default puts someone in the wrong pricing tier.
        let go = app.buttons["profile.continue"]
        XCTAssertTrue(go.waitForExistence(timeout: 10))
        XCTAssertFalse(go.isEnabled,
                       "Continue was enabled before the membership question was answered")

        app.buttons["profile.member.yes"].tap()
        XCTAssertTrue(go.isEnabled, "Continue stayed disabled after a complete form")

        // The software keyboard is still up from the name fields and covers the
        // bottom of the form, so Continue exists and is enabled but is not
        // hittable. Scroll it into view rather than sleeping: a real player on a
        // small phone hits exactly this, and a test that cannot reach the button
        // is telling us something true about the layout.
        XCTAssertTrue(scrollUntilHittable(go), "Continue never became reachable")
        go.tap()

        // The greeting must name the person who just signed up. "there" is the
        // exact symptom of the original bug.
        let greeting = app.staticTexts["home.greeting"]
        XCTAssertTrue(greeting.waitForExistence(timeout: 20),
                      "Never reached Home after completing the profile")
        XCTAssertTrue(greeting.label.contains(firstName),
                      "Greeting was '\(greeting.label)'. Not naming the new user means the profile did not save.")

        // And they must be a real player: a price rendering proves the profile
        // reached the view, which is what decides member vs non-member pricing.
        XCTAssertNotNil(firstClinicPriceLabel(),
                        "No price rendered for the new user, so their profile is not reaching the clinic list")
    }

    // MARK: - the bell

    /// The bell opens the notification center, rows are the seeded messages,
    /// and reading them clears the badge. Read state lives in the database,
    /// so the assertion at the end is that the bell's own label changed.
    func testPlayerCanReadNotificationsFromTheBell() {
        app.launch()
        signIn(as: memberEmail)

        let bell = app.buttons["home.bell"]
        XCTAssertTrue(bell.waitForExistence(timeout: 20), "Home bell never appeared. Buttons on screen: \(app.buttons.allElementsBoundByIndex.map { "\($0.identifier)|\($0.label)" })")
        bell.tap()

        let rows = app.buttons.matching(identifier: "notifications.row")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 20),
                      "No notification rows: the seed has two for Maria")
        XCTAssertGreaterThanOrEqual(rows.count, 2)

        let markAll = app.buttons["notifications.markAllRead"]
        XCTAssertTrue(markAll.waitForExistence(timeout: 10))
        if markAll.isEnabled {
            markAll.tap()
            // Disabled once nothing is unread: the database said so, not the view.
            let cleared = NSPredicate(format: "isEnabled == false")
            expectation(for: cleared, evaluatedWith: markAll)
            waitForExpectations(timeout: 10)
        }

        app.buttons["notifications.done"].tap()
        XCTAssertTrue(bell.waitForExistence(timeout: 10))
        XCTAssertEqual(bell.label, "Notifications",
                       "Bell still reports unread after Mark all read: '\(bell.label)'")
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

    /// Scrolls the containing scroll view until `element` is actually hittable.
    ///
    /// `exists` and `isEnabled` are both true for a control sitting under the
    /// software keyboard or below the fold, so waiting on those and then tapping
    /// fails with a misleading "never became tappable". Swiping a bounded number
    /// of times keeps a layout regression a failure rather than a hang.
    @discardableResult
    private func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 5) -> Bool {
        guard element.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<maxSwipes {
            if element.isHittable { return true }
            app.swipeUp()
        }
        return element.isHittable
    }

    /// Destructive actions confirm first as of 2026-08-28. The dialog's confirm
    /// button deliberately carries a DIFFERENT label than the button that opened
    /// it, so this helper taps the action and then whichever confirm appears.
    private func tapDestructiveAndConfirm(_ element: XCUIElement) -> Bool {
        guard tapWhenReady(element) else { return false }
        for label in ["Yes, cancel my spot", "Yes, leave the pool"] {
            let confirm = app.buttons[label]
            if confirm.waitForExistence(timeout: 4) { confirm.tap(); return true }
        }
        return false
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
            _ = tapDestructiveAndConfirm(action)
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
