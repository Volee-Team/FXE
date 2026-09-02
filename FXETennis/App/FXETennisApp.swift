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
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @State private var session = SessionStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                .tint(Brand.navy)
                // LOAD-BEARING. docs/design-system.md has said since 2026-08-12
                // that "the root view sets .preferredColorScheme(.light)", and
                // until 2026-08-27 that sentence was true only inside a COMMENT
                // in Brand.swift. Nothing applied it.
                //
                // Every colour in Brand is a hardcoded light-palette value, and
                // the palette is deliberately closed with no dark tokens (Tara
                // has not supplied dark surfaces). So under a dark system the
                // app kept its cream and white grounds while SwiftUI switched
                // its DEFAULT text and control colours to their dark variants:
                // white text on a white field. A player with dark mode on could
                // not read what they were typing on the sign-in screen.
                //
                // Do not remove this to "support dark mode". Supporting dark
                // mode means Tara supplying a dark surface set first; until
                // then this line is what makes the light palette honest.
                .preferredColorScheme(.light)
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
        case .needsProfile:
            // Authenticated but with no profile row. Previously this state sent
            // the user back to signedOut, which was a dead end: their auth user
            // already existed, so signing up again failed too.
            CompleteProfileView()
        case .signedIn:
            MainTabView()
                .pushPermissionPrompt()
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
