//
//  ClinicExplainerSheet.swift
//  FXETennis
//
//  The "?" beside a clinic name. Tara's idea, 2026-08-15:
//
//      "Should you put a '?' w the description by each clinic?"
//
//  WHY IT IS THE RIGHT CALL
//  ------------------------
//  Every clinic name is club shorthand. "Coed 105", "Ladies 3.0+", "All-Level"
//  mean nothing to a member who joined last week, and "105" in particular is a
//  format nobody outside FXE would guess: it appeared five times in her real
//  weekly schedule and was not defined anywhere in the spec, the Developer
//  Guide, or any of our docs until she explained it.
//
//  The alternative to a "?" is a paragraph on every row, which contradicts the
//  standing rule that player screens must never feel like long blocks of
//  writing. This is also the SAME affordance as the NTRP "?" on the profile
//  screen, so a player learns the pattern once and it works everywhere.
//
//  COPY: every word here is Tara's, transcribed in docs/copy.md. Nothing on
//  this screen is written by us.
//

import SwiftUI

struct ClinicExplainerSheet: View {
    let clinic: ClinicPublic

    @Environment(\.dismiss) private var dismiss

    private var clinicName: String { clinic.name }
    private var description: String? { clinic.description }

    /// Tara's definition of "105", verbatim (docs/copy.md).
    ///
    /// Shown IN ADDITION to the clinic's own description whenever the name
    /// contains "105", because the format is the part a new player does not
    /// know and it is not repeated in each clinic's own text. She described it
    /// as "a game that just about everyone knows about", which is exactly the
    /// kind of thing that is invisible to the people who already know it.
    private static let oneOhFive = """
        105 is a fast-paced doubles game for ladies and coed players. With a \
        maximum of six players per court, a pro feeds the ball, keeps score, \
        and keeps the action moving as players rotate in and out. Fast points, \
        lots of balls, great music, and nonstop movement!
        """

    /// Checks the NAME and the CATEGORY.
    ///
    /// Tara writes it into the name in her real schedule ("Coed 105",
    /// "level 4.0+ 105", see docs/taras-real-week.md), but it is also a clinic
    /// category in the data model. Matching only one of the two would leave the
    /// explainer silent on exactly the clinics that need it most.
    private var mentions105: Bool {
        clinicName.localizedCaseInsensitiveContains("105")
            || (clinic.category?.localizedCaseInsensitiveContains("105") ?? false)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Brand.surface.ignoresSafeArea()

                ScrollView {
                    VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                        Text(clinicName)
                            .font(Brand.Typography.title)
                            .foregroundStyle(Brand.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)

                        if let description, !description.isEmpty {
                            Text(description)
                                .font(Brand.Typography.body)
                                .foregroundStyle(Brand.textPrimary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            // Honest rather than invented. A clinic with no
                            // description is a gap for Tara to fill, and making
                            // one up here would be exactly the copy rule broken.
                            Text("No description yet.")
                                .font(Brand.Typography.body)
                                .foregroundStyle(Brand.textSecondary)
                        }

                        if mentions105 {
                            VStack(alignment: .leading, spacing: Brand.Spacing.xs) {
                                Text("What is 105?")
                                    .font(Brand.Typography.headline)
                                    .foregroundStyle(Brand.navy)
                                Text(Self.oneOhFive)
                                    .font(Brand.Typography.body)
                                    .foregroundStyle(Brand.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            .padding(Brand.Spacing.cardPadding)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Brand.surfaceRaised,
                                in: RoundedRectangle(cornerRadius: Brand.Radius.md)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: Brand.Radius.md)
                                    .stroke(Brand.hairline)
                            )
                        }
                    }
                    .padding(Brand.Spacing.pageMargin)
                }
            }
            .navigationTitle("About this clinic")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

/// The circled "?" itself, so every place that offers an explainer looks and
/// behaves identically.
///
/// It is a real 44pt target despite being a small glyph: this app is used
/// standing on a court, often one-handed, and `Brand.Layout.minTapTarget` is a
/// floor rather than a goal.
struct ExplainerButton: View {
    let label: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "questionmark.circle")
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(Brand.navy)
                .frame(width: Brand.Layout.minTapTarget,
                       height: Brand.Layout.minTapTarget)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // The glyph carries no meaning to a screen reader, so the label does.
        .accessibilityLabel(label)
        .accessibilityIdentifier("clinic.explainer")
    }
}
