//
//  AuthView.swift
//  FXETennis
//
//  Sign in or create an account. Everyone makes an account (Tara, 2026-08-02).
//  This is the lean shell: email + password against Supabase Auth. The full
//  signup → profile onboarding (name, member y/n, NTRP) is built on top of this.
//

import SwiftUI

struct AuthView: View {
    @Environment(SessionStore.self) private var session

    @State private var mode: Mode = .signIn
    @State private var email = ""
    @State private var password = ""
    @State private var working = false

    enum Mode { case signIn, signUp
        var cta: String { self == .signIn ? "Sign In" : "Create Account" }
        var toggle: String { self == .signIn ? "Create an account" : "Sign in" }
    }

    var body: some View {
        ZStack {
            Brand.surface.ignoresSafeArea()
            VStack(spacing: Brand.Spacing.lg) {
                Spacer()
                Image("gator-x")
                    .resizable().scaledToFit()
                    .frame(width: 96, height: 96)
                Text("FXE Tennis")
                    .font(Brand.Typography.display)
                    .foregroundStyle(Brand.navy)

                VStack(spacing: Brand.Spacing.sm) {
                    TextField("Email", text: $email)
                        .accessibilityIdentifier("auth.email")
                        .textContentType(.emailAddress)
                        .keyboardType(.emailAddress)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .padding()
                        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))

                    SecureField("Password", text: $password)
                        .accessibilityIdentifier("auth.password")
                        .textContentType(mode == .signIn ? .password : .newPassword)
                        .padding()
                        .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                        .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
                }

                if let err = session.authError {
                    Text(err)
                        .accessibilityIdentifier("auth.error")
                        .font(Brand.Typography.caption)
                        .foregroundStyle(Brand.Status.canceled.ink)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                Button {
                    Task {
                        working = true
                        switch mode {
                        case .signIn: await session.signIn(email: email, password: password)
                        case .signUp: await session.signUp(email: email, password: password)
                        }
                        working = false
                    }
                } label: {
                    Group {
                        if working { ProgressView().tint(Brand.textOnNavy) }
                        else { Text(mode.cta).font(Brand.Typography.button) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                    .accessibilityIdentifier("auth.submit")
                    .foregroundStyle(Brand.textOnNavy)
                }
                .disabled(working || email.isEmpty || password.isEmpty)

                Button(mode.toggle) {
                    mode = (mode == .signIn) ? .signUp : .signIn
                }
                .font(Brand.Typography.caption)
                .foregroundStyle(Brand.textSecondary)

                if mode == .signUp {
                    Text("Clinic updates come through the app. Keep notifications on so you don't miss them.")
                        .font(Brand.Typography.caption)
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Brand.Spacing.xs)
                }
                Spacer()
            }
            .padding(Brand.Spacing.pageMargin)
        }
    }
}
