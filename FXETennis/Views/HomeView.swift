//
//  HomeView.swift
//  FXETennis
//
//  The front page, as specified by Kat and Tara on 2026-09-26 ("FXE Final
//  Updates", p.1), which replaces the two-section, two-button layout:
//
//    1. Make the logo smaller.
//    2. Clinics already enrolled should be first, under My Clinics.
//    3. If no clinics enrolled, list open clinics.
//    4. Remove all other CTAs.
//    5. If the user has 2 or more enrolled clinics, show the blue CTA.
//    6. The court photo behind it, with the overlay.
//
//  Kat, same day: "Pick one button or the other or just list available
//  clinics. It's all the same info. If they are registered or waitlisted that
//  would be top of page." Tara: the word "clinic" appeared six times.
//
//  Reading of 3 and 5 together (written down in docs/decisions/0015 and asked
//  back as question 59): with none or one enrolled there is room, so the open
//  clinics are listed; with two or more, the page would become a long list of
//  both, so the open list gives way to the one blue button that leads to it.
//  "Open" means open for registration for THIS player right now (members from
//  the Thursday, everyone from the Friday, until the 3-hour close), which is
//  the sense of Tara's own empty line, "No clinics currently open for
//  registration". My Clinics, with Past, moved to Profile.
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = ClinicsViewModel()
    @State private var showNotifications = false
    @State private var unread = 0

    private var isMember: Bool { session.activePlayer?.isMember ?? false }

    /// Upcoming clinics this player holds a live registration in (You're In!,
    /// Player Pool, Response Needed), soonest first.
    private var myClinics: [ClinicPublic] {
        model.clinics.filter { model.myRegistrationsByClinic[$0.id] != nil && !$0.isCanceled }
    }
    /// Open for registration to this player at `now`, and not already theirs.
    private func openNow(at now: Date) -> [ClinicPublic] {
        model.clinics.filter {
            model.myRegistrationsByClinic[$0.id] == nil && $0.isOpenForRegistration(isMember: isMember, now: now)
        }
    }
    /// When the open list changes on its own: any clinic's opening for this
    /// player, its close, its start (MVP audit item 8). Thursday 8:00 lists
    /// the week's clinics without a pull.
    private var openListRedraws: [Date] {
        RedrawSchedule.at(model.clinics.flatMap { $0.upcomingMoments(isMember: isMember) })
    }
    /// Final Updates p.1 items 3 and 5: the list while there is room, the
    /// blue button once two or more of the player's own clinics fill the top.
    private var showsOpenList: Bool { myClinics.count < 2 }

    /// The icon shows the bell's count, set only from a count that came
    /// back, and only while still signed in: a failed fetch used to set the
    /// icon from the old number, and one landing after sign-out put the
    /// previous person's number back (review, 2026-09-27).
    private func refreshUnread() async {
        guard let count = try? await NotificationRepository.unreadCount() else { return }
        unread = count
        if session.phase == .signedIn { PushRegistrar.shared.setBadge(count) }
    }

    var body: some View {
        NavigationStack {
            GeometryReader { geo in
                ZStack(alignment: .top) {
                    CourtBackdrop(strength: .front)

                    VStack(spacing: 0) {
                        BrandHeader(height: geo.safeAreaInsets.top + 76) {
                            HStack(alignment: .center) {
                                Wordmark(compact: true)
                                Spacer()
                                BellButton(unread: unread) { showNotifications = true }
                                    // A push landed while open, or was tapped (NotificationRouter).
                                    .onChange(of: NotificationRouter.shared.reloads) { Task { await model.load(); await refreshUnread() } }
                            }
                            .padding(.horizontal, Brand.Spacing.pageMargin)
                            .padding(.top, geo.safeAreaInsets.top + 4)
                        }

                        ScrollView {
                            VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                                // The greeting block from the guide: centered under
                                // the header, serif greeting in navy, then the accent
                                // line in italic gator-green.
                                VStack(spacing: Brand.Spacing.xxs) {
                                    Text(greetingText)
                                        .brandFont(.greeting)
                                        .foregroundStyle(Brand.navy)
                                        .multilineTextAlignment(.center)
                                        .accessibilityIdentifier("home.greeting")
                                    Text("Let's Play.")
                                        .brandFont(.greetingAccent)
                                        .foregroundStyle(Brand.court)
                                }
                                .frame(maxWidth: .infinity)
                                .padding(.top, Brand.Spacing.xs)
                                NotificationsOffLine()

                                // The last load failed. Said above everything
                                // else, because what is below may be old, and
                                // an empty list below is not "no clinics"
                                // (MVP audit item 9: with no signal, Home told
                                // a member holding a spot that nothing was open).
                                if let loadError = model.loadError {
                                    Text(loadError)
                                        .brandFont(.subheadline)
                                        .foregroundStyle(Brand.Status.canceled.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                        .accessibilityIdentifier("home.loadError")
                                }

                                if !myClinics.isEmpty {
                                    SectionBlock(title: "My Clinics") {
                                        ForEach(myClinics) { clinic in row(clinic) }
                                    }
                                    .accessibilityIdentifier("home.myClinics")
                                }

                                if !model.hasLoaded {
                                    // The first load is still out: nothing
                                    // below would be true yet.
                                    // The shape of the list, not a spinner:
                                    // first sign-in only (decision 0028).
                                    PlaceholderRows()
                                        .padding(.vertical, Brand.Spacing.md)
                                        .accessibilityIdentifier("home.loading")
                                } else if showsOpenList {
                                    TimelineView(.explicit(openListRedraws)) { _ in
                                        openList(openNow(at: Date()))
                                    }
                                } else {
                                    NavigationLink { ClinicsView() } label: {
                                        FilledButtonLabel("View Open Clinics", icon: "figure.tennis")
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("home.viewOpenClinics")
                                }
                            }
                            .padding(Brand.Spacing.pageMargin)
                        }
                        // Room for the floating tab bar, so the last row is never under it.
                        .contentMargins(.bottom, Brand.Spacing.xxl + Brand.Spacing.xl, for: .scrollContent)
                    }
                    .ignoresSafeArea(edges: .top)
                }
            }
            .navigationBarHidden(true)
            // White status bar text over the navy header (the bar stays
            // hidden; its colour scheme is what sets the status bar). See
            // lightStatusBar() in BrandHeader.swift.
            .toolbarColorScheme(.dark, for: .navigationBar)
            .task { await model.load(); await refreshUnread() }
            // A "Remind me" moves or goes with what this list says (RegistrationReminders).
            .reconcilesReminders(clinics: model.clinics, registered: Set(model.myRegistrationsByClinic.keys),
                                 isMember: isMember)
            .refreshable { await model.load(); await refreshUnread() }
            // Opening the app is how a Pool player learns she was invited
            // until push is live (MVP audit item 8).
            .reloadOnForeground { await model.load(); await refreshUnread() }
            .sheet(isPresented: $showNotifications, onDismiss: { Task { await refreshUnread() } }) {
                NotificationsView { Task { await refreshUnread() } }
            }
        }
    }

    /// The open list, or its empty line. After a failed load with nothing to
    /// show, the section is left out: "No clinics currently open" would be a
    /// claim the app cannot make, and the error line above says why.
    @ViewBuilder private func openList(_ open: [ClinicPublic]) -> some View {
        if !(open.isEmpty && model.loadError != nil) {
            SectionBlock(title: "Open for Registration") {
                if open.isEmpty {
                    EmptyLine("No clinics currently open for registration")
                } else {
                    ForEach(open) { clinic in row(clinic) }
                }
            }
            .accessibilityIdentifier("home.openList")
        }
    }

    /// Her mockup reads "Good Morning, Sara!" — time-aware, first name, warm.
    ///
    /// Falls back to the ACCOUNT name before "there". An admin account has no
    /// `players` row of its own, so reading only `activePlayer` greeted Tara as
    /// "there" on her own app (seen on the simulator 2026-08-15). "there" now
    /// means what it should: we genuinely do not know who this is, which is the
    /// signal that a profile failed to load.
    private var greetingText: String {
        let name = session.activePlayer?.firstName
            ?? session.account?.firstName
            ?? "there"
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "Good Morning" : (hour < 17 ? "Good Afternoon" : "Good Evening")
        return "\(part), \(name)!"
    }

    private func row(_ clinic: ClinicPublic) -> some View {
        NavigationLink {
            ClinicDetailView(clinic: clinic, isMember: isMember,
                             onChanged: { await model.load() })
        } label: {
            ClinicRow(clinic: clinic,
                      registration: model.myRegistrationsByClinic[clinic.id],
                      isMember: isMember)
        }
        .buttonStyle(.plain)
        // On the LINK, not on the row inside it. A SwiftUI accessibility
        // identifier set on a NavigationLink's label lands on the label element
        // rather than on the button the link publishes, so
        // `app.buttons["clinic.card"]` finds nothing and every Home-based UI
        // test dies at "No clinic cards rendered". ClinicsView:84 already does
        // it this way; Home drifted when it was rebuilt in 8357fb9.
        .accessibilityIdentifier("clinic.card")
    }
}

