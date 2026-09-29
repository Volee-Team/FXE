//
//  ProfileView.swift
//  FXETennis
//
//  The player's own details, the NTRP explainer behind a "?", and sign out.
//  Editing name/contact/rating is built on top of this shell.
//

import SwiftUI

struct ProfileView: View {
    @Environment(\.openURL) private var openURL
    @Environment(SessionStore.self) private var session
    @State private var showNTRP = false
    @State private var editing = false
    @State private var confirmDelete = false
    @State private var deleting = false
    @State private var deleteError: String?
    /// Payments are switched on. Until then there is no card to show or add
    /// (decision 0016: "Let's only do if stripe is connected"). Starts false,
    /// so the section never flashes up and away.
    @State private var paymentsOn = false
    /// Subscribe in Calendar (decision 0029): asking the server for the link.
    @State private var subscribing = false
    @State private var calendarError: String?

    var body: some View {
        NavigationStack {
            ZStack {
                CourtBackdrop()
                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                        header
                        detailsCard
                        // My Clinics, with Past, used to hang off Home's "View All
                        // Clinics" button; Final Updates p.1 removed that button.
                        NavigationLink { MyClinicsView() } label: {
                            OutlinedButtonLabel("My Clinics", icon: "calendar")
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.myClinics")
                        // Every clinic she holds, kept up to date by the phone
                        // itself (decision 0029). Not for an account with no
                        // player row: its calendar would always be empty.
                        if session.activePlayer != nil {
                            Button {
                                Task { await subscribeInCalendar() }
                            } label: {
                                OutlinedButtonLabel("Subscribe in Calendar", icon: "calendar.badge.plus")
                            }
                            .buttonStyle(.plain)
                            .disabled(subscribing)
                            .accessibilityIdentifier("profile.subscribeCalendar")
                            if let calendarError {
                                Text(calendarError)
                                    .brandFont(.caption)
                                    .foregroundStyle(Brand.Status.canceled.ink)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("profile.subscribeCalendarError")
                            }
                        }
                        if paymentsOn {
                            CardOnFileView()
                        }

                        Button {
                            editing = true
                        } label: {
                            Text("Edit details")
                                .brandFont(.button)
                                .frame(maxWidth: .infinity)
                                .frame(minHeight: Brand.Layout.comfortableTapTarget)
                                .foregroundStyle(Brand.textOnNavy)
                                .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("profile.edit")
                        // Identifier on the BUTTON, not on the Text inside it.
                        // Set on the label, it lands on the inner static text
                        // and `app.buttons["profile.signOut"]` matches nothing,
                        // which is why every UI test that signs out failed with
                        // "No sign-out control on Profile". Same drift as the
                        // Home clinic card.
                        // A text link, not a button: signing out is not the
                        // screen's main action (TestFlight, 2026-09-22).
                        Button(role: .destructive) {
                            Task { await session.signOut() }
                        } label: {
                            Text("Sign Out")
                                .brandFont(.body)
                                .underline()
                                .foregroundStyle(Brand.textPrimary)
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(QuietLinkButtonStyle())
                        .accessibilityIdentifier("profile.signOut")

                        // How a member reaches Tara: question 76, "Yes" on
                        // 2026-09-28 (decision 0024). Her address, the one the
                        // privacy policy and the App Store listing show.
                        Button("Contact Tara") {
                            openURL(URL(string: "mailto:fersctennispro@gmail.com")!)
                        }
                        .brandFont(.caption)
                        .foregroundStyle(Brand.textPrimary)
                        .buttonStyle(QuietLinkButtonStyle())
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("profile.contactTara")

                        // Apple requires the privacy policy to be reachable in the app
                        // (guideline 5.1.1). Tara approved it on 2026-09-27.
                        Button("Privacy Policy") {
                            openURL(URL(string: "https://fxe-tennis-admin.vercel.app/privacy.html")!)
                        }
                        .brandFont(.caption)
                        .foregroundStyle(Brand.textSecondary)
                        .buttonStyle(QuietLinkButtonStyle())
                        .frame(maxWidth: .infinity)
                        .accessibilityIdentifier("profile.privacy")

                        // Last of the actions, under Contact Tara and Privacy Policy
                        // (2026-09-28): the destructive one sits at the foot, where
                        // iOS Settings puts it, not between two everyday links.
                        // App Store 5.1.1(v); decision 0013 §5: history stays,
                        // the person is removed. Two taps, spelled out.
                        Button(role: .destructive) {
                            confirmDelete = true
                        } label: {
                            Text("Delete my account")
                                .brandFont(.caption)
                                .frame(maxWidth: .infinity)
                                .foregroundStyle(Brand.Status.canceled.ink)
                        }
                        .buttonStyle(QuietLinkButtonStyle())
                        .disabled(deleting || session.account?.isAdmin == true)
                        .accessibilityIdentifier("profile.delete")
                        .confirmationDialog(
                            "Delete your account? Your name, phone, email and card are removed and you are signed out. This can't be undone.",
                            isPresented: $confirmDelete, titleVisibility: .visible
                        ) {
                            Button("Delete my account", role: .destructive) {
                                Task {
                                    deleting = true
                                    do {
                                        try await ProfileRepository.deleteMyAccount()
                                        await session.signOut()
                                    } catch {
                                        deleteError = "Couldn't delete your account."
                                    }
                                    deleting = false
                                }
                            }
                            Button("Keep my account", role: .cancel) {}
                        }
                        if let deleteError {
                            Text(deleteError)
                                .brandFont(.caption)
                                .foregroundStyle(Brand.Status.canceled.ink)
                                .frame(maxWidth: .infinity)
                        }

                        // Which build is this? The first question in every
                        // "it looks wrong on my phone" text from Tara or a
                        // tester, and TestFlight installs several a week.
                        Text(Self.versionLine)
                            .brandFont(.caption)
                            .foregroundStyle(Brand.textSecondary)
                            .frame(maxWidth: .infinity)
                            .accessibilityIdentifier("profile.version")
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
                .crispTopEdge()
            }
            .bannerTitle("Profile")
            // Read on every visit, so the switch shows without an app update.
            // A failed read (bad signal) keeps what was last known.
            .task { if let on = try? await PaymentsRepository.paymentsEnabled() { paymentsOn = on } }
            .sheet(isPresented: $showNTRP) { NTRPExplainerSheet() }
            .sheet(isPresented: $editing) { EditProfileView() }
        }
    }

    /// Asks the server for this account's feed token and hands the webcal
    /// link to iOS, which shows its own "Subscribe to calendar?" and does the
    /// rest in Calendar. Tapping again later gives the same link.
    private func subscribeInCalendar() async {
        subscribing = true
        defer { subscribing = false }
        calendarError = nil
        do {
            let token = try await ProfileRepository.calendarFeedToken()
            guard let url = CalendarFeed.webcalURL(
                functionURL: CalendarFeed.functionURL(projectURL: supabaseProjectURL), token: token)
            else {
                calendarError = CalendarFeed.failedLine
                return
            }
            openURL(url)
        } catch {
            let failure = RequestFailure(error)
            if failure == .cancelled { return }
            calendarError = failure.line ?? CalendarFeed.failedLine
        }
    }

    /// "Version 0.1.0 (1)", from the bundle so it can never drift from what
    /// was actually shipped.
    static var versionLine: String {
        let info = Bundle.main.infoDictionary ?? [:]
        let short = info["CFBundleShortVersionString"] as? String ?? "?"
        let build = info["CFBundleVersion"] as? String ?? "?"
        return "Version \(short) (\(build))"
    }

    private var header: some View {
        let player = session.activePlayer
        // An admin account can have no player row (Tara runs the program; she
        // is not on a roster). Her name then comes from the account and there
        // is no membership to show: her Profile used to read "Player" and
        // "Non-member" (seen on the simulator, 2026-09-28).
        let accountName = session.account.map { "\($0.firstName) \($0.lastName)" }?
            .trimmingCharacters(in: .whitespaces)
        return VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(player?.fullName ?? accountName ?? "")
                .brandFont(.display)
                .foregroundStyle(Brand.navy)
            if let player {
                Text(player.isMember ? "FXE Member" : "Non-member")
                    .brandFont(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
            }
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
                // Final Updates p.2 item 1: the "?" sits next to the rating,
                // below the phone, and smaller (it was in the toolbar).
                VStack(alignment: .leading, spacing: 2) {
                    Text("Rating").brandFont(.caption).foregroundStyle(Brand.textSecondary)
                    HStack(spacing: Brand.Spacing.xxs) {
                        Text(String(format: "%.1f", rating))
                            .brandFont(.body).foregroundStyle(Brand.textPrimary)
                        Button { showNTRP = true } label: {
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 15, weight: .regular))
                                .foregroundStyle(Brand.textSecondary)
                        }
                        .buttonStyle(QuietLinkButtonStyle())
                        .accessibilityLabel("What do the ratings mean?")
                        .accessibilityIdentifier("profile.ratingHelp")
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
    }

    /// Label above value, both left-aligned. TestFlight, 2026-09-22 (Kat):
    /// the right-justified values sat too far from their labels to read as pairs.
    private func row(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).brandFont(.caption).foregroundStyle(Brand.textSecondary)
            Text(value).brandFont(.body).foregroundStyle(Brand.textPrimary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
                                .brandFont(.headline)
                                .foregroundStyle(Brand.navy)
                            Text(rating.detail)
                                .brandFont(.subheadline)
                                .foregroundStyle(Brand.textSecondary)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .background(Brand.surfaceGradient)
            .crispTopEdge()
            .navyTitle("Rating Guide")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                    .tint(Brand.textOnNavy)
                }
                .onNavy()
            }
        }
    }
}

/// The Rating Guide's "?", placed right beside the rating words. Tara,
/// 2026-09-28 (decision 0024): "Correct. Words do not change. Tool tip next to
/// “rating” language". The words she kept are the accessible name; the glyph
/// is the tool tip she asked for, the same one Profile already uses.
struct RatingGuideButton: View {
    let identifier: String
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Brand.textSecondary)
        }
        .buttonStyle(QuietLinkButtonStyle())
        .accessibilityLabel("Rating Guide")
        .accessibilityIdentifier(identifier)
    }
}
