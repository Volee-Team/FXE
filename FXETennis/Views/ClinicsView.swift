//
//  ClinicsView.swift
//  FXETennis
//
//  Browse clinics a month ahead. A clinic that is not open yet shows
//  "Registration opens ..." instead of a Register button (Tara, 2026-08-02:
//  players should see the month ahead even before they can register).
//
//  This is the reference screen for the data layer. Clinic Details and the
//  register action are built on top; the card here is the shared surface.
//

import SwiftUI

@MainActor
@Observable
final class ClinicsViewModel {
    var clinics: [ClinicPublic] = []
    var myRegistrationsByClinic: [UUID: MyRegistration] = [:]
    var loading = false
    var loadError: String?
    /// A load has finished, with an answer or a failure. Until then an empty
    /// list means "not asked yet", not "none" (review, 2026-09-27: Home said
    /// "No clinics currently open for registration" while the first load ran).
    var hasLoaded = false

    /// Both lists land together or not at all: a half-applied load showed new
    /// clinics beside old registrations. A failure keeps what was shown and
    /// says why; no signal reads as no signal, not as "no clinics" (MVP audit
    /// item 9).
    func load() async {
        loading = true; loadError = nil
        do {
            async let clinics = ClinicRepository.upcoming()
            async let regs = RegistrationRepository.mine()
            let (fetchedClinics, fetchedRegs) = try await (clinics, regs)
            let live = fetchedRegs.filter { $0.status != .canceled }
            self.clinics = fetchedClinics
            self.myRegistrationsByClinic = Dictionary(
                live.map { ($0.clinicId, $0) }, uniquingKeysWith: { a, _ in a }
            )
            hasLoaded = true
        } catch {
            let failure = RequestFailure(error)
            if failure != .cancelled {
                loadError = failure.line ?? "Couldn't load clinics."
                hasLoaded = true
            }
        }
        loading = false
    }
}

struct ClinicsView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = ClinicsViewModel()
    /// The clinic whose "?" was tapped. `nil` means no sheet.
    @State private var explaining: ClinicPublic?

    private var isMember: Bool { session.activePlayer?.isMember ?? false }

    var body: some View {
        NavigationStack {
            ZStack {
                CourtBackdrop()
                Group {
                    if model.loading && model.clinics.isEmpty {
                        ProgressView().tint(Brand.navy)
                    } else if let err = model.loadError, model.clinics.isEmpty {
                        emptyState(err)
                    } else if model.clinics.isEmpty {
                        emptyState("No clinics scheduled yet.")
                    } else {
                        list
                    }
                }
            }
            .navigationTitle("Clinics")
            .task { await model.load() }
            .refreshable { await model.load() }
            .reloadOnForeground { await model.load() }
            .sheet(item: $explaining) { clinic in
                ClinicExplainerSheet(clinic: clinic)
            }
        }
    }

    /// Grouped by service week so the list reads the way Tara publishes it:
    /// this week's clinics, then next week's, then the rest. The week is the
    /// unit registration opens in (decision 0001), so it is the natural fold.
    private var weeks: [(start: Date, items: [ClinicPublic])] {
        ServiceWeek.grouped(model.clinics, startsAt: \.startsAt)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: Brand.Spacing.md) {
                ForEach(weeks, id: \.start) { week in
                    Text(ServiceWeek.label(forWeekStarting: week.start).uppercased())
                        .brandFont(.chip)
                        .foregroundStyle(Brand.textSecondary)
                        .padding(.top, week.start == weeks.first?.start ? 0 : Brand.Spacing.sm)
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("clinics.week")

                ForEach(week.items) { clinic in
                    // The "?" is a SIBLING of the NavigationLink, not a child.
                    // A Button placed inside a NavigationLink's label does not
                    // reliably receive taps: the link swallows them, so the
                    // explainer would look tappable and simply navigate. An
                    // overlay keeps two independent targets on one row.
                    //
                    // Bottom-trailing rather than beside the name, because the
                    // card's top-trailing corner already belongs to the status
                    // chip and two controls in one corner is a mis-tap waiting
                    // to happen on a court.
                    ZStack(alignment: .bottomTrailing) {
                        NavigationLink {
                            ClinicDetailView(clinic: clinic, isMember: isMember,
                                             onChanged: { await model.load() })
                        } label: {
                            ClinicCard(
                                clinic: clinic,
                                registration: model.myRegistrationsByClinic[clinic.id],
                                isMember: isMember
                            )
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("clinic.card")

                        ExplainerButton(label: "What is \(clinic.name)?") {
                            explaining = clinic
                        }
                        .padding(.trailing, Brand.Spacing.xxs)
                        .padding(.bottom, Brand.Spacing.xxs)
                    }
                }
                }
            }
            .padding(Brand.Spacing.pageMargin)
        }
    }

    private func emptyState(_ text: String) -> some View {
        VStack(spacing: Brand.Spacing.sm) {
            Image(systemName: "figure.tennis")
                .font(.system(size: 40))
                .foregroundStyle(Brand.disabled)
            Text(text)
                .brandFont(.body)
                .foregroundStyle(Brand.textSecondary)
                .multilineTextAlignment(.center)
        }
        .padding(Brand.Spacing.pageMargin)
    }
}

