//
//  AdminFlowUITests.swift
//  FXETennisUITests
//
//  Tara's side of the phone, walked against the local stack on a fresh seed.
//  Until 2026-09-02 every XCUITest was a player; the admin tab had none.
//
//  Ordering matters and is encoded in the names (XCTest runs alphabetically):
//  A puts Maria into a clinic and then runs it as Tara; C reads the directory;
//  D cancels the LAST clinic so nothing after it depends on that clinic.
//  Each test signs in on its own; none assumes another passed.
//

import XCTest

final class AdminFlowUITests: XCTestCase {
    private let admin = "tara@fxe.test"
    private let member = "maria@fxe.test"
    private let seedPassword = "password"
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "-AppleKeyboardsAutocorrection", "0"]
        app.launchEnvironment["UITEST_SIGNED_OUT"] = "1"
    }

    // MARK: - A. run a clinic from the phone

    /// Maria registers for the members-only clinic (its public window has not
    /// opened, so a member lands in You're In! rather than the Player Pool —
    /// decision 0001); Tara opens that roster, gives her a court, sends the
    /// unpaid reminder, then marks her paid. Each step is asserted from the
    /// element's own accessibility label, which is built from the database
    /// row after the RPC returns, not from local state.
    func testAdminA_RunsAClinicFromThePhone() {
        app.launch()
        signIn(as: member)
        ensureRegistered(forClinicContaining: "Saturday Members")
        signOut()

        signIn(as: admin)
        openAdminClinic(containing: "Saturday Members")

        // Court: the menu is a button; its items are buttons too.
        let court = app.descendants(matching: .any).matching(identifier: "admin.court").firstMatch
        XCTAssertTrue(court.waitForExistence(timeout: 20),
                      "No court control on the roster row. Identifiers: \(app.descendants(matching: .any).allElementsBoundByIndex.compactMap { $0.identifier.isEmpty ? nil : $0.identifier }.prefix(40)) Texts: \(app.staticTexts.allElementsBoundByIndex.map(\.label).prefix(25))")
        court.tap()
        let court3 = app.buttons["Court 3"]
        XCTAssertTrue(court3.waitForExistence(timeout: 10), "Court menu did not open")
        court3.tap()
        let assigned = NSPredicate(format: "label CONTAINS[c] 'court 3'")
        expectation(for: assigned, evaluatedWith: court)
        waitForExpectations(timeout: 15)

        // Reminder: exists only while someone is unpaid, so it comes before Paid.
        let remind = app.buttons["admin.remindUnpaid"]
        XCTAssertTrue(remind.waitForExistence(timeout: 10), "No Remind unpaid button while a player is unpaid")
        remind.tap()
        let send = app.buttons["Send reminder"]
        XCTAssertTrue(send.waitForExistence(timeout: 10), "No confirmation before messaging several people")
        send.tap()
        XCTAssertTrue(app.staticTexts["admin.remindNote"].waitForExistence(timeout: 15), "No confirmation that the reminder went")

        // Paid.
        let paid = app.buttons["admin.paidToggle"].firstMatch
        XCTAssertTrue(paid.waitForExistence(timeout: 10))
        paid.tap()
        let isPaid = NSPredicate(format: "label CONTAINS[c] ', paid.'")
        expectation(for: isPaid, evaluatedWith: paid)
        waitForExpectations(timeout: 15)

        // And the reminder button is gone, because nobody is unpaid now.
        XCTAssertFalse(app.buttons["admin.remindUnpaid"].waitForExistence(timeout: 3),
                       "Remind unpaid still offered with nobody unpaid")
    }

    // MARK: - B. the Player Pool, Tara's hand-pick, and the answer

    /// Hard rule 2 end to end. Tuesday's public window opened in the seed, so
    /// a member lands in the Player Pool (decision 0001). Nothing promotes
    /// her: Tara invites, and only Maria's own Accept moves her to You're In!.
    func testAdminB_InvitesFromThePoolAndThePlayerAccepts() {
        app.launch()
        signIn(as: member)
        ensureRegistered(forClinicContaining: "Tuesday Ladies")
        signOut()

        signIn(as: admin)
        openAdminClinic(containing: "Tuesday Ladies")
        let invite = app.buttons["admin.invite"].firstMatch
        XCTAssertTrue(invite.waitForExistence(timeout: 20), "Maria is not in the Player Pool to invite")
        invite.tap()
        // She moves to Response Needed; You're In! is unchanged (hard rule 2).
        XCTAssertTrue(app.buttons["admin.cancelInvite"].firstMatch.waitForExistence(timeout: 15),
                      "Invite did not move her to Response Needed")
        XCTAssertFalse(app.buttons["admin.paidToggle"].firstMatch.exists,
                       "Someone is in You're In! after an invite; nothing may auto-promote")
        signOut()

        signIn(as: member)
        let card = app.buttons.matching(identifier: "clinic.card")
            .matching(NSPredicate(format: "label CONTAINS[c] 'Tuesday Ladies'")).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        card.tap()
        // Accept and Decline share the primary-action identifier on this
        // screen, so pick by label as well.
        let accept = app.buttons.matching(identifier: "clinic.primaryAction")
            .matching(NSPredicate(format: "label CONTAINS[c] 'accept'")).firstMatch
        XCTAssertTrue(accept.waitForExistence(timeout: 10), "No Accept on the invitation screen")
        accept.tap()
        let chip = app.descendants(matching: .any).matching(identifier: "clinic.statusChip").firstMatch
        let isIn = NSPredicate(format: "label CONTAINS[c] \"you're in\"")
        expectation(for: isIn, evaluatedWith: chip)
        waitForExpectations(timeout: 20)
    }

    // MARK: - C. the directory

    func testAdminC_DirectoryNoteRoundTrips() {
        app.launch()
        signIn(as: admin)
        app.buttons["Manage"].tap()
        let players = app.buttons["admin.players"]
        XCTAssertTrue(players.waitForExistence(timeout: 20), "No Players entry on Manage")
        players.tap()

        let search = app.searchFields.firstMatch
        XCTAssertTrue(search.waitForExistence(timeout: 10))
        search.tap()
        search.typeText("Mar")

        let row = app.descendants(matching: .any).matching(identifier: "admin.players.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "Search found nobody for 'Mar'")
        row.tap()

        let note = app.textViews["admin.player.note"]
        XCTAssertTrue(note.waitForExistence(timeout: 10), "No note editor on the player page")
        let stamp = "XCUITest \(Int.random(in: 1000...9999))"
        note.tap()
        note.press(forDuration: 1.0)
        if app.menuItems["Select All"].waitForExistence(timeout: 2) { app.menuItems["Select All"].tap() }
        note.typeText(stamp)

        let save = app.buttons["admin.player.saveNote"]
        XCTAssertTrue(save.isEnabled, "Save stayed disabled after typing")
        save.tap()
        XCTAssertTrue(app.staticTexts["Saved."].waitForExistence(timeout: 15), "Note did not report saving")
    }

    // MARK: - D. cancel clinic, last, because it changes the list

    func testAdminD_CancelsAClinicWithConfirmation() {
        app.launch()
        signIn(as: admin)
        app.buttons["Manage"].tap()
        let cards = app.descendants(matching: .any).matching(identifier: "admin.clinic.card")
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 20), "No clinics on Manage")
        let last = cards.element(boundBy: cards.count - 1)
        XCTAssertTrue(scrollUntilHittable(last), "Could not reach the last clinic card")
        last.tap()

        let more = app.buttons["admin.more"]
        XCTAssertTrue(more.waitForExistence(timeout: 10), "No More menu on a live clinic")
        more.tap()
        let cancelItem = app.buttons["Cancel clinic"].firstMatch
        XCTAssertTrue(cancelItem.waitForExistence(timeout: 10))
        cancelItem.tap()

        // The confirmation reuses the same words; it is the second "Cancel
        // clinic" on screen and it sits inside the dialog.
        let confirm = app.buttons["Cancel clinic"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "No confirmation dialog")
        confirm.tap()

        // Back on the list, which reloaded, with a Canceled chip somewhere.
        XCTAssertTrue(app.staticTexts["Canceled"].firstMatch.waitForExistence(timeout: 20),
                      "List did not show a Canceled chip after cancel")
    }

    // MARK: - helpers (mirrors PlayerFlowUITests; kept local so each file reads alone)

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
        let out = app.buttons["profile.signOut"]
        XCTAssertTrue(out.waitForExistence(timeout: 10), "No sign-out control on Profile")
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

    /// Register for the first card on Home if not already in it. Idempotent
    /// across runs: a second run finds "Cancel" as the primary action and
    /// leaves it alone.
    private func ensureRegistered(forClinicContaining name: String) {
        let card = app.buttons.matching(identifier: "clinic.card")
            .matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "No Home card for \(name)")
        card.tap()
        let action = app.buttons["clinic.primaryAction"]
        XCTAssertTrue(action.waitForExistence(timeout: 10))
        if action.label.localizedCaseInsensitiveContains("register") {
            action.tap()
            let changed = NSPredicate(format: "NOT (label CONTAINS[c] 'register')")
            expectation(for: changed, evaluatedWith: action)
            waitForExpectations(timeout: 20)
        }
        app.navigationBars.buttons.element(boundBy: 0).tap()
    }

    private func openAdminClinic(containing name: String) {
        app.buttons["Manage"].tap()
        let card = app.descendants(matching: .any).matching(identifier: "admin.clinic.card")
            .matching(NSPredicate(format: "label CONTAINS[c] %@", name)).firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 20), "No Manage card for \(name)")
        XCTAssertTrue(scrollUntilHittable(card))
        card.tap()
    }

    private func scrollUntilHittable(_ element: XCUIElement, maxSwipes: Int = 6) -> Bool {
        guard element.waitForExistence(timeout: 10) else { return false }
        for _ in 0..<maxSwipes {
            if element.isHittable { return true }
            app.swipeUp()
        }
        return element.isHittable
    }
}
