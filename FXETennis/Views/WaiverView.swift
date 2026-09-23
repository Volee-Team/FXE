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
//  version, or an account from before the waiver existed).
//

import SwiftUI

struct WaiverView: View {
    @Environment(SessionStore.self) private var session
    @Environment(\.dismiss) private var dismiss
    @State private var waiver: Waiver?
    @State private var agreed = false
    @State private var legalName = ""
    @State private var sending = false
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
                                .font(Brand.Typography.title)
                                .foregroundStyle(Brand.navy)
                            Text(w.organizer)
                                .font(Brand.Typography.subheadline)
                                .foregroundStyle(Brand.textSecondary)
                        }
                        ForEach(Array(w.paragraphs.enumerated()), id: \.offset) { _, paragraph in
                            Text(paragraph.text)
                                .font(paragraph.isHeading ? Brand.Typography.bodyEmphasis : Brand.Typography.body)
                                .foregroundStyle(Brand.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        signature(w)
                    } else if let error {
                        Text(error)
                            .font(Brand.Typography.body)
                            .foregroundStyle(Brand.Status.canceled.ink)
                    } else {
                        ProgressView().frame(maxWidth: .infinity)
                    }
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .background(Brand.surfaceGradient)
            .navigationTitle("Waiver")
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
                        .font(Brand.Typography.body)
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
                    .font(Brand.Typography.caption)
                    .foregroundStyle(Brand.textSecondary)
                TextField("First and last name", text: $legalName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("waiver.name")
            }

            if let error {
                Text(error)
                    .font(Brand.Typography.caption)
                    .foregroundStyle(Brand.Status.canceled.ink)
            }

            Button {
                Task { await sign(w) }
            } label: {
                Group {
                    if sending { ProgressView().tint(Brand.textOnNavy) }
                    else { Text("Agree and sign").font(Brand.Typography.button) }
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

    private func load() async {
        do { waiver = try await ProfileRepository.currentWaiver() }
        catch { self.error = "Couldn't load the waiver." }
    }

    private func sign(_ w: Waiver) async {
        sending = true
        defer { sending = false }
        do {
            try await ProfileRepository.acceptWaiver(version: w.version, legalName: trimmedName, appVersion: ProfileView.versionLine)
            session.waiverAccepted = true
            dismiss()
        } catch {
            self.error = String(describing: error).contains("legal_name_required")
                ? "Type your first and last name."
                : "Couldn't save your signature."
        }
    }
}

/// Presents the waiver over the app until the signed-in player has signed the
/// current version. Admins are exempt (paperwork never blocks Tara). A player
/// who has not signed cannot reach Register: the server refuses anyway.
private struct WaiverGate: ViewModifier {
    @Environment(SessionStore.self) private var session

    func body(content: Content) -> some View {
        content
            .sheet(isPresented: Binding(
                get: { session.waiverAccepted == false && session.account?.role != "admin" },
                set: { _ in }
            )) { WaiverView() }
    }
}

extension View {
    func waiverGate() -> some View { modifier(WaiverGate()) }
}
