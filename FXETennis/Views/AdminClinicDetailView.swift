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

    var youreIn: [RosterEntry] { roster.filter { $0.registration.status == .in_ } }
    var pool: [RosterEntry] { roster.filter { $0.registration.status == .pool } }
    var responseNeeded: [RosterEntry] { roster.filter { $0.registration.status == .responseNeeded } }
    var canceled: [RosterEntry] { roster.filter { $0.registration.status == .canceled } }
    var unpaidCount: Int { youreIn.filter { !$0.registration.paid }.count }

    func load() async {
        loading = true
        defer { loading = false }
        do {
            roster = try await AdminRepository.roster(clinic: clinic.id)
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
            self.error = "That didn't go through. Check your connection and try again."
        }
    }
}

struct AdminClinicDetailView: View {
    let clinic: ClinicAdmin
    @State private var model: AdminClinicModel
    @State private var showMessage = false

    init(clinic: ClinicAdmin) {
        self.clinic = clinic
        _model = State(initialValue: AdminClinicModel(clinic: clinic))
    }

    var body: some View {
        ZStack {
            Brand.surface.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    header

                    if let error = model.error {
                        Text(error)
                            .font(Brand.Typography.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                    }

                    rosterSection(
                        Brand.Status.youreIn, model.youreIn,
                        empty: "Nobody is in yet."
                    ) { entry in AnyView(paidToggle(entry)) }

                    rosterSection(
                        Brand.Status.playerPool, model.pool,
                        empty: "The Player Pool is empty.",
                        numbered: true
                    ) { entry in AnyView(inviteButton(entry)) }

                    rosterSection(
                        Brand.Status.responseNeeded, model.responseNeeded,
                        empty: ""
                    ) { entry in AnyView(cancelInviteButton(entry)) }

                    // Canceled stays visible: hard rule 4, and Screen 14 says
                    // "Keep canceled players visible to Tara."
                    if !model.canceled.isEmpty {
                        rosterSection(Brand.Status.canceled, model.canceled, empty: "") { _ in AnyView(EmptyView()) }
                    }
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .refreshable { await model.load() }
        }
        .navigationTitle(clinic.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .sheet(isPresented: $showMessage) {
            MessageClinicSheet(clinic: clinic, unpaidCount: model.unpaidCount)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(dateLine)
                .font(Brand.Typography.subheadline)
                .foregroundStyle(Brand.textSecondary)

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
                    .font(Brand.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Brand.Layout.comfortableTapTarget)
                    .foregroundStyle(Brand.textOnNavy)
                    .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("admin.messagePlayers")
        }
    }

    private func rosterSection(
        _ status: Brand.Status,
        _ entries: [RosterEntry],
        empty: String,
        numbered: Bool = false,
        @ViewBuilder trailing: @escaping (RosterEntry) -> AnyView
    ) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            HStack {
                StatusChip(status)
                Spacer()
                Text("\(entries.count)")
                    .font(Brand.Typography.chip)
                    .foregroundStyle(Brand.textSecondary)
            }

            if entries.isEmpty {
                if !empty.isEmpty {
                    Text(empty)
                        .font(Brand.Typography.body)
                        .foregroundStyle(Brand.textSecondary)
                }
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(entries.enumerated()), id: \.element.id) { index, entry in
                        HStack(spacing: Brand.Spacing.sm) {
                            // Registration order is visible for the Player Pool
                            // specifically: the guide requires it, and it is
                            // what makes the queue legible to Tara.
                            if numbered {
                                Text("\(index + 1)")
                                    .font(Brand.Typography.chip)
                                    .foregroundStyle(Brand.textSecondary)
                                    .frame(width: 18, alignment: .trailing)
                            }

                            VStack(alignment: .leading, spacing: 1) {
                                Text(entry.displayName)
                                    .font(Brand.Typography.bodyEmphasis)
                                    .foregroundStyle(Brand.textPrimary)
                                Text(entry.subtitle)
                                    .font(Brand.Typography.caption)
                                    .foregroundStyle(Brand.textSecondary)
                            }

                            Spacer(minLength: Brand.Spacing.xs)
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

    // MARK: - Row actions

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
                .font(Brand.Typography.chip)
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
                .font(Brand.Typography.chip)
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

    private func cancelInviteButton(_ entry: RosterEntry) -> some View {
        Button {
            Task { await model.perform(entry.id) {
                try await AdminRepository.cancelInvitation(registration: entry.id)
            } }
        } label: {
            Text("Cancel Invite")
                .font(Brand.Typography.chip)
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
            .font(Brand.Typography.chip)
            .foregroundStyle(status.ink)
            .padding(.horizontal, Brand.Spacing.xs)
            .padding(.vertical, 3)
            .background(Capsule().fill(status.tint))
    }

    private var dateLine: String {
        clinic.startsAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        + " · "
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

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surface.ignoresSafeArea()

                VStack(alignment: .leading, spacing: Brand.Spacing.md) {
                    Text("To")
                        .font(Brand.Typography.subheadline)
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
                            .font(Brand.Typography.caption)
                            .foregroundStyle(Brand.textSecondary)
                    }

                    TextEditor(text: $body_)
                        .font(Brand.Typography.body)
                        .frame(minHeight: 140)
                        .padding(Brand.Spacing.xs)
                        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.sm).stroke(Brand.border, lineWidth: Brand.Layout.borderWidth))
                        .accessibilityIdentifier("admin.messageBody")
                        .accessibilityLabel("Message")

                    if let error {
                        Text(error)
                            .font(Brand.Typography.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                    }

                    Spacer()
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .navigationTitle("Message Players")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(sending ? "Sending…" : "Send") { send() }
                        .disabled(sending || body_.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        .accessibilityIdentifier("admin.sendMessage")
                }
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
