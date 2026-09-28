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
        // The logo keeps its size under Larger Text on purpose: it sits in a
        // header of fixed height (Brand.Typography.Role.wordmarkCompact). The
        // audit reaches its "TENNIS" text even inside the one logo element.
        if issue.auditType == .dynamicType,
           e.identifier == "brand.wordmark" || e.label == "TENNIS" { return true }
        // Bar buttons are the system's: iOS 26 draws them as glass capsules,
        // and they stop growing at a cap (a long press shows the large-content
        // viewer instead). The audit samples the capsule's edge and shadow:
        // measured from pixels on 2026-09-28, navy Cancel and Save on the
        // capsule are 16.4:1. So in a navigation bar we accept contrast and
        // "partially" unsupported Dynamic Type, and nothing else.
        if issue.auditType == .contrast || issue.compactDescription.contains("partially"),
           isInNavigationBar(e) { return true }
        // The same is true of the strip under the floating tab bar for
        // "partially" unsupported text: a week header or a clinic's time
        // down there is flagged, the identical one higher up passes.
        if issue.compactDescription.contains("partially"), screen != "sign-in",
           e.frame.maxY > app.frame.height - 150 { return true }
        // A second week header lower in the Clinics list: the audit grows the
        // text and the header scrolls out of view before the largest sizes,
        // so it can only check some of them. The first header, the same view,
        // passes every size.
        if issue.compactDescription.contains("partially"), e.identifier == "clinics.week",
           e.frame.minY > app.frame.height / 2 { return true }
        // The system search field's placeholder, not ours to lay out.
        if issue.auditType == .textClipped, e.elementType == .searchField { return true }
        // An email address is not "human-readable" to the audit, and it is
        // exactly what the person typed.
        if issue.auditType == .sufficientElementDescription, e.label.contains("@") { return true }
        return false
    }

    private func isInNavigationBar(_ e: XCUIElement) -> Bool {
        let centre = CGPoint(x: e.frame.midX, y: e.frame.midY)
        return app.navigationBars.allElementsBoundByIndex.contains { $0.frame.contains(centre) }
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

        // Home. Wait for the greeting, not just the tab: the first run of
        // this test audited Home mid-transition and reported nothing at all.
        XCTAssertTrue(app.staticTexts["home.greeting"].waitForExistence(timeout: 20))
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

        // My Clinics, from Profile
        let myClinics = app.buttons["profile.myClinics"]
        if myClinics.waitForExistence(timeout: 5) {
            myClinics.tap(); sleep(2)
            audit("my clinics")
            app.navigationBars.buttons.firstMatch.tap()
        }

        // Edit details
        let edit = app.buttons["profile.edit"]
        if edit.waitForExistence(timeout: 5) {
            edit.tap(); sleep(2)
            audit("edit details")
            app.swipeDown(velocity: .fast)
        }

        // The bell, from Home
        let home = app.tabBars.buttons["Home"].exists ? app.tabBars.buttons["Home"] : app.buttons["Home"].firstMatch
        home.tap()
        let bell = app.buttons["home.bell"]
        if bell.waitForExistence(timeout: 10) {
            bell.tap(); sleep(2)
            audit("notifications")
            if app.buttons["notifications.done"].exists { app.buttons["notifications.done"].tap() }
        }
    }

    /// The brightest and darkest pixel (as r+g+b) where the status bar's
    /// clock sits: the top left of the screen on every iPhone with a
    /// Dynamic Island.
    private func clockPixels() -> (brightest: Int, darkest: Int) {
        guard let cg = XCUIScreen.main.screenshot().image.cgImage else { return (0, 0) }
        let w = cg.width, h = cg.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let drew: Void? = data.withUnsafeMutableBytes { buf in
            CGContext(data: buf.baseAddress, width: w, height: h, bitsPerComponent: 8,
                      bytesPerRow: w * 4, space: CGColorSpaceCreateDeviceRGB(),
                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)?
                .draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        guard drew != nil else { return (0, 0) }
        var hi = 0, lo = 765
        for y in Int(Double(h) * 0.02)..<Int(Double(h) * 0.05) {
            for x in Int(Double(w) * 0.10)..<Int(Double(w) * 0.25) {
                let i = (y * w + x) * 4
                let sum = Int(data[i]) + Int(data[i + 1]) + Int(data[i + 2])
                hi = max(hi, sum); lo = min(lo, sum)
            }
        }
        return (hi, lo)
    }

    /// The clock was black on the navy headers until 2026-09-28: the root
    /// view's .preferredColorScheme(.light) pinned the status bar dark. Navy
    /// is at most 98 as r+g+b, so white glyphs are the only way past 600.
    func testStatusBarIsReadableOverNavy() {
        app.launch()
        XCTAssertTrue(app.textFields["auth.email"].waitForExistence(timeout: 20))
        sleep(1)
        XCTAssertGreaterThan(clockPixels().brightest, 600, "sign-in: the clock should be white on navy")

        let email = app.textFields["auth.email"]
        email.tap(); email.typeText(memberEmail)
        let pw = app.secureTextFields["auth.password"]
        pw.tap(); pw.typeText(seedPassword)
        app.buttons["auth.submit"].tap()
        XCTAssertTrue(app.staticTexts["home.greeting"].waitForExistence(timeout: 20))
        sleep(1)
        XCTAssertGreaterThan(clockPixels().brightest, 600, "Home: the clock should be white on navy")

        // And dark again where the top is light, or it would vanish there.
        let profileTab = app.tabBars.buttons["Profile"].exists ? app.tabBars.buttons["Profile"] : app.buttons["Profile"].firstMatch
        profileTab.tap()
        if !app.buttons["profile.signOut"].waitForExistence(timeout: 5) { profileTab.tap() }
        XCTAssertTrue(app.buttons["profile.signOut"].waitForExistence(timeout: 15))
        sleep(1)
        XCTAssertLessThan(clockPixels().darkest, 60, "Profile: the clock should be dark on the light top")
    }

    func testTarasScreensPassTheAudit() {
        app.launch()
        let email = app.textFields["auth.email"]
        XCTAssertTrue(email.waitForExistence(timeout: 20))
        email.tap(); email.typeText("tara@fxe.test")
        let pw = app.secureTextFields["auth.password"]
        pw.tap(); pw.typeText(seedPassword)
        app.buttons["auth.submit"].tap()

        // Her Home first (an admin has no player row, so it is not the
        // player's Home: no My Clinics, her own greeting).
        XCTAssertTrue(app.staticTexts["home.greeting"].waitForExistence(timeout: 20))
        sleep(2)
        audit("tara home")

        // The iOS 26 simulator's tab bar drops the first tap now and then
        // (openProfileTab in PlayerFlowUITests); tap again if nothing moved.
        let manage = app.buttons["Manage"]
        XCTAssertTrue(manage.waitForExistence(timeout: 20))
        manage.tap()
        let cards = app.descendants(matching: .any).matching(identifier: "admin.clinic.card")
        if !cards.firstMatch.waitForExistence(timeout: 5) { manage.tap() }
        XCTAssertTrue(cards.firstMatch.waitForExistence(timeout: 20))
        sleep(1)
        audit("manage")

        cards.firstMatch.tap(); sleep(2)
        audit("roster")
        app.navigationBars.buttons.firstMatch.tap()

        let players = app.buttons["admin.players"]
        if players.waitForExistence(timeout: 10) {
            players.tap(); sleep(2)
            audit("players")
        }
    }
}
