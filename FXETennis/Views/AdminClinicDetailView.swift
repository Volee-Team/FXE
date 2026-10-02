//
//  AdminClinicDetailView.swift
//  FXETennis
//
//  Tara's operating screen for one clinic. The guide's Screen 14: "This is
//  Tara's primary operating screen for one clinic. Most work should happen here
//  without navigating through multiple menus."
//
//  Three lists in the order she works them, per the guide:
//    You're In!        name, member status, rating, Paid checkbox
//    Player Pool       registration ORDER visible, with an Invite button
//    Response Needed   invitation sent time, with Cancel Invitation
//
//  HARD RULE 2 IS THE WHOLE DESIGN. Tara picks every invitation by hand and
//  nothing is ever auto-promoted. Inviting does NOT confirm anyone: it moves
//  them to Response Needed and they must accept. The guide is explicit that
//  "Selecting a player from Player Pool never instantly confirms them."
//
//  The app also never blocks her. `for-tara.md` question 4 asked whether it
//  should stop her inviting past capacity; her answer was no. So the count is
//  shown and the button stays enabled. It is her program.
//

import SwiftUI

@MainActor
@Observable
final class AdminClinicModel {
    var roster: [RosterEntry] = []
    var loading = false
    var error: String?
    /// Registration ids with an action in flight, so a row can disable just
    /// itself rather than freezing the whole screen.
    var busy: Set<UUID> = []

    let clinic: ClinicAdmin
    init(clinic: ClinicAdmin) { self.clinic = clinic }

    /// Court order, no court last: the list IS her court sheet.
    var youreIn: [RosterEntry] {
        roster.filter { $0.registration.status == .in_ }
            .sorted { ($0.registration.courtNumber ?? 99, $0.displayName) < ($1.registration.courtNumber ?? 99, $1.displayName) }
    }
    var pool: [RosterEntry] { roster.filter { $0.registration.status == .pool } }
    var responseNeeded: [RosterEntry] { roster.filter { $0.registration.status == .responseNeeded } }
    var canceled: [RosterEntry] { roster.filter { $0.registration.status == .canceled } }
    var lateRequests: [(request: LateRequest, player: PlayerProfile?)] = []
    var unpaidCount: Int { youreIn.filter { !$0.registration.paid }.count }
    /// Decision 0013: false, so Paid/Unpaid and the reminder stay hidden.
    var zelleAllowed = false
    /// app_settings.cancel_cutoff_hours (3, decision 0013), for Late cancel.
    var cutoffHours = 3
    /// Each Player Pool player's history (decision 0027 §1), by player id:
    /// the line under the name that makes choosing who to invite one look.
    var history: [UUID: PlayerHistory] = [:]

    /// Late cancel (20260927100002) is offered on a You're In! row inside the
    /// cutoff or later, on a clinic that is not canceled, while the row holds
    /// no live charge. The server enforces all three; this decides the menu.
    func canLateCancel(_ entry: RosterEntry, now: Date = Date()) -> Bool {
        !clinic.isCanceled
            && entry.registration.status == .in_
            && !entry.registration.hasLiveCharge
            && CancelPolicy.isInsideCutoff(startsAt: clinic.startsAt, cutoffHours: cutoffHours, now: now)
    }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            roster = try await AdminRepository.roster(clinic: clinic.id)
            zelleAllowed = (try? await AdminRepository.zelleAllowed()) ?? false
            cutoffHours = (try? await RegistrationRepository.cancelCutoffHours()) ?? 3
            let asks = (try? await AdminRepository.pendingLateRequests(clinic: clinic.id)) ?? []
            let people = (try? await AdminRepository.players(ids: asks.map(\.playerId))) ?? []
            let byId = Dictionary(uniqueKeysWithValues: people.map { ($0.id, $0) })
            lateRequests = asks.map { ($0, byId[$0.playerId]) }
            // One call for the whole Pool. Read leniently: without it a row
            // simply shows no history line, and the roster still works.
            let poolIds = Array(Set(pool.map(\.registration.playerId)))
            let rows = (try? await AdminRepository.playerHistory(players: poolIds)) ?? []
            history = Dictionary(rows.map { ($0.playerId, $0) }, uniquingKeysWith: { first, _ in first })
            error = nil
        } catch {
            self.error = "Couldn't load the roster. Pull to refresh."
        }
    }

    /// Runs one roster action and reloads.
    ///
    /// Always reloads from the server rather than mutating the local array: the
    /// server decides the resulting status (a race with the player accepting is
    /// real and named in CLAUDE.md), so guessing locally would show Tara a state
    /// the database disagrees with.
    func perform(_ id: UUID, _ work: @escaping () async throws -> Void) async {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await work()
            await load()
        } catch {
            let message = Self.message(for: error)
            // A row that changed under her (hard rule 3): show the latest,
            // then say so. load() clears the error, so the words go last.
            if message == Self.changedUnderYou { await load() }
            self.error = message
        }
    }

    static let changedUnderYou = "That just changed. Here's the latest."

    /// The server's named refusals in words (20260927100001/2); anything
    /// else is most likely the connection.
    static func message(for error: Error) -> String {
        let e = String(describing: error)
        if e.contains("charged_refund_first") { return "Already charged: refund it first." }
        if e.contains("not_late_yet") { return "Not late yet." }
        if e.contains("clinic_canceled") { return "That clinic is canceled." }
        if e.contains("registration_not_in") || e.contains("already_canceled") { return changedUnderYou }
        return "That didn't go through. Check your connection and try again."
    }
}

