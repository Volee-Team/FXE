//
//  PureLogicTests.swift
//  FXETennisTests
//
//  WHY THIS FILE EXISTS
//  --------------------
//  Until 2026-08-13 `FXETennisTests/` contained ZERO files. Two consequences,
//  and the second is worse than the first:
//
//  1. No Swift logic was covered by anything.
//  2. `project.yml` declares the target and the shared scheme lists it as a
//     Testable, so a target with no sources built an .xctest bundle with no
//     executable. Every `xcodebuild test` therefore died with
//     "The bundle FXETennisTests couldn't be loaded because its executable
//     couldn't be located" and exit 65 — even when the UI tests themselves
//     passed. The test action could not exit 0 under any circumstances.
//     `build-for-testing` alone still printed SUCCEEDED, which is why nobody
//     noticed. An empty directory also broke `xcodegen generate` on a fresh
//     clone, so a second developer could not open the project at all.
//
//  So the first job of this file is to exist. The second is to pin the pure
//  logic that has no other net: these functions are called by views, and the
//  SQL probes cannot see them.
//
//  Scope: pure, synchronous, dependency-free logic ONLY. Anything needing the
//  database belongs in tests/sql/, which is a better tool for it.
//

import XCTest
@testable import FXETennis

final class PriceFormattingTests: XCTestCase {

    /// Tara writes her prices as whole dollars, so 1800 must read "$18" and not
    /// "$18.00". The `.00` suffix is the thing this property exists to remove.
    func testWholeDollarsDropTheDecimals() {
        XCTAssertEqual(1800.centsAsPrice, "$18")
        XCTAssertEqual(2500.centsAsPrice, "$25")
        XCTAssertEqual(100.centsAsPrice, "$1")
    }

    func testNonWholeDollarsKeepTwoDecimals() {
        XCTAssertEqual(1850.centsAsPrice, "$18.50")
        XCTAssertEqual(1899.centsAsPrice, "$18.99")
        XCTAssertEqual(105.centsAsPrice, "$1.05")
    }

    /// A free clinic is a real case: Tara runs them. It must not render as ""
    /// or crash, and "$0" is the correct reading.
    func testZeroIsFree() {
        XCTAssertEqual(0.centsAsPrice, "$0")
    }

    /// Guard against the classic float-formatting slip where a value that is
    /// exactly representable still prints a trailing .00 or drops a cent.
    func testRoundTripAcrossTheRealisticRange() {
        for cents in stride(from: 0, through: 20_000, by: 25) {
            let text = cents.centsAsPrice
            XCTAssertTrue(text.hasPrefix("$"), "\(cents) rendered as \(text)")
            let hasDecimals = text.contains(".")
            XCTAssertEqual(
                hasDecimals, cents % 100 != 0,
                "\(cents) rendered as \(text): decimals should appear only for non-whole dollars"
            )
        }
    }
}

final class ClinicPricingTests: XCTestCase {

    private func clinic(member: Int?, nonmember: Int?) -> ClinicPublic {
        ClinicPublic(
            id: UUID(),
            name: "Tuesday Ladies 3.0+",
            audience: "ladies",
            category: nil,
            description: nil,
            startsAt: Date(),
            endsAt: Date().addingTimeInterval(3600),
            memberOpensAt: nil,
            publicOpensAt: nil,
            closesAt: nil,
            status: "published",
            canceledAt: nil,
            memberPriceCents: member,
            nonmemberPriceCents: nonmember,
            durationMinutes: 60
        )
    }

    /// The whole point of carrying both rates on the row: the client picks, so
    /// a member and a non-member looking at the same clinic see different money.
    func testMemberAndNonMemberSeeDifferentPrices() {
        let c = clinic(member: 1800, nonmember: 2500)
        XCTAssertEqual(c.priceCents(forMember: true), 1800)
        XCTAssertEqual(c.priceCents(forMember: false), 2500)
    }

