//
//  ClinicDetailView.swift
//  FXETennis
//
//  One clinic, full detail, and the single primary action for the player's
//  current state. The action shown is driven entirely by their registration
//  status, per the Developer Guide's "one appropriate primary action" rule:
//    not registered + open   -> Register
//    You're In!              -> Cancel Registration
//    Player Pool             -> Leave Player Pool
//    Response Needed         -> Accept / Decline
//    not open yet            -> "Registration opens ..."
//    canceled clinic         -> Canceled banner, no action
//
//  Still hides everything players must not see: no capacity, no counts, no other
//  players, no court, no location. Only this player's own status.
//

import SwiftUI

@MainActor
@Observable
final class ClinicDetailModel {
    var registration: MyRegistration?
    var messages: [ClinicMessage] = []
    var paymentLine: String?
    var working = false
    var notice: String?      // friendly "someone got there first" / error text
    var loaded = false

    func load(clinicId: UUID) async {
        do {
            let regs = try await RegistrationRepository.mine()
            registration = regs.first { $0.clinicId == clinicId && $0.status != .canceled }
            messages = try await ClinicRepository.messages(clinicId: clinicId)
            if paymentLine == nil { paymentLine = try? await ProfileRepository.paymentInstructions() }
        } catch {
            notice = "Couldn't load this clinic. Pull to refresh."
        }
        loaded = true
    }

    /// Runs an action, surfaces a friendly notice on failure, and reloads so the
    /// button reflects the new truth. Every transition is conditional server-side
    /// (hard rule 3); a race just means the reload shows the real state.
    func act(clinicId: UUID, _ work: @escaping () async throws -> Void, onChanged: () async -> Void) async {
        working = true; notice = nil
        do {
            try await work()
            await load(clinicId: clinicId)
            await onChanged()
        } catch {
            await load(clinicId: clinicId)
            notice = "That didn't go through — someone may have acted first. Here's the latest."
        }
        working = false
    }
}

struct ClinicDetailView: View {
    let clinic: ClinicPublic
    let isMember: Bool
    var onChanged: () async -> Void = {}

    @Environment(SessionStore.self) private var session
    @State private var model = ClinicDetailModel()

