//
//  AdminClinicsView.swift
//  FXETennis
//
//  Tara's clinic list: today first, then upcoming, then past. The entry point
//  to the screen where she actually runs a session.
//
//  This is the ONLY screen in the app that shows counts, and it does so
//  deliberately. Hard rule 1 hides capacity and every count from PLAYERS; Tara
//  needs them to decide who to invite. The guide's Screen 14 lists "Counts for
//  admin only: You're In!, Player Pool, Response Needed" as required.
//
//  Never reuse a view from here on a player screen. The separation is the
//  control.
//

import SwiftUI

@MainActor
@Observable
final class AdminClinicsModel {
    var clinics: [ClinicAdmin] = []
    var rosterCounts: [UUID: RosterCounts] = [:]
    var lateRequests: [LateRequest] = []
    var notices: [AdminNotice] = []
    var loading = false
    var error: String?

    struct RosterCounts: Sendable {
        var youreIn = 0
        var pool = 0
        var responseNeeded = 0
        var unpaid = 0
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            clinics = try await AdminRepository.allClinics()
            // Both were recorded by the backend from day one and shown by no
            // screen. A late request is an ask waiting on her; a notice is a
            // cancellation, decline or acceptance she has not seen yet.
            lateRequests = (try? await AdminRepository.pendingLateRequests()) ?? []
            notices = (try? await AdminRepository.unreadNotices()) ?? []
            error = nil
            await loadCounts()
        } catch {
            self.error = "Couldn't load clinics. Pull to refresh."
        }
    }

    /// Counts for the clinics Tara is most likely to act on. Deliberately NOT
    /// every clinic: a full roster fetch per row would be one round trip each,
    /// and the past ones are not decisions she is making today.
    private func loadCounts() async {
        let soon = clinics.filter { $0.endsAt >= .now }.prefix(12)
        for clinic in soon {
            guard let roster = try? await AdminRepository.roster(clinic: clinic.id) else { continue }
            var c = RosterCounts()
            for entry in roster {
                switch entry.registration.status {
                case .in_:
                    c.youreIn += 1
                    if !entry.registration.paid { c.unpaid += 1 }
                case .pool: c.pool += 1
                case .responseNeeded: c.responseNeeded += 1
                case .canceled: break
                }
            }
            rosterCounts[clinic.id] = c
        }
    }
}

struct AdminClinicsView: View {
    @State private var model = AdminClinicsModel()

