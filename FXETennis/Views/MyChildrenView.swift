//
//  MyChildrenView.swift
//  FXETennis
//
//  Juniors phase 1 (decision 0061). Tara's flow, spec 01: "Profile → My
//  Children → Add a Child. Collect child name and birthday. Support multiple
//  children." Each child opens their own page: the waiver signed for them,
//  the programs, and Request Approval for the ones that need Tara's yes.
//
//  Nothing here books a child into anything (that is phase 2), and a child is
//  never the session's player (decision 0057).
//

import SwiftUI

/// The parent's children, programs and approvals, shared by the list and a
/// child's page so a change on one shows on the other.
@MainActor @Observable
final class JuniorsModel {
    var children: [Child] = []
    var programs: [JuniorProgram] = []
    var approvals: [ProgramApproval] = []
    var loading = false
    var loaded = false
    /// The last load failed; what is on screen may be old.
    var loadError: String?

    func load() async {
        loading = true
        defer { loading = false }
        do {
            async let kids = JuniorsRepository.myChildren()
            async let progs = JuniorsRepository.programs()
            async let asks = JuniorsRepository.myApprovals()
            let (k, p, a) = try await (kids, progs, asks)
            children = k
            programs = p
            approvals = a
            loadError = nil
            loaded = true
        } catch {
            let failure = RequestFailure(error)
            if failure == .cancelled { return }
            loadError = failure.line ?? JuniorCopy.loadFailedLine
        }
    }

    func child(_ id: UUID) -> Child? { children.first { $0.id == id } }
}

struct MyChildrenView: View {
    @State private var model = JuniorsModel()
    @State private var adding = false

    var body: some View {
        ZStack {
            CourtBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    if let loadError = model.loadError {
                        Text(loadError)
                            .brandFont(.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                            .fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("children.loadError")
                        if !model.loaded {
                            Button("Try again") { Task { await model.load() } }
                                .brandFont(.button)
                                .accessibilityIdentifier("children.retry")
                        }
                    }

                    if model.loading && !model.loaded {
                        PlaceholderRows()
                    } else if model.loaded {
                        if model.children.isEmpty {
                            // On the raised card the children's list uses: on the
                            // court backdrop this line failed the iOS 18 contrast
                            // audit on the iPhone SE in either ink (2026-11-21), as
                            // the clinic page's price line did.
                            EmptyLine("No children added yet.")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, Brand.Spacing.cardPadding)
                                .padding(.vertical, Brand.Spacing.sm)
                                .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
                                .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
                                .accessibilityIdentifier("children.empty")
                        } else {
                            VStack(spacing: 0) {
                                ForEach(model.children) { child in
                                    NavigationLink {
                                        ChildDetailView(model: model, childId: child.id)
                                    } label: {
                                        ChildRow(child: child)
                                    }
                                    .buttonStyle(.plain)
                                    .accessibilityIdentifier("children.row")
                                    if child.id != model.children.last?.id {
                                        Divider().overlay(Brand.hairline)
                                    }
                                }
                            }
                            .padding(.horizontal, Brand.Spacing.cardPadding)
                            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
                            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
                        }
                    }

                    Button { adding = true } label: {
                        FilledButtonLabel("Add a Child", icon: "plus")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("children.add")

                    NavigationLink {
                        JuniorProgramsView(model: model)
                    } label: {
                        OutlinedButtonLabel("Programs", icon: "list.bullet")
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("children.programs")
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .crispTopEdge()
        }
        .navyTitle("My Children")
        .navigationBarTitleDisplayMode(.inline)
        .task { await model.load() }
        .refreshable { await model.load() }
        .sheet(isPresented: $adding, onDismiss: { Task { await model.load() } }) {
            ChildFormView(child: nil)
        }
    }
}

/// Name, then age and waiver on one line.
private struct ChildRow: View {
    let child: Child

    /// "Age 8 · Waiver needed", or the waiver alone when there is no age.
    private var statusLine: Text {
        let age = child.age.map { Text("Age \($0) · ") } ?? Text("")
        return age + Text(JuniorCopy.waiverLine(child.waiverStatus))
    }

    var body: some View {
        HStack(alignment: .center, spacing: Brand.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(child.fullName)
                    .brandFont(.bodyEmphasis)
                    .foregroundStyle(Brand.navy)
                    .multilineTextAlignment(.leading)
                statusLine
                    .brandFont(.subheadline)
                    .foregroundStyle(Brand.textSecondary)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: Brand.Spacing.sm)
            Image(systemName: "chevron.right")
                .font(.footnote.weight(.semibold))
                .foregroundStyle(Brand.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Brand.Spacing.sm)
        .frame(minHeight: Brand.Layout.comfortableTapTarget)
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }
}
