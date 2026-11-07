//
//  InvitePlayerSheet.swift
//  FXETennis
//
//  Tara invites anyone, not only the Waitlist (admin_invite_player,
//  20261107000002). Her words, 2026-11-06: "Allow me to invite anyone to a
//  clinic that is not on a waitlist". It is always an invitation: the player
//  gets "A spot opened in ... Accept or decline." and lands in Response
//  Needed; a decline ends it rather than putting them on the Waitlist.
//
//  Item 5 the same day: when the clinic is full, ask first ("are you sure you
//  want to invite ___ your clinic is full"). A question, never a refusal.
//

import SwiftUI

struct InvitePlayerSheet: View {
    let clinic: ClinicAdmin
    let inCount: Int
    /// Players already In, waiting or invited on this clinic.
    let onClinic: Set<UUID>
    let onInvited: () async -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var results: [PlayerSearchResult] = []
    @State private var searchTask: Task<Void, Never>?
    @State private var busy = false
    @State private var error: String?
    @State private var confirmFull: PlayerSearchResult?

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surfaceGradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: Brand.Spacing.md) {
                    Text("They get an invitation to accept or decline.")
                        .brandFont(.subheadline)
                        .foregroundStyle(Brand.textSecondary)

                    TextField("Search by name", text: $query)
                        .brandFont(.body)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .padding(Brand.Spacing.sm)
                        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
                        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.sm).stroke(Brand.border, lineWidth: Brand.Layout.borderWidth))
                        .accessibilityIdentifier("admin.invite.search")
                        .onChange(of: query) { _, _ in search() }

                    if let error {
                        Text(error)
                            .brandFont(.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                            .accessibilityIdentifier("admin.invite.error")
                    }

                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(results) { p in
                                row(p)
                                if p.id != results.last?.id { Divider().background(Brand.hairline) }
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .crispTopEdge()
            .navyTitle("Invite a Player")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                    .tint(Brand.textOnNavy)
                }
                .onNavy()
            }
            .confirmationDialog(
                confirmFull.map { ClinicFull.question(.invite, name: "\($0.firstName) \($0.lastName)",
                                                      inCount: inCount, capacity: clinic.internalCapacity ?? 0) } ?? "",
                isPresented: Binding(get: { confirmFull != nil }, set: { if !$0 { confirmFull = nil } }),
                titleVisibility: .visible
            ) {
                Button("Invite") {
                    if let p = confirmFull { invite(p) }
                    confirmFull = nil
                }
                Button("Cancel", role: .cancel) { confirmFull = nil }
            }
        }
    }

    private func row(_ p: PlayerSearchResult) -> some View {
        let already = onClinic.contains(p.id)
        let name = "\(p.firstName) \(p.lastName)"
        return Button {
            if ClinicFull.isFull(inCount: inCount, capacity: clinic.internalCapacity) { confirmFull = p } else { invite(p) }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 1) {
                    Text(name)
                        .brandFont(.bodyEmphasis)
                        .foregroundStyle(already ? Brand.textSecondary : Brand.textPrimary)
                    Text(already ? "Already on this clinic" : (p.isMember ? "Member" : "Non-member"))
                        .brandFont(.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
                Spacer()
                if !already {
                    Text("Invite")
                        .brandFont(.chip)
                        .foregroundStyle(Brand.textOnNavy)
                        .padding(.horizontal, Brand.Spacing.sm)
                        .frame(minHeight: Brand.Layout.minTapTarget)
                        .background(Capsule().fill(Brand.navy))
                }
            }
            .frame(minHeight: Brand.Layout.comfortableTapTarget)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(already || busy)
        .accessibilityIdentifier("admin.invite.player")
        .accessibilityLabel(already ? "\(name), already on this clinic" : "Invite \(name)")
    }

    private func search() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                results = try await AdminRepository.searchPlayers(q)
                error = nil
            } catch {
                self.error = "Couldn't search right now. Check your connection and try again."
            }
        }
    }

    private func invite(_ p: PlayerSearchResult) {
        busy = true
        Task {
            do {
                try await AdminRepository.invitePlayer(clinic: clinic.id, player: p.id)
                await onInvited()
                dismiss()
            } catch {
                self.error = ClinicFull.inviteError(error, name: "\(p.firstName) \(p.lastName)")
            }
            busy = false
        }
    }
}
