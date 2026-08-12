//
//  MainTabView.swift
//  FXETennis
//
//  Three tabs. Tara, 2026-08-12: "no community tab rn, just 3 tabs i guess."
//  Home, Clinics, Profile. Admin is a separate web surface, not a tab here.
//

import SwiftUI

struct MainTabView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house.fill") }
            ClinicsView()
                .tabItem { Label("Clinics", systemImage: "figure.tennis") }
            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.fill") }
        }
    }
}
