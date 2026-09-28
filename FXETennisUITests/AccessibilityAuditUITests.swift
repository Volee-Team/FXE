//
//  AccessibilityAuditUITests.swift
//  FXETennisUITests
//
//  Apple's own accessibility audit (XCUIApplication.performAccessibilityAudit,
//  iOS 17+) run on every main screen a player sees: missing labels, tap
//  targets too small, text clipped at larger sizes, contrast, Dynamic Type.
//  Added 2026-09-28: the launch checklist listed "accessibility pass" as a
//  missing kind of testing, and CLAUDE.md promises large text, generous tap
//  areas and never colour alone. This makes those promises a test.
//
//  Known, recorded exceptions are filtered by `isAccepted`, each with the
//  reason; anything else fails the test and prints the element.
//

import XCTest

final class AccessibilityAuditUITests: XCTestCase {

    private let memberEmail = "maria@fxe.test"
    private let seedPassword = "password"
    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = true
        app = XCUIApplication()
        app.launchArguments += ["-UITestMode", "-AppleKeyboardsAutocorrection", "0"]
        app.launchEnvironment["UITEST_SIGNED_OUT"] = "1"
        for key in ["FXE_SUPABASE_URL", "FXE_SUPABASE_ANON_KEY"] {
            if let value = ProcessInfo.processInfo.environment[key] { app.launchEnvironment[key] = value }
        }
    }

    override func tearDown() { app = nil }

    /// Issues we accept on purpose, with why. Keep this list short and
    /// explained; an unexplained exception is a bug with a sticker on it.
    private func isAccepted(_ issue: XCUIAccessibilityAuditIssue, screen: String) -> Bool {
        guard let e = issue.element else {
            // Nothing to attribute it to (system-drawn, e.g. inside the status
            // bar or the floating tab bar's glass): not ours to fix.
            return true
        }
        // iOS 26 fades scrolling content under the floating tab bar (the
        // scroll-edge effect). Text caught in that strip measures low
        // contrast mid-fade and reads normally once scrolled up. System
        // behaviour, and the same content passes above the strip.
        if issue.auditType == .contrast, screen != "sign-in",
           e.frame.maxY > app.frame.height - 150 { return true }
        // The quiet text links carry the full 44-point tap frame (the
        // QuietLinkButtonStyle fix for "hit area too small"), and the audit
        // samples that whole frame, court photo and its white lines included,
        // around small text. Measured from simulator pixels on 2026-09-28 with
        // scripts/measure-contrast.py (navy glyphs against the median
        // background inside the frame): Create an account 11.8:1, Forgot
        // password? 11.5:1, Sign Out 12.7:1. The minimum is 4.5:1.
        if issue.auditType == .contrast,
           ["auth.toggleMode", "auth.forgot", "profile.signOut"].contains(e.identifier) { return true }
        // An email address is not "human-readable" to the audit, and it is
        // exactly what the person typed.
        if issue.auditType == .sufficientElementDescription, e.label.contains("@") { return true }
        return false
    }

    private func audit(_ screen: String) {
        do {
            try app.performAccessibilityAudit { issue in
                if self.isAccepted(issue, screen: screen) { return true }
                let e = issue.element
                print("A11Y [\(screen)] \(issue.auditType) :: \(issue.compactDescription) :: \(issue.detailedDescription) :: frame=\(e?.frame ?? .zero) :: id='\(e?.identifier ?? "")' label='\(e?.label ?? "")' type=\(e?.elementType.rawValue ?? 0)")
                return false
            }
        } catch {
            XCTFail("Accessibility audit on \(screen) failed: \(error)")
        }
    }

    func testEveryPlayerScreenPassesTheAudit() {
        app.launch()
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 20))
        audit("sign-in")

        email.tap(); email.typeText(memberEmail)
        let pw = app.secureTextFields["auth.password"]
        pw.tap(); pw.typeText(seedPassword)
        app.buttons["auth.submit"].tap()

        // Home
        XCTAssertTrue(app.tabBars.buttons["Home"].waitForExistence(timeout: 20) || app.buttons["Home"].waitForExistence(timeout: 5))
        sleep(2)
        audit("home")

        // Clinics
        let clinicsTab = app.tabBars.buttons["Clinics"].exists ? app.tabBars.buttons["Clinics"] : app.buttons["Clinics"].firstMatch
        clinicsTab.tap()
        let card = app.buttons.matching(identifier: "clinic.card").firstMatch
        if !card.waitForExistence(timeout: 5) { clinicsTab.tap() }
        XCTAssertTrue(card.waitForExistence(timeout: 20))
        audit("clinics")

        // A clinic
        card.tap()
        sleep(2)
        audit("clinic detail")
        app.navigationBars.buttons.firstMatch.tap()

        // Profile
        let profileTab = app.tabBars.buttons["Profile"].exists ? app.tabBars.buttons["Profile"] : app.buttons["Profile"].firstMatch
        profileTab.tap()
        if !app.buttons["profile.signOut"].waitForExistence(timeout: 5) { profileTab.tap() }
        XCTAssertTrue(app.buttons["profile.signOut"].waitForExistence(timeout: 15))
        audit("profile")
    }
}
