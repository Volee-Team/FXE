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
    /// Decision 0013: the card is the only way to pay, so "N unpaid" (the
    /// Paid flag, which cannot turn true before a clinic ends) is not shown
    /// while this is false, the same gate as the Unpaid audience.
    var zelleAllowed = false
    /// Money work from the ledger (20260927100003).
    var paymentsOn = false
    var moneyClinics: [MoneyClinic] = []
    var declines: [MoneyDecline] = []

    /// Clinics that ended with someone one more Charge clinic would charge.
    /// Only while payments are on: the tap is the resolving action.
    var uncharged: [MoneyClinic] {
        paymentsOn ? moneyClinics.filter { !$0.canceled && $0.chargeableCount > 0 } : []
    }

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
            zelleAllowed = (try? await AdminRepository.zelleAllowed()) ?? false
            paymentsOn = (try? await AdminRepository.paymentsEnabled()) ?? false
            moneyClinics = (try? await AdminRepository.moneyClinics()) ?? []
            declines = (try? await AdminRepository.moneyDeclined()) ?? []
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
                CourtBackdrop()

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
                        // The word alone. A Label in a toolbar renders icon-only
                        // on iOS 26 whatever the label style says (seen 09-02),
                        // and an unlabelled icon breaks the icons-with-text rule.
                        Text("Players")
                            .font(Brand.Typography.button)
                    }
                    .accessibilityIdentifier("admin.players")
                }
                // Final Updates p.2, Admin Panel item 1: "Add Stripe Admin link
                // in the U/I." The web admin's Money tab has had it since
                // 09-22; Tara's courtside surface gets it too. Opens Stripe's
                // own dashboard in Safari, where refunds, disputes and payouts live.
                ToolbarItem(placement: .topBarLeading) {
                    Link(destination: URL(string: "https://dashboard.stripe.com")!) {
                        Text("Stripe")
                            .font(Brand.Typography.button)
                    }
                    .accessibilityIdentifier("admin.stripe")
                }
            }
        }
        .task { await model.load() }
        // A late request or a reply that came in while the app slept shows
        // when Tara comes back to it (MVP audit item 8).
        .reloadOnForeground { await model.load() }
    }

    private var actionNeeded: some View {
        let waiting = model.rosterCounts.values.reduce(0) { $0 + $1.responseNeeded }
        // The Paid flag cannot turn true before a clinic ends, so with the card
        // as the only way to pay this always equalled everyone booked (the
        // audit, 2026-09-27). Shown only while Zelle is allowed.
        let unpaid = model.zelleAllowed ? model.rosterCounts.values.reduce(0) { $0 + $1.unpaid } : 0
        let pool = model.rosterCounts.values.reduce(0) { $0 + $1.pool }

        let asks = model.lateRequests.count
        let news = model.notices.count
        let money = !model.uncharged.isEmpty || !model.declines.isEmpty

        return Group {
            if waiting > 0 || unpaid > 0 || pool > 0 || asks > 0 || news > 0 || money {
                VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                    Text("ACTION NEEDED")
                        .font(Brand.Typography.chip)
                        .foregroundStyle(Brand.textSecondary)

                    VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                        // Money first: each row opens its clinic, where Charge
                        // clinic is (20260927100003).
                        ForEach(model.uncharged) { m in
                            clinicLink(m.clinicId) {
                                needRow(Brand.Status.responseNeeded, "\(m.clinicName) ended, not charged yet",
                                        detail: m.startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            }
                        }
                        ForEach(model.declines) { d in
                            clinicLink(d.clinicId) {
                                needRow(Brand.Status.canceled, "\(d.displayName)'s card was declined",
                                        detail: declineDetail(d))
                            }
                        }
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

    private func needRow(_ status: Brand.Status, _ text: String, detail: String? = nil) -> some View {
        HStack(spacing: Brand.Spacing.xs) {
            Circle().fill(status.ink).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .font(Brand.Typography.body)
                    .foregroundStyle(Brand.textPrimary)
                if let detail {
                    Text(detail)
                        .font(Brand.Typography.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
        // The dot is decoration; the sentence carries the meaning, so the row
        // reads as one element and colour is never the only signal.
        .accessibilityElement(children: .combine)
    }

    /// "Tuesday Ladies 3.0+ · Tue, Sep 29 · Insufficient funds (NSF)".
    private func declineDetail(_ d: MoneyDecline) -> String {
        var parts = [d.clinicName, d.clinicStartsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())]
        if let reason = DeclineReason.label(d.failureCode) { parts.append(reason) }
        return parts.joined(separator: " · ")
    }

    /// A money row opens its clinic. A clinic the list does not hold (it
    /// should always) leaves the row as plain text rather than a dead link.
    @ViewBuilder private func clinicLink<Content: View>(_ id: UUID, @ViewBuilder _ content: () -> Content) -> some View {
        let row = content()
        if let clinic = model.clinics.first(where: { $0.id == id }) {
            NavigationLink {
                AdminClinicDetailView(clinic: clinic, onChanged: { await model.load() })
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("admin.actionNeeded.money")
        } else {
            row
        }
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

            // Admin-only counts. Never render this on a player screen. A
            // canceled clinic has nothing to count; the chip is the message.
            if let c = counts, !clinic.isCanceled {
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
