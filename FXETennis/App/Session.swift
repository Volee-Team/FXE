//
//  Session.swift
//  FXETennis
//
//  Auth state and the signed-in identity, in one observable store injected at
//  the root. Screens read `session.activePlayer` / `session.account` rather than
//  reaching for the client. Adults only in v1, so `activePlayer` is simply the
//  account's single player.
//
//  "NO ROW" IS NOT "NO ANSWER" (MVP audit item 9, 2026-09-27). A profile load
//  that worked and found no `accounts` row means sign-up is unfinished, and
//  the profile screen finishes it. A load that FAILED means nothing about the
//  person: with one bar of signal at the courts, the old catch-all set the
//  account to nil, which sent a returning member to "Almost there!" at launch
//  and, mid-session, blanked `activePlayer`, flipping prices to non-member and
//  making Register return silently. So a failure now keeps the last known
//  identity, and at launch, with none known yet, shows "Couldn't reach the
//  server" with Try again (`.loadFailed`) instead of guessing.
//
//  A LOAD BELONGS TO WHOEVER STARTED IT (review, 2026-09-27). A profile load
//  in flight when Sign out is tapped used to land afterwards and route back
//  to `.signedIn` with the previous person's data in memory. `generation`
//  counts sign-outs; every load captures it when it starts, and an answer
//  from an older generation is dropped (`.superseded`). And once
//  supabase-swift has dropped the stored session (the server ended it, the
//  account was deleted), a load that fails or finds no row signs out, rather
//  than Try again forever or signed in with nobody (`next(after:...)`).
//

import Foundation
import Supabase
import Observation

@MainActor
@Observable
final class SessionStore {

    enum Phase: Equatable {
        case loading        // deciding whether we're signed in
        case signedOut
        case needsProfile   // authenticated, and the server says no accounts row yet
        case loadFailed     // authenticated, but who you are could not be loaded
        case signedIn
    }

    /// What one profile load found.
    enum ProfileLoad: Equatable {
        case loaded                   // the accounts row came back
        case noProfile                // the request worked; there is no row
        case failed(RequestFailure)   // the request did not work; nothing was changed
        case superseded               // signed out while it ran; its answer was dropped
    }

    /// Where the app goes after a profile load.
    enum Next: Equatable {
        case stay                       // a dropped answer changes nothing
        case show(Phase)
        case loadFailed(RequestFailure)
        case signOut
    }

    /// Bumped by signOut, at its start and its end. A load captures it when
    /// it starts; an answer from an older generation is dropped.
    @ObservationIgnored private(set) var generation = 0

    /// The rule, separate from the network so it is unit-tested
    /// (SessionResilienceTests). `hasAuthSession` is whether supabase-swift
    /// still holds a stored session once the load has returned: it keeps an
    /// expired one it could not refresh for lack of signal, and drops one
    /// the server refused, so its absence means nobody can be loaded again.
    nonisolated static func next(after load: ProfileLoad, knowsSomeone: Bool, hasAuthSession: Bool) -> Next {
        switch load {
        case .superseded:
            return .stay
        case .loaded:
            return .show(.signedIn)
        case .noProfile:
            // Unfinished sign-up, never "signed in with no account".
            return hasAuthSession ? .show(.needsProfile) : .signOut
        case .failed(let failure):
            if !hasAuthSession { return .signOut }
            return knowsSomeone ? .show(.signedIn) : .loadFailed(failure)
        }
    }

    /// The gates the server can refuse a registration for (decision 0013 §4,
    /// 0015 §5, and 0024 for a declined card). The app reopens the matching
    /// step when it does.
    enum Gate: Equatable { case waiver, card, cardDeclined }

    var phase: Phase = .loading {
        // A banner for a push that lands while nobody is signed in would show
        // the previous account's words on a shared phone (PushAppDelegate).
        didSet { NotificationRouter.shared.signedIn = phase == .signedIn }
    }
    var account: Account? {
        // A new card cleared the decline (or someone else signed in): the
        // step asked for after a refusal has done its job, and a decline next
        // month must not reopen it unasked.
        // Written only when it changes: an @Observable write invalidates
        // every view that reads it (the root's card sheet) even when the
        // value is the same, and profiles load often.
        didSet { if cardChangeRequested, account?.isCardDeclined != true { cardChangeRequested = false } }
    }
    /// nil until known; false shows the waiver over the app (decision 0013).
    var waiverAccepted: Bool?
    /// Consent on file for the current card-permission words (decision 0015).
    var cardConsent: Bool?
    /// Payments are on and a card is required (app_settings), so onboarding
    /// asks for a card after the waiver.
    var cardsRequired = false
    /// The onboarding card step is due: cards required, none saved, a player.
    var cardStepDue: Bool {
        cardsRequired && account != nil && account?.hasCard != true && account?.isAdmin != true
    }
    /// Register or Accept was refused for a declined card (decision 0024):
    /// the card step opens so a new card can be saved. Unlike the onboarding
    /// step it can be closed, and it closes itself once the webhook has
    /// recorded a new card (the decline is cleared, `account` above).
    var cardChangeRequested = false
    /// The card step is up: due at onboarding, or asked for after a decline.
    /// A declined card alone takes nothing over: browsing, My Clinics and
    /// cancelling all still work; only Register and Accept are refused.
    var cardStepShown: Bool {
        cardStepDue
            || (cardChangeRequested && account?.isCardDeclined == true && account?.isAdmin != true)
    }
    var players: [PlayerProfile] = []
    var activePlayer: PlayerProfile?
    var authError: String?
    /// Why the identity could not be loaded; shown by LoadFailedView.
    var loadFailureLine: String?

