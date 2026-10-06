//
//  ProFlowUITests.swift
//  FXETennisUITests
//
//  A pro's phone (decision 0025), walked against the local stack on a fresh
//  seed. The seed makes pro@fxe.test a pro through admin_set_pro and puts
//  "Today Drill" on today's New York date with Lena Brooks (court 1) and Theo
//  Grant You're In! (supabase/seed.sql). The server side is pinned by
//  tests/sql/pro_role.sql; this is what the pro actually gets on screen.
//
//  The test leaves the database as it found it (No-show, then Came again), so
//  a second run without a reset starts from the same state.
//

import XCTest

final class ProFlowUITests: XCTestCase {
    private let pro = "pro@fxe.test"
    private let member = "maria@fxe.test"
    private let admin = "tara@fxe.test"
    private let seedPassword = "password"
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "-AppleKeyboardsAutocorrection", "0"]
        app.launchEnvironment["UITEST_SIGNED_OUT"] = "1"
        // The same pass-through as the other UI test files: a Debug app
        // pointed at another backend by the runner's environment.
        for key in ["FXE_SUPABASE_URL", "FXE_SUPABASE_ANON_KEY"] {
            if let value = ProcessInfo.processInfo.environment[key] { app.launchEnvironment[key] = value }
        }
    }

    /// The pro signs in, has Today and no Manage, sees today's clinic with
    /// its two players and their courts, marks Lena a No-show (read back from
    /// the server's answer), and finds no Invite, no Player Pool and no price
    /// anywhere on the tab.
    func testProSeesTodayAndMarksANoShow() {
        app.launch()
        signIn(as: pro)

        XCTAssertTrue(todayTab.waitForExistence(timeout: 10), "A pro has no Today tab")
        XCTAssertFalse(app.tabBars.buttons["Manage"].exists, "A pro was given Tara's Manage tab")

        openToday()
        XCTAssertTrue(app.staticTexts["Today Drill"].waitForExistence(timeout: 20),
                      "Today's seeded clinic is not on the Today tab. Texts: \(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(30))")
        XCTAssertTrue(app.staticTexts["Lena Brooks"].waitForExistence(timeout: 10), "Lena is not listed")
        XCTAssertTrue(app.staticTexts["Theo Grant"].exists, "Theo is not listed")
        XCTAssertTrue(app.staticTexts["Court 1"].exists, "Lena's court is not shown")
        keepScreenshot("1 Today tab, as the pro")

        // Came -> No-show, asserted from the toggle's own label, which is
        // rebuilt from pro_today() after the RPC returns.
        let lena = app.buttons.matching(identifier: "pro.noShowToggle")
            .matching(NSPredicate(format: "label CONTAINS[c] 'Lena Brooks'")).firstMatch
        XCTAssertTrue(lena.waitForExistence(timeout: 10), "No Came / No-show control on Lena's row")
        if lena.label.localizedCaseInsensitiveContains("no-show") {
            // A previous run stopped half way: start from Came.
            lena.tap()
            expectation(for: NSPredicate(format: "label CONTAINS[c] 'came'"), evaluatedWith: lena)
            waitForExpectations(timeout: 15)
        }
        lena.tap()
        expectation(for: NSPredicate(format: "label CONTAINS[c] 'no-show'"), evaluatedWith: lena)
        waitForExpectations(timeout: 15)
        keepScreenshot("2 Lena marked No-show")

        // The clinic started at 00:30, so Late cancel is offered on each row.
        XCTAssertTrue(app.buttons["Late cancel Lena Brooks"].exists, "No Late cancel on Lena's row")

        // Nothing of Tara's: no Invite, no Player Pool, no money.
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS[c] 'invite'")).count, 0,
                       "An Invite control reached a pro")
        XCTAssertFalse(app.staticTexts["Player Pool"].exists, "The Player Pool reached a pro")
        XCTAssertEqual(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '$'")).count, 0,
                       "A price reached a pro: \(app.staticTexts.matching(NSPredicate(format: "label CONTAINS '$'")).allElementsBoundByIndex.map(\.label))")
        XCTAssertFalse(app.buttons["Remove from clinic"].exists, "Remove reached a pro")

        // Leave the seed as it was.
        lena.tap()
        expectation(for: NSPredicate(format: "label CONTAINS[c] 'came'"), evaluatedWith: lena)
        waitForExpectations(timeout: 15)
    }

    /// Players never see the tab; Tara keeps Manage and does not get Today.
    func testOnlyAProHasTheTodayTab() {
        app.launch()
        signIn(as: member)
        XCTAssertTrue(app.tabBars.buttons["Profile"].waitForExistence(timeout: 10))
        XCTAssertFalse(todayTab.exists, "A member was given the pro's Today tab")
        XCTAssertFalse(app.tabBars.buttons["Manage"].exists, "A member was given Manage")
        signOut()

        signIn(as: admin)
        XCTAssertTrue(app.tabBars.buttons["Manage"].waitForExistence(timeout: 10), "Tara lost Manage")
        XCTAssertFalse(todayTab.exists, "Tara was given the pro's Today tab")

        // Her roster of the same clinic still has her controls. Came /
        // No-show is on every You're In! row before and after the clinic;
        // the Court menu is only before it ends (decision 0037: after, the
        // row is Came, Remove and Charge). The Today Drill runs 00:30 to
        // 01:30 New York, so which layout shows depends on the clock, and the
        // first version of this test failed at 19:11 for asking for a court
        // (2026-10-04).
        app.tabBars.buttons["Manage"].tap()
        let card = app.descendants(matching: .any).matching(identifier: "admin.clinic.card")
            .matching(NSPredicate(format: "label CONTAINS[c] 'Today Drill'")).firstMatch
        if !card.waitForExistence(timeout: 5) { app.tabBars.buttons["Manage"].tap() }
        XCTAssertTrue(card.waitForExistence(timeout: 20), "No Manage card for Today Drill")
        card.tap()
        XCTAssertTrue(app.buttons["admin.noShowToggle"].firstMatch.waitForExistence(timeout: 20), "Tara's roster has no Came / No-show")
        keepScreenshot("3 Tara's roster of the same clinic")
    }

    // MARK: - helpers (mirrors AdminFlowUITests; kept local so each file reads alone)

    /// A screenshot kept in the result bundle even when the test passes, so
    /// each step can be looked at afterwards (CLAUDE.md: UI changes are
    /// verified by screenshots read back, not by a green line alone).
    private func keepScreenshot(_ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }

    private var todayTab: XCUIElement { app.tabBars.buttons["Today"] }

    /// The iOS 26 simulator's tab bar drops a first tap now and then
    /// (2026-09-12), so tap once more before calling it a failure.
    private func openToday() {
        todayTab.tap()
        if !app.navigationBars["Today"].waitForExistence(timeout: 5) {
            todayTab.tap()
        }
        XCTAssertTrue(app.navigationBars["Today"].waitForExistence(timeout: 15), "The Today tab never opened")
    }

    private func signIn(as email: String) {
        let emailField = app.textFields["auth.email"]
        XCTAssertTrue(emailField.waitForExistence(timeout: 20), "Sign-in screen never appeared")
        emailField.tap()
        emailField.typeText(email)
        let password = app.secureTextFields["auth.password"]
        password.tap()
        password.typeText(seedPassword)
        dismissSavePasswordSheetIfPresent()
        app.buttons["auth.submit"].tap()
        dismissSavePasswordSheetIfPresent()
        XCTAssertTrue(app.staticTexts["home.greeting"].waitForExistence(timeout: 25), "Home never appeared after sign-in")
        dismissSavePasswordSheetIfPresent()
    }

    private func signOut() {
        dismissSavePasswordSheetIfPresent()
        app.buttons["Profile"].tap()
        if !app.buttons["profile.signOut"].waitForExistence(timeout: 5) {
            app.buttons["Profile"].tap()
        }
        let out = app.buttons["profile.signOut"]
        XCTAssertTrue(out.waitForExistence(timeout: 15), "No sign-out control on Profile")
        out.tap()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 15))
    }

    private func dismissSavePasswordSheetIfPresent() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        for source in [app!, springboard] {
            let notNow = source.buttons["Not Now"]
            if notNow.waitForExistence(timeout: 2) { notNow.tap(); return }
        }
    }
}
