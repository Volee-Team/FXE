//
//  GenderQuestionView.swift
//  FXETennis
//
//  The one-time gender question (decision 0044). Tara, 2026-10-30: men see
//  Men and Coed clinics, women Ladies and Coed. Sign-up asks it on the profile
//  form; this screen asks everyone who signed up before that, once, after
//  the waiver and before Home. Once answered it never comes back: the answer
//  is on the player row, and only Tara changes it.
//
//  COPY: plain chrome only ("Gender", "Female", "Male", "Continue"), the same
//  words as the profile form, approved by John for Tara's rule. No sentence
//  of ours explains it.
//
//  The server lists every clinic to someone who has not answered, so leaving
//  through the footer hides nothing they could see before.
//

import SwiftUI

struct GenderQuestionView: View {
    @Environment(SessionStore.self) private var session
    @State private var gender: String?
    @State private var saving = false

    var body: some View {
        ZStack {
            CourtBackdrop(strength: .front)

            ScrollView {
                VStack(alignment: .leading, spacing: Brand.Spacing.lg) {
                    Text("Gender")
                        .brandFont(.display)
                        .foregroundStyle(Brand.textPrimary)
                        .accessibilityAddTraits(.isHeader)

                    HStack(spacing: Brand.Spacing.sm) {
                        choice("Female", value: "female", id: "gender.female")
                        choice("Male", value: "male", id: "gender.male")
                    }

                    if let error = session.authError {
                        Text(error)
                            .brandFont(.subheadline)
                            .foregroundStyle(Brand.Status.canceled.ink)
                    }

                    Button {
                        guard let gender else { return }
                        Task {
                            saving = true
                            _ = await session.answerGender(gender)
                            saving = false
                        }
                    } label: {
                        Text(saving ? "Saving…" : "Continue")
                            .brandFont(.button)
                            .frame(maxWidth: .infinity)
                            .frame(minHeight: Brand.Layout.comfortableTapTarget)
                            .foregroundStyle(Brand.textOnNavy)
                            .background(
                                RoundedRectangle(cornerRadius: Brand.Radius.sm)
                                    .fill(gender != nil && !saving ? Brand.navy : Brand.disabled)
                            )
                    }
                    .buttonStyle(.plain)
                    .disabled(gender == nil || saving)
                    .accessibilityIdentifier("gender.continue")

                    AccountExitFooter(signOutID: "gender.signOut", deleteID: "gender.delete")
                }
                .padding(Brand.Spacing.pageMargin)
            }
        }
        .statusBarScrim()
        .accessibilityIdentifier("gender.screen")
    }

    private func choice(_ label: String, value: String, id: String) -> some View {
        let selected = gender == value
        return Button { gender = value } label: {
            Text(label)
                .brandFont(.button)
                .frame(maxWidth: .infinity)
                .frame(minHeight: Brand.Layout.comfortableTapTarget)
                .foregroundStyle(selected ? Brand.textOnNavy : Brand.textPrimary)
                .background(
                    RoundedRectangle(cornerRadius: Brand.Radius.sm)
                        .fill(selected ? Brand.navy : Brand.surfaceRaised)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Brand.Radius.sm)
                        .stroke(Brand.border, lineWidth: Brand.Layout.borderWidth)
                )
        }
        .buttonStyle(.plain)
        // Selection must not be carried by colour alone.
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
        .accessibilityIdentifier(id)
    }
}
