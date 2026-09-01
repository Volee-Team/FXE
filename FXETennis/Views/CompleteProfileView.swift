//
//  CompleteProfileView.swift
//  FXETennis
//
//  The second half of sign-up. `auth.signUp` creates an auth user and nothing
//  else; this screen creates the `accounts` and `players` rows via
//  `create_my_account`. Without it a new user reached an app where Home greeted
//  them "Good Evening, there!", every price was the non-member rate, and the
//  Register button silently did nothing.
//
//  COPY: every label here is Tara's, from the Developer Guide, Screen 4
//  ("Complete Adult or Parent Profile"). CLAUDE.md: do not invent copy. The
//  membership question in particular is quoted exactly, including the club's
//  full name, because that is the wording her members recognise.
//
//  NOT collected here, deliberately:
//  * Email. It is already on the auth user and is read server-side; a client
//    that could name its own email could impersonate someone.
//  * The optional private note for Tara. It is in her Screen 4 spec but there is
//    no column for it in `accounts` or `players` yet. Adding one is a schema
//    decision, so it is a backlog item rather than an invented field.
//  * Children. v1 is adults only (decision 0004).
//

import SwiftUI

struct CompleteProfileView: View {
    @Environment(SessionStore.self) private var session

    @State private var firstName = ""
    @State private var lastName = ""
    @State private var phone = ""
    @State private var isMember: Bool?          // nil until answered: no default
    @State private var rating: NTRPRating?
    @State private var showNTRP = false
    @State private var saving = false