struct AdminClinicDetailView: View {
    let clinic: ClinicAdmin
    /// Called after a change the list behind this screen must reflect.
    let onChanged: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var confirmCancelClinic = false
    @State private var confirmCharge = false
    @State private var chargeNote: String?
    @State private var removing: RosterEntry?
    @State private var lateCanceling: RosterEntry?
    @State private var lateNote = ""
    @State private var cancelError: String?
    @State private var model: AdminClinicModel
    @State private var showMessage = false
    @State private var confirmRemind = false
    @State private var remindNote: String?

    init(clinic: ClinicAdmin, onChanged: @escaping () async -> Void = {}) {
        self.clinic = clinic
        self.onChanged = onChanged
        _model = State(initialValue: AdminClinicModel(clinic: clinic))
    }

    var body: some View {
        ZStack {
            CourtBackdrop()

            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    header

                    if let error = model.error {
                        Text(error)
                            .brandFont(.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                    }

                    rosterSection(
                        Brand.Status.youreIn, model.youreIn,
                        empty: "Nobody is in yet."
                    ) { entry in AnyView(HStack(spacing: Brand.Spacing.xs) { courtMenu(entry); if model.zelleAllowed { paidToggle(entry) }; noShowToggle(entry); declinedLabel(entry) }) }

                    rosterSection(
                        Brand.Status.playerPool, model.pool,
                        empty: "The Player Pool is empty.",
                        numbered: true,
                        showsHistory: true
                    ) { entry in
                        // Nothing to invite into, or take out of, once the
                        // clinic is canceled (20260928400001 refuses both).
                        AnyView(Group {
                            if clinic.status != "canceled" {
                                HStack(spacing: Brand.Spacing.xs) { inviteButton(entry); removeFromPoolButton(entry) }
                            }
                        })
                    }

                    rosterSection(
                        Brand.Status.responseNeeded, model.responseNeeded,
                        empty: ""
                    ) { entry in AnyView(cancelInviteButton(entry)) }

                    lateRequestSection

                    // Canceled stays visible: hard rule 4, and Screen 14 says
                    // "Keep canceled players visible to Tara." A late cancel
                    // says so, with its note, the way the web roster does.
                    if !model.canceled.isEmpty {
                        rosterSection(Brand.Status.canceled, model.canceled, empty: "") { entry in AnyView(lateLabel(entry)) }
                    }
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .refreshable { await model.load() }
        }
        .crispTopEdge()
        .navyTitle(clinic.name)
        .toolbar {
            if clinic.status != "canceled" {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        // Decision 0012: cards are charged after the clinic, on her
                        // tap. Offered only once the clinic has ended.
                        if clinic.endsAt < Date() {
                            Button("Charge clinic") { confirmCharge = true }
                        }
                        Button("Cancel clinic", role: .destructive) { confirmCancelClinic = true }
                    } label: {
                        // The word, not an ellipsis: a Label in a toolbar renders
                        // icon-only on iOS 26 (seen 09-10), and an unlabelled icon
                        // breaks the icons-with-text rule.
                        Text("More")
                            .brandFont(.button)
                    }
                    .accessibilityIdentifier("admin.more")
                    .tint(Brand.textOnNavy)
                }
                .onNavy()
            }
        }
        .confirmationDialog(
            "Charge every card for \(clinic.name)? Attendees pay the clinic fee; no-shows and late cancellations pay the full fee.",
            isPresented: $confirmCharge, titleVisibility: .visible
        ) {
            Button("Charge clinic") {
                Task {
                    do {
                        // What Stripe answered for this clinic's fees, then
                        // the roster again, so each row's charge state is fresh.
                        let outcome = try await AdminRepository.chargeClinic(clinic.id)
                        chargeNote = ChargeSummary.text(outcome)
                        await model.load()
                    } catch {
                        let e = String(describing: error)
                        chargeNote = e.contains("payments_disabled") ? "Payments are switched off."
                            : e.contains("clinic_not_over") ? "The clinic hasn't ended yet."
                            : e.contains("clinic_canceled") ? "That clinic is canceled."
                            : e.contains("clinic_before_payments") ? "That clinic ended before card payments were on."
                            : "That didn't go through. Try again."
                    }
                }
            }
            Button("Not now", role: .cancel) {}
        }
        // Canceling tells everyone in You're In!, the Player Pool and Response
        // Needed. A confirmation with the consequence spelled out, because a
        // courtside mis-tap must not send that message.
        .confirmationDialog(
            "Cancel \(clinic.name)? Everyone registered or waiting is told.",
            isPresented: $confirmCancelClinic, titleVisibility: .visible
        ) {
            Button("Cancel clinic", role: .destructive) {
                Task {
                    do {
                        try await AdminRepository.cancelClinic(clinic.id)
                        await onChanged()
                        dismiss()
                    } catch {
                        cancelError = "That didn't save. Check your connection and try again."
                    }
                }
            }
            Button("Keep the clinic", role: .cancel) {}
        }
        .confirmationDialog(
            "Remove \(removing?.displayName ?? "this player") from \(clinic.name)?",
            isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let entry = removing {
                    Task { await model.perform(entry.id) {
                        try await RegistrationRepository.cancelRegistration(registrationId: entry.id)
                    } }
                }
                removing = nil
            }
            Button("Keep", role: .cancel) { removing = nil }
        }
        // Late cancel (20260927100002): the player told Tara inside the
        // cutoff. An alert, not a confirmation dialog, because it carries the
        // optional note the web roster shows beside "Fee applies".
        .alert(
            "Late cancel \(lateCanceling?.displayName ?? "this player")?",
            isPresented: Binding(get: { lateCanceling != nil }, set: { if !$0 { lateCanceling = nil } })
        ) {
            TextField("Note (optional)", text: $lateNote)
            Button("Late cancel", role: .destructive) {
                if let entry = lateCanceling {
                    let note = lateNote
                    Task { await model.perform(entry.id) {
                        try await AdminRepository.markLateCancel(registration: entry.id, note: note)
                    } }
                }
                lateCanceling = nil
            }
            Button("Keep", role: .cancel) { lateCanceling = nil }
        } message: {
            Text("The fee applies.")
        }
        .alert("Couldn't cancel", isPresented: Binding(get: { cancelError != nil }, set: { if !$0 { cancelError = nil } })) {
            Button("OK") { cancelError = nil }
        } message: { Text(cancelError ?? "") }
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        // The roster as it is now when Tara comes back to the app (MVP audit item 8).
        .reloadOnForeground { await model.load() }
        .sheet(isPresented: $showMessage) {
            MessageClinicSheet(clinic: clinic, unpaidCount: model.unpaidCount)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(dateLine)
                .brandFont(.subheadline)
                .foregroundStyle(Brand.textSecondary)
                .accessibilityIdentifier("roster.dateLine")

            // Admin-only counts, with capacity. Shown so Tara can decide, never
            // to stop her deciding.
            HStack(spacing: Brand.Spacing.sm) {
                countPill(Brand.Status.youreIn, model.youreIn.count, of: clinic.internalCapacity)
                countPill(Brand.Status.playerPool, model.pool.count, of: nil)
                if !model.responseNeeded.isEmpty {
                    countPill(Brand.Status.responseNeeded, model.responseNeeded.count, of: nil)
                }
            }

            Button {
                showMessage = true
            } label: {
                Label("Message Players", systemImage: "bubble.left.and.bubble.right")
                    .brandFont(.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Brand.Layout.comfortableTapTarget)
                    .foregroundStyle(Brand.textOnNavy)
                    .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("admin.messagePlayers")

            // One tap plus a confirmation: it messages several people at once,
            // and a mis-tap standing courtside should not do that.
            if model.zelleAllowed && model.unpaidCount > 0 {
                Button {
                    confirmRemind = true
                } label: {
                    Label("Remind unpaid (\(model.unpaidCount))", systemImage: "bell")
                        .brandFont(.button)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Brand.Layout.comfortableTapTarget)
                        .foregroundStyle(Brand.navy)
                        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.sm).stroke(Brand.navy, lineWidth: Brand.Layout.borderWidth))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("admin.remindUnpaid")
                .confirmationDialog(
                    "Send a payment reminder to \(model.unpaidCount) unpaid?",
                    isPresented: $confirmRemind, titleVisibility: .visible
                ) {
                    Button("Send reminder") {
                        Task {
                            do {
                                try await AdminRepository.remindUnpaid(clinic: clinic)
                                remindNote = "Reminder sent to \(model.unpaidCount)."
                            } catch {
                                remindNote = "The reminder didn't send. Check your connection and try again."
                            }
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                }
            }

            if let remindNote {
                Text(remindNote)
                    .brandFont(.caption)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityIdentifier("admin.remindNote")
            }
            if let chargeNote {
                Text(chargeNote)
                    .brandFont(.caption)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityIdentifier("admin.chargeNote")
            }
        }
    }

    private func rosterSection(
        _ status: Brand.Status,
        _ entries: [RosterEntry],
        empty: String,
        numbered: Bool = false,
        showsHistory: Bool = false,
        @ViewBuilder trailing: @escaping (RosterEntry) -> AnyView
    ) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            HStack {
                StatusChip(status)
                Spacer()
                Text("\(entries.count)")
                    .brandFont(.chip)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityIdentifier("roster.count")
            }

            if entries.isEmpty {
                if !empty.isEmpty {
                    Text(empty)
                        .brandFont(.body)
                        .foregroundStyle(Brand.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        // The Player Pool's rows carry the player's history
                        // (decision 0027 §1); the other lists do not.
                        let history = showsHistory ? model.history[entry.registration.playerId]?.line : nil
                        // Side by side at the usual text sizes, stacked at the
                        // accessibility sizes, as ONE layout whose parts keep
                        // their identity when it changes; a long name wraps.
                        // This was ViewThatFits, which builds two copies of
                        // the row and swaps them as the text grows: Apple's
                        // audit lost each text part way up the sizes and
                        // reported "Dynamic Type partially unsupported" on
                        // every name, court and toggle, found 2026-09-28 the
                        // first time a seeded roster had rows in it (the pro's
                        // Today Drill). The pro's Today tab has the same fix.
                        let layout = typeSize.isAccessibilitySize
                            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Brand.Spacing.xxs))
                            : AnyLayout(HStackLayout(alignment: .center, spacing: Brand.Spacing.sm))
                        layout {
                            rosterIdentity(entry, index: numbered ? index + 1 : nil, history: history)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            trailing(entry)
                        }
                        .padding(.vertical, Brand.Spacing.xs)
                        .frame(minHeight: Brand.Layout.comfortableTapTarget)

                        if entry.id != entries.last?.id {
                            Divider().background(Brand.hairline)
                        }
                    }
                }
                .padding(.horizontal, Brand.Spacing.cardPadding)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
            }
        }
    }

    /// "Can I still get in?" asks, with the two answers Tara can give. Only
    /// shown when there are any: an empty section would be noise on the
    /// screen she uses most. Approving re-checks capacity server-side.
    @ViewBuilder private var lateRequestSection: some View {
        if !model.lateRequests.isEmpty {
            VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                HStack {
                    StatusChip(.responseNeeded)
                    Text("asking to get in")
                        .brandFont(.caption)
                        .foregroundStyle(Brand.textSecondary)
                    Spacer()
                    Text("\(model.lateRequests.count)")
                        .brandFont(.chip)
                        .foregroundStyle(Brand.textSecondary)
                }
                VStack(spacing: 0) {
                    ForEach(model.lateRequests, id: \.request.id) { item in
                        HStack(spacing: Brand.Spacing.sm) {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(item.player.map { "\($0.firstName) \($0.lastName)" } ?? "Unknown player")
                                    .brandFont(.bodyEmphasis)
                                    .foregroundStyle(Brand.textPrimary)
                                if let m = item.request.message, !m.isEmpty {
                                    Text("“\(m)”")
                                        .brandFont(.caption)
                                        .foregroundStyle(Brand.textSecondary)
                                }
                            }
                            Spacer(minLength: Brand.Spacing.xs)
                            Button {
                                Task { await model.perform(item.request.id) {
                                    try await AdminRepository.resolveLateRequest(id: item.request.id, approve: false)
                                } }
                            } label: {
                                Text("No room")
                                    .brandFont(.chip)
                                    .foregroundStyle(Brand.Status.canceled.ink)
                                    .frame(minHeight: Brand.Layout.minTapTarget)
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("admin.lateDecline")
                            // Not into a canceled clinic (20260928400001 refuses
                            // it); No room still clears the request.
                            if clinic.status != "canceled" {
                                Button {
                                    Task { await model.perform(item.request.id) {
                                        try await AdminRepository.resolveLateRequest(id: item.request.id, approve: true)
                                    } }
                                } label: {
                                    Text("Put them in")
                                        .brandFont(.chip)
                                        .foregroundStyle(Brand.textOnNavy)
                                        .padding(.horizontal, Brand.Spacing.sm)
                                        .frame(minHeight: Brand.Layout.minTapTarget)
                                        .background(Capsule().fill(Brand.navy))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("admin.lateApprove")
                            }
                        }
                        .padding(.vertical, Brand.Spacing.xs)
                        .disabled(model.busy.contains(item.request.id))
                        if item.request.id != model.lateRequests.last?.request.id {
                            Divider().background(Brand.hairline)
                        }
                    }
                }
                .padding(.horizontal, Brand.Spacing.cardPadding)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
            }
        }
    }

    /// Name and subtitle, with the Player Pool's queue number when asked for:
    /// the guide requires registration order to be visible, and it is what
    /// makes the queue legible to Tara.
    private func rosterIdentity(_ entry: RosterEntry, index: Int?, history: String? = nil) -> some View {
        HStack(spacing: Brand.Spacing.sm) {
            if let index {
                Text("\(index)")
                    .brandFont(.chip)
                    .foregroundStyle(Brand.textSecondary)
                    .frame(width: 18, alignment: .trailing)
            }
            VStack(alignment: .leading, spacing: 1) {
                Text(entry.displayName)
                    .brandFont(.bodyEmphasis)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(entry.subtitle)
                    .brandFont(.caption)
                    .foregroundStyle(Brand.textSecondary)
                // "12 played · 1 no-show · 2 late cancels", or "New".
                if let history {
                    Text(history)
                        .brandFont(.caption)
                        .foregroundStyle(Brand.textSecondary)
                        .accessibilityIdentifier("admin.poolHistory")
                }
                // The note left with a late cancel, the player's or Tara's.
                if let note = entry.lateNote {
                    Text(note)
                        .brandFont(.caption)
                        .foregroundStyle(Brand.textSecondary)
                        .lineLimit(3)
                }
            }
        }
    }

    /// "Late · Fee applies" on a late cancel in the Canceled list (the web
    /// roster's words); nothing on any other canceled row.
    @ViewBuilder private func lateLabel(_ entry: RosterEntry) -> some View {
        if let label = entry.lateLabel {
            Text(label)
                .brandFont(.chip)
                .foregroundStyle(Brand.Status.canceled.ink)
        }
    }

    /// A declined card, courtside: the row reads "Declined" until a retry
    /// goes through. The name and Stripe's reason are in Action Needed and in
    /// the summary after Charge clinic.
    @ViewBuilder private func declinedLabel(_ entry: RosterEntry) -> some View {
        if entry.registration.chargeStatus == "failed" {
            Text("Declined")
                .brandFont(.chip)
                .foregroundStyle(Brand.Status.canceled.ink)
        }
    }

    // MARK: - Row actions

    /// Court 1-5 or none. A menu, not a picker wheel: one tap opens, one tap
    /// chooses, standing courtside. The label always shows the current value so
    /// the roster reads as her court sheet without opening anything.
    private func courtMenu(_ entry: RosterEntry) -> some View {
        let current = entry.registration.courtNumber
        return Menu {
            Button("No court") { assign(entry, nil) }
            ForEach(1...5, id: \.self) { n in
                Button("Court \(n)") { assign(entry, n) }
            }
            Divider()
            // A player who told Tara inside the cutoff (a text an hour
            // before): off You're In!, marked late, the fee applies
            // (20260927100002). Only while the server would accept it.
            if model.canLateCancel(entry) {
                Button("Late cancel") { lateNote = ""; lateCanceling = entry }
            }
            // A walk-up placed on the wrong clinic, or a player who told Tara
            // in person. Same RPC the player's own Cancel uses; the row is
            // kept as canceled, never deleted (hard rule 4). Never late, and
            // since 20260927100002 not echoed back as the player canceling.
            // Not on a charged spot: the server refuses it (charged_refund_first,
            // 20260927300002), because the fee would stay taken with nothing
            // on any screen saying a refund is owed. Refund first.
            if !entry.registration.hasLiveCharge {
                Button("Remove from clinic", role: .destructive) { removing = entry }
            }
        } label: {
            Label(current.map { "Court \($0)" } ?? "Court", systemImage: "rectangle.split.2x1")
                .brandFont(.chip)
                .foregroundStyle(current == nil ? Brand.textSecondary : Brand.navy)
                .frame(minHeight: Brand.Layout.minTapTarget)
        }
        .disabled(model.busy.contains(entry.id))
        .accessibilityIdentifier("admin.court")
        .accessibilityLabel("\(entry.displayName), \(current.map { "court \($0)" } ?? "no court"). Tap to change.")
    }

    private func assign(_ entry: RosterEntry, _ court: Int?) {
        Task { await model.perform(entry.id) {
            try await AdminRepository.assignCourt(registration: entry.id, court: court)
        } }
    }

    /// Decision 0012: who did not come. Charged the full fee by the tap.
    private func noShowToggle(_ entry: RosterEntry) -> some View {
        let noShow = entry.registration.noShow ?? false
        return Button {
            Task { await model.perform(entry.id) {
                try await AdminRepository.setNoShow(registration: entry.id, noShow: !noShow)
            } }
        } label: {
            Label(noShow ? "No-show" : "Came", systemImage: noShow ? "person.fill.xmark" : "person.fill.checkmark")
                .brandFont(.chip)
                .foregroundStyle(noShow ? Brand.Status.canceled.ink : Brand.textSecondary)
                .frame(minHeight: Brand.Layout.minTapTarget)
                // The whole 44-point frame is the button, not just the text:
                // a plain button hit-tests its visible pixels, and the audit
                // measured this one at 15 points tall (2026-09-28).
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy.contains(entry.id))
        .accessibilityIdentifier("admin.noShowToggle")
    }

    private func paidToggle(_ entry: RosterEntry) -> some View {
        let paid = entry.registration.paid
        return Button {
            Task { await model.perform(entry.id) {
                try await AdminRepository.setPaid(registration: entry.id, paid: !paid)
            } }
        } label: {
            // Icon PLUS text: an unlabelled checkbox is exactly the case
            // CLAUDE.md's "icons always paired with text labels" rule is for.
            Label(paid ? "Paid" : "Unpaid", systemImage: paid ? "checkmark.circle.fill" : "circle")
                .brandFont(.chip)
                .foregroundStyle(paid ? Brand.Status.youreIn.ink : Brand.textSecondary)
                .frame(minHeight: Brand.Layout.minTapTarget)
        }
        .buttonStyle(.plain)
        .disabled(model.busy.contains(entry.id))
        .accessibilityIdentifier("admin.paidToggle")
        .accessibilityLabel("\(entry.displayName), \(paid ? "paid" : "unpaid"). Tap to change.")
    }

    private func inviteButton(_ entry: RosterEntry) -> some View {
        Button {
            Task { await model.perform(entry.id) {
                try await AdminRepository.invite(registration: entry.id)
            } }
        } label: {
            Text("Invite")
                .brandFont(.chip)
                .foregroundStyle(Brand.textOnNavy)
                .padding(.horizontal, Brand.Spacing.sm)
                .frame(minHeight: Brand.Layout.minTapTarget)
                .background(Capsule().fill(Brand.navy))
        }
        .buttonStyle(.plain)
        .disabled(model.busy.contains(entry.id))
        .accessibilityIdentifier("admin.invite")
        .accessibilityLabel("Invite \(entry.displayName)")
    }

    /// Out of the Player Pool, behind the same confirmation as You're In!'s
    /// Remove. Until 2026-09-28 no screen could do this, so her own "You've
    /// been removed from the Player Pool" (#6, decision 0022) could never be
    /// sent; the server sends it from this same cancel_registration.
    private func removeFromPoolButton(_ entry: RosterEntry) -> some View {
        Button { removing = entry } label: {
            Text("Remove")
                .brandFont(.chip)
                .foregroundStyle(Brand.Status.canceled.ink)
                .padding(.horizontal, Brand.Spacing.xs)
                .frame(minHeight: Brand.Layout.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy.contains(entry.id))
        .accessibilityIdentifier("admin.removeFromPool")
        .accessibilityLabel("Remove \(entry.displayName) from the Player Pool")
    }

    private func cancelInviteButton(_ entry: RosterEntry) -> some View {
        Button {
            Task { await model.perform(entry.id) {
                try await AdminRepository.cancelInvitation(registration: entry.id)
            } }
        } label: {
            Text("Cancel Invite")
                .brandFont(.chip)
                .foregroundStyle(Brand.Status.canceled.ink)
                .frame(minHeight: Brand.Layout.minTapTarget)
        }
        .buttonStyle(.plain)
        .disabled(model.busy.contains(entry.id))
        .accessibilityIdentifier("admin.cancelInvite")
        .accessibilityLabel("Cancel the invitation to \(entry.displayName)")
    }

    private func countPill(_ status: Brand.Status, _ n: Int, of capacity: Int?) -> some View {
        Text(capacity.map { "\(status.label) \(n)/\($0)" } ?? "\(status.label) \(n)")
            .brandFont(.chip)
            .foregroundStyle(status.ink)
            .padding(.horizontal, Brand.Spacing.xs)
            .padding(.vertical, 3)
            .background(Capsule().fill(status.tint))
    }

    private var dateLine: String {
        clinic.startsAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        + ", "
        + clinic.startsAt.formatted(.dateTime.hour().minute())
        + " to "
        + clinic.endsAt.formatted(.dateTime.hour().minute())
    }
}

