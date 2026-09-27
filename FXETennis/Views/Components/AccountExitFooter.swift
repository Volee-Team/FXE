//
//  AccountExitFooter.swift
//  FXETennis
//
//  The way off a step that is not "finish it": Sign out, and Delete my
//  account behind the same confirmation Profile uses, word for word. Shared
//  by every screen that stands between a new account and the app: the
//  profile form, the waiver, the card step (CardStepView should adopt it in
//  place of its own Sign out), and the load-failed screen (Sign out only).
//
//  Why (MVP audit item 7, 2026-09-27). The waiver sheet cannot be swiped
//  away and had no exit at all: someone who would not sign could not sign
//  out or delete the account they had just made, and on bad court Wi-Fi a
//  failed load showed "Couldn't load the waiver." until the app was killed,
//  with the same sheet after every relaunch. That is the dead-end shape
//  CompleteProfileView was fixed for on 2026-08-15, one screen further along.
//  App Store guideline 5.1.1(v) also asks that an account can be deleted from
//  inside the app, and until now only Profile, behind these steps, offered it.
//

import SwiftUI

struct AccountExitFooter: View {
    @Environment(SessionStore.self) private var session
    /// Identifier for Sign out (kept per screen so existing UI tests hold).
    let signOutID: String
    /// Identifier for Delete my account; nil leaves the button out.
    let deleteID: String?

    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?

    var body: some View {
        VStack(spacing: Brand.Spacing.xxs) {
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
            .disabled(deleting)
            .accessibilityIdentifier(signOutID)
            .accessibilityHint("Signs you out, you can finish later if needed")

            if let deleteID {
                // The same dialog and words as ProfileView (decision 0013 §5):
                // history stays, the person is removed. Two taps, spelled out.
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Text("Delete my account")
                        .font(Brand.Typography.caption)
                        .foregroundStyle(Brand.Status.canceled.ink)
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: Brand.Layout.minTapTarget)
                }
                .buttonStyle(.plain)
                .disabled(deleting || session.account?.isAdmin == true)
                .accessibilityIdentifier(deleteID)
                .confirmationDialog(
                    "Delete your account? Your name, phone, email and card are removed and you are signed out. This can't be undone.",
                    isPresented: $confirmDelete, titleVisibility: .visible
                ) {
                    Button("Delete my account", role: .destructive) {
                        Task { await delete() }
                    }
                    Button("Keep my account", role: .cancel) {}
                }

                if let deleteError {
                    Text(deleteError)
                        .font(Brand.Typography.caption)
                        .foregroundStyle(Brand.Status.canceled.ink)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.top, Brand.Spacing.sm)
    }

    private func delete() async {
        deleting = true
        deleteError = nil
        do {
            try await ProfileRepository.deleteMyAccount()
            await session.signOut()
        } catch {
            deleteError = "Couldn't delete your account."
        }
        deleting = false
    }
}
