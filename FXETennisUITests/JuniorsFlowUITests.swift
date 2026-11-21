//
//  JuniorsFlowUITests.swift
//  FXETennisUITests
//
//  Juniors phase 1 (decision 0061), driven as a parent drives it: Profile →
//  My Children → Add a Child → the child's page → sign the waiver for them →
//  Request Approval for Elite; and, with no waiver text published (hosted's
//  state until Tara sends hers), the page says so, and the child can be
//  removed.
//
//  The account is Priya (priya@fxe.test), whom no other UI test uses, so her
//  children cannot disturb another test. Each test removes what it made, as
//  service_role, in teardown.
//
//  The junior waiver text below is a LOCAL TEST FIXTURE, published through
//  the local stack's REST API for the length of one test. It is not Tara's
//  text and never reaches hosted: hosted gets hers by a migration (decision
//  0061). Needs TEST_RUNNER_FXE_SUPABASE_SERVICE_KEY, which
//  scripts/run-ui-tests.sh passes; skipped without it, as on CI.
//

import XCTest

final class JuniorsFlowUITests: XCTestCase {
    private let parentEmail = "priya@fxe.test"
    private let parentAccount = "55555555-5555-5555-5555-555555555555"
    private let seedPassword = "password"
    private let fixtureVersion = "uitest-junior-1"

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "-AppleKeyboardsAutocorrection", "0"]
        app.launchEnvironment["UITEST_SIGNED_OUT"] = "1"
        for key in ["FXE_SUPABASE_URL", "FXE_SUPABASE_ANON_KEY"] {
            if let value = ProcessInfo.processInfo.environment[key] { app.launchEnvironment[key] = value }
        }
    }

    override func tearDown() {
        app = nil
        super.tearDown()
    }

    // MARK: - the parent's path

    func testParentAddsAChildSignsTheWaiverAndAsksForElite() throws {
        let stack = try fixture(publishWaiver: true)
        app.launch()
        signIn()
        openMyChildren()
        XCTAssertTrue(app.descendants(matching: .any)["children.empty"].waitForExistence(timeout: 15),
                      "A parent with no children should see the empty line")

        addChild(first: "Sam", last: "Tester", year: "2017")
        let row = app.buttons.matching(identifier: "children.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "The new child was not listed")
        XCTAssertTrue(row.label.contains("Sam Tester"), "Row was '\(row.label)'")
        XCTAssertTrue(row.label.contains("Waiver needed"), "Row was '\(row.label)'")
        XCTAssertEqual(try stack.count("players?account_id=eq.\(parentAccount)&kind=eq.junior&is_active=eq.true"), 1,
                       "the database agrees: one child on Priya's account")

        row.tap()
        let status = app.staticTexts["child.waiverStatus"]
        XCTAssertTrue(status.waitForExistence(timeout: 15), "The child's page did not open")
        XCTAssertEqual(status.label, "Waiver needed")

        // Sign for the child.
        let signButton = app.buttons["child.signWaiver"]
        XCTAssertTrue(signButton.waitForExistence(timeout: 10))
        signButton.tap()
        XCTAssertTrue(app.staticTexts["childWaiver.for"].waitForExistence(timeout: 15), "The waiver did not open")
        XCTAssertEqual(app.staticTexts["childWaiver.for"].label, "For Sam Tester")
        let agree = app.buttons["childWaiver.agree"]
        scrollTo(agree)
        agree.tap()
        let name = app.textFields["childWaiver.name"]
        scrollTo(name)
        name.tap()
        name.typeText("Priya Raman")
        let sign = app.buttons["childWaiver.sign"]
        scrollTo(sign)
        XCTAssertTrue(sign.isEnabled, "Agree and sign stayed disabled with the box ticked and a full name")
        sign.tap()
        XCTAssertTrue(waitForLabel(status, "Waiver signed", timeout: 15), "Status stayed '\(status.label)' after signing")
        XCTAssertEqual(try stack.count("junior_waiver_acceptances?version=eq.\(fixtureVersion)&account_id=eq.\(parentAccount)"), 1,
                       "the database agrees: one signature, by Priya, on the fixture text")

        // Request Approval for Elite (spec 01: Tara approval required).
        let request = app.buttons.matching(identifier: "program.requestApproval")
            .matching(NSPredicate(format: "label == %@", "Request Approval for Elite")).firstMatch
        XCTAssertTrue(request.waitForExistence(timeout: 15), "Elite offered no Request Approval")
        scrollTo(request)
        request.tap()
        let requested = app.staticTexts.matching(identifier: "program.approvalStatus")
            .matching(NSPredicate(format: "label == %@", "Approval requested")).firstMatch
        XCTAssertTrue(requested.waitForExistence(timeout: 15), "No 'Approval requested' after the tap")
        XCTAssertFalse(app.buttons.matching(identifier: "program.requestApproval")
            .matching(NSPredicate(format: "label == %@", "Request Approval for Elite")).firstMatch.exists,
                       "Request Approval stayed after asking")
        XCTAssertEqual(try RawRest(base: stack.base, key: stack.key)
                        .count("program_approvals?requested_by=eq.\(parentAccount)&status=eq.requested", column: "player_id"), 1,
                       "the database agrees: one open request, for Elite")
        // Programs that need no approval offer nothing to ask.
        XCTAssertEqual(app.buttons.matching(identifier: "program.requestApproval").count, 1,
                       "Only Junior Elite should still offer Request Approval")
    }

    /// Hosted's state until Tara's text arrives: no waiver to sign, said
    /// plainly, no button; and Remove child archives the child.
    func testNoWaiverYetSaysSoAndAChildCanBeRemoved() throws {
        let stack = try fixture(publishWaiver: false)
        app.launch()
        signIn()
        openMyChildren()
        addChild(first: "Alex", last: "Tester", year: "2015")

        let row = app.buttons.matching(identifier: "children.row").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "The new child was not listed")
        XCTAssertTrue(row.label.contains("Waiver not available yet"), "Row was '\(row.label)'")
        row.tap()

        XCTAssertTrue(app.staticTexts["child.waiverNotAvailable"].waitForExistence(timeout: 15),
                      "The page did not say the waiver is not available")
        XCTAssertFalse(app.buttons["child.signWaiver"].exists, "A sign button with nothing to sign")

        let remove = app.buttons["child.remove"]
        scrollTo(remove)
        remove.tap()
        // The dialog's button can appear twice in the tree (the sheet and its
        // popover form), so take the first.
        let confirm = app.buttons.matching(identifier: "child.confirmRemove").firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 10), "No confirmation before removing")
        confirm.tap()

        XCTAssertTrue(app.descendants(matching: .any)["children.empty"].waitForExistence(timeout: 15),
                      "The child was still listed after Remove")
        XCTAssertEqual(try stack.count("players?account_id=eq.\(parentAccount)&kind=eq.junior&is_active=eq.true"), 0,
                       "the database agrees: no active child")
        XCTAssertEqual(try stack.count("players?account_id=eq.\(parentAccount)&kind=eq.junior&is_active=eq.false"), 1,
                       "removed means archived, not deleted")
    }

    // MARK: - fixture

    /// Clears Priya's children, and publishes the fixture junior waiver or
    /// makes sure none is current. Everything is put back in teardown.
    private func fixture(publishWaiver: Bool) throws -> ServiceRest {
        guard let key = ProcessInfo.processInfo.environment["FXE_SUPABASE_SERVICE_KEY"], !key.isEmpty else {
            throw XCTSkip("Needs the local stack's service key (TEST_RUNNER_FXE_SUPABASE_SERVICE_KEY)")
        }
        let base = ProcessInfo.processInfo.environment["FXE_SUPABASE_URL"] ?? "http://localhost:54321"
        let stack = ServiceRest(base: base, key: key)
        let raw = RawRest(base: base, key: key)
        let clean: () -> Void = { [parentAccount, fixtureVersion] in
            try? stack.delete("app_settings?key=eq.junior_waiver_version")
            try? stack.delete("junior_waiver_acceptances?account_id=eq.\(parentAccount)")
            try? stack.delete("program_approvals?requested_by=eq.\(parentAccount)")
            try? stack.delete("players?account_id=eq.\(parentAccount)&kind=eq.junior")
            try? stack.delete("waivers?version=eq.\(fixtureVersion)")
        }
        clean()
        addTeardownBlock(clean)
        if publishWaiver {
            try raw.post("waivers", [
                "version": fixtureVersion, "kind": "junior",
                "title": "Test parent and guardian waiver",
                "organizer": "Local test fixture",
                "body": "1  Test\n\nThis local test text stands in for the club's parent and guardian waiver.",
            ])
            try raw.post("app_settings", ["key": "junior_waiver_version", "value": fixtureVersion])
        }
        return stack
    }

    // MARK: - helpers

    private func signIn() {
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 20), "Sign-in screen never appeared")
        email.tap(); email.typeText(parentEmail)
        let pw = app.secureTextFields["auth.password"]
        pw.tap(); pw.typeText(seedPassword)
        app.buttons["auth.submit"].tap()
        dismissSavePasswordSheetIfPresent()
        XCTAssertTrue(app.staticTexts["home.greeting"].waitForExistence(timeout: 20), "Home never appeared")
    }

    private func openMyChildren() {
        let profileTab = app.tabBars.buttons["Profile"].exists ? app.tabBars.buttons["Profile"] : app.buttons["Profile"].firstMatch
        profileTab.tap()
        if !app.buttons["profile.signOut"].waitForExistence(timeout: 5) { profileTab.tap() }
        let link = app.buttons["profile.myChildren"]
        XCTAssertTrue(link.waitForExistence(timeout: 15), "Profile has no My Children")
        scrollTo(link)
        link.tap()
        XCTAssertTrue(app.buttons["children.add"].waitForExistence(timeout: 15), "My Children did not open")
    }

    private func addChild(first: String, last: String, year: String) {
        app.buttons["children.add"].tap()
        let firstField = app.textFields["child.firstName"]
        XCTAssertTrue(firstField.waitForExistence(timeout: 10), "Add a Child did not open")
        firstField.tap(); firstField.typeText(first)
        let lastField = app.textFields["child.lastName"]
        lastField.tap(); lastField.typeText(last)
        // Save waits for a birthday chosen on purpose.
        XCTAssertFalse(app.buttons["child.save"].isEnabled, "Save was on before a birthday was chosen")
        // Month, day, year wheels: set the year.
        let wheels = app.pickerWheels
        XCTAssertTrue(wheels.firstMatch.waitForExistence(timeout: 10), "No birthday wheels")
        wheels.element(boundBy: wheels.count - 1).adjust(toPickerWheelValue: year)
        let save = app.buttons["child.save"]
        XCTAssertTrue(waitForEnabled(save, timeout: 5), "Save stayed off after choosing a birthday")
        save.tap()
        let closed = expectation(for: NSPredicate(format: "exists == false"), evaluatedWith: firstField)
        if XCTWaiter().wait(for: [closed], timeout: 15) != .completed {
            let error = app.staticTexts["child.error"]
            XCTFail("Add a Child did not close: '\(error.exists ? error.label : "no error shown")'")
        }
    }

    private func scrollTo(_ element: XCUIElement) {
        var tries = 0
        while !element.isHittable && tries < 8 {
            app.swipeUp(velocity: .slow)
            tries += 1
        }
    }

    private func waitForLabel(_ element: XCUIElement, _ label: String, timeout: TimeInterval) -> Bool {
        let e = expectation(for: NSPredicate(format: "label == %@", label), evaluatedWith: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval) -> Bool {
        let e = expectation(for: NSPredicate(format: "isEnabled == true"), evaluatedWith: element)
        return XCTWaiter().wait(for: [e], timeout: timeout) == .completed
    }

    private func dismissSavePasswordSheetIfPresent() {
        let notNow = app.buttons["Not Now"]
        if notNow.waitForExistence(timeout: 2) { notNow.tap() }
    }
}