// MARK: - Message sheet

/// Compose a clinic message to one audience. Push only, no duplicate email, and
/// it stays on the clinic page for that audience (decision 0005).
private struct MessageClinicSheet: View {
    let clinic: ClinicAdmin
    let unpaidCount: Int

    @Environment(\.dismiss) private var dismiss
    @State private var audience: MessageAudience = .everyone
    @State private var body_ = ""
    @State private var sending = false
    @State private var error: String?
    /// Her saved messages (decision 0030): the Saved menu and Save this message.
    @State private var saved = SavedMessagesModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surfaceGradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: Brand.Spacing.md) {
                    Text("To")
                        .brandFont(.subheadline)
                        .foregroundStyle(Brand.textSecondary)

                    Picker("To", selection: $audience) {
                        ForEach(MessageAudience.allCases) { a in
                            Text(a.label).tag(a)
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(Brand.navy)
                    .accessibilityIdentifier("admin.messageAudience")

                    if audience == .unpaid {
                        Text("\(unpaidCount) unpaid.")
                            .brandFont(.caption)
                            .foregroundStyle(Brand.textSecondary)
                    }

                    SavedMessagesMenu(model: saved, text: $body_)

                    TextEditor(text: $body_)
                        .brandFont(.body)
                        .frame(minHeight: 140)
                        .padding(Brand.Spacing.xs)
                        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.sm).stroke(Brand.border, lineWidth: Brand.Layout.borderWidth))
                        .accessibilityIdentifier("admin.messageBody")
                        .accessibilityLabel("Message")

                    SaveMessageButton(model: saved, text: body_)

                    if let error = error ?? saved.error {
                        Text(error)
                            .brandFont(.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                    }

                    Spacer()
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .crispTopEdge()
            .navyTitle("Message Players")
            .navigationBarTitleDisplayMode(.inline)
            .task { await saved.load() }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                    .tint(Brand.textOnNavy)
                }
                .onNavy()
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sending…" : "Send") { send() }
                        .disabled(sending || body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("admin.sendMessage")
                    .tint(Brand.textOnNavy)
                }
                .onNavy()
            }
        }
    }

    private func send() {
        sending = true
        Task {
            do {
                try await AdminRepository.sendMessage(
                    clinic: clinic.id,
                    audience: audience,
                    body: body_.trimmingCharacters(in: .whitespacesAndNewlines)
                )
                dismiss()
            } catch {
                self.error = "The message didn't send. Check your connection and try again."
            }
            sending = false
        }
    }
}

