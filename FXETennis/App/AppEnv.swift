//
//  AppEnv.swift
//  FXETennis
//
//  Environment facts the app needs to behave differently under automation.
//  Kept in one place so "are we in a test?" is never re-derived ad hoc.
//

import Foundation

enum AppEnv {
    /// True when driven by XCUITest. Set from the test target's launch
    /// environment; never true for a human running the app.
    static let isUITesting = ProcessInfo.processInfo.environment["UITEST_SIGNED_OUT"] == "1"
}

extension AppEnv {
    /// Where "Forgot password?" links land. One page serves both clients; it
    /// lives beside the web admin. Debug points at the locally served copy so
    /// the whole flow can be exercised against Mailpit.
    static var passwordResetURL: URL {
        #if DEBUG
        return URL(string: "http://localhost:8765/reset.html")!
        #else
        return URL(string: "https://fxe-tennis-admin.vercel.app/reset.html")!
        #endif
    }
}
