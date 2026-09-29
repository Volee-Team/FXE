//
//  WaiverView.swift
//  FXETennis
//
//  Tara's Adult Tennis Participation Waiver and Release (decision 0013 §4),
//  signed electronically the way her document's last page specifies: a
//  required checkbox with her sentence, the participant's full legal name
//  typed as the signature, the email taken from the signed-in account, the
//  time recorded by the server, and the version stored with the record.
//
//  The text is hers, served by current_waiver(); nothing on this screen is
//  ours except the field labels and the button. Shown once after sign-up,
//  and again whenever register_for_clinic answers waiver_required (a new
//  version, or an account from before the waiver existed): ClinicDetailModel
//  hands that refusal to SessionStore.reopen(.waiver), which is what opens
//  this sheet. Until 2026-09-27 nothing did, and the promise in this comment
//  was untrue.
//
//  The sheet cannot be swiped away, so it carries its own exits: Try again
//  when the text fails to load, and Sign out and Delete my account at the
//  foot (AccountExitFooter).
//

import SwiftUI

struct WaiverView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var waiver: Waiver?
    @State private var agreed = false
    @State private var legalName = ""
    @State private var sending = false
    @State private var loading = false
    /// The text could not be loaded; shown with Try again.
    @State private var loadError: String?
    /// The signature could not be saved; shown under the name field.
    @State private var error: String?

    private var trimmedName: String { legalName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameLooksFull: Bool { trimmedName.count >= 3 && trimmedName.contains(" ") }
    private var canSign: Bool { agreed && nameLooksFull && waiver != nil && !sending }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    if let w = waiver {
                        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                            Text(w.title)
                                .brandFont(.title)
                                .foregroundStyle(Brand.navy)
                            Text(w.organizer)
                                .brandFont(.subheadline)
                                .foregroundStyle(Brand.textSecondary)
                        }
                        ForEach(Array(w.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph.text)
                                .brandFont(paragraph.isHeading ? .bodyEmphasis : .body)
                                .foregroundStyle(Brand.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        signature(w)
                    } else if let loadError, !loading {
                        // A failed load used to end here, with no button, on a
                        // sheet that cannot be swiped away (MVP audit item 7).
                        Text(loadError)
                            .brandFont(.body)
                            .foregroundStyle(Brand.Status.canceled.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("waiver.loadError")
                        Button {
                            Task { await load() }
                        } label: {
                            Text("Try again")
                                .brandFont(.button)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: Brand.Layout.comfortableTapTarget)
                                .foregroundStyle(Brand.textOnNavy)
                                .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("waiver.retry")
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }

                    // The way off this sheet that is not signing: whatever
                    // state the text is in, including a load that failed.
                    AccountExitFooter(signOutID: "waiver.signOut", deleteID: "waiver.delete")
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .background(Brand.surfaceGradient)
            .crispTopEdge()
            .navyTitle("Waiver")
            .navigationBarTitleDisplayMode(.inline)
            .task { await load() }
        }
        .interactiveDismissDisabled()
    }

    private func signature(_ w: Waiver) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            // A checkbox that reads as one on a phone: the box and her sentence
            // share one tap target. A Button rather than a styled Toggle so the
            // element is a button with this identifier to XCUITest and VoiceOver.
            Button { agreed.toggle() } label: {
                HStack(alignment: .top, spacing: Brand.Spacing.sm) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(agreed ? Brand.navy : Brand.textSecondary)
                    // Her required-checkbox sentence, verbatim.
                    Text("I have read and agree to the Adult Tennis Participation Waiver and Release.")
                        .brandFont(.body)
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(agreed ? [.isSelected] : [])
            .accessibilityIdentifier("waiver.agree")

            VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
                Text("Full legal name")
                    .brandFont(.caption)
                    .foregroundStyle(Brand.textSecondary)
                TextField("First and last name", text: $legalName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("waiver.name")
            }

            if let error {
                Text(error)
                    .brandFont(.caption)
                    .foregroundStyle(Brand.Status.canceled.ink)
            }

            Button {
                Task { await sign(w) }
            } label: {
                Group {
                    if sending { ProgressView().tint(Brand.textOnNavy) }
                    else { Text("Agree and sign").brandFont(.button) }
                }
                .frame(maxWidth: .infinity)
                .frame(minHeight: Brand.Layout.comfortableTapTarget)
                .foregroundStyle(Brand.textOnNavy)
                .background(canSign ? Brand.navy : Brand.textSecondary, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
            }
            .buttonStyle(.plain)
            .disabled(!canSign)
            .accessibilityIdentifier("waiver.sign")
        }
        .padding(Brand.Spacing.cardPadding)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
    }

    /// No signal says so in the approved line; anything else, or no published
    /// waiver at all (which used to spin forever), says the waiver did not load.
    private func load() async {
        loading = true
        defer { loading = false }
        loadError = nil
        do {
            waiver = try await ProfileRepository.currentWaiver()
            if waiver == nil { loadError = "Couldn't load the waiver." }
        } catch {
            let failure = RequestFailure(error)
            guard failure != .cancelled else { return }
            loadError = failure.line ?? "Couldn't load the waiver."
        }
    }

    private func sign(_ w: Waiver) async {
        sending = true
        defer { sending = false }
        do {
            try await ProfileRepository.acceptWaiver(version: w.version, legalName: trimmedName, appVersion: ProfileView.versionLine)
            session.waiverAccepted = true
            dismiss()
        } catch {
            // Say which refusal it was (2026-09-29: a generic "Couldn't save
            // your signature." told Alex nothing when his local account had
            // been wiped by a database reset underneath him).
            let text = String(describing: error)
            if text.contains("legal_name_required") {
                self.error = "Type your first and last name."
            } else if text.contains("waiver_version_stale") {
                // Tara published a new version while this one was open.
                self.error = "The waiver was updated. Read it again and sign."
                agreed = false
                await load()
            } else if text.contains("account_not_found") || text.contains("not_authenticated") {
                self.error = "Couldn't find your account. Sign out and sign in again."
            } else {
                self.error = RequestFailure(error).line ?? "Couldn't save your signature."
            }
        }
    }
}

// The waiver is shown by RootView as its own screen, before the app
// (2026-09-29); it used to be a sheet over Home.