/// One clinic, as a player sees it. No capacity, no counts, no location.
struct ClinicCard: View {
    let clinic: ClinicPublic
    let registration: MyRegistration?
    let isMember: Bool
    /// At the accessibility text sizes the name and the chip stack instead of
    /// sharing one row, where the chip left the name a sliver of width.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            if typeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                    name
                    chip
                }
            } else {
                HStack(alignment: .top) {
                    name
                    Spacer()
                    chip
                }
            }

            Label(dateLine, systemImage: "calendar")
                .brandFont(.subheadline)
                .foregroundStyle(Brand.textSecondary)

            if let price = clinic.priceCents(forMember: isMember) {
                Label("\(durationLine) · \(price.centsAsPrice)", systemImage: "tennisball")
                    .brandFont(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
                    .accessibilityElement(children: .combine)
                    .accessibilityIdentifier("clinic.price")
            }

            if registration == nil && !clinic.isCanceled {
                // Redrawn at the opening, so "Registration open" appears on
                // the second without a pull (MVP audit item 8).
                TimelineView(.explicit(RedrawSchedule.at(clinic.upcomingMoments(isMember: isMember)))) { _ in
                    openLine(now: Date())
                }
            }
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
        .opacity(clinic.isCanceled ? 0.6 : 1)
    }

    private var name: some View {
        Text(clinic.name)
            .brandFont(.headline)
            .foregroundStyle(Brand.navy)
    }

    @ViewBuilder private var chip: some View {
        if let reg = registration {
            StatusChip(reg.status.display)
        } else if clinic.isCanceled {
            StatusChip(.canceled)
        }
    }

    /// The same decision as the clinic page (ClinicPublic.door): "open"
    /// only while Register would work, so not after the close or the start
    /// (review, 2026-09-27: the card said open all the way to the start).
    @ViewBuilder private func openLine(now: Date) -> some View {
        switch clinic.door(isMember: isMember, now: now) {
        case .register:
            Text("Registration open")
                .brandFont(.caption)
                .foregroundStyle(Brand.Status.youreIn.ink)
        case .opens(let openMoment):
            Text("Registration opens \(openMoment.formatted(.dateTime.month(.abbreviated).day()))")
                .brandFont(.caption)
                .foregroundStyle(Brand.textSecondary)
        case .askTara, .none:
            EmptyView()
        }
    }

    private var dateLine: String {
        clinic.startsAt.formatted(.dateTime.weekday(.wide).month(.abbreviated).day())
        + " · "
        + clinic.startsAt.formatted(.dateTime.hour().minute())
    }
    private var durationLine: String {
        if let d = clinic.durationMinutes { return "\(d) min" }
        return "Clinic"
    }
}