    /// Both names are required because they are NOT NULL on both tables and are
    /// what Tara reads in her roster. Membership is required because it decides
    /// which registration window opens first and which price is shown, and a
    /// silent default would quietly put someone in the wrong tier.
    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && isMember != nil
            && !saving
    }

    var body: some View {
        ZStack {
            Brand.surface.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    header

                    field("First Name", text: $firstName, content: .givenName, id: "profile.firstName")
                    field("Last Name", text: $lastName, content: .familyName, id: "profile.lastName")
                    field("Phone", text: $phone, content: .telephoneNumber, keyboard: .phonePad, id: "profile.phone")

                    membershipQuestion
                    ratingPicker

                    if let error = session.authError {
                        Text(error)
                            .font(Brand.Typography.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                            .accessibilityAddTraits(.isStaticText)
                    }

                    saveButton
                    escapeHatch
                }
                .padding(Brand.Spacing.pageMargin)
            }
        }
        .sheet(isPresented: $showNTRP) { NTRPExplainerSheet() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text("Almost there")
                .font(Brand.Typography.display)
                .foregroundStyle(Brand.textPrimary)
            Text("Tara uses this to build her clinic lists.")
                .font(Brand.Typography.subheadline)
                .foregroundStyle(Brand.textSecondary)
        }
        .padding(.bottom, Brand.Spacing.xs)
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        content: UITextContentType,
        keyboard: UIKeyboardType = .default,
        id: String
    ) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
            Text(label)
                .font(Brand.Typography.subheadline)
                .foregroundStyle(Brand.textSecondary)
            TextField("", text: text)
                .font(Brand.Typography.body)
                .foregroundStyle(Brand.textPrimary)
                .textContentType(content)
                .keyboardType(keyboard)
                .autocorrectionDisabled()
                .padding(Brand.Spacing.sm)
                .frame(minHeight: Brand.Layout.comfortableTapTarget)
                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.sm))
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.Radius.sm)
                        .stroke(Brand.border, lineWidth: Brand.Layout.borderWidth)
                )
                .accessibilityLabel(label)
                .accessibilityIdentifier(id)
        }
    }

    /// Tara's exact question, from Screen 4 of the Developer Guide.
    ///
    /// Self-reported on purpose: she answered question 5 in `for-tara.md` with
    /// "leave it as-is, and I can correct anyone's status on their profile". The
    /// only thing it affects is which window opens first and which published
    /// rate shows, both of which she can override.
    private var membershipQuestion: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text("Are you currently a Foxcroft East Racquet & Swim Club member?")
                .font(Brand.Typography.bodyEmphasis)
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Brand.Spacing.sm) {
                choice("Yes", selected: isMember == true, id: "profile.member.yes") { isMember = true }
                choice("No", selected: isMember == false, id: "profile.member.no") { isMember = false }
            }
        }
    }

    private func choice(
        _ label: String,
        selected: Bool,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(label)
                .font(Brand.Typography.button)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Brand.Layout.comfortableTapTarget)
                .foregroundStyle(selected ? Brand.textOnNavy : Brand.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: Brand.Radius.sm)
                        .fill(selected ? Brand.navy : Brand.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.Radius.sm)
                        .stroke(Brand.border, lineWidth: Brand.Layout.borderWidth)
                )
        }
        .buttonStyle(.plain)
        // Selection must not be carried by colour alone.
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }

    private var ratingPicker: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            HStack {
                Text("Your tennis rating")
                    .font(Brand.Typography.bodyEmphasis)
                    .foregroundStyle(Brand.textPrimary)
                Spacer()
                // Tara's exact label, from Screen 4.
                Button("Need Help?") { showNTRP = true }
                    .font(Brand.Typography.subheadline)
                    .foregroundStyle(Brand.navy)
                    .frame(minHeight: Brand.Layout.minTapTarget)
            }

            // Optional: a new player who does not know their level should not be
            // blocked at the door. Tara can set it later from her side.
            Text("Optional. Tara can set this for you later.")
                .font(Brand.Typography.caption)
                .foregroundStyle(Brand.textSecondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Brand.Spacing.xs) {
                    ForEach(NTRPRating.displayOrdered) { level in
                        Button {
                            rating = (rating == level) ? nil : level
                        } label: {
                            Text(level.label)
                                .font(Brand.Typography.chip)
                                .padding(.horizontal, Brand.Spacing.sm)
                                .frame(minHeight: Brand.Layout.minTapTarget)
                                .foregroundStyle(rating == level ? Brand.textOnNavy : Brand.textPrimary)
                                .background(
                                    Capsule().fill(rating == level ? Brand.navy : Brand.surfaceRaised)
                                )
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
    }

    /// A way off this screen that is not "finish the form".
    ///
    /// Found by hand on 2026-08-15: this screen had no exit. Anyone who reached
    /// it and could not or would not complete it was stuck, with no sign-out and
    /// no back, and relaunching returned them here because the auth session is
    /// still valid. That is the same dead-end shape as the sign-up bug this
    /// screen was built to fix, one screen further along, and no automated test
    /// would have caught it because every test completes the form.
    ///
    /// Signing out is the correct escape: it clears the session, so the next
    /// launch starts at sign-in. The auth user survives, which is why the copy
    /// says the account is kept.
    private var escapeHatch: some View {
        Button {
            Task { await session.signOut() }
        } label: {
            Text("Sign out")
                .font(Brand.Typography.subheadline)
                .foregroundStyle(Brand.textSecondary)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Brand.Layout.minTapTarget)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("profile.signOutFromSetup")
        .accessibilityHint("Signs you out. Your account is kept, and you can finish this later.")
    }

    private var saveButton: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
            Button {
                Task {
                    saving = true
                    _ = await session.completeProfile(
                        firstName: firstName.trimmingCharacters(in: .whitespaces),
                        lastName: lastName.trimmingCharacters(in: .whitespaces),
                        phone: phone.trimmingCharacters(in: .whitespaces).isEmpty ? nil : phone,
                        isMember: isMember ?? false,
                        adultRating: rating?.rawValue
                    )
                    saving = false
                }
            } label: {
                Text(saving ? "Saving…" : "Continue")
                    .font(Brand.Typography.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Brand.Layout.comfortableTapTarget)
                    .foregroundStyle(Brand.textOnNavy)
                    .background(
                        RoundedRectangle(cornerRadius: Brand.Radius.sm)
                            .fill(canSave ? Brand.navy : Brand.disabled)
                    )
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .accessibilityIdentifier("profile.continue")

            // A disabled control always gets visible helper text saying why.
            if !canSave && !saving {
                Text("Add your name and answer the membership question to continue.")
                    .font(Brand.Typography.caption)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
    }
}
