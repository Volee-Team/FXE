//
//  HomeView.swift
//  FXETennis
//
//  The morning-glance screen. Order from the Developer Guide: My Clinics first,
//  then what's available. Lean shell for now; the recent-results and news
//  preview blocks are built on top.
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = ClinicsViewModel()

    private var isMember: Bool { session.activePlayer?.isMember ?? false }

    private var myClinics: [ClinicPublic] {
        model.clinics.filter { model.myRegistrationsByClinic[$0.id] != nil && !$0.isCanceled }
    }
    private var available: [ClinicPublic] {
        model.clinics.filter { model.myRegistrationsByClinic[$0.id] == nil && !$0.isCanceled }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                        greeting
                        section("My Clinics", clinics: Array(myClinics.prefix(3)),
                                empty: "You're not in any clinics yet.")
                        section("Available This Week", clinics: Array(available.prefix(3)),
                                empty: "Nothing open right now.")
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
            }
            .navigationTitle("Home")
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }

    private var greeting: some View {
        let name = session.activePlayer?.firstName ?? "there"
        return Text("Hi, \(name)")
            .font(Brand.Typography.display)
            .foregroundStyle(Brand.navy)
    }

    private func section(_ title: String, clinics: [ClinicPublic], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            Text(title.uppercased())
                .font(Brand.Typography.caption)
                .foregroundStyle(Brand.textSecondary)
            if clinics.isEmpty {
                Text(empty)
                    .font(Brand.Typography.body)
                    .foregroundStyle(Brand.textSecondary)
            } else {
                ForEach(clinics) { clinic in
                    NavigationLink {
                        ClinicDetailView(clinic: clinic, isMember: isMember,
                                         onChanged: { await model.load() })
                    } label: {
                        ClinicCard(
                            clinic: clinic,
                            registration: model.myRegistrationsByClinic[clinic.id],
                            isMember: isMember
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