// MARK: - Pieces of Tara's layout, shared across screens

/// The navy bar her mockups put at the top of every important screen. The
/// greeting or screen name sits inside it, small and left-aligned, with the
/// notification bell on the right.
/// The bell that used to live in NavyHeaderBar; the header now carries the
/// wordmark (style guide) and the bell sits beside it.
struct BellButton: View {
    let unread: Int
    let onBell: () -> Void
    var body: some View {
        Button(action: onBell) {
            // Palette colours go to the symbol's layers in order: on
            // "bell.badge" the first is the dot, but "bell" has one layer and
            // took the dot's green, so the bell turned green whenever
            // everything was read (seen offline, 2026-09-28).
            Image(systemName: unread > 0 ? "bell.badge" : "bell")
                .font(.system(size: 20, weight: .regular))
                .symbolRenderingMode(.palette)
                .foregroundStyle(unread > 0 ? Brand.court : Brand.textOnNavy, Brand.textOnNavy)
                .frame(minWidth: Brand.Layout.minTapTarget, minHeight: Brand.Layout.minTapTarget)
                // A plain button is only the drawn glyph without this; the
                // audit measured the bell at 19 by 20 points (2026-09-28).
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.bell")
        .accessibilityLabel(unread > 0 ? "Notifications, \(unread) unread" : "Notifications")
    }
}

struct NavyHeaderBar: View {
    let title: String
    var showsBell: Bool = true
    /// Unread count for the badge; the bell is a button only when `onBell` is set.
    var unread: Int = 0
    var onBell: (() -> Void)? = nil
    /// Identifier for the title text (Home passes "home.greeting"). It has to
    /// sit on the Text, not the bar: once the bar held a button, SwiftUI
    /// merged the whole bar into one button labelled by the bell, which broke
    /// the greeting query AND made `app.buttons["Profile"]` match the Profile
    /// screen's own header instead of the tab (found by the UI tests, 09-02).
    var titleIdentifier: String? = nil

