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
    /// Return on the email moves to the password; Return there signs in.
    @FocusState private var field: Field?
    private enum Field { case email, password }

    enum Mode { case signIn, signUp
        var cta: String { self == .signIn ? "Sign In" : "Create Account" }
        var toggle: String { self == .signIn ? "Create an account" : "Sign in" }
    }

    private var canSubmit: Bool { !working && !email.isEmpty && !password.isEmpty }

    private func submit() {
        guard canSubmit else { return }
        field = nil
        Task {
            working = true
            switch mode {
            case .signIn: await session.signIn(email: email, password: password)
            case .signUp: await session.signUp(email: email, password: password)
            }
            working = false
        }
    }

    var body: some View {
        ZStack {
            CourtBackdrop(strength: .front)

            VStack(spacing: 0) {
                // Navy banner, straight from Tara's mockups: every important
                // screen opens on navy rather than a field of white. It also
                // anchors the layout, so nothing shifts when the keyboard or an
                // error message appears.
                BrandHeader(height: 250) {
                    Wordmark()
                        .padding(.top, Brand.Spacing.xxl + Brand.Spacing.sm)
                }
                // Her line (question 55), as the guide's greeting-accent: italic,
                // gator-green, centered under the header.
                Text("Let's Play.")
                    .brandFont(.greetingAccent)
                    .foregroundStyle(Brand.courtText)
                    .padding(.top, Brand.Spacing.md)

                // The form sits on cream, lifted slightly into the banner so the
                // two planes overlap rather than sitting in separate boxes.
                // In a scroll view that only scrolls when the form does not fit:
                // at the largest Larger Text sizes "Forgot password?" ran off the
                // bottom of the screen (seen on the simulator, 2026-09-27).
                ScrollView {
                VStack(spacing: Brand.Spacing.lg) {
                    // Capped so the form sits just under the banner instead of
                    // floating in the middle of an empty field of cream.
                    // Fixed, not a Spacer: inside the ScrollView a Spacer collapses to 0.
                    Color.clear.frame(height: Brand.Spacing.xl)
                    VStack(spacing: Brand.Spacing.sm) {
                        TextField("Email", text: $email)
                            .accessibilityIdentifier("auth.email")
                            .textContentType(.emailAddress)
                            .keyboardType(.emailAddress)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .focused($field, equals: .email)
                            .submitLabel(.next)
                            .onSubmit { field = .password }
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
                            .focused($field, equals: .password)
                            .submitLabel(.go)
                            .onSubmit(submit)
                            .padding()
                            .background(Brand.surfaceRaised, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                            .overlay(RoundedRectangle(cornerRadius: Brand.Radius.md).stroke(Brand.hairline))
                        if mode == .signUp {
                            // The hosted rule, stated before the server has to.
                            Text("At least 6 characters.")
                                .brandFont(.caption)
                                .foregroundStyle(Brand.textSecondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityIdentifier("auth.passwordRule")
                        }
                    }

                    // Reserve the error row's height always, so the button never
                    // moves when an error appears. A control that shifts under
                    // your thumb is how a real person mis-taps.
                    Text(session.authError ?? " ")
                        .accessibilityIdentifier("auth.error")
                        .brandFont(.caption)
                        .foregroundStyle(Brand.Status.canceled.ink)
                        .frame(maxWidth: .infinity, minHeight: 18, alignment: .leading)
                        .opacity(session.authError == nil ? 0 : 1)

                Button(action: submit) {
                    Group {
                        if working { ProgressView().tint(Brand.textOnNavy) }
                        else { Text(mode.cta).brandFont(.button) }
                    }
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Brand.navy, in: RoundedRectangle(cornerRadius: Brand.Radius.md))
                    .accessibilityIdentifier("auth.submit")
                    .foregroundStyle(Brand.textOnNavy)
                }
                .disabled(!canSubmit)

                Button(mode.toggle) {
                    mode = (mode == .signIn) ? .signUp : .signIn
                    // "That email already has an account" must not follow her
                    // to Sign in, where it reads as the new screen's answer.
                    session.authError = nil
                }
                .brandFont(.caption)
                // Navy, not grey: the links sit over the court photo, where
                // grey read under 4.5:1 (accessibility audit, 2026-09-28).
                .foregroundStyle(Brand.textPrimary)
                .buttonStyle(QuietLinkButtonStyle())
                // Identifier on the Button. The visible label flips between
                // "Create an account" and "Sign in", so a UI test cannot query
                // it by text without encoding which mode it is already in.
                .accessibilityIdentifier("auth.toggleMode")

                if mode == .signIn {
                    Button(resetSent ? "Check your email for a reset link. It can take a few minutes." : "Forgot password?") {
                        guard !resetSent else { return }
                        Task { resetSent = await session.sendPasswordReset(email: email) }
                    }
                    .brandFont(.caption)
                    .foregroundStyle(resetSent ? Brand.Status.youreIn.ink : Brand.textPrimary)
                    .buttonStyle(QuietLinkButtonStyle())
                    .accessibilityIdentifier("auth.forgot")
                }

                if mode == .signUp {
                    Text("Clinic updates come through the app. Keep notifications on so you don't miss them.")
                        .brandFont(.caption)
                        .foregroundStyle(Brand.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.top, Brand.Spacing.xs)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Brand.Spacing.pageMargin)
                }
                .scrollBounceBehavior(.basedOnSize)
                .scrollDismissesKeyboard(.interactively)
            }
            .ignoresSafeArea(edges: .top)
        }
    }
}
