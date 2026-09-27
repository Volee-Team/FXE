//
//  ClinicDetailView.swift
//  FXETennis
//
//  One clinic, full detail, and the single primary action for the player's
//  current state. The action shown is driven entirely by their registration
//  status, per the Developer Guide's "one appropriate primary action" rule:
//    not registered + open   -> Register
//    You're In!              -> Cancel Registration
//    Player Pool             -> Leave Player Pool
//    Response Needed         -> Accept / Decline
//    not open yet            -> "Registration opens ..."
//    canceled clinic         -> Canceled banner, no action
//
//  Still hides everything players must not see: no capacity, no counts, no other
//  players, no court, no location. Only this player's own status.
//

import SwiftUI

@MainActor
@Observable
final class ClinicDetailModel {
    var registration: MyRegistration?
    var messages: [ClinicMessage] = []
    var working = false
    var notice: String?      // friendly "someone got there first" / error text
    var loaded = false
    /// Set once the player has asked Tara to fit them in after registration
    /// closed. Kept on the model rather than derived from the server so the
    /// screen changes the instant she is messaged; `late_requests` has a unique
    /// index on (clinic, player) while pending, so a double tap is refused
    /// server-side regardless.
    var lateRequestSent = false

    /// Ask Tara to fit this player in after registration has closed.
    ///
    /// Not a registration: `request_late_spot` creates a request she approves or
    /// declines, because hard rule 2 says only she puts anyone in a clinic.
    func requestLateSpot(clinicId: UUID, playerId: UUID) async throws {
        _ = try await RegistrationRepository.requestLateSpot(
            clinicId: clinicId, playerId: playerId, message: nil)
        lateRequestSent = true
    }

    func load(clinicId: UUID) async {
        do {
            let regs = try await RegistrationRepository.mine()
            registration = regs.first { $0.clinicId == clinicId && $0.status != .canceled }
            messages = try await ClinicRepository.messages(clinicId: clinicId)
        } catch {
            let failure = RequestFailure(error)
            if failure != .cancelled {
                notice = failure.line ?? "Couldn't load this clinic."
            }
        }
        loaded = true
    }

    /// What a failed action tells the player, and which onboarding step the
    /// server's refusal should reopen.
    struct FailureOutcome: Equatable {
        let notice: String?
        let reopens: SessionStore.Gate?
    }

    /// The refusals this screen can explain, then what the request met. Only
    /// a real answer from the server is read as a race: a timeout or no signal
    /// used to read "someone beat you to the punch", so she did not retry and
    /// lost her place (MVP audit item 9).
    nonisolated static func outcome(for error: Error) -> FailureOutcome {
        let text = String(describing: error)
        // A card on file is required to register once payments are on
        // (decision 0012). The card step reopens with fresh switches.
        if text.contains("card_required") {
            return FailureOutcome(notice: "Add a card on your Profile to register.", reopens: .card)
        }
        // A new waiver version, or a check that failed at launch: the sheet
        // reopens (decision 0013 §4). The words stay, under the sheet.
        if text.contains("waiver_required") {
            return FailureOutcome(notice: "Sign the waiver first.", reopens: .waiver)
        }
        // Decision 0015 §13. Placeholder words until Tara writes them
        // (question 63); without this line a blocked non-member was
        // told someone beat them to the punch, which is not what happened.
        if text.contains("back_to_back_105") {
            return FailureOutcome(notice: "Non-members can take one 105 a day until 48 hours before.", reopens: nil)
        }
        let failure = RequestFailure(error)
        switch failure {
        case .unreachable, .rateLimited:
            return FailureOutcome(notice: failure.line, reopens: nil)
        case .cancelled:
            return FailureOutcome(notice: nil, reopens: nil)
        case .other:
            // The server answered and refused: every other refusal is a race,
            // and the reload shows the real state.
            return FailureOutcome(notice: "Sorry, someone beat you to the punch. Here's the latest!", reopens: nil)
        }
    }

    /// Runs an action, surfaces a friendly notice on failure, and reloads so the
    /// button reflects the new truth. Every transition is conditional server-side
    /// (hard rule 3); a race just means the reload shows the real state.
    func act(clinicId: UUID, _ work: @escaping () async throws -> Void,
             onChanged: () async -> Void,
             reopen: (SessionStore.Gate) async -> Void = { _ in }) async {
        working = true; notice = nil
        do {
            try await work()
            await load(clinicId: clinicId)
            await onChanged()
        } catch {
            await load(clinicId: clinicId)
            let outcome = Self.outcome(for: error)
            notice = outcome.notice
            if let gate = outcome.reopens { await reopen(gate) }
        }
        working = false
    }
}