    var body: some View {
        HStack {
            Text(title)
                .brandFont(.bodyEmphasis)
                .foregroundStyle(Brand.textOnNavy)
                .accessibilityIdentifier(titleIdentifier ?? "")
            Spacer()
            if showsBell {
                Button {
                    onBell?()
                } label: {
                    ZStack(alignment: .topTrailing) {
                        Image(systemName: unread > 0 ? "bell.badge" : "bell")
                            .font(.system(size: 17, weight: .medium))
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(unread > 0 ? Brand.accent : Brand.textOnNavy, Brand.textOnNavy)
                    }
                    .frame(minWidth: Brand.Layout.minTapTarget, minHeight: Brand.Layout.minTapTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(onBell == nil)
                .accessibilityIdentifier("home.bell")
                .accessibilityLabel(unread > 0 ? "Notifications, \(unread) unread" : "Notifications")
            }
        }
        .padding(.horizontal, Brand.Spacing.pageMargin)
        .padding(.vertical, Brand.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Brand.navy)
        .accessibilityElement(children: .contain)
    }
}

/// A titled block: small caps navy label, then its content.
struct SectionBlock<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            Text(title.uppercased())
                .brandFont(.chip)
                .tracking(0.6)
                .foregroundStyle(Brand.navy)
            content
        }
    }
}

