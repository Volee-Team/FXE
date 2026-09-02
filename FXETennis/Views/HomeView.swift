//
//  HomeView.swift
//  FXETennis
//
//  Built to match Tara's mockup, not to SwiftUI defaults. The specific things
//  her design does that stock SwiftUI does not:
//
//    * The greeting lives INSIDE a navy bar at the top, small and left-aligned
//      with a bell on the right. There is no oversized page title.
//    * Clinic rows are compact list rows — name and time on the left, status on
//      the right — not big stacked cards.
//    * Almost all text is navy. Grey is used sparingly, for the time line only.
//    * Two button weights: outlined for a secondary jump ("View All Clinics"),
//      navy-filled for the primary one ("View Open Clinics").
//
//  Order is from the Developer Guide: My Clinics first, then what's available.
//

import SwiftUI

struct HomeView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = ClinicsViewModel()
    @State private var showNotifications = false
    @State private var unread = 0

    private var isMember: Bool { session.activePlayer?.isMember ?? false }

    private var myClinics: [ClinicPublic] {
        model.clinics.filter { model.myRegistrationsByClinic[$0.id] != nil && !$0.isCanceled }
    }
    private var available: [ClinicPublic] {
        model.clinics.filter { model.myRegistrationsByClinic[$0.id] == nil && !$0.isCanceled }
    }

    private func refreshUnread() async {
        unread = (try? await NotificationRepository.unreadCount()) ?? unread
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Brand.surface.ignoresSafeArea()

                VStack(spacing: 0) {
                    NavyHeaderBar(title: greetingText, unread: unread, onBell: { showNotifications = true },
                                  titleIdentifier: "home.greeting")

                    ScrollView {
                        VStack(alignment: .leading, spacing: Brand.Spacing.lg) {

                            SectionBlock(title: "My Clinics") {
                                if myClinics.isEmpty {
                                    EmptyLine("You're not in any clinics yet.")
                                } else {
                                    ForEach(Array(myClinics.prefix(3))) { clinic in
                                        row(clinic)
                                    }
                                }
                                NavigationLink { ClinicsView() } label: {
                                    OutlinedButtonLabel("View All Clinics")
                                }
                                .buttonStyle(.plain)
                            }

                            SectionBlock(title: "Available Clinics") {
                                if available.isEmpty {
                                    EmptyLine("Nothing open right now.")
                                } else {
                                    ForEach(Array(available.prefix(3))) { clinic in
                                        row(clinic)
                                    }
                                }
                                NavigationLink { ClinicsView() } label: {
                                    FilledButtonLabel("View Open Clinics")
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(Brand.Spacing.pageMargin)
                    }
                }
            }
            .navigationBarHidden(true)
            .task { await model.load(); await refreshUnread() }
            .refreshable { await model.load(); await refreshUnread() }
            .sheet(isPresented: $showNotifications, onDismiss: { Task { await refreshUnread() } }) {
                NotificationsView { Task { await refreshUnread() } }
            }
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
                .font(Brand.Typography.bodyEmphasis)
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
                            .foregroundStyle(Brand.textOnNavy)
                            .symbolRenderingMode(.palette)
                            .foregroundStyle(Brand.accent, Brand.textOnNavy)
                    }
                    .frame(minWidth: Brand.Layout.minTapTarget, minHeight: Brand.Layout.minTapTarget)
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
                .font(Brand.Typography.chip)
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

    var body: some View {
        HStack(alignment: .center, spacing: Brand.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(clinic.name)
                    .font(Brand.Typography.bodyEmphasis)
                    .foregroundStyle(Brand.navy)
                    .multilineTextAlignment(.leading)
                Text(timeLine)
                    .font(Brand.Typography.subheadline)
                    .foregroundStyle(Brand.textSecondary)
            }
            Spacer(minLength: Brand.Spacing.sm)
            if let reg = registration {
                StatusDot(reg.status.display)
            } else if let price = clinic.priceCents(forMember: isMember) {
                Text(price.centsAsPrice)
                    .font(Brand.Typography.subheadline)
                    .foregroundStyle(Brand.navy)
                    // Home renders a real price and had no identifier on it,
                    // so the member-vs-non-member pricing test could not see
                    // the number it exists to compare. ClinicsView:140 labels
                    // the same value.
                    .accessibilityIdentifier("clinic.price")
            }
        }
        .padding(.vertical, Brand.Spacing.sm)
        .contentShape(Rectangle())
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
                .font(Brand.Typography.subheadline)
                .foregroundStyle(status.ink)
                .fixedSize()
        }
    }
}

struct OutlinedButtonLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(Brand.Typography.button)
            .foregroundStyle(Brand.navy)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Brand.Layout.comfortableTapTarget)
            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md)
                .stroke(Brand.navy, lineWidth: Brand.Layout.borderWidth))
    }
}

struct FilledButtonLabel: View {
    let title: String
    init(_ title: String) { self.title = title }
    var body: some View {
        Text(title)
            .font(Brand.Typography.button)
            .foregroundStyle(Brand.textOnNavy)
            .frame(maxWidth: .infinity)
            .frame(minHeight: Brand.Layout.comfortableTapTarget)
            .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
    }
}

struct EmptyLine: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text)
            .font(Brand.Typography.body)
            .foregroundStyle(Brand.textSecondary)
            .padding(.vertical, Brand.Spacing.xs)
    }
}
