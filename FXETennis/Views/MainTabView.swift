//
//  MainTabView.swift
//  FXETennis
//
//  Three tabs for a player. Tara, 2026-08-12: "no community tab rn, just 3 tabs
//  i guess." Home, Clinics, Profile. See docs/decisions/0006.
//
//  A FOURTH tab appears for an administrator only. That comment used to read
//  "Admin is a separate web surface, not a tab here", and the web surface is
//  still the plan for the laptop-heavy work (creating a week of clinics, court
//  drag-and-drop). But a 2026-08-13 audit walked Tara's weekly workflow and
//  found 1 of 11 steps supported, with 8 of the missing 10 needing NO new
//  backend at all. A phone tab was the fastest route to her actually running a
//  week, so it comes first and the web admin follows for the parts a phone is
//  genuinely bad at. Alex chose this on 2026-08-15.
//
//  THE TAB IS NOT A SECURITY CONTROL. `is_admin()` is enforced server-side in
//  every admin RPC and in the `clinics_admin` / `registrations_admin` views,
//  which return zero rows to a non-admin. Hiding the tab keeps the app simple
//  for players; it is not what keeps them out.
//

import SwiftUI

struct MainTabView: View {
    @Environment(SessionStore.self) private var session

    /// The guide asks for a navy-900 tab bar with the active item in
    /// gator-green. iOS 26 draws the tab bar as floating glass and ignores a
    /// solid fill from the toolbar-background APIs (tried 2026-09-22; the
    /// bar went frosted with white glyphs, unreadable). So: the system bar,
    /// active in gator-green, inactive in navy-900. A custom navy bar would
    /// mean replacing the system bar; flagged in docs/style-guide.md for Kat.
    init() {
        Brand.Fonts.register()
        UITabBar.appearance().unselectedItemTintColor = UIColor(Brand.navy)
    }

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
            ClinicsView()
                .tabItem { Label("Clinics", systemImage: "figure.tennis") }

            if session.account?.isAdmin == true {
                AdminClinicsView()
                    .tabItem { Label("Manage", systemImage: "list.clipboard") }
                    .accessibilityIdentifier("tab.admin")
                }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person") }
                .accessibilityIdentifier("tab.profile")
        }
        .tint(Brand.court)
    }
}
