//
//  ChildDetailView.swift
//  FXETennis
//
//  One child's page (decision 0061): their details, the waiver signed for
//  them, and Tara's programs with Request Approval on the ones that need her
//  yes (spec 01: "Junior Elite and Elite approvals are specific to the
//  program and carry between school-year and summer offerings"). The child's
//  name stays at the top of the page, as spec 06 asks.
//
//  No program here is booked or paid for: that is phase 2.
//

import SwiftUI

struct ChildDetailView: View {
    let model: JuniorsModel
    let childId: UUID
    @Environment(\.dismiss) private var dismiss

    @State private var editing = false
    @State private var signing = false
    @State private var confirmRemove = false
    @State private var removing = false
    @State private var requesting: UUID?
    /// The last action's refusal, shown under the section it came from.
    @State private var detailsError: String?
    @State private var programError: (program: UUID, line: String)?

    private var child: Child? { model.child(childId) }

    var body: some View {
        ZStack {
            CourtBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    if let child {
                        header(child)
                        detailsCard(child)
                        waiverCard(child)
                        programsSection(child)
                        removeButton(child)
                    } else if model.loaded {
                        // Removed on another screen, or no longer on the
                        // account: nothing to show.
                        EmptyLine(JuniorCopy.notYourChildLine)
                    } else {
                        PlaceholderRows()
                    }
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .crispTopEdge()
        }
        .navyTitle(child?.firstName ?? "")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .sheet(isPresented: $editing, onDismiss: { Task { await model.load() } }) {
            if let child { ChildFormView(child: child) }
        }
        .sheet(isPresented: $signing, onDismiss: { Task { await model.load() } }) {
            if let child { ChildWaiverView(child: child) }
        }
    }

