//
//  ProTodayView.swift
//  FXETennis
//
//  A pro's Today tab (decision 0025). Tara, 2026-09-28: "Let the pros see who
//  is coming to the clinics that day. I don't want the pros to invite people
//  from the player pool. See anything financial at all." And 2026-09-22: the
//  pros "can label them as no show, late cancellation, and see the clinic
//  list."
//
//  So this is Tara's roster with everything but two controls taken away:
//  today's clinics, who is You're In! and on which court, Came / No-show, and
//  Late cancel. No Player Pool, no Response Needed, no Invite, no Remove, no
//  court menu, no messages, no Paid, no charge, no capacity. The rows, the
//  toggle and the late-cancel alert are AdminClinicDetailView's, so a pro
//  who later gets more (Tara expects to let two of her pros see more,
//  eventually) finds the same screen with more on it.
//
//  THE TAB IS NOT A SECURITY CONTROL. pro_today() returns only these columns,
//  and only to a pro; both writes refuse any other day (tests/sql/pro_role.sql).
//

import SwiftUI

@MainActor
@Observable
final class ProTodayModel {
    var clinics: [ProTodayClinic] = []
    var loading = false
    var loaded = false
    var error: String?
    /// Registration ids with an action in flight, so a row disables itself.
    var busy: Set<UUID> = []
    /// app_settings.cancel_cutoff_hours (3, decision 0013), for Late cancel.
    var cutoffHours = 3

    func load() async {
        loading = true
        defer { loading = false }
        do {
            clinics = try await ProRepository.today()
            cutoffHours = (try? await RegistrationRepository.cancelCutoffHours()) ?? 3
            error = nil
            loaded = true
        } catch {
            self.error = "Couldn't load clinics."
        }
    }

    /// Runs one action, then reloads from the server rather than guessing: a
    /// player may have canceled, or Tara changed the row, meanwhile.
    func perform(_ id: UUID, _ work: @escaping () async throws -> Void) async {
        busy.insert(id)
        defer { busy.remove(id) }
        do {
            try await work()
            await load()
        } catch {
            let message = ProToday.message(for: error)
            if message == ProToday.changedUnderYou { await load() }
            self.error = message
        }
    }
}

