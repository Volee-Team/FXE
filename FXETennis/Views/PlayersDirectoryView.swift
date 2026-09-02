//
//  PlayersDirectoryView.swift
//  FXETennis
//
//  Tara's directory: everything she does to a PERSON rather than a
//  registration. Search (forgiving, "Ann" finds Joann), correct membership,
//  retire or bring back a player, and keep a private note.
//
//  The note is one of the nine hidden facts (CLAUDE.md hard rule 1): it is
//  read and written through admin-only RPCs, and the player-facing app has no
//  path to it at all. `search_players` reports only whether a note exists.
//

import SwiftUI

struct PlayersDirectoryView: View {
    @State private var query = ""
    @State private var includeInactive = false
    @State private var results: [PlayerSearchResult] = []
    @State private var error: String?
    @State private var searchTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            Brand.surface.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.md) {
                    Toggle("Show inactive players", isOn: $includeInactive)
                        .font(Brand.Typography.subheadline)
                        .tint(Brand.navy)
                        .accessibilityIdentifier("admin.players.inactive")
                        .onChange(of: includeInactive) { _, _ in search() }

                    if let error {
                        Text(error)
                            .font(Brand.Typography.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                    }

                    if query.trimmingCharacters(in: .whitespaces).count < 2 {
                        Text("Type at least two letters of a name.")
                            .font(Brand.Typography.body)
                            .foregroundStyle(Brand.textSecondary)
                    } else if results.isEmpty {
                        Text("Nobody by that name yet. They may need to sign up in the app first.")
                            .font(Brand.Typography.body)
                            .foregroundStyle(Brand.textSecondary)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(results) { player in
                                NavigationLink {
                                    PlayerAdminDetailView(player: player) { search() }
                                } label: {
                                    row(player)
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("admin.players.row")
                                if player.id != results.last?.id {
                                    Divider().background(Brand.hairline)
                                }
                            }
                        }
                        .padding(.horizontal, Brand.Spacing.cardPadding)
                        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
                    }
                }
                .padding(Brand.Spacing.pageMargin)
            }
        }
        .navigationTitle("Players")
        .navigationBarTitleDisplayMode(.inline)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Search by name")
        .onChange(of: query) { _, _ in search() }
    }

    private func row(_ player: PlayerSearchResult) -> some View {
        HStack(spacing: Brand.Spacing.sm) {
            VStack(alignment: .leading, spacing: 1) {
                Text("\(player.firstName) \(player.lastName)")
                    .font(Brand.Typography.bodyEmphasis)
                    .foregroundStyle(Brand.textPrimary)
                Text(subtitle(player))
                    .font(Brand.Typography.caption)
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer()
            if player.hasNotes {
                Image(systemName: "note.text")
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityLabel("Has a note")
            }
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(Brand.textSecondary)
        }
        .frame(minHeight: Brand.Layout.comfortableTapTarget)
        .contentShape(Rectangle())
    }

    private func subtitle(_ p: PlayerSearchResult) -> String {
        var parts: [String] = []
        if let r = p.adultRating, let bucket = NTRPRating(rating: r) { parts.append(bucket.label) }
        parts.append(p.isMember ? "Member" : "Non-member")
        if !p.isActive { parts.append("Inactive") }
        return parts.joined(separator: " · ")
    }

    private func search() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { results = []; return }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            do {
                results = try await AdminRepository.searchPlayers(q, includeInactive: includeInactive)
                error = nil
            } catch {
                self.error = "Couldn't search right now. Check your connection and try again."
            }
        }
    }
}

/// One player, from Tara's side. Membership and active status are single
/// switches; the note is free text saved on demand, never on every keystroke,
/// because a half-typed note is not a note.
private struct PlayerAdminDetailView: View {
    let player: PlayerSearchResult
    let onChange: () -> Void

    @State private var isMember: Bool
    @State private var isActive: Bool
    @State private var note = ""
    @State private var savedNote = ""
    @State private var loadedNote = false
    @State private var busy = false
    @State private var message: String?

    init(player: PlayerSearchResult, onChange: @escaping () -> Void) {
        self.player = player
        self.onChange = onChange
        _isMember = State(initialValue: player.isMember)
        _isActive = State(initialValue: player.isActive)
    }

    var body: some View {
        ZStack {
            Brand.surface.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
                        Text("\(player.firstName) \(player.lastName)")
                            .font(Brand.Typography.title)
                            .foregroundStyle(Brand.textPrimary)
                        if let r = player.adultRating, let bucket = NTRPRating(rating: r) {
                            Text("Rating \(bucket.label)")
                                .font(Brand.Typography.subheadline)
                                .foregroundStyle(Brand.textSecondary)
                        }
                    }

                    VStack(spacing: 0) {
                        Toggle("Member", isOn: $isMember)
                            .tint(Brand.navy)
                            .accessibilityIdentifier("admin.player.member")
                            .onChange(of: isMember) { _, new in
                                perform { try await AdminRepository.setMembership(player.id, isMember: new) }
                            }
                            .frame(minHeight: Brand.Layout.comfortableTapTarget)
                        Divider().background(Brand.hairline)
                        Toggle("Active", isOn: $isActive)
                            .tint(Brand.navy)
                            .accessibilityIdentifier("admin.player.active")
                            .onChange(of: isActive) { _, new in
                                perform { try await AdminRepository.setActive(player.id, isActive: new) }
                            }
                            .frame(minHeight: Brand.Layout.comfortableTapTarget)
                    }
                    .font(Brand.Typography.body)
                    .padding(.horizontal, Brand.Spacing.cardPadding)
                    .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))

                    VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                        Text("Private note")
                            .font(Brand.Typography.bodyEmphasis)
                            .foregroundStyle(Brand.textPrimary)
                        Text("Only you can see this.")
                            .font(Brand.Typography.caption)
                            .foregroundStyle(Brand.textSecondary)
                        TextEditor(text: $note)
                            .font(Brand.Typography.body)
                            .frame(minHeight: 120)
                            .padding(Brand.Spacing.xs)
                            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
                            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.sm).stroke(Brand.border, lineWidth: Brand.Layout.borderWidth))
                            .accessibilityIdentifier("admin.player.note")
                            .accessibilityLabel("Private note")

                        Button {
                            perform {
                                try await AdminRepository.setPlayerNote(player.id, body: note)
                                savedNote = note
                            }
                        } label: {
                            Text("Save note")
                                .font(Brand.Typography.button)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: Brand.Layout.comfortableTapTarget)
                                .foregroundStyle(Brand.textOnNavy)
                                .background(
                                    RoundedRectangle(cornerRadius: Brand.Radius.sm)
                                        .fill(note != savedNote && !busy ? Brand.navy : Brand.disabled)
                                )
                        }
                        .buttonStyle(.plain)
                        .disabled(note == savedNote || busy)
                        .accessibilityIdentifier("admin.player.saveNote")
                    }

                    if let message {
                        Text(message)
                            .font(Brand.Typography.caption)
                            .foregroundStyle(Brand.textSecondary)
                    }
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .navigationTitle("Player")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            guard !loadedNote else { return }
            note = (try? await AdminRepository.playerNote(player.id)) ?? ""
            savedNote = note
            loadedNote = true
        }
    }

    private func perform(_ work: @escaping () async throws -> Void) {
        busy = true
        Task {
            do {
                try await work()
                message = "Saved."
                onChange()
            } catch {
                message = "That didn't save. Check your connection and try again."
            }
            busy = false
        }
    }
}