/// A plain POST as service_role, for tables whose key is not `id` (waivers,
/// app_settings), which ServiceRest.insert cannot read back.
private struct RawRest {
    let base: String
    let key: String

    func post(_ table: String, _ fields: [String: Any]) throws {
        var request = URLRequest(url: URL(string: "\(base)/rest/v1/\(table)")!)
        request.httpMethod = "POST"
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: fields)
        var result: Result<Void, Error> = .failure(URLError(.timedOut))
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { result = .failure(error) }
            else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(NSError(domain: "RawRest", code: http.statusCode,
                                          userInfo: [NSLocalizedDescriptionKey: String(data: data ?? Data(), encoding: .utf8) ?? ""]))
            } else { result = .success(()) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 20)
        try result.get()
    }

    /// Rows a filter matches, for tables with no `id` column.
    func count(_ path: String, column: String) throws -> Int {
        var request = URLRequest(url: URL(string: "\(base)/rest/v1/\(path)&select=\(column)")!)
        request.setValue(key, forHTTPHeaderField: "apikey")
        request.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
        var result: Result<Data, Error> = .failure(URLError(.timedOut))
        let done = DispatchSemaphore(value: 0)
        URLSession.shared.dataTask(with: request) { data, response, error in
            if let error { result = .failure(error) }
            else if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
                result = .failure(NSError(domain: "RawRest", code: http.statusCode))
            } else { result = .success(data ?? Data()) }
            done.signal()
        }.resume()
        _ = done.wait(timeout: .now() + 20)
        let rows = try JSONSerialization.jsonObject(with: try result.get()) as? [Any]
        return rows?.count ?? -1
    }
}