/// Compact list row: name over time on the left, status on the right. This is
/// the shape her mockup uses on Home, as opposed to the taller cards on the
/// Clinics tab where there is room to breathe.
struct ClinicRow: View {
    let clinic: ClinicPublic
    let registration: MyRegistration?
    let isMember: Bool
    /// At the accessibility text sizes the status or price goes under the
    /// name: beside it, "Response Needed" alone is wider than the screen and
    /// left the name a sliver.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        Group {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
                    details
                    trailing
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                HStack(alignment: .center, spacing: Brand.Spacing.sm) {
                    details
                    Spacer(minLength: Brand.Spacing.sm)
                    trailing
                }
            }
        }
        .padding(.vertical, Brand.Spacing.sm)
        .contentShape(Rectangle())
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(clinic.name)
                .brandFont(.bodyEmphasis)
                .foregroundStyle(Brand.navy)
                .multilineTextAlignment(.leading)
            Text(timeLine)
                .brandFont(.subheadline)
                .foregroundStyle(Brand.textSecondary)
        }
    }

    @ViewBuilder private var trailing: some View {
        if let reg = registration {
            StatusDot(reg.status.display)
        } else if let price = clinic.priceCents(forMember: isMember) {
            Text(price.centsAsPrice)
                .brandFont(.subheadline)
                .foregroundStyle(Brand.navy)
                // Home renders a real price and had no identifier on it,
                // so the member-vs-non-member pricing test could not see
                // the number it exists to compare. ClinicsView:140 labels
                // the same value.
                .accessibilityIdentifier("clinic.price")
        }
    }

    private var timeLine: String {
        clinic.startsAt.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day())
        + " · "
        + clinic.startsAt.formatted(.dateTime.hour().minute())
    }
}

/// Dot plus label, the way her status legend reads.
struct StatusDot: View {
    let status: Brand.Status
    init(_ status: Brand.Status) { self.status = status }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(status.ink)
                .frame(width: 9, height: 9)
            Text(status.label)
                .brandFont(.subheadline)
                .foregroundStyle(status.ink)
                .fixedSize()
        }
    }
}

/// The guide's nav rows (docs/style-guide.md): white and navy alternate row
/// to row, not primary over secondary. These two names stay so every call
/// site keeps working; the shape is NavRowLabel's.
struct OutlinedButtonLabel: View {
    let title: String
    var icon: String? = nil
    init(_ title: String, icon: String? = nil) { self.title = title; self.icon = icon }
    var body: some View { NavRowLabel(title: title, icon: icon, navy: false) }
}

struct FilledButtonLabel: View {
    let title: String
    var icon: String? = nil
    init(_ title: String, icon: String? = nil) { self.title = title; self.icon = icon }
    var body: some View { NavRowLabel(title: title, icon: icon, navy: true) }
}

struct EmptyLine: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .brandFont(.body)
            .foregroundStyle(Brand.textSecondary)
            .padding(.vertical, Brand.Spacing.xs)
    }
}
