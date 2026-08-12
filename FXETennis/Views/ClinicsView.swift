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

    func load() async {
        loading = true; loadError = nil
        do {
            async let clinics = ClinicRepository.upcoming()
            async let regs = RegistrationRepository.mine()
            self.clinics = try await clinics
            let live = try await regs.filter { $0.status != .canceled }
            self.myRegistrationsByClinic = Dictionary(
                live.map { ($0.clinicId, $0) }, uniquingKeysWith: { a, _ in a }
            )
        } catch {
            loadError = "Couldn't load clinics. Pull to refresh."
        }
        loading = false
    }
}

struct ClinicsView: View {
    @Environment(SessionStore.self) private var session
    @State private var model = ClinicsViewModel()

    private var isMember: Bool { session.activePlayer?.isMember ?? false }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surface.ignoresSafeArea()
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
        }
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: Brand.Spacing.md) {
                ForEach(model.clinics) { clinic in
                    NavigationLink {
                        ClinicDetailView(clinic: clinic, isMember: isMember,
                                         onChanged: { await model.load() })
                    } label: {
                        ClinicCard(
                            clinic: clinic,
                            registration: model.myRegistrationsByClinic[clinic.id],
                            isMember: isMember
                        )
                    }
                    .buttonStyle(.plain)
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
                .font(Brand.Typography.body)
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

    private var openMoment: Date? { isMember ? clinic.memberOpensAt : clinic.publicOpensAt }
    private var isOpenNow: Bool {
        guard let openMoment else { return true }
        return openMoment <= Date()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            HStack(alignment: .top) {
                Text(clinic.name)
                    .font(Brand.Typography.headline)
                    .foregroundStyle(Brand.navy)
                Spacer()
                if let reg = registration {
                    StatusChip(reg.status.display)
                } else if clinic.isCanceled {
                    StatusChip(.canceled)
                }
            }

            Label(dateLine, systemImage: "calendar")
                .font(Brand.Typography.subheadline)
                .foregroundStyle(Brand.textSecondary)

            if let price = clinic.priceCents(forMember: isMember) {
                Label("\(durationLine) · \(price.centsAsPrice)", systemImage: "tennisball")
                    .font(Brand.Typography.subheadline)
                    .foregroundStyle(Brand.textSecondary)
            }

            if registration == nil && !clinic.isCanceled {
                if isOpenNow {
                    Text("Registration open")
                        .font(Brand.Typography.caption)
                        .foregroundStyle(Brand.Status.youreIn.ink)
                } else if let openMoment {
                    Text("Registration opens \(openMoment.formatted(.dateTime.month(.abbreviated).day()))")
                        .font(Brand.Typography.caption)
                        .foregroundStyle(Brand.textSecondary)
                }
            }
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
        .opacity(clinic.isCanceled ? 0.6 : 1)
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
