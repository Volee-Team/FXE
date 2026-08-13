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
            phase = players.isEmpty && account == nil ? .signedOut : .signedIn
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
            phase = .signedIn
        } catch {
            authError = friendly(error)
        }
    }

    func signUp(email: String, password: String) async {
        authError = nil
        do {
            try await supabase.auth.signUp(email: email, password: password)
            await loadProfile()
            phase = .signedIn
        } catch {
            authError = friendly(error)
        }
    }

    func signOut() async {
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