/// What Tara reads after Charge clinic. Was "Charged 6. Already charged 0. No
/// card 1.", which she marked Change on 2026-09-22 (decision 0016). Plain
/// sentences, zero counts left out. Chrome, listed for Alex's tick.
///
/// Since 2026-09-27 "Charged" counts what Stripe accepted, not what was
/// queued, and each declined card is named with its reason (the audit found
/// "Charged 6" printed when all six declined). The web admin's
/// chargeSummaryText is the same sentences.
enum ChargeSummary {
    /// One declined card: the cardholder and Stripe's reason in words.
    struct Decline: Equatable, Sendable {
        let name: String
        let reason: String?
    }

    static func text(paid: Int, declined: [Decline] = [], processing: Int = 0, already: Int, noCard: Int) -> String {
        var parts = [paid == 1 ? "Charged 1 card." : "Charged \(paid) cards."]
        for d in declined {
            if let reason = d.reason, !reason.isEmpty {
                parts.append("\(d.name)'s card was declined: \(reason).")
            } else {
                parts.append("\(d.name)'s card was declined.")
            }
        }
        if processing > 0 { parts.append(processing == 1 ? "1 is still processing." : "\(processing) are still processing.") }
        if already > 0 { parts.append(already == 1 ? "1 was already charged." : "\(already) were already charged.") }
        if noCard > 0 { parts.append(noCard == 1 ? "1 player has no card on file." : "\(noCard) players have no card on file.") }
        return parts.joined(separator: " ")
    }

