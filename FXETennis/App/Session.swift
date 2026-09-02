//
//  Session.swift
//  FXETennis
//
//  Auth state and the signed-in identity, in one observable store injected at
//  the root. Screens read `session.activePlayer` / `session.account` rather than
//  reaching for the client. Adults only in v1, so `activePlayer` is simply the
//  account's single player.
//

import Foundation
import Supabase
import Observation

@MainActor
@Observable
final class SessionStore {

    enum Phase {
        case loading        // deciding whether we're signed in
        case signedOut
        case needsProfile   // authenticated, but no accounts row yet
        case signedIn
    }

    var phase: Phase = .loading
    var account: Account?
    var players: [PlayerProfile] = []
    var activePlayer: PlayerProfile?
    var authError: String?

    /// Called once at launch. Restores a session if one exists, then loads the
    /// profile so screens have an identity before they render.
    func bootstrap() async {
        #if DEBUG
        // UI tests own their session: start every run signed out so the suite
        // controls who is logged in. Without this, a session left behind by a
        // previous run (or a manual poke at the simulator) makes the app skip
        // the auth screen and every test fails with "Sign-in screen never
        // appeared" — which is exactly how this was found.
        if ProcessInfo.processInfo.environment["UITEST_SIGNED_OUT"] == "1" {
            try? await supabase.auth.signOut()
            account = nil; players = []; activePlayer = nil
            phase = .signedOut
            return
        }
        #endif

        if (try? await supabase.auth.session) != nil {
            await loadProfile()
            // An authenticated user with no profile row used to be sent back to
            // signedOut with no explanation, which was a dead end: their auth
            // user already existed, so signing up again failed too. Now it
            // routes to the screen that finishes the job.
            phase = account == nil ? .needsProfile : .signedIn
        } else {
            phase = .signedOut
        }
    }

    func loadProfile() async {
        do {
            account = try await ProfileRepository.myAccount()
            players = try await ProfileRepository.myPlayers()
            // v1 is adults-only: the account's own player is the active one.
            activePlayer = players.first
        } catch {
            // A signed-in user with no profile row is a real state (see the
            // Volee "cannot load profile" lesson). Surface it rather than crash.
            account = nil
            players = []
            activePlayer = nil
        }
    }

    func signIn(email: String, password: String) async {
        authError = nil
        do {
            try await supabase.auth.signIn(email: email, password: password)
            await loadProfile()
            // Someone who signed up before this screen existed, or who quit
            // partway through it, still has no profile. Send them to finish it
            // rather than into an app where nothing works.
            phase = account == nil ? .needsProfile : .signedIn
        } catch {
            authError = friendly(error)
        }
    }

    /// Creates the auth user only. The `accounts` and `players` rows are written
    /// by `completeProfile` on the next screen, because they need a real name
    /// and `accounts.first_name` is NOT NULL.
    func signUp(email: String, password: String) async {
        authError = nil
        do {
            try await supabase.auth.signUp(email: email, password: password)
            phase = .needsProfile
        } catch {
            authError = friendly(error)
        }
    }

    /// Finishes sign-up by creating the profile rows, then reloads so screens
    /// have an identity. Stays on `.needsProfile` if it fails: landing in the
    /// app without a profile is the exact dead end this replaces.
    func completeProfile(
        firstName: String,
        lastName: String,
        phone: String?,
        isMember: Bool,
        adultRating: Double?
    ) async -> Bool {
        authError = nil
        do {
            _ = try await ProfileRepository.createMyAccount(
                firstName: firstName,
                lastName: lastName,
                phone: phone,
                isMember: isMember,
                adultRating: adultRating
            )
            await loadProfile()
            guard account != nil, activePlayer != nil else {
                // The RPC returned without error but the rows are not readable.
                // Report it rather than proceeding into a broken session: this
                // silent-success case IS the bug being fixed.
                authError = "Your profile didn't save. Please try again."
                return false
            }
            phase = .signedIn
            return true
        } catch {
            authError = friendly(error)
            return false
        }
    }

    /// Email a password-reset link. The link lands on the web admin's
    /// reset.html, which is where the new password is chosen — one page serves
    /// both clients. Same wording on success and on "no such account", on
    /// purpose: confirming which emails exist is an enumeration leak.
    func sendPasswordReset(email: String) async -> Bool {
        authError = nil
        guard !email.trimmingCharacters(in: .whitespaces).isEmpty else {
            authError = "Type your email above first."
            return false
        }
        do {
            try await supabase.auth.resetPasswordForEmail(
                email.trimmingCharacters(in: .whitespaces),
                redirectTo: AppEnv.passwordResetURL)
            return true
        } catch {
            authError = friendly(error)
            return false
        }
    }

    func signOut() async {
        await PushRegistrar.shared.unregisterForSignOut()
        try? await supabase.auth.signOut()
        account = nil
        players = []
        activePlayer = nil
        phase = .signedOut
    }

    private func friendly(_ error: Error) -> String {
        let raw = error.localizedDescription
        if raw.localizedCaseInsensitiveContains("invalid") { return "That email or password didn't work." }
        if raw.localizedCaseInsensitiveContains("network") { return "Couldn't reach the server. Check your connection." }
        return "Something went wrong. Please try again."
    }
}
