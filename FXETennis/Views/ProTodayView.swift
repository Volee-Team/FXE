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
//  The week (20261107000002). Tara, 2026-11-06: "Allow pros to have access to
//  the week ahead and what players are signed up. Not just day of (right now
//  their tab says TODAY. Have it say manage or whatever like mine but their
//  ONLY capabilities are to assign courts and see who is in the clinic."
//  So the tab is Manage, it lists today and the six days after (pro_week),
//  and every row has Tara's court menu (pro_assign_court). Came / No-show and
//  Late cancel stay on today's clinics only, as the server allows.
//
//  The 105 rounds (decision 0056). Tara, 2026-11-11: "Just wanna make sure
//  that they can position people on the courts like I can do now", and "I
//  think can change the rounds. That's totally fine. Probably need it in case
//  I'm out of town". A 105 in the week has Rounds, and a pro sets them as
//  Tara does, picking from clinic_round_people (decision 0054 had pros read
//  them only). The server holds the pro to the week (admin_set_round_court).
//

import SwiftUI

@MainActor
@Observable
final class ProTodayModel {
    var days: [ProDay] = []
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
            days = ProToday.days(try await ProRepository.week())
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
    /// A 105 whose rounds are open: the pro sets them in their week
    /// (decision 0056; 0054 had them read-only).
    @State private var roundsFor: ProTodayClinic?

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

                        if model.loaded && model.days.isEmpty {
                            Text("No clinics this week.")
                                .brandFont(.body)
                                .foregroundStyle(Brand.textSecondary)
                                .accessibilityIdentifier("pro.empty")
                        }

                        ForEach(model.days) { day in
                            // Tara's own section headings (AdminClinicsView.section).
                            Text(day.title.uppercased())
                                .brandFont(.chip)
                                .foregroundStyle(Brand.textSecondary)
                                .accessibilityAddTraits(.isHeader)
                                .accessibilityIdentifier("pro.day")
                            ForEach(day.clinics) { clinic in
                                clinicCard(clinic, today: day.isToday)
                            }
                        }
                    }
                    .padding(Brand.Spacing.pageMargin)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .refreshable { await model.load() }
            }
            .crispTopEdge()
            .bannerTitle("Manage")
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
        .sheet(item: $roundsFor) { clinic in
            RoundsSheet(clinicId: clinic.id, clinicName: clinic.name, people: [], editable: true,
                        onSaved: { await model.load() },
                        loadPeople: { try await RoundsRepository.people(clinic: clinic.id) })
        }
    }

    // MARK: - One clinic

    private func clinicCard(_ clinic: ProTodayClinic, today: Bool) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(clinic.name)
                .brandFont(.headline)
                .foregroundStyle(Brand.navy)
            Text(timeLine(clinic))
                .brandFont(.subheadline)
                .foregroundStyle(Brand.textSecondary)

            // The rounds for a 105, which a pro sets too (decision 0056). The
            // week's rows carry no category, so the name decides, as Tara
            // names every 105.
            if Rounds.is105(name: clinic.name, category: nil) {
                Button { roundsFor = clinic } label: {
                    Label("Rounds", systemImage: "square.grid.2x2")
                        .brandFont(.chip)
                        .foregroundStyle(Brand.navy)
                        .padding(.horizontal, Brand.Spacing.sm)
                        .frame(minHeight: Brand.Layout.minTapTarget)
                        .background(Capsule().fill(Brand.surfaceRaised))
                        .overlay(Capsule().stroke(Brand.navy, lineWidth: Brand.Layout.borderWidth))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("pro.rounds")
            }

            HStack {
                StatusChip(.youreIn)
                Spacer()
                Text("\(clinic.players.count)")
                    .brandFont(.chip)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityIdentifier("today.count")
            }

            if clinic.players.isEmpty {
                // On the raised card, like the rows: on the court backdrop it
                // failed the iOS 18 contrast audit (2026-11-07), once the week
                // brought clinics nobody is in yet.
                Text("Nobody is in yet.")
                    .brandFont(.body)
                    .foregroundStyle(Brand.textSecondary)
                    .frame(maxWidth: .infinity, minHeight: Brand.Layout.comfortableTapTarget, alignment: .leading)
                    .padding(.horizontal, Brand.Spacing.cardPadding)
                    .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
            } else {
                VStack(spacing: 0) {
                    ForEach(clinic.players) { player in
                        row(player, in: clinic, today: today)
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
    private func row(_ player: ProTodayPlayer, in clinic: ProTodayClinic, today: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: Brand.Spacing.xxs))
            : AnyLayout(HStackLayout(alignment: .center, spacing: Brand.Spacing.sm))
        return layout {
            identity(player)
                .frame(maxWidth: .infinity, alignment: .leading)
            controls(player, in: clinic, today: today)
        }
        .padding(.vertical, Brand.Spacing.xs)
        .frame(minHeight: Brand.Layout.comfortableTapTarget)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("pro.row")
    }

    /// The name. The court is on the menu beside it.
    private func identity(_ player: ProTodayPlayer) -> some View {
        Text(player.name)
            .brandFont(.bodyEmphasis)
            .foregroundStyle(Brand.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// The two controls, side by side; stacked too at the accessibility
    /// sizes, where side by side they no longer fit a phone's width.
    private func controls(_ player: ProTodayPlayer, in clinic: ProTodayClinic, today: Bool) -> some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 0))
            : AnyLayout(HStackLayout(spacing: Brand.Spacing.xs))
        return layout {
            courtMenu(player)
            if today {
                if ProToday.canLateCancel(startsAt: clinic.startsAt, cutoffHours: model.cutoffHours) {
                    lateCancelButton(player)
                }
                noShowToggle(player)
            }
        }
    }

    /// Tara's court menu (AdminClinicDetailView.courtMenu) with only the
    /// courts in it: no Late cancel, no Remove.
    private func courtMenu(_ player: ProTodayPlayer) -> some View {
        Menu {
            Button("No court") { assign(player, nil) }
            ForEach(1...5, id: \.self) { n in
                Button("Court \(n)") { assign(player, n) }
            }
        } label: {
            Label(player.court.map { "Court \($0)" } ?? "Court", systemImage: "rectangle.split.2x1")
                .brandFont(.chip)
                .fixedSize()
                .foregroundStyle(player.court == nil ? Brand.textSecondary : Brand.navy)
                .frame(minHeight: Brand.Layout.minTapTarget)
        }
        .disabled(model.busy.contains(player.id))
        .accessibilityIdentifier("pro.court")
        .accessibilityLabel("\(player.name), \(player.court.map { "court \($0)" } ?? "no court"). Tap to change.")
    }

    private func assign(_ player: ProTodayPlayer, _ court: Int?) {
        guard court != player.court else { return }
        Task { await model.perform(player.id) {
            try await ProRepository.assignCourt(registration: player.id, court: court)
        } }
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
