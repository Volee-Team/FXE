//
//  SavedMessagesControls.swift
//  FXETennis
//
//  The Saved menu and "Save this message" in Message Players (decision 0030).
//  Choosing a saved message only fills the box; Tara still picks the audience
//  and taps Send, exactly as before.
//

import SwiftUI

@MainActor
@Observable
final class SavedMessagesModel {
    var messages: [SavedMessage] = []
    var busy = false
    var error: String?

    func load() async {
        do {
            messages = try await SavedMessagesRepository.list()
            error = nil
        } catch {
            self.error = Self.line(for: error)
        }
    }

    func save(_ text: String) async {
        guard let body = SavedMessageRule.savable(text) else { return }
        await run { try await SavedMessagesRepository.save(body) }
    }

    func remove(_ message: SavedMessage) async {
        await run { try await SavedMessagesRepository.remove(message.id) }
    }

    private func run(_ work: () async throws -> Void) async {
        busy = true
        defer { busy = false }
        do {
            try await work()
            await load()
        } catch {
            self.error = Self.line(for: error)
        }
    }

    /// Approved chrome only: the connection line, or the screen's usual one.
    static func line(for error: Error) -> String {
        RequestFailure(error).line ?? "That didn't save. Check your connection and try again."
    }
}

/// The saved messages as a menu above the box. Choosing one fills the box;
/// Remove is a submenu naming each one, so nothing is removed by one stray tap.
struct SavedMessagesMenu: View {
    let model: SavedMessagesModel
    @Binding var text: String

    var body: some View {
        Menu {
            if model.messages.isEmpty {
                Text("No saved messages yet.")
            } else {
                ForEach(model.messages) { message in
                    Button { text = message.body } label: { Text(message.body) }
                }
                Divider()
                Menu("Remove") {
                    ForEach(model.messages) { message in
                        Button(role: .destructive) {
                            Task { await model.remove(message) }
                        } label: { Text(message.body) }
                    }
                }
            }
        } label: {
            Label("Saved", systemImage: "text.bubble")
                .brandFont(.button)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Brand.Layout.comfortableTapTarget)
                .foregroundStyle(Brand.navy)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.sm).stroke(Brand.navy, lineWidth: Brand.Layout.borderWidth))
        }
        .disabled(model.busy)
        .accessibilityIdentifier("admin.savedMessages")
    }
}

/// Under the box: keeps the current text for next time.
struct SaveMessageButton: View {
    let model: SavedMessagesModel
    let text: String

    var body: some View {
        let savable = SavedMessageRule.savable(text) != nil
        Button {
            Task { await model.save(text) }
        } label: {
            Text("Save this message")
                .brandFont(.subheadline)
                .frame(minHeight: Brand.Layout.minTapTarget)
                .foregroundStyle(savable && !model.busy ? Brand.navy : Brand.textSecondary)
        }
        .buttonStyle(.plain)
        .disabled(!savable || model.busy)
        .accessibilityIdentifier("admin.saveMessage")
    }
}
