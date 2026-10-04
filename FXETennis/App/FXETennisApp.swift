//
//  FXETennisApp.swift
//  FXETennis
//
//  Entry point and the auth gate. One SessionStore, created here, injected into
//  the environment so every screen shares one identity.
//

import SwiftUI
import StripePaymentSheet

@main
struct FXETennisApp: App {
    @UIApplicationDelegateAdaptor(PushAppDelegate.self) private var pushDelegate
    @State private var session = SessionStore()

    init() {
        ClubTime.apply()
        Brand.styleNavigationTitles()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(session)
                // Charlotte time in SwiftUI's own formatting too (ClubTime).
                .environment(\.timeZone, ClubTime.zone)
                .tint(Brand.navy)
                // LIGHT MODE IS LOAD-BEARING, and it lives in Info.plist now
                // (project.yml, INFOPLIST_KEY_UIUserInterfaceStyle: Light).
                //
                // Every colour in Brand is a hardcoded light-palette value, and
                // the palette is deliberately closed with no dark tokens (Tara
                // has not supplied dark surfaces). Under a dark system without
                // the lock, the app kept its cream and white grounds while the
                // DEFAULT text and control colours went dark-mode: white text on
                // a white field (2026-08-27, the sign-in screen).
                //
                // Until 2026-09-28 the lock was `.preferredColorScheme(.light)`
                // right here. It also pinned the status bar to dark text, so
                // the clock was black on every navy header and no screen could
                // ask for light text (tried on the simulator: the navigation
                // bar's colour scheme had no effect while it was here). The
                // Info.plist key is Apple's documented opt-out and covers every
                // window, sheet and UIKit screen (Stripe's card sheet, the
                // calendar editor) the same way.
                //
                // Do not remove the key to "support dark mode". Supporting dark
                // mode means Tara supplying a dark surface set first.
                .task { await session.bootstrap() }
                // A bank's 3-D Secure check returning to Stripe's card sheet
                // (CardOnFileView's returnURL). Anything else is ignored.
                .onOpenURL { url in _ = StripeAPI.handleURLCallback(with: url) }
        }
    }
}

/// Chooses the screen for the current auth phase. The launch state shows the
/// mark rather than a blank window, so there is no flash before we know.
struct RootView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            switch session.phase {
            case .loading:
                LaunchView().lightStatusBar()
            case .signedOut:
                AuthView().lightStatusBar()
            case .needsProfile:
                // Authenticated but with no profile row. Previously this state sent
                // the user back to signedOut, which was a dead end: their auth user
                // already existed, so signing up again failed too.
                CompleteProfileView()
            case .loadFailed:
                // Authenticated, but the profile could not be loaded (no signal,
                // a server error). Not the sign-up form: that is for "no row".
                LoadFailedView().lightStatusBar()
            case .signedIn:
                // The waiver comes before the app, as its own screen, not a
                // sheet over Home (Alex, 2026-09-29: "it should be there
                // before you EVEN SEE the home screen"). Admins are exempt.
                // Unknown (nil, a check that failed) still opens the app:
                // register_for_clinic refuses an unsigned player anyway, and
                // its refusal brings this screen back (SessionStore.reopen).
                if session.waiverAccepted == false && session.account?.role != "admin" {
                    WaiverView()
                } else {
                    MainTabView()
                        .pushTapRouting()
                        .pushPermissionPrompt()
                        .cardGate()
                }
            }
        }
        // Coming back to the app refreshes the identity and the waiver and card
        // gates (throttled inside), or retries a failed load (MVP audit item 8).
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { Task { await session.returnedToForeground() } }
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
                    .brandFont(.title)
                    .foregroundStyle(Brand.textOnNavy)
                ProgressView()
                    .tint(Brand.textOnNavyMuted)
            }
        }
    }
}
