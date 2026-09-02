//
//  MyClinicsView.swift
//  FXETennis
//
//  "View All Clinics" under My Clinics on Home used to open the browse list,
//  which is every clinic, not mine. This is mine: every clinic I hold a live
//  registration in (You're In!, Player Pool, Response Needed), grouped by
//  service week like the browse list, each row wearing its status chip.
//

import SwiftUI

struct MyClinicsView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = ClinicsViewModel()

    private var isMember: Bool { session.activePlayer?.isMember ?? false }

    private var mine: [ClinicPublic] {
        model.clinics.filter { model.myRegistrationsByClinic[$0.id] != nil && !$0.isCanceled }
    }

    private var weeks: [(start: Date, items: [ClinicPublic])] {
        ServiceWeek.grouped(mine, startsAt: \.startsAt)
    }

    var body: some View {
        ZStack {
            Brand.surface.ignoresSafeArea()
            if model.loading && model.clinics.isEmpty {
                ProgressView().tint(Brand.navy)
            } else if mine.isEmpty {
                VStack(spacing: Brand.Spacing.sm) {
                    Image(systemName: "figure.tennis")
                        .font(.system(size: 40))
                        .foregroundStyle(Brand.disabled)
                    Text("You're not in any clinics yet.")
                        .font(Brand.Typography.body)
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                    NavigationLink { ClinicsView() } label: {
                        FilledButtonLabel("View Open Clinics")
                    }
                    .buttonStyle(.plain)
                    .padding(.top, Brand.Spacing.sm)
                }
                .padding(Brand.Spacing.pageMargin)
                .accessibilityIdentifier("myClinics.empty")
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: Brand.Spacing.md) {
                        ForEach(weeks, id: \.start) { week in
                            Text(ServiceWeek.label(forWeekStarting: week.start).uppercased())
                                .font(Brand.Typography.chip)
                                .foregroundStyle(Brand.textSecondary)
                                .padding(.top, week.start == weeks.first?.start ? 0 : Brand.Spacing.sm)
                                .accessibilityAddTraits(.isHeader)
                            ForEach(week.items) { clinic in
                                NavigationLink {
                                    ClinicDetailView(clinic: clinic, isMember: isMember,
                                                     onChanged: { await model.load() })
                                } label: {
                                    ClinicCard(clinic: clinic,
                                               registration: model.myRegistrationsByClinic[clinic.id],
                                               isMember: isMember)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("myClinics.card")
                            }
                        }
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
                .refreshable { await model.load() }
            }
        }
        .navigationTitle("My Clinics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
    }
}
