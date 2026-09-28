//
//  BrandTypeScaleTests.swift
//  FXETennisTests
//
//  The rule (MVP audit item 16; CLAUDE.md "Large text ... for outdoor use"):
//  every text style grows with the iPhone's Larger Text setting, and at the
//  default setting every size is exactly Kat's (docs/style-guide.md). The
//  logo is the one exception and keeps its size.
//
//  Expected numbers are Kat's sizes, and Apple's UIFontMetrics curve for the
//  Body style, which is the curve the rule names. Measured once on the iOS
//  26.2 simulator for Body's own default size: 17 points at the default
//  (Large) is 14.67 at Extra Small and 48 at the largest accessibility size
//  (AX5). Kat's body is 15, so on that curve it is 15 x 14.67 / 17 = 12.9 at
//  the smallest and 15 x 48 / 17 = 42.4 at the largest.
//
//  The first draft of this test took its numbers from Apple's table of the
//  system Body FONT (14 and 53) and failed at 13.0 and 42.3: UIFontMetrics
//  scales a custom font along a gentler curve than the system fonts' own
//  sizes. The failure was the test's assumption, not the code's, and it is
//  recorded because the wrong table is the one everyone quotes.
//

import XCTest
import CoreText
@testable import FXETennis

final class BrandTypeScaleTests: XCTestCase {
    private typealias Role = Brand.Typography.Role

    private func traits(_ category: UIContentSizeCategory) -> UITraitCollection {
        UITraitCollection(preferredContentSizeCategory: category)
    }

    func testKatsSizesAtTheDefaultSetting() {
        let kat: [Role: CGFloat] = [
            .greeting: 34, .greetingAccent: 23, .wordmarkInitial: 56, .wordmarkLockup: 22,
            .navRowLabel: 19, .tabBarLabel: 12, .body: 15, .title: 22, .headline: 17,
            .bodyEmphasis: 15, .subheadline: 13, .caption: 12, .chip: 12, .wordmarkCompact: 12,
        ]
        XCTAssertEqual(Set(kat.keys), Set(Role.allCases), "Every style in the scale has a stated size")
        for role in Role.allCases {
            XCTAssertEqual(role.uiFont(traits: traits(.large)).pointSize, kat[role]!, accuracy: 0.01,
                           "\(role) at the default setting")
        }
    }

    func testBodyFollowsTheBodyCurve() {
        XCTAssertEqual(Role.body.uiFont(traits: traits(.accessibilityExtraExtraExtraLarge)).pointSize,
                       15 * 48 / 17, accuracy: 0.5)
        XCTAssertEqual(Role.body.uiFont(traits: traits(.extraSmall)).pointSize,
                       15 * 14.67 / 17, accuracy: 0.5)
    }

    func testEveryTextStyleGrowsWithLargerText() {
        for role in Role.allCases where role.textStyle != nil {
            let largest = role.uiFont(traits: traits(.accessibilityExtraExtraExtraLarge)).pointSize
            XCTAssertGreaterThan(largest, role.size * 1.5,
                                 "\(role) must grow with Larger Text; it is \(largest) at the largest size")
        }
    }

    func testTheWaiverCardSentenceAndErrorsGrow() {
        // The three the audit named: the waiver (body), the card sentence and
        // error lines (caption), read outdoors by older members.
        for role in [Role.body, .caption, .subheadline] {
            XCTAssertGreaterThan(role.uiFont(traits: traits(.accessibilityLarge)).pointSize,
                                 role.uiFont(traits: traits(.large)).pointSize, "\(role)")
        }
    }

    func testTheLogoKeepsItsSize() {
        for role in [Role.wordmarkInitial, .wordmarkLockup, .wordmarkCompact] {
            XCTAssertEqual(role.uiFont(traits: traits(.accessibilityExtraExtraExtraLarge)).pointSize,
                           role.size, accuracy: 0.01, "\(role) is part of the mark")
        }
    }

    func testKatsFacesAndWeightsSurviveScaling() {
        let font = Role.bodyEmphasis.uiFont(traits: traits(.accessibilityExtraExtraExtraLarge))
        // CoreText names a variation instance after its axes
        // ("Inter-Regular_opsz…_wght…"), so the family is what to check.
        XCTAssertEqual(font.familyName, "Inter", "Inter is registered and used, not a fallback")
        let axes = CTFontCopyVariation(font as CTFont) as? [NSNumber: NSNumber] ?? [:]
        XCTAssertEqual(axes[NSNumber(value: Brand.Fonts.wghtAxis)]?.doubleValue ?? 0, 600, accuracy: 0.5,
                       "bodyEmphasis stays semibold at every size")
        // Inter's optical size follows the drawn size (its axis tops out at 32).
        XCTAssertEqual(axes[NSNumber(value: Brand.Fonts.opszAxis)]?.doubleValue ?? 0, 32, accuracy: 0.5)
    }

    func testWithNoTraitsTheAppsOwnSettingIsUsed() {
        // What the screens get: the app's current Larger Text setting.
        let current = UIApplication.shared.preferredContentSizeCategory
        XCTAssertEqual(Role.body.uiFont().pointSize,
                       Role.body.uiFont(traits: traits(current)).pointSize, accuracy: 0.01,
                       "Scaled for \(current.rawValue)")
    }
}
