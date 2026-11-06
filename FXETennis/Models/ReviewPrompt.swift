//
//  ReviewPrompt.swift
//  FXETennis
//
//  Apple's own star-rating popup (SKStoreReviewController through SwiftUI's
//  `requestReview`), asked at a happy moment: right after a player lands in
//  You're In! for the second time or later, and at most once per app version.
//  Never on first launch, never after an error, never after the Waitlist.
//  Apple shows it at most three times a year per person whatever we ask.
//
//  John, 2026-11-05. App Review Guideline 5.6.1: only Apple's prompt, no
//  incentive and no "do you like the app?" screen in front of it.
//

import Foundation

enum ReviewPrompt {
    /// "You're In!" landings before the first ask.
    static let landingsBeforeAsking = 2

    static let countKey = "reviewPrompt.youreInCount"
    static let askedVersionKey = "reviewPrompt.askedVersion"

    /// Pure: whether this landing should ask.
    static func shouldAsk(youreInCount: Int, lastAskedVersion: String?, currentVersion: String) -> Bool {
        youreInCount >= landingsBeforeAsking && lastAskedVersion != currentVersion
    }

    static var currentVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0"
        let build = info?["CFBundleVersion"] as? String ?? "0"
        return "\(short) (\(build))"
    }

    /// Counts one landing in You're In! and answers whether to ask now. When
    /// it says yes it records the version, so the next landing does not ask.
    static func recordYoureIn(defaults: UserDefaults = .standard, version: String = currentVersion) -> Bool {
        let count = defaults.integer(forKey: countKey) + 1
        defaults.set(count, forKey: countKey)
        guard shouldAsk(youreInCount: count,
                        lastAskedVersion: defaults.string(forKey: askedVersionKey),
                        currentVersion: version) else { return false }
        defaults.set(version, forKey: askedVersionKey)
        return true
    }
}
