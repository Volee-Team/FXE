//
//  EditProfileView.swift
//  FXETennis
//
//  Fix a typo in your name, change your phone, update your rating. Membership
//  is shown but not editable here: it decides which registration window opens
//  first and which rate is shown, so after sign-up it is Tara's to correct
//  (for-tara.md q5). The same fields and the same rating pills as the profile
//  screen a new player fills in, so the two never drift apart.
//

import SwiftUI

struct EditProfileView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var rating: NTRPRating?
    @State private var saving = false
    @State private var error: String?
    @State private var loaded = false
    @FocusState private var typing: Bool

    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && !saving
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                        field("First Name", text: $firstName, content: .givenName, id: "edit.firstName")
                        field("Last Name", text: $lastName, content: .familyName, id: "edit.lastName")
                        field("Phone", text: $phone, content: .telephoneNumber, keyboard: .phonePad, id: "edit.phone")

                        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                            Text("Your tennis rating")
                                .font(Brand.Typography.bodyEmphasis)
                                .foregroundStyle(Brand.textPrimary)
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: Brand.Spacing.xs) {
                                    ForEach(NTRPRating.displayOrdered) { level in
                                        Button {
                                            rating = (rating == level) ? nil : level
                                            typing = false
                                        } label: {
                                            Text(level.label)
                                                .font(Brand.Typography.chip)
                                                .padding(.horizontal, Brand.Spacing.sm)
                                                .frame(minHeight: Brand.Layout.minTapTarget)
                                                .foregroundStyle(rating == level ? Brand.textOnNavy : Brand.textPrimary)
                                                .background(Capsule().fill(rating == level ? Brand.navy : Brand.surfaceRaised))
                                                .overlay(Capsule().stroke(Brand.border, lineWidth: Brand.Layout.hairlineWidth))
                                        }
                                        .buttonStyle(.plain)
                                        .accessibilityLabel("USTA \(level.label)")
                                        .accessibilityAddTraits(rating == level ? [.isButton, .isSelected] : .isButton)
                                    }
                                }
                                .padding(.vertical, Brand.Spacing.xxs)
                            }
                        }

                        HStack {
                            Text(session.activePlayer?.isMember == true ? "FXE Member" : "Non-member")
                                .font(Brand.Typography.body)
                                .foregroundStyle(Brand.textPrimary)
                            Spacer()
                            Text("Set by Tara")
                                .font(Brand.Typography.caption)
                                .foregroundStyle(Brand.textSecondary)
                        }
                        .padding(Brand.Spacing.cardPadding)
                        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))

                        if let error {
                            Text(error)
                                .font(Brand.Typography.subheadline)
                                .foregroundStyle(Brand.Status.canceled.ink)
                        }
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
                .scrollDismissesKeyboard(.interactively)
            }
            .navigationTitle("Edit details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("edit.cancel")
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(saving ? "Saving…" : "Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("edit.save")
                }
            }
            .task {
                guard !loaded else { return }
                firstName = session.account?.firstName ?? ""
                lastName = session.account?.lastName ?? ""
                phone = session.account?.phone ?? ""
                if let r = session.activePlayer?.adultRating { rating = NTRPRating(rating: r) }
                loaded = true
            }
        }
    }

    private func field(_ label: String, text: Binding<String>, content: UITextContentType,
                       keyboard: UIKeyboardType = .default, id: String) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
            Text(label)
                .font(Brand.Typography.subheadline)
                .foregroundStyle(Brand.textSecondary)
            TextField("", text: text)
                .focused($typing)
                .font(Brand.Typography.body)
                .foregroundStyle(Brand.textPrimary)
                .textContentType(content)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(Brand.Spacing.sm)
                .frame(minHeight: Brand.Layout.comfortableTapTarget)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.sm).stroke(Brand.border, lineWidth: Brand.Layout.borderWidth))
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
    }

    private func save() {
        guard let player = session.activePlayer?.id else { return }
        saving = true
        Task {
            do {
                try await ProfileRepository.updateMyProfile(
                    firstName: firstName.trimmingCharacters(in: .whitespaces),
                    lastName: lastName.trimmingCharacters(in: .whitespaces),
                    phone: phone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : phone.trimmingCharacters(in: .whitespaces),
                    adultRating: rating?.rawValue,
                    player: player
                )
                await session.loadProfile()
                dismiss()
            } catch {
                self.error = "That didn't save. Check your connection and try again."
            }
            saving = false
        }
    }
}