    static func text(_ o: ChargeOutcome) -> String {
        text(paid: o.paid, declined: o.declined, processing: o.processing, already: o.already, noCard: o.noCard)
    }
}

/// What one Charge clinic tap came to, from Stripe's answers.
struct ChargeOutcome: Equatable, Sendable {
    /// One of this clinic's fees that stripe-charge took, named by the ledger.
    struct Fee: Sendable {
        let id: UUID
        let name: String
        let reason: String?
    }

    var paid = 0
    var declined: [ChargeSummary.Decline] = []
    var processing = 0
    var already = 0
    var noCard = 0

    /// `statuses`: Stripe's status per payment id, for every row stripe-charge
    /// took (any clinic). `fees`: this clinic's fees among them. `queued`: rows
    /// this tap created (admin_charge_clinic's `charged`); any Stripe has not
    /// answered for yet count as still processing.
    static func tally(statuses: [UUID: String], fees: [Fee], queued: Int, already: Int, noCard: Int) -> ChargeOutcome {
        var outcome = ChargeOutcome(already: already, noCard: noCard)
        var answered = 0
        for fee in fees {
            guard let status = statuses[fee.id] else { continue }
            answered += 1
            switch status {
            case "succeeded": outcome.paid += 1
            case "failed": outcome.declined.append(.init(name: fee.name, reason: fee.reason))
            default: outcome.processing += 1
            }
        }
        // Queued by this tap, not answered by Stripe yet.
        outcome.processing += max(0, queued - answered)
        return outcome
    }
}
