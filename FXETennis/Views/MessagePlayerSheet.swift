//
//  MessagePlayerSheet.swift
//  FXETennis
//
//  Tara writes to one player (admin_message_player, 20261107000002). Her
//  words, 2026-11-06: "Allow me to send a message to anyone whenever they are
//  (meaning in a clinic, not registered, on a waitlist, etc)", and on her
//  screenshot of Message Players: "option to message individual".
//
//  From the Players tab there is no clinic: the message is a notification.
//  The clinic's own Message sheet sends to one player through its To menu
//  (MessageClinicSheet), and that one is kept on the clinic page for them.
//  Same box, same Saved menu, as her group messages (decision 0030).
//

import SwiftUI

struct MessagePlayerSheet: View {
    let playerId: UUID
    let name: String

    @Environment(\.dismiss) private var dismiss
    @State private var body_ = ""
    @State private var sending = false
    @State private var error: String?
    @State private var saved = SavedMessagesModel()

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surfaceGradient.ignoresSafeArea()

                VStack(alignment: .leading, spacing: Brand.Spacing.md) {
                    Text("To \(name)")
                        .brandFont(.subheadline)
                        .foregroundStyle(Brand.textSecondary)
                        .accessibilityIdentifier("admin.messagePlayer.to")

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
            .navyTitle("Message Player")
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
                try await AdminRepository.messagePlayer(
                    playerId, body: body_.trimmingCharacters(in: .whitespacesAndNewlines), clinic: nil)
                dismiss()
            } catch {
                self.error = "The message didn't send. Check your connection and try again."
            }
            sending = false
        }
    }
}
