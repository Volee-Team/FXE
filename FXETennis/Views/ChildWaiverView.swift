//
//  ChildWaiverView.swift
//  FXETennis
//
//  The parent/guardian waiver, signed by the parent for one child (spec 01:
//  "Require a parent-signed waiver for each child"; decision 0061). The same
//  mechanism as the adult waiver (WaiverView, decision 0013 §4): the text is
//  Tara's, served by current_junior_waiver(); a checkbox; the parent's full
//  legal name typed as the signature; email, time and version recorded by the
//  server. A new version each year means a new signature (question 145:
//  "once per child per year").
//
//  Until Tara's parent/guardian text is published there is nothing to sign:
//  the child's page says so and never opens this sheet. If it opens anyway
//  (the text was withdrawn meanwhile), it says the same and offers Close.
//
//  Unlike the adult waiver, this sheet can be closed: nothing waits on it
//  until phase 2's sign-up.
//

import SwiftUI

struct ChildWaiverView: View {
    let child: Child
    @Environment(\.dismiss) private var dismiss
    @State private var waiver: Waiver?
    @State private var agreed = false
    @State private var legalName = ""
    @State private var sending = false
    @State private var loading = true
    @State private var loadError: String?
    @State private var error: String?

    private var trimmedName: String { legalName.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var nameLooksFull: Bool { trimmedName.count >= 3 && trimmedName.contains(" ") }
    private var canSign: Bool { agreed && nameLooksFull && waiver != nil && !sending }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    // Whose waiver this is, above everything else.
                    Text("For \(child.fullName)")
                        .brandFont(.headline)
                        .foregroundStyle(Brand.navy)
                        .accessibilityIdentifier("childWaiver.for")
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
                    } else if loading {
                        ProgressView().frame(maxWidth: .infinity)
                    } else {
                        Text(loadError ?? JuniorCopy.waiverNotAvailableLine)
                            .brandFont(.body)
                            .foregroundStyle(loadError == nil ? Brand.textSecondary : Brand.Status.canceled.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("childWaiver.unavailable")
                        if loadError != nil {
                            Button("Try again") { Task { await load() } }
                                .brandFont(.button)
                                .accessibilityIdentifier("childWaiver.retry")
                        }
                    }
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .accessibilityIdentifier("childWaiver.screen")
            .background(Brand.surfaceGradient)
            .crispTopEdge()
            .navyTitle("Waiver")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                        .accessibilityIdentifier("childWaiver.close")
                        .tint(Brand.textOnNavy)
                }
                .onNavy()
            }
            .task { await load() }
        }
    }

    private func signature(_ w: Waiver) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.md) {
            Button { agreed.toggle() } label: {
                HStack(alignment: .top, spacing: Brand.Spacing.sm) {
                    Image(systemName: agreed ? "checkmark.square.fill" : "square")
                        .font(.title2)
                        .foregroundStyle(agreed ? Brand.navy : Brand.textSecondary)
                    Text("I am \(child.firstName)'s parent or guardian, and I have read and agree to this waiver for them.")
                        .brandFont(.body)
                        .foregroundStyle(Brand.textPrimary)
                        .multilineTextAlignment(.leading)
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(agreed ? [.isSelected] : [])
            .accessibilityIdentifier("childWaiver.agree")

            VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
                Text("Your full legal name")
                    .brandFont(.caption)
                    .foregroundStyle(Brand.textSecondary)
                TextField("First and last name", text: $legalName)
                    .textContentType(.name)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("childWaiver.name")
            }

            if let error {
                Text(error)
                    .brandFont(.caption)
                    .foregroundStyle(Brand.Status.canceled.ink)
                    .accessibilityIdentifier("childWaiver.error")
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
            .accessibilityIdentifier("childWaiver.sign")
        }
        .padding(Brand.Spacing.cardPadding)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
    }

    private func load() async {
        loading = true
        defer { loading = false }
        loadError = nil
        do {
            waiver = try await JuniorsRepository.currentWaiver()
        } catch {
            let failure = RequestFailure(error)
            guard failure != .cancelled else { return }
            loadError = failure.line ?? "Couldn't load the waiver."
        }
    }

    private func sign(_ w: Waiver) async {
        sending = true
        defer { sending = false }
        error = nil
        do {
            try await JuniorsRepository.acceptWaiver(child: child.id, version: w.version, legalName: trimmedName,
                                                     appVersion: ProfileView.versionLine)
            dismiss()
        } catch {
            let text = String(describing: error)
            if text.contains("legal_name_required") {
                self.error = "Type your first and last name."
            } else if text.contains("waiver_version_stale") {
                // Tara published a new version while this one was open.
                self.error = "The waiver was updated. Read it again and sign."
                agreed = false
                await load()
            } else if text.contains("account_not_found") {
                self.error = "Couldn't find your account. Sign out and sign in again."
            } else {
                self.error = JuniorCopy.line(for: error) ?? "Couldn't save your signature."
            }
        }
    }
}
