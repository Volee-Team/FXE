//
//  RoundsSheet.swift
//  FXETennis
//
//  Tara's 105 rounds (decision 0054, item 8). Her words, 2026-11-06: "Can
//  there be a place in every 105 on the app for me to make 2-3 rounds of 105.
//  Like a message board or something like / Round 1 / Coirt 1: player a,bc /
//  player d,e,f / Coirt 2 / 3 / 4 / 5 / Round 2 Etc / Round 3 Etc". Her
//  answers, 2026-11-09: "Just me and pros for rounds" and "Hmmm pick from
//  roster great".
//
//  Tara picks from You're In! and her guests: up to 3 rounds, courts 1 to 5,
//  two sides of up to 3 (admin_set_round_court). A pro sees the same rounds,
//  read-only, for a clinic in their week (clinic_rounds). Players never: the
//  server gives them nothing to read.
//

import SwiftUI

/// The rounds as text, for her clinic page and the pro's week: each round
/// with anyone in it, then each court's "a, b, c / d, e, f".
struct RoundsSummary: View {
    let spots: [RoundSpot]

    var body: some View {
        let rounds = Rounds.rounds.filter { !Rounds.isEmpty(spots, round: $0) }
        if !rounds.isEmpty {
            VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                ForEach(rounds, id: \.self) { round in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Round \(round)")
                            .brandFont(.bodyEmphasis)
                            .foregroundStyle(Brand.navy)
                        ForEach(Array(Rounds.courts), id: \.self) { court in
                            if let line = Rounds.line(spots, round: round, court: court) {
                                Text("Court \(court): \(line)")
                                    .brandFont(.caption)
                                    .foregroundStyle(Brand.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                    }
                }
            }
            .padding(Brand.Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("rounds.summary")
        }
    }
}

struct RoundsSheet: View {
    let clinicId: UUID
    let clinicName: String
    /// Who can be picked: You're In! then the guests. Empty for a pro.
    let people: [RoundPerson]
    /// Tara edits; a pro only reads.
    let editable: Bool
    var onSaved: () async -> Void = {}

    @Environment(\.dismiss) private var dismiss
    @State private var spots: [RoundSpot] = []
    @State private var round = 1
    /// Every court of every round as she is editing it, six spots each
    /// [side 1 x3, side 2 x3], keyed by key(round, court). Switching rounds
    /// keeps what she picked; Save sends every court she changed.
    @State private var draft: [Int: [UUID?]] = [:]
    @State private var loading = true
    @State private var saving = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surfaceGradient.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Spacing.md) {
                        if editable {
                            Picker("Round", selection: $round) {
                                ForEach(Array(Rounds.rounds), id: \.self) { Text("Round \($0)").tag($0) }
                            }
                            .pickerStyle(.segmented)
                            .accessibilityIdentifier("rounds.round")
                        }

                        if let error {
                            Text(error)
                                .brandFont(.subheadline)
                                .foregroundStyle(Brand.Status.canceled.ink)
                        }

                        if loading {
                            ProgressView().frame(maxWidth: .infinity)
                        } else if editable {
                            ForEach(Array(Rounds.courts), id: \.self) { court in courtEditor(court) }
                        } else if spots.isEmpty {
                            Text("No rounds yet.")
                                .brandFont(.body)
                                .foregroundStyle(Brand.textSecondary)
                        } else {
                            RoundsSummary(spots: spots)
                        }
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
            }
            .crispTopEdge()
            .navyTitle("Rounds")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(editable ? "Cancel" : "Done") { dismiss() }
                        .tint(Brand.textOnNavy)
                }
                .onNavy()
                if editable {
                    ToolbarItem(placement: .confirmationAction) {
                        Button(saving ? "Saving…" : "Save") { save() }
                            .disabled(saving || loading)
                            .accessibilityIdentifier("rounds.save")
                            .tint(Brand.textOnNavy)
                    }
                    .onNavy()
                }
            }
            .task { await load() }
        }
    }

    // MARK: - One court

    private func courtEditor(_ court: Int) -> some View {
        let six = draft[key(round, court)] ?? Array(repeating: nil, count: Rounds.perSide * 2)
        let left = Rounds.lineup(spots, round: round, court: court).compactMap { $0 }.filter(\.gone)
        return VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text("Court \(court)")
                .brandFont(.headline)
                .foregroundStyle(Brand.navy)
            ForEach(1...2, id: \.self) { side in
                Text("Side \(side)")
                    .brandFont(.caption)
                    .foregroundStyle(Brand.textSecondary)
                ForEach(0..<Rounds.perSide, id: \.self) { slot in
                    let index = (side - 1) * Rounds.perSide + slot
                    Picker("Court \(court), side \(side), spot \(slot + 1)", selection: binding(court: court, index: index)) {
                        Text("Open").tag(UUID?.none)
                        ForEach(people) { person in
                            Text(person.isGuest ? "\(person.name) (guest)" : person.name).tag(UUID?.some(person.id))
                        }
                    }
                    .pickerStyle(.menu)
                    .tint(six[index] == nil ? Brand.textSecondary : Brand.navy)
                    .frame(maxWidth: .infinity, minHeight: Brand.Layout.minTapTarget, alignment: .leading)
                    .accessibilityIdentifier("rounds.pick")
                }
            }
            // Someone placed here who has since left the clinic: their spot
            // is open in the pickers; this says who it was.
            ForEach(left, id: \.personId) { gone in
                Text("\(gone.displayName) left the clinic.")
                    .brandFont(.caption)
                    .foregroundStyle(Brand.Status.canceled.ink)
            }
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("rounds.court")
    }

    /// Picking someone puts them here and takes them out of any other spot
    /// of this round: one place per person per round, as the server keeps it.
    private func binding(court: Int, index: Int) -> Binding<UUID?> {
        let round = round
        return Binding(
            get: { draft[key(round, court)]?[index] ?? nil },
            set: { new in
                if let new {
                    for c in Rounds.courts {
                        guard var six = draft[key(round, c)] else { continue }
                        for i in six.indices where six[i] == new { six[i] = nil }
                        draft[key(round, c)] = six
                    }
                }
                var six = draft[key(round, court)] ?? Array(repeating: nil, count: Rounds.perSide * 2)
                six[index] = new
                draft[key(round, court)] = six
            })
    }

    private func key(_ round: Int, _ court: Int) -> Int { round * 10 + court }

    /// A court as saved: six ids, nil where open or where someone has left.
    private func saved(_ round: Int, _ court: Int) -> [UUID?] {
        Rounds.lineup(spots, round: round, court: court).map { spot in
            guard let spot, !spot.gone else { return nil }
            return spot.personId
        }
    }

    // MARK: - Load and save

    private func load() async {
        loading = true
        defer { loading = false }
        do {
            spots = try await RoundsRepository.rounds(clinic: clinicId)
            error = nil
            fillDraft()
        } catch {
            self.error = "Couldn't load the rounds."
        }
    }

    /// Every court as saved, without anyone who has left (they are named
    /// under the court instead).
    private func fillDraft() {
        var d: [Int: [UUID?]] = [:]
        for r in Rounds.rounds {
            for court in Rounds.courts { d[key(r, court)] = saved(r, court) }
        }
        draft = d
    }

    /// Only the courts she changed, one call each. A court that still holds
    /// someone who has left is sent too, which clears them.
    private func save() {
        saving = true
        Task {
            do {
                for r in Rounds.rounds {
                    for court in Rounds.courts {
                        let six = draft[key(r, court)] ?? Array(repeating: nil, count: Rounds.perSide * 2)
                        let asSaved = Rounds.lineup(spots, round: r, court: court).map { $0?.personId }
                        if six != asSaved {
                            try await AdminRepository.setRoundCourt(clinic: clinicId, round: r, court: court, people: six)
                        }
                    }
                }
                await onSaved()
                dismiss()
            } catch {
                self.error = ClinicExtrasError.message(error)
                await load()
            }
            saving = false
        }
    }
}
