//
//  ProfileView.swift
//  FXETennis
//
//  The player's own details, the NTRP explainer behind a "?", and sign out.
//  Editing name/contact/rating is built on top of this shell.
//

import SwiftUI

struct ProfileView: View {
    @Environment(SessionStore.self) private var session
    @State private var showNTRP = false

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surface.ignoresSafeArea()
                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                        header
                        detailsCard
                        // Identifier on the BUTTON, not on the Text inside it.
                        // Set on the label, it lands on the inner static text
                        // and `app.buttons["profile.signOut"]` matches nothing,
                        // which is why every UI test that signs out failed with
                        // "No sign-out control on Profile". Same drift as the
                        // Home clinic card.
                        Button(role: .destructive) {
                            Task { await session.signOut() }
                        } label: {
                            Text("Sign Out")
                                .font(Brand.Typography.button)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
                        }
                        .accessibilityIdentifier("profile.signOut")
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
            }
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { showNTRP = true } label: {
                        Image(systemName: "questionmark.circle")
                    }
                    .accessibilityLabel("What do the ratings mean?")
                }
            }
            .sheet(isPresented: $showNTRP) { NTRPExplainerSheet() }
        }
    }

    private var header: some View {
        let player = session.activePlayer
        return VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(player?.fullName ?? "Player")
                .font(Brand.Typography.display)
                .foregroundStyle(Brand.navy)
            Text(player?.isMember == true ? "FXE Member" : "Non-member")
                .font(Brand.Typography.subheadline)
                .foregroundStyle(Brand.textSecondary)
        }
    }

    private var detailsCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            if let email = session.account?.email {
                row("Email", email)
            }
            if let phone = session.account?.phone {
                row("Phone", phone)
            }
            if let rating = session.activePlayer?.adultRating {
                row("Rating", String(format: "%.1f", rating))
            }
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).font(Brand.Typography.subheadline).foregroundStyle(Brand.textSecondary)
            Spacer()
            Text(value).font(Brand.Typography.body).foregroundStyle(Brand.textPrimary)
        }
    }
}

/// The USTA NTRP scale in Tara's words, matching Volee verbatim. Opened from the
/// "?" so a nervous new player can self-place.
struct NTRPExplainerSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.md) {
                    ForEach(NTRPRating.displayOrdered) { rating in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(rating.label)
                                .font(Brand.Typography.headline)
                                .foregroundStyle(Brand.navy)
                            Text(rating.detail)
                                .font(Brand.Typography.subheadline)
                                .foregroundStyle(Brand.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .background(Brand.surface)
            .navigationTitle("Rating Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}