    private func header(_ child: Child) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            Text(child.fullName)
                .brandFont(.display)
                .foregroundStyle(Brand.navy)
                .accessibilityIdentifier("child.name")
            if let age = child.age {
                Text("Age \(age)")
                    .brandFont(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
            }
        }
    }

    private func detailsCard(_ child: Child) -> some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Birthday").brandFont(.caption).foregroundStyle(Brand.textSecondary)
                Text(JuniorCopy.birthdayLine(child.dateOfBirth))
                    .brandFont(.body).foregroundStyle(Brand.textPrimary)
                    .accessibilityIdentifier("child.birthdayLine")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button { editing = true } label: {
                Text("Edit")
                    .brandFont(.button)
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Brand.Layout.minTapTarget)
                    .foregroundStyle(Brand.navy)
                    .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.navy, lineWidth: Brand.Layout.borderWidth))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("child.edit")
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
    }

    private func waiverCard(_ child: Child) -> some View {
        SectionBlock(title: "Waiver") {
            VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
                Text(JuniorCopy.waiverLine(child.waiverStatus))
                    .brandFont(.bodyEmphasis)
                    .foregroundStyle(child.waiverStatus == .signed ? Brand.courtText : Brand.textPrimary)
                    .accessibilityIdentifier("child.waiverStatus")
                switch child.waiverStatus {
                case .needed:
                    Button { signing = true } label: {
                        Text("Sign the waiver")
                            .brandFont(.button)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Brand.Layout.comfortableTapTarget)
                            .foregroundStyle(Brand.textOnNavy)
                            .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("child.signWaiver")
                case .notAvailable:
                    // No dead end: nothing to do yet, and it says so.
                    Text(JuniorCopy.waiverNotAvailableLine)
                        .brandFont(.subheadline)
                        .foregroundStyle(Brand.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("child.waiverNotAvailable")
                case .signed:
                    EmptyView()
                }
            }
            .padding(Brand.Spacing.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
        }
    }

    private func programsSection(_ child: Child) -> some View {
        SectionBlock(title: "Programs") {
            if model.programs.isEmpty {
                EmptyLine("No programs yet.")
            } else {
                VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
                    ForEach(model.programs) { program in
                        programCard(program, child: child)
                    }
                }
            }
        }
    }

    private func programCard(_ program: JuniorProgram, child: Child) -> some View {
        let state = ProgramApprovalState.state(program: program, child: child.id, approvals: model.approvals)
        return VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
            ProgramSummary(program: program)
            if let line = JuniorCopy.approvalLine(state) {
                Text(line)
                    .brandFont(.bodyEmphasis)
                    .foregroundStyle(state == .approved ? Brand.courtText
                                     : state == .declined ? Brand.Status.canceled.ink : Brand.textPrimary)
                    .accessibilityIdentifier("program.approvalStatus")
            }
            if state == .canRequest {
                Button {
                    Task { await request(program: program, child: child) }
                } label: {
                    Group {
                        if requesting == program.id { ProgressView().tint(Brand.textOnNavy) }
                        else { Text("Request Approval").brandFont(.button) }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(minHeight: Brand.Layout.comfortableTapTarget)
                    .foregroundStyle(Brand.textOnNavy)
                    .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                }
                .buttonStyle(.plain)
                .disabled(requesting != nil)
                .accessibilityLabel("Request Approval for \(program.name)")
                .accessibilityIdentifier("program.requestApproval")
            }
            if let programError, programError.program == program.id {
                Text(programError.line)
                    .brandFont(.subheadline)
                    .foregroundStyle(Brand.Status.canceled.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("program.error")
            }
        }
        .padding(Brand.Spacing.cardPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("program.card")
    }

    private func removeButton(_ child: Child) -> some View {
        VStack(spacing: Brand.Spacing.xs) {
            Button(role: .destructive) { confirmRemove = true } label: {
                Text("Remove child")
                    .brandFont(.caption)
                    .frame(maxWidth: .infinity)
                    .foregroundStyle(Brand.Status.canceled.ink)
            }
            .buttonStyle(QuietLinkButtonStyle())
            .disabled(removing)
            .accessibilityIdentifier("child.remove")
            .confirmationDialog(Text("Remove \(child.firstName) from your account?"),
                                isPresented: $confirmRemove, titleVisibility: .visible) {
                Button("Remove", role: .destructive) { Task { await remove(child) } }
                    .accessibilityIdentifier("child.confirmRemove")
                Button("Cancel", role: .cancel) {}
            }
            if let detailsError {
                Text(detailsError)
                    .brandFont(.subheadline)
                    .foregroundStyle(Brand.Status.canceled.ink)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("child.removeError")
            }
        }
    }

    private func request(program: JuniorProgram, child: Child) async {
        requesting = program.id
        programError = nil
        defer { requesting = nil }
        do {
            try await JuniorsRepository.requestApproval(child: child.id, program: program.id)
            await model.load()
        } catch {
            if let line = JuniorCopy.line(for: error) { programError = (program.id, line) }
            // A refusal like approval_declined means the status moved: show it.
            await model.load()
        }
    }

    private func remove(_ child: Child) async {
        removing = true
        detailsError = nil
        defer { removing = false }
        do {
            try await JuniorsRepository.removeChild(id: child.id)
            await model.load()
            dismiss()
        } catch {
            detailsError = JuniorCopy.line(for: error)
        }
    }
}

/// A program's name, Tara's age guidance and her description. Shared by a
/// child's page and the Programs list.
struct ProgramSummary: View {
    let program: JuniorProgram

    var body: some View {
        VStack(alignment: .leading, spacing: Brand.Spacing.xxs) {
            Text(program.name)
                .brandFont(.headline)
                .foregroundStyle(Brand.navy)
                .accessibilityIdentifier("program.name")
            if !program.ageGuidance.isEmpty {
                Text(program.ageGuidance)
                    .brandFont(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
            }
            if program.needsApproval {
                // Her table, spec 01: "Tara approval required".
                Text("Tara approval required")
                    .brandFont(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
            }
            if !program.description.isEmpty {
                Text(program.description)
                    .brandFont(.body)
                    .foregroundStyle(Brand.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
