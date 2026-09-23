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
    /// Finished clinics, from the player's own view (decision 0012 §10).
    @State private var past: [PastClinic] = []

    private var isMember: Bool { session.activePlayer?.isMember ?? false }

    private var mine: [ClinicPublic] {
        model.clinics.filter { model.myRegistrationsByClinic[$0.id] != nil && !$0.isCanceled }
    }

    private var weeks: [(start: Date, items: [ClinicPublic])] {
        ServiceWeek.grouped(mine, startsAt: \.startsAt)
    }

    var body: some View {
        ZStack {
            Brand.surfaceGradient.ignoresSafeArea()
            if model.loading && model.clinics.isEmpty {
                ProgressView().tint(Brand.navy)
            } else if mine.isEmpty && past.isEmpty {
                VStack(spacing: Brand.Spacing.sm) {
                    Image(systemName: "figure.tennis")
                        .font(.system(size: 40))
                        .foregroundStyle(Brand.disabled)
                    Text("You're not registered for any clinics this week")
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
                        if mine.isEmpty {
                            Text("You're not registered for any clinics this week")
                                .font(Brand.Typography.body)
                                .foregroundStyle(Brand.textSecondary)
                        }
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
                        if !past.isEmpty { pastSection }
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
                .refreshable { await model.load(); await loadPast() }
            }
        }
        .navigationTitle("My Clinics")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .task { await loadPast() }
    }
}

extension MyClinicsView {
    private func loadPast() async {
        past = (try? await RegistrationRepository.past()) ?? []
    }

    /// What I played and what it cost me. Own rows only: the view carries
    /// nothing about anyone else and none of the nine hidden facts.
    private var pastSection: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text("PAST")
                .font(Brand.Typography.chip)
                .foregroundStyle(Brand.textSecondary)
                .padding(.top, Brand.Spacing.sm)
                .accessibilityAddTraits(.isHeader)
            ForEach(past) { row in
                HStack(alignment: .firstTextBaseline, spacing: Brand.Spacing.sm) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.name)
                            .font(Brand.Typography.bodyEmphasis)
                            .foregroundStyle(Brand.textPrimary)
                        Text(row.startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            .font(Brand.Typography.caption)
                            .foregroundStyle(Brand.textSecondary)
                    }
                    Spacer()
                    Text(pastOutcome(row))
                        .font(Brand.Typography.chip)
                        .foregroundStyle(pastOutcomeColor(row))
                }
                .padding(Brand.Spacing.cardPadding)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier("myClinics.past")
            }
        }
    }

    private func pastOutcome(_ row: PastClinic) -> String {
        if row.status == .canceled { return row.lateCancel == true ? "Canceled late" : "Canceled" }
        if row.noShow == true { return "No-show" }
        if let cents = row.priceCentsCharged { return "Played · \(cents.centsAsPrice)" }
        return "Played"
    }

    private func pastOutcomeColor(_ row: PastClinic) -> Color {
        if row.status == .canceled || row.noShow == true { return Brand.Status.canceled.ink }
        return Brand.Status.youreIn.ink
    }
}
