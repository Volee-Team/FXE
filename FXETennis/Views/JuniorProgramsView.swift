//
//  JuniorProgramsView.swift
//  FXETennis
//
//  Tara's juniors programs, read only (decision 0061; spec 01: "Show Tara's
//  program descriptions and age guidance. Never assign a group automatically
//  from a birthday."). Parents can browse before adding a child or a card.
//  Request Approval lives on each child's page, where the child is named.
//

import SwiftUI

struct JuniorProgramsView: View {
    let model: JuniorsModel

    var body: some View {
        ZStack {
            CourtBackdrop()
            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.sm) {
                    if let loadError = model.loadError, model.programs.isEmpty {
                        Text(loadError)
                            .brandFont(.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if model.programs.isEmpty {
                        if model.loaded { EmptyLine("No programs yet.") } else { PlaceholderRows() }
                    }
                    ForEach(model.programs) { program in
                        ProgramSummary(program: program)
                            .padding(Brand.Spacing.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.lg))
                            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.lg).stroke(Brand.hairline))
                            .accessibilityElement(children: .contain)
                            .accessibilityIdentifier("programs.card")
                    }
                }
                .padding(Brand.Spacing.pageMargin)
            }
            .crispTopEdge()
        }
        .navyTitle("Programs")
        .navigationBarTitleDisplayMode(.inline)
        .refreshable { await model.load() }
        .task { if !model.loaded { await model.load() } }
    }
}