    /// Membership is unknown before a profile exists. Today the call sites use
    /// `?? false`, which means an unknown viewer is quoted the NON-member rate.
    /// Quoting the higher price to someone whose status we do not know is the
    /// safe direction to be wrong: it is correctable at the desk, whereas
    /// under-quoting is a refund conversation.
    func testUnknownMembershipFallsBackToTheNonMemberRate() {
        let c = clinic(member: 1800, nonmember: 2500)
        let unknownMembership: Bool? = nil
        XCTAssertEqual(c.priceCents(forMember: unknownMembership ?? false), 2500)
    }

    /// A clinic with no price set must return nil rather than 0, because the UI
    /// distinguishes "free" from "no price yet" and "$0" is a claim.
    func testMissingPriceIsNilNotZero() {
        let c = clinic(member: nil, nonmember: nil)
        XCTAssertNil(c.priceCents(forMember: true))
        XCTAssertNil(c.priceCents(forMember: false))
    }
}

final class NTRPRatingTests: XCTestCase {

    /// 5.0 is the ceiling BUCKET, not the top of the scale. A verified USTA 5.5
    /// is a real person who must land on a row instead of falling off the end.
    func testAboveFivePointZeroCollapsesIntoTheCeiling() {
        XCTAssertEqual(NTRPRating(rating: 5.0), .level5_0Plus)
        XCTAssertEqual(NTRPRating(rating: 5.5), .level5_0Plus)
        XCTAssertEqual(NTRPRating(rating: 7.0), .level5_0Plus)
    }

    /// A continuous rating floors to the nearest half point: 3.7 is a 3.5
    /// player, never a 4.0 one. Rounding up would put someone in a clinic
    /// above their level, which is a court-safety problem, not a display bug.
    func testContinuousRatingsFloorToTheHalfPoint() {
        XCTAssertEqual(NTRPRating(rating: 3.5), .level3_5)
        XCTAssertEqual(NTRPRating(rating: 3.7), .level3_5)
        XCTAssertEqual(NTRPRating(rating: 3.99), .level3_5)
        XCTAssertEqual(NTRPRating(rating: 4.0), .level4_0)
    }

    /// The scale does not go below 2.0 here, so anything lower is absent rather
    /// than clamped. Clamping would silently invent a rating for a player who
    /// never gave one.
    func testBelowTwoPointZeroIsNil() {
        XCTAssertNil(NTRPRating(rating: 1.9))
        XCTAssertNil(NTRPRating(rating: 0))
        XCTAssertNil(NTRPRating(rating: -1))
    }

    /// Every level must survive a round trip through its own raw value, or a
    /// rating stored by Volee would come back as a different bucket here.
    func testEveryLevelRoundTripsThroughItsRawValue() {
        for level in NTRPRating.allCases {
            XCTAssertEqual(
                NTRPRating(rating: level.rawValue), level,
                "\(level) did not round-trip"
            )
        }
    }

    /// Only the ceiling carries the "+". This is copy Tara reads, and the
    /// suffix appearing on 3.5 would misstate a player's level.
    func testOnlyTheCeilingGetsAPlusSuffix() {
        XCTAssertEqual(NTRPRating.level3_5.label, "3.5")
        XCTAssertEqual(NTRPRating.level5_0Plus.label, "5.0+")
        XCTAssertEqual(NTRPRating.level3_5.displayName, "USTA 3.5")

        for level in NTRPRating.allCases where level != .level5_0Plus {
            XCTAssertFalse(
                level.label.contains("+"),
                "\(level) should not carry the ceiling suffix"
            )
        }
    }

    /// `displayOrdered` is what the "?" explainer renders. It must be complete
    /// and ascending: a missing row means a level a player cannot pick.
    func testDisplayOrderIsCompleteAndAscending() {
        let ordered = NTRPRating.displayOrdered
        XCTAssertEqual(ordered.count, NTRPRating.allCases.count)
        XCTAssertEqual(ordered, ordered.sorted())
        XCTAssertEqual(ordered.first, .level2_0)
        XCTAssertEqual(ordered.last, .level5_0Plus)
    }
}