    private var openMoment: Date? { isMember ? clinic.memberOpensAt : clinic.publicOpensAt }
    private var isOpenNow: Bool {
        guard let openMoment else { return true }
        return openMoment <= Date()
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                header
                if clinic.isCanceled { canceledBanner }
                detailCard
                if let line = model.paymentLine, !line.isEmpty { paymentCard(line) }
                messageBoard
                if let notice = model.notice { noticeText(notice) }
                actionArea
            }
            .padding(Brand.Spacing.pageMargin)
        }
        .background(Brand.surface)
        .navigationTitle(clinic.name)
        .navigationBarTitleDisplayMode(.inline)
        .task { if !model.loaded { await model.load(clinicId: clinic.id) } }
        .refreshable { await model.load(clinicId: clinic.id) }
    }

    // MARK: header

    private var header: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(clinic.name)
                .font(Brand.Typography.display)
                .foregroundStyle(Brand.navy)
            if let reg = model.registration {
                StatusChip(reg.status.display)
            }
        }
    }

    private var canceledBanner: some View {
        Text("This clinic has been canceled.")
            .font(Brand.Typography.bodyEmphasis)
            .foregroundStyle(Brand.Status.canceled.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(Brand.Spacing.md)
            .background(Brand.Status.canceled.tint, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
    }

    // MARK: detail

    private var detailCard: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            detailRow("calendar", clinic.startsAt.formatted(.dateTime.weekday(.wide).month(.wide).day()))
            detailRow("clock", timeRange)
            if let price = clinic.priceCents(forMember: isMember) {
                detailRow("tennisball", "\(durationLine) · \(price.centsAsPrice)")
            }
            if let desc = clinic.description, !desc.isEmpty {
                Divider().overlay(Brand.hairline)
                Text(desc)
                    .font(Brand.Typography.body)
                    .foregroundStyle(Brand.textPrimary)
            }
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
    }

    private func detailRow(_ symbol: String, _ text: String) -> some View {
        Label(text, systemImage: symbol)
            .font(Brand.Typography.subheadline)
            .foregroundStyle(Brand.textSecondary)
    }

    private func paymentCard(_ line: String) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
            Text("PAYMENT").font(Brand.Typography.caption).foregroundStyle(Brand.textSecondary)
            Text(line).font(Brand.Typography.subheadline).foregroundStyle(Brand.textPrimary)
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
    }

    // MARK: message board

    @ViewBuilder private var messageBoard: some View {
        if !model.messages.isEmpty {
            VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
                Text("FROM TARA").font(Brand.Typography.caption).foregroundStyle(Brand.textSecondary)
                ForEach(model.messages) { msg in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(msg.body).font(Brand.Typography.body).foregroundStyle(Brand.textPrimary)
                        Text(msg.sentAt.formatted(.dateTime.month().day().hour().minute()))
                            .font(Brand.Typography.caption).foregroundStyle(Brand.textSecondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(Brand.Spacing.sm)
                    .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                    .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
                }
            }
        }
    }

    private func noticeText(_ text: String) -> some View {
        Text(text)
            .font(Brand.Typography.caption)
            .foregroundStyle(Brand.Status.playerPool.ink)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: the one primary action

    @ViewBuilder private var actionArea: some View {
        if clinic.isCanceled {
            EmptyView()
        } else if let reg = model.registration {
            switch reg.status {
            case .in_:
                destructiveButton("Cancel Registration") {
                    try await RegistrationRepository.cancelRegistration(registrationId: reg.id)
                }
            case .pool:
                destructiveButton("Leave Player Pool") {
                    try await RegistrationRepository.leavePool(registrationId: reg.id)
                }
            case .responseNeeded:
                HStack(spacing: Brand.Spacing.sm) {
                    primaryButton("Accept") {
                        try await RegistrationRepository.respondToInvitation(registrationId: reg.id, accept: true)
                    }
                    secondaryButton("Decline") {
                        try await RegistrationRepository.respondToInvitation(registrationId: reg.id, accept: false)
                    }
                }
            case .canceled:
                EmptyView()
            }
        } else if isOpenNow {
            primaryButton("Register") {
                guard let playerId = session.activePlayer?.id else { return }
                _ = try await RegistrationRepository.register(clinicId: clinic.id, playerId: playerId)
            }
        } else if let openMoment {
            Text("Registration opens \(openMoment.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute()))")
                .font(Brand.Typography.subheadline)
                .foregroundStyle(Brand.textSecondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(Brand.Spacing.md)
        }
    }

    // MARK: button builders

    private func primaryButton(_ title: String, _ work: @escaping () async throws -> Void) -> some View {
        Button {
            Task { await model.act(clinicId: clinic.id, work, onChanged: onChanged) }
        } label: {
            actionLabel(title, fg: Brand.textOnNavy, bg: Brand.navy)
        }
        .disabled(model.working)
    }

    private func secondaryButton(_ title: String, _ work: @escaping () async throws -> Void) -> some View {
        Button {
            Task { await model.act(clinicId: clinic.id, work, onChanged: onChanged) }
        } label: {
            actionLabel(title, fg: Brand.navy, bg: Brand.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.navy, lineWidth: Brand.Layout.borderWidth))
        }
        .disabled(model.working)
    }

    private func destructiveButton(_ title: String, _ work: @escaping () async throws -> Void) -> some View {
        Button(role: .destructive) {
            Task { await model.act(clinicId: clinic.id, work, onChanged: onChanged) }
        } label: {
            actionLabel(title, fg: Brand.Status.canceled.ink, bg: Brand.surfaceRaised)
                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
        }
        .disabled(model.working)
    }

    private func actionLabel(_ title: String, fg: Color, bg: Color) -> some View {
        Group {
            if model.working { ProgressView().tint(fg) }
            else { Text(title).font(Brand.Typography.button) }
        }
        .frame(maxWidth: .infinity)
        .frame(minHeight: Brand.Layout.comfortableTapTarget)
        .background(bg, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
        .foregroundStyle(fg)
    }

    private var timeRange: String {
        clinic.startsAt.formatted(.dateTime.hour().minute())
        + " – "
        + clinic.endsAt.formatted(.dateTime.hour().minute())
    }
    private var durationLine: String {
        if let d = clinic.durationMinutes { return "\(d) min" }
        return "Clinic"
    }
}