    /// Coming back to the app reloads the profile and the gates, at most once
    /// per 30 seconds (MVP audit item 8). Any load resets the clock.
    @ObservationIgnored private var foregroundThrottle = ReloadThrottle()

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
        await restore()
    }

    /// LoadFailedView's Try again: the same path as launch, minus the UI-test
    /// sign-out above.
    func retry() async { await restore() }

    /// Restores the stored session and loads who it belongs to.
    private func restore() async {
        let started = generation
        do {
            _ = try await supabase.auth.session
        } catch {
            guard started == generation else { return }   // signed out meanwhile
            // No stored session, or one the server has ended: sign in. But an
            // expired session that could not be REFRESHED for lack of signal is
            // still on this phone, and the sign-in screen would be the wrong
            // answer; say what happened and let them retry.
            let failure = RequestFailure(error)
            if failure.isNoAnswer {
                fail(failure)
            } else {
                // Ended by the server (signed out everywhere, or deleted):
                // signOut() never runs on this path, so the person's
                // "Remind me" reminders are cleared here (review, 2026-09-28).
                await RegistrationReminders.removeAll()
                guard started == generation else { return }
                phase = .signedOut
            }
            return
        }
        guard started == generation else { return }
        await settle(await loadProfile())
    }

    /// Routes after a load, reading whether supabase-swift still holds a
    /// session once the load has returned, and signs out when it does not.
    private func settle(_ load: ProfileLoad) async {
        if route(after: load, hasAuthSession: supabase.auth.currentUser != nil) {
            await signOut()
        }
    }

    /// Where a launch, a sign-in or a retry goes once the profile load is in.
    /// An authenticated user with no profile row used to be sent back to
    /// signedOut with no explanation, which was a dead end: their auth user
    /// already existed, so signing up again failed too. `.noProfile` routes to
    /// the screen that finishes the job. A failed load never does. Returns
    /// true when the caller must sign out (`settle` does).
    @discardableResult
    func route(after load: ProfileLoad, hasAuthSession: Bool = true) -> Bool {
        switch Self.next(after: load, knowsSomeone: account != nil, hasAuthSession: hasAuthSession) {
        case .stay:
            return false
        case .show(let next):
            if next != .loadFailed { loadFailureLine = nil }
            phase = next                   // .signedIn after a failure keeps who we knew
            return false
        case .loadFailed(let failure):
            fail(failure)
            return false
        case .signOut:
            return true
        }
    }

    private func fail(_ failure: RequestFailure) {
        loadFailureLine = failure.line ?? "Something went wrong. Please try again."
        phase = .loadFailed
    }

    /// Loads the account, its players and the two gates. A failure changes
    /// nothing that was known before it (see the header).
    @discardableResult
    func loadProfile() async -> ProfileLoad {
        let started = generation
        let fetched: Result<(account: Account?, players: [PlayerProfile]), Error>
        do {
            let account = try await ProfileRepository.myAccount()
            let players = try await ProfileRepository.myPlayers()
            fetched = .success((account, players))
        } catch {
            fetched = .failure(error)
        }
        let result = apply(fetched, from: started)
        guard result == .loaded else { return result }
        // The gates. A check that fails keeps its last known answer rather
        // than switching the gate off; register_for_clinic enforces both
        // anyway, and its refusal reopens the step (`reopen`). Each answer is
        // dropped if a sign-out happened while it was asked.
        if let accepted = try? await ProfileRepository.myWaiverAccepted(), started == generation { waiverAccepted = accepted }
        if let consent = try? await PaymentsRepository.myCardConsent(), started == generation { cardConsent = consent }
        if let required = try? await PaymentsRepository.cardStepRequired(), started == generation { cardsRequired = required }
        return started == generation ? result : .superseded
    }

    /// Applies one fetch of the account and its players. Separate from the
    /// network so the rule is testable: a failure keeps everything; a
    /// successful answer with no row clears it.
    @discardableResult
    func apply(_ fetched: Result<(account: Account?, players: [PlayerProfile]), Error>) -> ProfileLoad {
        apply(fetched, from: generation)
    }

    @discardableResult
    func apply(_ fetched: Result<(account: Account?, players: [PlayerProfile]), Error>, from started: Int) -> ProfileLoad {
        // Started before a sign-out: the answer is the previous person's.
        guard started == generation else { return .superseded }
        switch fetched {
        case .failure(let error):
            return .failed(RequestFailure(error))
        case .success(let found):
            account = found.account
            players = found.players
            // v1 is adults-only: the account's own player is the active one.
            activePlayer = found.players.first
            foregroundThrottle.recordLoad()
            return found.account == nil ? .noProfile : .loaded
        }
    }

    /// The server refused a registration for a gate this phone thought was
    /// passed (a new waiver version, a check that failed at launch, a card
    /// removed, payments switched on since). Reopen the step instead of only
    /// saying so: WaiverView's promise, and decision 0013 §4.
    func reopen(_ gate: Gate) async {
        switch gate {
        case .waiver:
            // The waiver sheet opens on false (admins are exempt there, and
            // the server never asks them).
            waiverAccepted = false
        case .card:
            // Fresh card summary and payments switches; the card step opens if
            // they say a card is due.
            await settle(await loadProfile())
        case .cardDeclined:
            // The server just said the card is declined: fresh account (its
            // code for Profile), then the step, unless the reload shows the
            // decline already cleared (a card saved meanwhile).
            await settle(await loadProfile())
            if account?.isCardDeclined == true { cardChangeRequested = true }
        }
    }

    /// The app came back to the front (RootView's scenePhase). Refresh who
    /// this is and the gates, so a waiver version or a membership change Tara
    /// made while the app slept shows without a relaunch; or, on the
    /// load-failed screen, try again on its own.
    func returnedToForeground() async {
        switch phase {
        case .signedIn:
            guard foregroundThrottle.shouldReload() else { return }
            // The server may have ended this session while the app slept
            // (signed out elsewhere, or the account deleted): settle signs
            // out then, and a row gone with the sign-in still here finishes
            // sign-up, rather than an app with nobody in it.
            await settle(await loadProfile())
        case .loadFailed:
            await restore()
        case .loading, .signedOut, .needsProfile:
            break
        }
    }

    func signIn(email: String, password: String) async {
        authError = nil
        do {
            try await supabase.auth.signIn(email: email, password: password)
        } catch {
            authError = Self.friendly(error)
            return
        }
        // Someone who signed up before the profile screen existed, or who quit
        // partway through it, still has no profile and is sent to finish it.
        // A load that failed is not that, and goes to Try again instead.
        await settle(await loadProfile())
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
            authError = Self.friendly(error)
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
        adultRating: Double?,
        levelNote: String? = nil
    ) async -> Bool {
        authError = nil
        do {
            _ = try await ProfileRepository.createMyAccount(
                firstName: firstName,
                lastName: lastName,
                phone: phone,
                isMember: isMember,
                adultRating: adultRating,
                levelNote: levelNote
            )
            let load = await loadProfile()
            if load == .superseded { return false }   // signed out meanwhile
            if case .failed(let failure) = load {
                // Saved, most likely, but not read back. Continue again is
                // safe: create_my_account is idempotent.
                authError = failure.line ?? "Your profile didn't save. Please try again."
                return false
            }
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
            authError = Self.friendly(error)
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
            authError = Self.resetFriendly(error)
            return false
        }
    }

    func signOut() async {
        // Anything in flight now belongs to the person leaving.
        generation &+= 1
        await PushRegistrar.shared.unregisterForSignOut()
        // "Remind me" reminders are this person's, like their pushes.
        await RegistrationReminders.removeAll()
        try? await supabase.auth.signOut()
        // After the session is gone, so a count fetched before it cannot
        // put the number back on the icon.
        PushRegistrar.shared.clearBadge()
        generation &+= 1
        account = nil
        players = []
        activePlayer = nil
        waiverAccepted = nil
        cardConsent = nil
        cardsRequired = false
        cardChangeRequested = false
        loadFailureLine = nil
        phase = .signedOut
    }

    /// The line an auth screen shows for a failed sign-in, sign-up, profile
    /// save or reset. What the request met is read first, by code: no answer
    /// or a rate limit says so before any text is looked at, because an
    /// offline error's text has no word "network" in it and a certificate
    /// error's text says "invalid" (MVP audit items 9 and 15).
    /// A failed password reset. GoTrue's reset-email limit is hourly, so it
    /// must not say "a minute" the way the request limit does.
    nonisolated static func resetFriendly(_ error: Error) -> String {
        if RequestFailure.isEmailRateLimit(error) { return "Too many reset emails. Try again later." }
        return friendly(error)
    }

    nonisolated static func friendly(_ error: Error) -> String {
        if let line = RequestFailure(error).line { return line }
        let raw = error.localizedDescription
        let full = String(describing: error)
        // GoTrue states the password rule itself ("Password should be at
        // least 6 characters."); show that sentence rather than a generic
        // line. TestFlight, 2026-09-22: a weak password read "Something went
        // wrong", which told the person nothing they could act on.
        if full.localizedCaseInsensitiveContains("weak_password") || raw.localizedCaseInsensitiveContains("password should") {
            if let range = raw.range(of: "Password should[^.]*\\.", options: .regularExpression) {
                return String(raw[range])
            }
            return "Password should be at least 6 characters."
        }
        if full.localizedCaseInsensitiveContains("already registered") || raw.localizedCaseInsensitiveContains("already registered") {
            return "That email already has an account. Sign in instead."
        }
        if raw.localizedCaseInsensitiveContains("invalid") { return "That email or password didn't work." }
        return "Something went wrong. Please try again."
    }
}
