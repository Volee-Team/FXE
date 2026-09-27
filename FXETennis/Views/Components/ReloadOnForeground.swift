//
//  ReloadOnForeground.swift
//  FXETennis
//
//  Screens reload when the app comes back to the front (MVP audit item 8,
//  2026-09-27). Every screen used to load only on first appearance and on
//  pull-to-refresh, and iOS keeps a backgrounded app suspended for hours, so
//  a resumed app showed yesterday's Home and bell count. Until push is live,
//  opening the app is how a Player Pool player learns Tara invited her; and
//  Tara's Manage tab missed late requests the same way.
//
//  At most once per 30 seconds, so flicking between apps does not refetch
//  every screen each time. A screen's first appearance counts as a load,
//  since its own `.task` loads then.
//

import SwiftUI

/// Whether coming back to the app should reload: yes, unless the last load
/// was less than `interval` seconds ago.
struct ReloadThrottle {
    let interval: TimeInterval
    private(set) var lastLoad: Date?

    init(interval: TimeInterval = 30) {
        self.interval = interval
    }

    /// A load happened (first appearance, pull to refresh, a sign-in).
    mutating func recordLoad(at now: Date = .now) {
        lastLoad = now
    }

    /// True when a reload is due, and records it: no load yet, the last one
    /// at least `interval` ago, or the last one "in the future" because the
    /// phone's clock was set back (otherwise reloads would stop until the
    /// clock caught up).
    mutating func shouldReload(at now: Date = .now) -> Bool {
        if let lastLoad, now >= lastLoad, now.timeIntervalSince(lastLoad) < interval {
            return false
        }
        lastLoad = now
        return true
    }
}

private struct ReloadOnForeground: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase
    @State private var throttle = ReloadThrottle()
    let reload: () async -> Void

    func body(content: Content) -> some View {
        content
            .onAppear { throttle.recordLoad() }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, throttle.shouldReload() else { return }
                Task { await reload() }
            }
    }
}

extension View {
    /// Reloads this screen when the app returns to the foreground, at most
    /// once every 30 seconds.
    func reloadOnForeground(_ reload: @escaping () async -> Void) -> some View {
        modifier(ReloadOnForeground(reload: reload))
    }
}
