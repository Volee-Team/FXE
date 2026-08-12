//
//  FXETennisApp.swift
//  FXETennis
//
//  Entry point and the auth gate. One SessionStore, created here, injected into
//  the environment so every screen shares one identity.
//

import SwiftUI

@main
struct FXETennisApp: App {
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Brand.navy)
                .task { await session.bootstrap() }
        }
    }
}

/// Chooses the screen for the current auth phase. The launch state shows the
/// mark rather than a blank window, so there is no flash before we know.
struct RootView: View {
    @Environment(SessionStore.self) private var session

    var body: some View {
        switch session.phase {
        case .loading:
            LaunchView()
        case .signedOut:
            AuthView()
        case .signedIn:
            MainTabView()
        }
    }
}

struct LaunchView: View {
    var body: some View {
        ZStack {
            Brand.navy.ignoresSafeArea()
            VStack(spacing: Brand.Spacing.md) {
                Image("gator-x")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 120, height: 120)
                Text("FXE Tennis")
                    .font(Brand.Typography.title)
                    .foregroundStyle(Brand.textOnNavy)
                ProgressView()
                    .tint(Brand.textOnNavyMuted)
            }
        }
    }
}
