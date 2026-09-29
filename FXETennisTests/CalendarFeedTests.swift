//
//  CalendarFeedTests.swift
//  FXETennisTests
//
//  "Subscribe in Calendar" (decision 0029). The rules, written from the
//  decision, not the code:
//    * the link is the calendar-feed function's address with the scheme
//      swapped for webcal (so iOS hands it to Calendar) and the token as t;
//    * the host and port are kept (hosted, and the local stack in Debug);
//    * only the server's shape of token (64 lowercase hex) becomes a link.
//

import XCTest
@testable import FXETennis

final class CalendarFeedTests: XCTestCase {
    private let token = String(repeating: "0123456789abcdef", count: 4)

    func testTheHostedLinkIsWebcalWithTheToken() {
        let function = CalendarFeed.functionURL(projectURL: URL(string: "https://amnaxvznkadkgzdxzegw.supabase.co")!)
        XCTAssertEqual(function.absoluteString, "https://amnaxvznkadkgzdxzegw.supabase.co/functions/v1/calendar-feed")
        XCTAssertEqual(CalendarFeed.webcalURL(functionURL: function, token: token)?.absoluteString,
                       "webcal://amnaxvznkadkgzdxzegw.supabase.co/functions/v1/calendar-feed?t=\(token)")
    }

    func testTheLocalStackKeepsItsPort() {
        let function = CalendarFeed.functionURL(projectURL: URL(string: "http://localhost:54321")!)
        XCTAssertEqual(CalendarFeed.webcalURL(functionURL: function, token: token)?.absoluteString,
                       "webcal://localhost:54321/functions/v1/calendar-feed?t=\(token)")
    }

    func testOnlyTheServersShapeOfTokenBecomesALink() {
        let function = URL(string: "https://example.supabase.co/functions/v1/calendar-feed")!
        XCTAssertNil(CalendarFeed.webcalURL(functionURL: function, token: ""))
        XCTAssertNil(CalendarFeed.webcalURL(functionURL: function, token: String(token.dropLast())))
        XCTAssertNil(CalendarFeed.webcalURL(functionURL: function, token: token + "0"))
        XCTAssertNil(CalendarFeed.webcalURL(functionURL: function, token: token.uppercased()))
        XCTAssertNil(CalendarFeed.webcalURL(functionURL: function, token: "\"" + token.dropFirst(2) + "\""),
                     "a JSON string that was never decoded")
        XCTAssertNil(CalendarFeed.webcalURL(functionURL: function, token: String(token.dropLast()) + "&"))
    }

    func testAnExistingQueryIsReplacedNotDoubled() {
        let function = URL(string: "https://example.supabase.co/functions/v1/calendar-feed?t=old")!
        XCTAssertEqual(CalendarFeed.webcalURL(functionURL: function, token: token)?.absoluteString,
                       "webcal://example.supabase.co/functions/v1/calendar-feed?t=\(token)")
    }
}
