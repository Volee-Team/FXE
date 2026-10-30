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
    /// Open chargebacks (20260928200001). Tara answers them in Stripe.
    var disputes: [MoneyDispute] = []
    /// Charges held for her answer (20260927300003).
    var held: [HeldCharge] = []

    /// Clinics that ended with someone who still owes a fee.
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
            // A deleted account's decline is nobody's to fix (20260927300001).
            declines = ((try? await AdminRepository.moneyDeclined()) ?? []).filter { $0.accountDeleted != true }
            disputes = (try? await AdminRepository.moneyDisputes()) ?? []
            held = (try? await AdminRepository.heldCharges()) ?? []
            error = nil
            await loadCounts()
        } catch {
            self.error = "Couldn't load clinics. Pull to refresh."
        }
    }

    /// Tara's Resolved on a declined card (decision 0024, question 83): one
    /// tap, no confirmation, because it moves no money, tells nobody and
    /// leaves the player's card declined; the row goes and the ledger keeps
    /// the charge. The list is read again either way; if the charge changed
    /// meanwhile, hard rule 3's line says so after the reload.
    func resolve(_ decline: MoneyDecline) async {
        guard let payment = decline.paymentId else { return }
        var line: String?
        do {
            try await AdminRepository.resolveDecline(payment: payment)
        } catch {
            line = String(describing: error).contains("decline_not_open")
                ? AdminClinicModel.changedUnderYou
                : (RequestFailure(error).line ?? "That didn't go through. Check your connection and try again.")
        }
        await load()
        if let line { self.error = line }
    }

    /// Her answer on a held charge, after she has looked in Stripe.
    func resolve(_ charge: HeldCharge, outcome: String) async {
        var line: String?
        do {
            try await AdminRepository.resolveHeld(payment: charge.id, outcome: outcome)
        } catch {
            line = String(describing: error).contains("payment_not_held")
                ? "That charge is no longer held."
                : (RequestFailure(error).line ?? "That didn't go through. Check your connection and try again.")
        }
        await load()
        if let line { self.error = line }
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

/// A held-charge answer waiting on "Really?".
private struct PendingHeldAnswer {
    let charge: HeldCharge
    let label: String
    let outcome: String
}

struct AdminClinicsView: View {
    @State private var model = AdminClinicsModel()
    @State private var pendingHeldAnswer: PendingHeldAnswer?
    @State private var showNotices = false
    private var pendingHeld: (HeldCharge, String, String)? {
        get { pendingHeldAnswer.map { ($0.charge, $0.label, $0.outcome) } }
        nonmutating set { pendingHeldAnswer = newValue.map { PendingHeldAnswer(charge: $0.0, label: $0.1, outcome: $0.2) } }
    }

    private var today: [ClinicAdmin] {
        model.clinics.filter { Calendar.current.isDateInToday($0.startsAt) }
    }
    private var upcoming: [ClinicAdmin] {
        model.clinics.filter { $0.startsAt > .now && !Calendar.current.isDateInToday($0.startsAt) }
    }
    /// Only the last 7 days (Tara, 2026-10-19: "she doesn't need to see all
    /// past clinics just maybe the past week"). An older clinic that still
    /// owes a fee stays in Action Needed, which reads its own list.
    private var past: [ClinicAdmin] {
        model.clinics.filter { PastWeek.contains(endsAt: $0.endsAt) && !Calendar.current.isDateInToday($0.startsAt) }
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
                                .brandFont(.subheadline)
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
                            section("Past", past, empty: "")
                        }
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
                .refreshable { await model.load() }
            }
            .crispTopEdge()
            .bannerTitle("Clinics")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink {
                        PlayersDirectoryView()
                    } label: {
                        // The word alone. A Label in a toolbar renders icon-only
                        // on iOS 26 whatever the label style says (seen 09-02),
                        // and an unlabelled icon breaks the icons-with-text rule.
                        Text("Players")
                            .brandFont(.button)
                    }
                    .accessibilityIdentifier("admin.players")
                    .tint(Brand.textOnNavy)
                }
                .onNavy()
                // Final Updates p.2, Admin Panel item 1: "Add Stripe Admin link
                // in the U/I." The web admin's Money tab has had it since
                // 09-22; Tara's courtside surface gets it too. Opens Stripe's
                // own dashboard in Safari, where refunds, disputes and payouts live.
                // Trailing since 2026-09-29: the leading edge holds the page
                // name on the navy banner.
                ToolbarItem(placement: .topBarTrailing) {
                    Link(destination: URL(string: "https://dashboard.stripe.com")!) {
                        Text("Stripe")
                            .brandFont(.button)
                    }
                    .accessibilityIdentifier("admin.stripe")
                    .tint(Brand.textOnNavy)
                }
                .onNavy()
            }
        }
        .task { await model.load() }
        .confirmationDialog(pendingHeldAnswer?.label ?? "",
                            isPresented: .init(get: { pendingHeldAnswer != nil }, set: { if !$0 { pendingHeldAnswer = nil } }),
                            titleVisibility: .visible) {
            if let p = pendingHeldAnswer {
                Button("Really?") { Task { await model.resolve(p.charge, outcome: p.outcome) } }
            }
        }
        // A late request or a reply that came in while the app slept shows
        // when Tara comes back to it (MVP audit item 8).
        .reloadOnForeground { await model.load() }
        .sheet(isPresented: $showNotices, onDismiss: { Task { await model.load() } }) {
            NotificationsView()
        }
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
        let money = !model.uncharged.isEmpty || !model.declines.isEmpty || !model.disputes.isEmpty || !model.held.isEmpty

        return Group {
            if waiting > 0 || unpaid > 0 || pool > 0 || asks > 0 || news > 0 || money {
                VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                    Text("ACTION NEEDED")
                        .brandFont(.chip)
                        .foregroundStyle(Brand.textSecondary)

                    VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                        // Money first: each row opens its clinic, where each
                        // person is charged on the row (decision 0037).
                        ForEach(model.uncharged) { m in
                            clinicLink(m.clinicId) {
                                needRow(Brand.Status.responseNeeded, "\(m.clinicName) ended, not charged yet",
                                        detail: m.startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))
                            }
                        }
                        ForEach(model.declines) { d in
                            HStack(spacing: Brand.Spacing.xs) {
                                clinicLink(d.clinicId) {
                                    needRow(Brand.Status.canceled, "\(d.displayName)'s card was declined",
                                            detail: declineDetail(d))
                                }
                                Spacer(minLength: 0)
                                // Her word (question 83). Beside the row, not
                                // inside its link, so the tap is only this.
                                if d.paymentId != nil {
                                    Button {
                                        Task { await model.resolve(d) }
                                    } label: {
                                        Text("Resolved")
                                            .brandFont(.chip)
                                            .foregroundStyle(Brand.navy)
                                            .frame(minHeight: Brand.Layout.minTapTarget)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("admin.actionNeeded.resolved")
                                }
                            }
                        }
                        // A held charge: she looks in Stripe, then answers.
                        // Each answer asks once more, as on the laptop.
                        ForEach(model.held) { h in
                            VStack(alignment: .leading, spacing: 2) {
                                needRow(Brand.Status.responseNeeded, h.displayName,
                                        detail: "\(h.clinicName.map { $0 + ": " } ?? "")Check this charge in Stripe.")
                                HStack(spacing: Brand.Spacing.sm) {
                                    heldAnswer(h, label: "Went through", outcome: "succeeded")
                                    heldAnswer(h, label: "Did not go through", outcome: "canceled")
                                }
                                .padding(.leading, 17)
                            }
                            .accessibilityIdentifier("admin.actionNeeded.held")
                        }
                        // A dispute is answered in Stripe, so the row opens
                        // Stripe's dashboard in Safari, like the toolbar link.
                        ForEach(model.disputes) { d in
                            Link(destination: URL(string: "https://dashboard.stripe.com")!) {
                                needRow(Brand.Status.canceled, "\(d.displayName) disputed a charge",
                                        detail: disputeDetail(d))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("admin.actionNeeded.dispute")
                        }
                        // Every row opens what it counts (Tara, 2026-10-30:
                        // she tapped "2 in the Player Pool" and nothing
                        // happened). The cancellations and replies open the
                        // list the bell opens; a count that belongs to a
                        // clinic is one row per clinic, opening that clinic.
                        if news > 0 {
                            Button { showNotices = true } label: {
                                needRow(Brand.Status.canceled, "\(news) cancellations or replies to see")
                                    .frame(maxWidth: .infinity, minHeight: Brand.Layout.minTapTarget, alignment: .leading)
                                    .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("admin.actionNeeded.notices")
                        }
                        ForEach(perClinic { id in model.lateRequests.filter { $0.clinicId == id }.count }, id: \.clinic.id) { row in
                            clinicLink(row.clinic.id, identifier: "admin.actionNeeded.clinic") {
                                needRow(Brand.Status.responseNeeded, "\(row.count) asking to get in after close", detail: clinicDetail(row.clinic))
                            }
                        }
                        ForEach(perClinic { model.rosterCounts[$0]?.responseNeeded ?? 0 }, id: \.clinic.id) { row in
                            clinicLink(row.clinic.id, identifier: "admin.actionNeeded.clinic") {
                                needRow(Brand.Status.responseNeeded, "\(row.count) waiting on a reply", detail: clinicDetail(row.clinic))
                            }
                        }
                        ForEach(perClinic { model.rosterCounts[$0]?.pool ?? 0 }, id: \.clinic.id) { row in
                            clinicLink(row.clinic.id, identifier: "admin.actionNeeded.clinic") {
                                needRow(Brand.Status.playerPool, "\(row.count) on the Waitlist", detail: clinicDetail(row.clinic))
                            }
                        }
                        if model.zelleAllowed {
                            ForEach(perClinic { model.rosterCounts[$0]?.unpaid ?? 0 }, id: \.clinic.id) { row in
                                clinicLink(row.clinic.id, identifier: "admin.actionNeeded.clinic") {
                                    needRow(Brand.Status.canceled, "\(row.count) unpaid", detail: clinicDetail(row.clinic))
                                }
                            }
                        }
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

    /// One of her two answers on a held charge, confirmed with "Really?".
    private func heldAnswer(_ h: HeldCharge, label: String, outcome: String) -> some View {
        Button {
            pendingHeld = (h, label, outcome)
        } label: {
            Text(label)
                .brandFont(.chip)
                .foregroundStyle(Brand.navy)
                .frame(minHeight: Brand.Layout.minTapTarget)
        }
        .buttonStyle(.plain)
    }

    private func needRow(_ status: Brand.Status, _ text: String, detail: String? = nil) -> some View {
        HStack(spacing: Brand.Spacing.xs) {
            Circle().fill(status.ink).frame(width: 9, height: 9)
            VStack(alignment: .leading, spacing: 1) {
                Text(text)
                    .brandFont(.body)
                    .foregroundStyle(Brand.textPrimary)
                if let detail {
                    Text(detail)
                        .brandFont(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
        // The dot is decoration; the sentence carries the meaning, so the row
        // reads as one element and colour is never the only signal.
        .accessibilityElement(children: .combine)
    }

    /// "Tuesday Ladies 3.0+ on Tue, Sep 29: Insufficient funds (NSF)". No
    /// middle dots (Alex, 2026-10-01: they read as machine-made); the date
    /// already holds a comma, so "on" and a colon carry the joins.
    private func declineDetail(_ d: MoneyDecline) -> String {
        let head = "\(d.clinicName) on \(d.clinicStartsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day()))"
        guard let reason = DeclineReason.label(d.failureCode) else { return head }
        return "\(head): \(reason)"
    }

    /// "Tuesday Ladies 3.0+ on Tue, Sep 29: $18, respond by Oct 5".
    private func disputeDetail(_ d: MoneyDispute) -> String {
        var line = "\(d.clinicName) on \(d.clinicStartsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())): \(d.amountCents.centsAsPrice)"
        if let by = d.respondBy { line += ", respond by \(by.formatted(.dateTime.month(.abbreviated).day()))" }
        return line
    }

    /// The clinics a count applies to, soonest first, with their count.
    private func perClinic(_ count: (UUID) -> Int) -> [(clinic: ClinicAdmin, count: Int)] {
        model.clinics.sorted { $0.startsAt < $1.startsAt }
            .map { ($0, count($0.id)) }
            .filter { $0.1 > 0 }
    }

    /// "Coed 105 on Sun, Nov 1, 4:30 PM": which clinic a count row opens.
    private func clinicDetail(_ c: ClinicAdmin) -> String {
        "\(c.name) on \(c.startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))"
    }

    /// A money row opens its clinic. A clinic the list does not hold (it
    /// should always) leaves the row as plain text rather than a dead link.
    @ViewBuilder private func clinicLink<Content: View>(_ id: UUID, identifier: String = "admin.actionNeeded.money", @ViewBuilder _ content: () -> Content) -> some View {
        let row = content()
        if let clinic = model.clinics.first(where: { $0.id == id }) {
            NavigationLink {
                AdminClinicDetailView(clinic: clinic, onChanged: { await model.load() })
            } label: {
                row
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier(identifier)
        } else {
            row
        }
    }

    private func section(_ title: String, _ clinics: [ClinicAdmin], empty: String) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(title.uppercased())
                .brandFont(.chip)
                .foregroundStyle(Brand.textSecondary)

            if clinics.isEmpty {
                if !empty.isEmpty {
                    Text(empty)
                        .brandFont(.body)
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
                    .brandFont(.headline)
                    .foregroundStyle(Brand.navy)
                Spacer()
                if clinic.isCanceled {
                    StatusChip(.canceled)
                } else if clinic.isDraft {
                    Text("Draft")
                        .brandFont(.chip)
                        .foregroundStyle(Brand.textSecondary)
                }
            }

            Text(timeLine)
                .brandFont(.subheadline)
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
            .brandFont(.chip)
            .foregroundStyle(status.ink)
            .padding(.horizontal, Brand.Spacing.xs)
            .padding(.vertical, 3)
            .background(Capsule().fill(status.tint))
            .accessibilityLabel("\(status.label): \(n)\(capacity.map { " of \($0)" } ?? "")")
    }

    private var timeLine: String {
        clinic.startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        + " at "
        + clinic.startsAt.formatted(.dateTime.hour().minute())
    }
}

/// Which ended clinics Tara's Past section shows: those that ended in the
/// last 7 days. Pure, so `PastWeekTests` can pin the edges.
enum PastWeek {
    static func contains(endsAt: Date, now: Date = .now) -> Bool {
        endsAt < now && endsAt >= now.addingTimeInterval(-7 * 24 * 3600)
    }
}
