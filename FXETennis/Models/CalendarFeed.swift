//
//  CalendarFeed.swift
//  FXETennis
//
//  "Subscribe in Calendar" on Profile (decision 0029): the account's clinics
//  as a calendar the phone re-reads on its own, so a clinic Tara moves or
//  cancels is right without anyone doing anything. Add to Calendar (decision
//  0023) stays for one clinic at a time.
//
//  The server hands out only the token (my_calendar_feed_token); the app
//  knows its own project URL and builds the link. webcal:// is the scheme
//  iOS gives to Calendar, which then asks "Subscribe to calendar?" itself.
//  Google and Outlook take the same address with https:// pasted in.
//
//  Pure and unit-tested (CalendarFeedTests).
//

import Foundation

enum CalendarFeed {
    /// The edge function's address under a project URL.
    static func functionURL(projectURL: URL) -> URL {
        projectURL.appendingPathComponent("functions/v1/calendar-feed")
    }

    /// webcal://<host>[:port]/functions/v1/calendar-feed?t=<token>. Nil for
    /// anything but the 64 lowercase hex characters the server makes, so a
    /// garbled answer never becomes a link iOS subscribes to.
    static func webcalURL(functionURL: URL, token: String) -> URL? {
        guard token.count == 64,
              token.allSatisfy({ ("0"..."9").contains($0) || ("a"..."f").contains($0) }),
              var parts = URLComponents(url: functionURL, resolvingAgainstBaseURL: false),
              parts.scheme == "https" || parts.scheme == "http"
        else { return nil }
        parts.scheme = "webcal"
        parts.queryItems = [URLQueryItem(name: "t", value: token)]
        return parts.url
    }

    /// Shown under the button when the server refused or answered oddly;
    /// no signal and too many attempts use RequestFailure's own lines.
    static let failedLine = "Couldn't load your calendar link."
}
