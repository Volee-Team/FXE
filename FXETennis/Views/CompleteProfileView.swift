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
    /// Only Tara reads it (decision 0012, her ask 2026-09-16).
    @State private var levelNote = ""
    @State private var showNTRP = false
    @State private var saving = false
    /// The keyboard covers Continue on every phone once a name field has focus,
    /// and this ScrollView cannot scroll far enough to expose it. Found by the
    /// sign-up XCUITest on 2026-09-01 ("Continue never became reachable"), which
    /// is the exact experience of a real player. Leaving the text fields, by
    /// answering the membership question or picking a rating, drops the keyboard;
    /// so does dragging the form.
    @FocusState private var typing: TypedField?
    /// Return moves first name to last name to phone (the phone pad has no
    /// Return key; the membership question below drops the keyboard).
    private enum TypedField { case firstName, lastName, phone }

    /// Both names are required because they are NOT NULL on both tables and are
    /// what Tara reads in her roster. Membership is required because it decides
    /// which registration window opens first and which price is shown, and a
    /// silent default would quietly put someone in the wrong tier.
    /// Phone and rating became required on 2026-09-16 (Tara: "app needs to
    /// ask every player for their rating.. and phone number").
    private var canSave: Bool {
        !firstName.trimmingCharacters(in: .whitespaces).isEmpty
            && !lastName.trimmingCharacters(in: .whitespaces).isEmpty
            && !phone.trimmingCharacters(in: .whitespaces).isEmpty
            && isMember != nil
            && rating != nil
            && !saving
    }

    var body: some View {
        ZStack {
            CourtBackdrop(strength: .front)

            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    header

                    field("First Name", text: $firstName, content: .givenName, id: "profile.firstName",
                          name: .firstName, next: .lastName)
                    field("Last Name", text: $lastName, content: .familyName, id: "profile.lastName",
                          name: .lastName, next: .phone)
                    field("Phone", text: $phone, content: .telephoneNumber, keyboard: .phonePad, id: "profile.phone",
                          name: .phone, next: nil)

                    membershipQuestion
                    ratingPicker
                    levelNoteField

                    if let error = session.authError {
                        Text(error)
                            .brandFont(.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                            .accessibilityAddTraits(.isStaticText)
                    }

                    saveButton
                    // A way off this screen that is not "finish the form".
                    //
                    // Found by hand on 2026-08-15: this screen had no exit.
                    // Anyone who reached it and could not or would not complete
                    // it was stuck, with no sign-out and no back, and
                    // relaunching returned them here because the auth session
                    // is still valid. No automated test would have caught it
                    // because every test completes the form. Since 2026-09-27
                    // the exit is the footer every onboarding step shares, with
                    // Delete my account beside Sign out (MVP audit item 7).
                    // Signing out keeps the auth user, so they can finish later.
                    AccountExitFooter(signOutID: "profile.signOutFromSetup", deleteID: "profile.deleteFromSetup")
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .scrollDismissesKeyboard(.interactively)
        }
        .statusBarScrim()
        .sheet(isPresented: $showNTRP) { NTRPExplainerSheet() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text("Almost there!")
                .brandFont(.display)
                .foregroundStyle(Brand.textPrimary)
            Text("Members get 24-hour early access to all clinics")
                .brandFont(.subheadline)
                .foregroundStyle(Brand.textSecondary)
        }
        .padding(.bottom, Brand.Spacing.xs)
    }

    private func field(
        _ label: String,
        text: Binding<String>,
        content: UITextContentType,
        keyboard: UIKeyboardType = .default,
        id: String,
        name: TypedField,
        next: TypedField?
    ) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
            Text(label)
                .brandFont(.subheadline)
                .foregroundStyle(Brand.textSecondary)
            TextField("", text: text)
                .focused($typing, equals: name)
                .submitLabel(next == nil ? .done : .next)
                .onSubmit { typing = next }
                .brandFont(.body)
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
                .brandFont(.bodyEmphasis)
                .foregroundStyle(Brand.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Brand.Spacing.sm) {
                choice("Yes", selected: isMember == true, id: "profile.member.yes") { isMember = true; typing = nil }
                choice("No", selected: isMember == false, id: "profile.member.no") { isMember = false; typing = nil }
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
                .brandFont(.button)
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

    /// Her words for the caption. The placeholder is her own example.
    private var levelNoteField: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text("Note for Tara (optional)")
                .brandFont(.bodyEmphasis)
                .foregroundStyle(Brand.textPrimary)
            TextField("Just coming back from a back injury - probably a low 3.5", text: $levelNote, axis: .vertical)
                .lineLimit(2...4)
                .textFieldStyle(.roundedBorder)
                .accessibilityIdentifier("profile.levelNote")
            Text("Only Tara sees this.")
                .brandFont(.caption)
                .foregroundStyle(Brand.textSecondary)
        }
    }

    private var ratingPicker: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            HStack(spacing: Brand.Spacing.xxs) {
                Text("Your tennis rating")
                    .brandFont(.bodyEmphasis)
                    .foregroundStyle(Brand.textPrimary)
                // Was a "Rating Guide" text link at the far right (her
                // "Need Help?" before that, decision 0016). Tara, 2026-09-28:
                // the tool tip goes next to the rating words (decision 0024).
                RatingGuideButton(identifier: "profile.ratingGuide") { showNTRP = true }
                Spacer()
            }

            // Required since 2026-09-16 (Tara: the app "needs to ask every
            // player for their rating"); it was optional before. "Need Help?"
            // opens her chart for anyone unsure.

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: Brand.Spacing.xs) {
                    ForEach(NTRPRating.displayOrdered) { level in
                        Button {
                            rating = (rating == level) ? nil : level
                            typing = nil
                        } label: {
                            Text(level.label)
                                .brandFont(.chip)
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
                        adultRating: rating?.rawValue,
                        levelNote: levelNote.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : levelNote.trimmingCharacters(in: .whitespacesAndNewlines)
                    )
                    saving = false
                }
            } label: {
                Text(saving ? "Saving…" : "Continue")
                    .brandFont(.button)
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
                Text("Add your name, phone number, and tennis rating. Please answer the membership question to continue")
                    .brandFont(.caption)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
    }
}
