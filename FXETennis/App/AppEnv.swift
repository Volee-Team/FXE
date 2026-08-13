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
