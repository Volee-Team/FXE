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

    @State private var resetSent = false
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

            VStack(spacing: 0) {
                // Navy banner, straight from Tara's mockups: every important
                // screen opens on navy rather than a field of white. It also
                // anchors the layout, so nothing shifts when the keyboard or an
                // error message appears.
                ZStack {
                    Brand.navy
                    VStack(spacing: Brand.Spacing.sm) {
                        Image("gator-x")
                            .resizable().scaledToFit()
                            .frame(width: 84, height: 84)
                        Text("FXE TENNIS")
                            .font(Brand.Typography.display)
                            .tracking(1.5)
                            .foregroundStyle(Brand.textOnNavy)
                        // Her tagline from the mockups, not invented here.
                        Text("Smart. Simple. Built for Tennis.")
                            .font(Brand.Typography.subheadline)
                            .foregroundStyle(Brand.textOnNavy.opacity(0.72))
                    }
                    .padding(.top, Brand.Spacing.xl)
                }
                .frame(height: 320)
                .ignoresSafeArea(edges: .top)

                // The form sits on cream, lifted slightly into the banner so the
                // two planes overlap rather than sitting in separate boxes.
                VStack(spacing: Brand.Spacing.lg) {
                    // Capped so the form sits just under the banner instead of
                    // floating in the middle of an empty field of cream.
                    Spacer(minLength: 0).frame(maxHeight: Brand.Spacing.xl)
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
                            // Under UI test, declare no content type. `.password`
                            // is what tells iOS "this is a login form", which
                            // makes SpringBoard show the "Save Password?" sheet
                            // after a successful sign-in. That sheet covers the
                            // app and every XCUITest query then finds nothing,
                            // surfacing as a misleading "not hittable".
                            .textContentType(AppEnv.isUITesting
                                             ? nil
                                             : (mode == .signIn ? .password : .newPassword))
                            .padding()
                            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
                    }

                    // Reserve the error row's height always, so the button never
                    // moves when an error appears. A control that shifts under
                    // your thumb is how a real person mis-taps.
                    Text(session.authError ?? " ")
                        .accessibilityIdentifier("auth.error")
                        .font(Brand.Typography.caption)
                        .foregroundStyle(Brand.Status.canceled.ink)
                        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                        .opacity(session.authError == nil ? 0 : 1)

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
                // Identifier on the Button. The visible label flips between
                // "Create an account" and "Sign in", so a UI test cannot query
                // it by text without encoding which mode it is already in.
                .accessibilityIdentifier("auth.toggleMode")

                if mode == .signIn {
                    Button(resetSent ? "Check your email for a reset link." : "Forgot password?") {
                        guard !resetSent else { return }
                        Task { resetSent = await session.sendPasswordReset(email: email) }
                    }
                    .font(Brand.Typography.caption)
                    .foregroundStyle(resetSent ? Brand.Status.youreIn.ink : Brand.textSecondary)
                    .frame(minHeight: Brand.Layout.minTapTarget)
                    .accessibilityIdentifier("auth.forgot")
                }

                if mode == .signUp {
                    Text("Clinic updates come through the app. Keep notifications on so you don't miss them.")
                        .font(Brand.Typography.caption)
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Brand.Spacing.xs)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Brand.Spacing.pageMargin)
            }
        }
    }
}