struct ProTodayView: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var model = ProTodayModel()
    @State private var lateCanceling: ProTodayPlayer?
    @State private var lateNote = ""

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
                                .accessibilityIdentifier("pro.error")
                        }

                        if model.loaded && model.clinics.isEmpty {
                            Text("No clinics today.")
                                .brandFont(.body)
                                .foregroundStyle(Brand.textSecondary)
                                .accessibilityIdentifier("pro.empty")
                        }

                        ForEach(model.clinics) { clinic in
                            clinicCard(clinic)
                        }
                    }
                    .padding(Brand.Spacing.pageMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .refreshable { await model.load() }
            }
            .navigationTitle("Today")
        }
        // Late cancel: a player told the pro inside the cutoff. Tara's alert,
        // with her optional note, and without "The fee applies.": a pro is
        // told nothing about money.
        .alert(
            "Late cancel \(lateCanceling?.name ?? "")?",
            isPresented: Binding(get: { lateCanceling != nil }, set: { if !$0 { lateCanceling = nil } })
        ) {
            TextField("Note (optional)", text: $lateNote)
            Button("Late cancel", role: .destructive) {
                if let player = lateCanceling {
                    let note = lateNote
                    Task { await model.perform(player.id) {
                        try await ProRepository.markLateCancel(registration: player.id, note: note)
                    } }
                }
                lateCanceling = nil
            }
            Button("Keep", role: .cancel) { lateCanceling = nil }
        }
        .task { await model.load() }
        .reloadOnForeground { await model.load() }
    }

    // MARK: - One clinic

    private func clinicCard(_ clinic: ProTodayClinic) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(clinic.name)
                .brandFont(.headline)
                .foregroundStyle(Brand.navy)
            Text(timeLine(clinic))
                .brandFont(.subheadline)
                .foregroundStyle(Brand.textSecondary)

            HStack {
                StatusChip(.youreIn)
                Spacer()
                Text("\(clinic.players.count)")
                    .brandFont(.chip)
                    .foregroundStyle(Brand.textSecondary)
            }

            if clinic.players.isEmpty {
                Text("Nobody is in yet.")
                    .brandFont(.body)
                    .foregroundStyle(Brand.textSecondary)
            } else {
                VStack(spacing: 0) {
                    ForEach(clinic.players) { player in
                        row(player, in: clinic)
                        if player.id != clinic.players.last?.id {
                            Divider().background(Brand.hairline)
                        }
                    }
                }
                .padding(.horizontal, Brand.Spacing.cardPadding)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro.clinic")
    }

    /// Side by side at the usual text sizes, stacked at the accessibility
    /// sizes, as ONE layout whose parts keep their identity when it changes.
    /// It was the roster's ViewThatFits, which builds two copies of the row
    /// and swaps them as the text grows: Apple's audit lost each text part way
    /// up the sizes and reported "Dynamic Type partially unsupported" on every
    /// name, court and toggle (2026-09-28). A long name wraps instead of being
    /// cut off ("text clipped", the same audit).
    private func row(_ player: ProTodayPlayer, in clinic: ProTodayClinic) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Brand.Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Brand.Spacing.sm))
        return layout {
            identity(player)
                .frame(maxWidth: .infinity, alignment: .leading)
            controls(player, in: clinic)
        }
        .padding(.vertical, Brand.Spacing.xs)
        .frame(minHeight: Brand.Layout.comfortableTapTarget)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro.row")
    }

    /// Name, and the court when Tara has set one: pros coach on those courts.
    private func identity(_ player: ProTodayPlayer) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(player.name)
                .brandFont(.bodyEmphasis)
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let court = player.court {
                Text("Court \(court)")
                    .brandFont(.caption)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
    }

    /// The two controls, side by side; stacked too at the accessibility
    /// sizes, where side by side they no longer fit a phone's width.
    private func controls(_ player: ProTodayPlayer, in clinic: ProTodayClinic) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: Brand.Spacing.xs))
        return layout {
            if ProToday.canLateCancel(startsAt: clinic.startsAt, cutoffHours: model.cutoffHours) {
                lateCancelButton(player)
            }
            noShowToggle(player)
        }
    }

    // MARK: - The two controls

    /// Tara's Came / No-show toggle (AdminClinicDetailView.noShowToggle).
    private func noShowToggle(_ player: ProTodayPlayer) -> some View {
        Button {
            Task { await model.perform(player.id) {
                try await ProRepository.setNoShow(registration: player.id, noShow: !player.noShow)
            } }
        } label: {
            Label(player.noShow ? "No-show" : "Came",
                  systemImage: player.noShow ? "person.fill.xmark" : "person.fill.checkmark")
                .brandFont(.chip)
                // One line, always: "Late cancel" broke in two on a long
                // name's row (seen on the simulator, 2026-09-28); the name
                // wraps instead.
                .fixedSize()
                .foregroundStyle(player.noShow ? Brand.Status.canceled.ink : Brand.textSecondary)
                .frame(minHeight: Brand.Layout.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy.contains(player.id))
        .accessibilityIdentifier("pro.noShowToggle")
        .accessibilityLabel("\(player.name), \(player.noShow ? "no-show" : "came")")
    }

    private func lateCancelButton(_ player: ProTodayPlayer) -> some View {
        Button {
            lateNote = ""
            lateCanceling = player
        } label: {
            Text("Late cancel")
                .brandFont(.chip)
                .fixedSize()
                .foregroundStyle(Brand.Status.canceled.ink)
                .padding(.horizontal, Brand.Spacing.xs)
                .frame(minHeight: Brand.Layout.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(model.busy.contains(player.id))
        .accessibilityIdentifier("pro.lateCancel")
        .accessibilityLabel("Late cancel \(player.name)")
    }

    private func timeLine(_ clinic: ProTodayClinic) -> String {
        clinic.startsAt.formatted(.dateTime.hour().minute())
        + " to "
        + clinic.endsAt.formatted(.dateTime.hour().minute())
    }
}