/// A destructive action waiting for the player to confirm it.
///
/// Exists because all three irreversible taps used to fire instantly: one
/// mistap standing courtside and you were out of the clinic, with re-registering
/// possibly landing you at the BACK of the Player Pool. The spec's own rule is
/// that destructive actions confirm first. Identifiable so a single
/// confirmationDialog serves every destructive button on the screen.
private struct PendingAction: Identifiable {
    let id = UUID()
    let title: String       // what the button said, repeated as the question
    let confirmLabel: String// distinct from the button label, so a UI test (and
                            // a person) can tell the two apart at a glance
    let work: () async throws -> Void
}

struct ClinicDetailView: View {
    @State private var pending: PendingAction?
    /// Inside the cutoff the cancel needs the player's note first (0010).
    @State private var lateCancel: MyRegistration?
    @State private var cutoffHours = 3
    let clinic: ClinicPublic
    let isMember: Bool
    var onChanged: () async -> Void = {}

    @Environment(SessionStore.self) private var session
    /// Accept and Decline stack at the accessibility text sizes.
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model = ClinicDetailModel()

    private var openMoment: Date? { isMember ? clinic.memberOpensAt : clinic.publicOpensAt }
    private func isOpen(at now: Date) -> Bool {
        guard let openMoment else { return true }
        return openMoment <= now
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                header
                if clinic.isCanceled { canceledBanner }
                detailCard
                messageBoard
                if let notice = model.notice { noticeText(notice) }
                // Redrawn at this viewer's opening, the close and the start,
                // so Register appears at 8:00 on the second and gives way to
                // the late-request door at the close, with nobody pulling to
                // refresh (MVP audit item 8). The clock is read at each draw.
                TimelineView(.explicit(RedrawSchedule.at(clinic.upcomingMoments(isMember: isMember)))) { _ in
                    confirmDialog(actionArea(now: Date()))
                }
            }
            .padding(Brand.Spacing.pageMargin)
        }
        .background(CourtBackdrop())
        .navigationTitle(clinic.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if !model.loaded { await model.load(clinicId: clinic.id) } }
        .task {
            cutoffHours = (try? await RegistrationRepository.cancelCutoffHours()) ?? 3
        }
        .sheet(item: $lateCancel) { reg in
            LateCancelSheet { note in
                await run {
                    try await RegistrationRepository.cancelRegistration(registrationId: reg.id, note: note)
                }
            }
        }
        .refreshable { await model.load(clinicId: clinic.id) }
        // A Pool player who left this page open sees Response Needed when she
        // comes back to the app, not the state from before (MVP audit item 8).
        .reloadOnForeground { await model.load(clinicId: clinic.id) }
    }

    /// Every action on this screen goes through here, so a refusal for the
    /// waiver or the card reopens that step (SessionStore.reopen).
    private func run(_ work: @escaping () async throws -> Void) async {
        await model.act(clinicId: clinic.id, work, onChanged: onChanged,
                        reopen: { gate in await session.reopen(gate) })
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(clinic.name)
                .font(Brand.Typography.display)
                .foregroundStyle(Brand.navy)
            if let reg = model.registration {
                StatusChip(reg.status.display)
                    .accessibilityIdentifier("clinic.statusChip")
            }
        }
    }

    private var canceledBanner: some View {
        Text("This clinic has been canceled.")
            .font(Brand.Typography.bodyEmphasis)
            .foregroundStyle(Brand.Status.canceled.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Brand.Spacing.md)
            .background(Brand.Status.canceled.tint, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
    }

    // MARK: detail

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            detailRow("calendar", clinic.startsAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            detailRow("clock", timeRange)
            if let price = clinic.priceCents(forMember: isMember) {
                detailRow("tennisball", "\(durationLine) · \(price.centsAsPrice)")
            }
            if let desc = clinic.description, !desc.isEmpty {
                Divider().overlay(Brand.hairline)
                Text(desc)
                    .font(Brand.Typography.body)
                    .foregroundStyle(Brand.textPrimary)
            }
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
    }

    private func detailRow(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(Brand.Typography.subheadline)
            .foregroundStyle(Brand.textSecondary)
    }

    // MARK: message board

    @ViewBuilder private var messageBoard: some View {
        if !model.messages.isEmpty {
            VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
                Text("FROM TARA").font(Brand.Typography.caption).foregroundStyle(Brand.textSecondary)
                ForEach(model.messages) { msg in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(msg.body).font(Brand.Typography.body).foregroundStyle(Brand.textPrimary)
                        Text(msg.sentAt.formatted(.dateTime.month().day().hour().minute()))
                            .font(Brand.Typography.caption).foregroundStyle(Brand.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Brand.Spacing.sm)
                    .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
                }
            }
        }
    }

    private func noticeText(_ text: String) -> some View {
        Text(text)
            .font(Brand.Typography.caption)
            .foregroundStyle(Brand.Status.playerPool.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: the one primary action

    /// One dialog for every destructive button. `item:` binding means the
    /// dialog always describes the action that summoned it.
    private func confirmDialog<V: View>(_ v: V) -> some View {
        v.confirmationDialog(
            pending?.title ?? "",
            isPresented: .init(get: { pending != nil }, set: { if !$0 { pending = nil } }),
            titleVisibility: .visible
        ) {
            if let p = pending {
                Button(p.confirmLabel, role: .destructive) {
                    Task { await run(p.work) }
                }
                Button("Keep my spot", role: .cancel) {}
            }
        }
    }

    @ViewBuilder private func actionArea(now: Date) -> some View {
        if clinic.isCanceled {
            EmptyView()
        } else if let reg = model.registration {
            switch reg.status {
            case .in_:
                if CancelPolicy.isInsideCutoff(startsAt: clinic.startsAt, cutoffHours: cutoffHours) {
                    // Same button, different path: the server refuses a late
                    // cancel without a note, so ask for it before the tap.
                    Button(role: .destructive) { lateCancel = reg } label: {
                        actionLabel("Cancel Registration", fg: Brand.Status.canceled.ink, bg: Brand.surfaceRaised)
                            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
                    }
                    .disabled(model.working)
                } else {
                    destructiveButton("Cancel Registration") {
                        try await RegistrationRepository.cancelRegistration(registrationId: reg.id)
                    }
                }
            case .pool:
                destructiveButton("Leave Player Pool") {
                    try await RegistrationRepository.leavePool(registrationId: reg.id)
                }
            case .responseNeeded:
                // Side by side, or stacked at the accessibility text sizes,
                // where half the width cannot hold "Decline".
                let layout = typeSize.isAccessibilitySize
                    ? AnyLayout(VStackLayout(spacing: Brand.Spacing.sm))
                    : AnyLayout(HStackLayout(spacing: Brand.Spacing.sm))
                layout {
                    primaryButton("Accept") {
                        try await RegistrationRepository.respondToInvitation(registrationId: reg.id, accept: true)
                    }
                    secondaryButton("Decline") {
                        try await RegistrationRepository.respondToInvitation(registrationId: reg.id, accept: false)
                    }
                }
            case .canceled:
                EmptyView()
            }
        } else if hasClosed(at: now) {
            // Registration has closed. Before 2026-08-27 this branch did not
            // exist: `closesAt` was decoded on ClinicPublic and read by NO view,
            // so the Register button stayed fully enabled on a closed clinic and
            // tapping it failed with a raw `registration_closed` from Postgres.
            // The server was right and the screen lied.
            //
            // Tara's answer covers this exact moment: "if they try to register
            // within 3 hours, they have the option to send me a direct message
            // to get into the clinic, assuming there is space and it isn't
            // full." So the closed state is not a dead end, it is a door.
            lateRequestArea
        } else if isOpen(at: now) {
            primaryButton("Register") {
                guard let playerId = session.activePlayer?.id else { return }
                _ = try await RegistrationRepository.register(clinicId: clinic.id, playerId: playerId)
            }
        } else if let openMoment {
            Text("Registration opens \(openMoment.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))")
                .font(Brand.Typography.subheadline)
                .foregroundStyle(Brand.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(Brand.Spacing.md)
        }
    }

    /// True once registration has closed but the clinic has not started.
    ///
    /// Deliberately NOT `closesAt < now` alone: after the clinic has begun there
    /// is nothing to ask for, and offering to message Tara about a session she
    /// is already coaching would be worse than saying nothing.
    private func hasClosed(at now: Date) -> Bool {
        guard let closes = clinic.closesAt else { return false }
        return closes <= now && now < clinic.startsAt
    }

    /// The closed-window state: explain why, then offer the way through.
    ///
    /// Copy note: every sentence here is functional rather than promotional, and
    /// the ask is phrased as messaging Tara because that is exactly how she
    /// described it. It is chrome under hard rule 13, but it is chrome about a
    /// disappointment, so it says what happened and what can be done rather than
    /// apologising.
    @ViewBuilder private var lateRequestArea: some View {
        VStack(spacing: Brand.Spacing.sm) {
            if model.lateRequestSent {
                HStack(spacing: Brand.Spacing.xs) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundStyle(Brand.Status.youreIn.ink)
                    Text("Tara has your message.")
                        .font(Brand.Typography.bodyEmphasis)
                        .foregroundStyle(Brand.textPrimary)
                }
                Text("She will let you know as soon as possible if there is room in this clinic")
                    .font(Brand.Typography.subheadline)
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)
            } else {
                Text("Registration has closed for this clinic.")
                    .font(Brand.Typography.bodyEmphasis)
                    .foregroundStyle(Brand.textPrimary)
                Text("You can still ask Tara to fit you in.")
                    .font(Brand.Typography.subheadline)
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.center)

                primaryButton("Message Tara") {
                    guard let playerId = session.activePlayer?.id else { return }
                    try await model.requestLateSpot(clinicId: clinic.id, playerId: playerId)
                }
                .accessibilityIdentifier("clinic.lateRequest")
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, Brand.Spacing.xs)
    }

    // MARK: button builders

    private func primaryButton(_ title: String, _ work: @escaping () async throws -> Void) -> some View {
        Button {
            Task { await run(work) }
        } label: {
            actionLabel(title, fg: Brand.textOnNavy, bg: Brand.navy)
        }
        .disabled(model.working)
    }

    private func secondaryButton(_ title: String, _ work: @escaping () async throws -> Void) -> some View {
        Button {
            Task { await run(work) }
        } label: {
            actionLabel(title, fg: Brand.navy, bg: Brand.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.navy, lineWidth: Brand.Layout.borderWidth))
        }
        .disabled(model.working)
    }

    private func destructiveButton(_ title: String, _ work: @escaping () async throws -> Void) -> some View {
        Button(role: .destructive) {
            // Ask first. The dialog's confirm button carries a DIFFERENT label
            // than this button, so "Cancel Registration" is never one ambiguous
            // tap away from "Cancel" meaning keep-my-spot.
            let confirm = title == "Cancel Registration"
                ? "Yes, cancel my spot" : "Yes, leave the pool"
            pending = PendingAction(title: title, confirmLabel: confirm, work: work)
        } label: {
            actionLabel(title, fg: Brand.Status.canceled.ink, bg: Brand.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
        }
        .disabled(model.working)
    }

    private func actionLabel(_ title: String, fg: Color, bg: Color) -> some View {
        Group {
            if model.working { ProgressView().tint(fg) }
            else { Text(title).font(Brand.Typography.button) }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: Brand.Layout.comfortableTapTarget)
        .background(bg, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
        .foregroundStyle(fg)
        .accessibilityIdentifier("clinic.primaryAction")
        .accessibilityLabel(title)
    }

    private var timeRange: String {
        clinic.startsAt.formatted(.dateTime.hour().minute())
        + " – "
        + clinic.endsAt.formatted(.dateTime.hour().minute())
    }
    private var durationLine: String {
        if let d = clinic.durationMinutes { return "\(d) min" }
        return "Clinic"
    }
}

/// The prompt inside the cutoff (decision 0013). The sentence is Tara's,
/// verbatim from her 2026-09-16 answer to question 40 with the 3 hours she
/// gave on 2026-09-21 ("3 hours instead of 4. Otherwise good"). No courtesy
/// exists any more. The note is optional and is the player's own words.
private struct LateCancelSheet: View {
    let confirm: (String) async -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var note = ""
    @State private var sending = false
    @FocusState private var focused: Bool

    private var trimmed: String { note.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: Brand.Spacing.md) {
                // Tara's words, 2026-09-22 round-two review (decision 0016).
                Text("This cancellation is within 3 hours of clinic and the full clinic fee will apply. If an emergency, please leave a note below.")
                    .font(Brand.Typography.body)
                    .foregroundStyle(Brand.textPrimary)
                    .accessibilityIdentifier("lateCancel.sentence")
                TextField("Note for Tara (optional)", text: $note, axis: .vertical)
                    .lineLimit(3...6)
                    .textFieldStyle(.roundedBorder)
                    .focused($focused)
                    .accessibilityIdentifier("lateCancel.note")
                Button {
                    sending = true
                    Task { await confirm(trimmed); sending = false; dismiss() }
                } label: {
                    Group {
                        if sending { ProgressView().tint(Brand.textOnNavy) }
                        else { Text("Cancel my spot").font(Brand.Typography.button) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Brand.Layout.comfortableTapTarget)
                    .foregroundStyle(Brand.textOnNavy)
                    .background(Brand.Status.canceled.ink, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(sending)
                .accessibilityIdentifier("lateCancel.confirm")
                Spacer()
            }
            .padding(Brand.Spacing.pageMargin)
            .background(Brand.surfaceGradient)
            .navigationTitle("Cancel Registration")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Keep my spot") { dismiss() }
                }
            }
            .onAppear { focused = true }
        }
    }
}
