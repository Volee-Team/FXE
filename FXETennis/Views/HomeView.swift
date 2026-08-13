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

    private var isMember: Bool { session.activePlayer?.isMember ?? false }

    private var myClinics: [ClinicPublic] {
        model.clinics.filter { model.myRegistrationsByClinic[$0.id] != nil && !$0.isCanceled }
    }
    private var available: [ClinicPublic] {
        model.clinics.filter { model.myRegistrationsByClinic[$0.id] == nil && !$0.isCanceled }
    }

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                Brand.surface.ignoresSafeArea()

                VStack(spacing: 0) {
                    NavyHeaderBar(title: greetingText)
                        .accessibilityIdentifier("home.greeting")

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
            .task { await model.load() }
            .refreshable { await model.load() }
        }
    }

    /// Her mockup reads "Good Morning, Sara!" — time-aware, first name, warm.
    private var greetingText: String {
        let name = session.activePlayer?.firstName ?? "there"
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
    }
}

// MARK: - Pieces of Tara's layout, shared across screens

/// The navy bar her mockups put at the top of every important screen. The
/// greeting or screen name sits inside it, small and left-aligned, with the
/// notification bell on the right.
struct NavyHeaderBar: View {
    let title: String
    var showsBell: Bool = true

    var body: some View {
        HStack {
            Text(title)
                .font(Brand.Typography.bodyEmphasis)
                .foregroundStyle(Brand.textOnNavy)
            Spacer()
            if showsBell {
                Image(systemName: "bell")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(Brand.textOnNavy)
            }
        }
        .padding(.horizontal, Brand.Spacing.pageMargin)
        .padding(.vertical, Brand.Spacing.md)
        .frame(maxWidth: .infinity)
        .background(Brand.navy)
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
            }
        }
        .padding(.vertical, Brand.Spacing.sm)
        .contentShape(Rectangle())
        .accessibilityIdentifier("clinic.card")
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