    private var today: [ClinicAdmin] {
        model.clinics.filter { Calendar.current.isDateInToday($0.startsAt) }
    }
    private var upcoming: [ClinicAdmin] {
        model.clinics.filter { $0.startsAt > .now && !Calendar.current.isDateInToday($0.startsAt) }
    }
    private var past: [ClinicAdmin] {
        model.clinics.filter { $0.endsAt < .now && !Calendar.current.isDateInToday($0.startsAt) }
            .sorted { $0.startsAt > $1.startsAt }
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surface.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                        if let error = model.error {
                            Text(error)
                                .font(Brand.Typography.subheadline)
                                .foregroundStyle(Brand.Status.canceled.ink)
                        }

                        // Action Needed first, always. The guide's dashboard
                        // principle: "The app should surface work. Tara should
                        // not have to remember that somebody canceled, that
                        // invitations are unanswered, or that players remain
                        // unpaid."
                        actionNeeded

                        section("Today", today, empty: "No clinics today.")
                        section("Upcoming", upcoming, empty: "Nothing scheduled yet.")
                        if !past.isEmpty {
                            section("Past", Array(past.prefix(10)), empty: "")
                        }
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
                .refreshable { await model.load() }
            }
            .navigationTitle("Clinics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PlayersDirectoryView()
                    } label: {
                        // Icon plus word: the toolbar would otherwise show the
                        // icon alone (CLAUDE.md: icons always paired with text).
                        Label("Players", systemImage: "person.2")
                            .labelStyle(.titleAndIcon)
                    }
                    .accessibilityIdentifier("admin.players")
                }
            }
        }
        .task { await model.load() }
    }

    private var actionNeeded: some View {
        let waiting = model.rosterCounts.values.reduce(0) { $0 + $1.responseNeeded }
        let unpaid = model.rosterCounts.values.reduce(0) { $0 + $1.unpaid }
        let pool = model.rosterCounts.values.reduce(0) { $0 + $1.pool }

        let asks = model.lateRequests.count
        let news = model.notices.count

        return Group {
            if waiting > 0 || unpaid > 0 || pool > 0 || asks > 0 || news > 0 {
                VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                    Text("ACTION NEEDED")
                        .font(Brand.Typography.chip)
                        .foregroundStyle(Brand.textSecondary)

                    VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                        if asks > 0 { needRow(Brand.Status.responseNeeded, "\(asks) asking to get in after close") }
                        if news > 0 { needRow(Brand.Status.canceled, "\(news) cancellations or replies to see") }
                        if waiting > 0 { needRow(Brand.Status.responseNeeded, "\(waiting) waiting on a reply") }
                        if pool > 0 { needRow(Brand.Status.playerPool, "\(pool) in the Player Pool") }
                        if unpaid > 0 { needRow(Brand.Status.canceled, "\(unpaid) unpaid") }
                    }
                    .padding(Brand.Spacing.cardPadding)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                    .overlay(
                        RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline)
                    )
                }
                .accessibilityIdentifier("admin.actionNeeded")
            }
        }
    }

    private func needRow(_ status: Brand.Status, _ text: String) -> some View {
        HStack(spacing: Brand.Spacing.xs) {
            Circle().fill(status.ink).frame(width: 9, height: 9)
            Text(text)
                .font(Brand.Typography.body)
                .foregroundStyle(Brand.textPrimary)
        }
        // The dot is decoration; the sentence carries the meaning, so the row
        // reads as one element and colour is never the only signal.
        .accessibilityElement(children: .combine)
    }

    private func section(_ title: String, _ clinics: [ClinicAdmin], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(title.uppercased())
                .font(Brand.Typography.chip)
                .foregroundStyle(Brand.textSecondary)

            if clinics.isEmpty {
                if !empty.isEmpty {
                    Text(empty)
                        .font(Brand.Typography.body)
                        .foregroundStyle(Brand.textSecondary)
                }
            } else {
                ForEach(clinics) { clinic in
                    NavigationLink {
                        AdminClinicDetailView(clinic: clinic, onChanged: { await model.load() })
                    } label: {
                        AdminClinicRow(clinic: clinic, counts: model.rosterCounts[clinic.id])
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("admin.clinic.card")
                }
            }
        }
    }
}

private struct AdminClinicRow: View {
    let clinic: ClinicAdmin
    let counts: AdminClinicsModel.RosterCounts?

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
            HStack {
                Text(clinic.name)
                    .font(Brand.Typography.headline)
                    .foregroundStyle(Brand.navy)
                Spacer()
                if clinic.isCanceled {
                    StatusChip(.canceled)
                } else if clinic.isDraft {
                    Text("Draft")
                        .font(Brand.Typography.chip)
                        .foregroundStyle(Brand.textSecondary)
                }
            }

            Text(timeLine)
                .font(Brand.Typography.subheadline)
                .foregroundStyle(Brand.textSecondary)

            // Admin-only counts. Never render this on a player screen.
            if let c = counts {
                HStack(spacing: Brand.Spacing.sm) {
                    countPill(Brand.Status.youreIn, c.youreIn, of: clinic.internalCapacity)
                    if c.pool > 0 { countPill(Brand.Status.playerPool, c.pool, of: nil) }
                    if c.responseNeeded > 0 { countPill(Brand.Status.responseNeeded, c.responseNeeded, of: nil) }
                }
                .padding(.top, 2)
            }
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
        .contentShape(Rectangle())
    }

    private func countPill(_ status: Brand.Status, _ n: Int, of capacity: Int?) -> some View {
        let text = capacity.map { "\(status.label) \(n)/\($0)" } ?? "\(status.label) \(n)"
        return Text(text)
            .font(Brand.Typography.chip)
            .foregroundStyle(status.ink)
            .padding(.horizontal, Brand.Spacing.xs)
            .padding(.vertical, 3)
            .background(Capsule().fill(status.tint))
            .accessibilityLabel("\(status.label): \(n)\(capacity.map { " of \($0)" } ?? "")")
    }

    private var timeLine: String {
        clinic.startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        + " · "
        + clinic.startsAt.formatted(.dateTime.hour().minute())
    }
}
