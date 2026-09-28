//
//  InvitationActions.swift
//  FXETennis
//
//  Accept and Decline on the invitation push itself (2026-09-28). Tara's
//  invitation says "Tap below to accept", and "below" is two buttons on the
//  notification. The app registers the category INVITATION at launch with an
//  Accept and a Decline (PushAppDelegate); iOS shows them on any push whose
//  `aps.category` is INVITATION. The server side is a separate change to
//  supabase/functions/push/index.ts, which must set that category on
//  invitation_received rows only. Until it is deployed no push carries the
//  category, iOS shows no buttons, and a tap opens the clinic as before.
//
//  A button answers WITHOUT opening the app, and only on an unlocked phone
//  (.authenticationRequired: someone picking up a locked phone cannot answer
//  for its owner). iOS wakes the app in the background and the delegate
//  calls `respond`, which is the clinic page's own path: the same
//  RegistrationRepository.respondToInvitation, so respond_to_invitation's
//  conditional UPDATE (hard rule 3) decides, and the same failure words
//  (ClinicDetailModel.outcome).
//
//  Hard rule 2: only the player's own explicit tap on Accept ever accepts.
//  A plain tap on the notification still just opens its clinic, as before;
//  a dismissal answers nothing. `answer(forAction:category:)` is the gate,
//  unit-tested (FXETennisTests/InvitationActionTests.swift).
//
//  What she is told, since she is not looking at the app:
//    * taken: nothing new; the row is read and the icon's number drops;
//    * the invitation changed (Tara withdrew it, or it was already answered):
//      Tara's own line, "Sorry, someone beat you to the punch. Here's the
//      latest!", as a notification that opens the clinic;
//    * no signal: "Couldn't reach the server. Check your connection.", the
//      same words the page uses, because the invitation may still be open
//      and she has to try again (MVP audit item 9: a timeout is not a race).
//      iOS allows a background action about 30 seconds, so an answer still
//      out after `answerLimit` counts as no signal, and if iOS takes the time
//      back first, the same line goes out from the expiry handler;
//    * someone else's invitation on a shared phone (respond_to_invitation's
//      own not_authorized): nothing;
//    * nobody signed in, or a login the database refused: nothing can be
//      sent, so the push is handed to the app (it opens the clinic once
//      someone signs in) and the invitation is shown again, without buttons,
//      so there is something to tap. iOS offers no way for a background
//      action to bring the app forward.
//  No new words: every line above is already in the app.
//

import UIKit
import UserNotifications
import Supabase

/// What answering an invitation from its notification ran into.
enum InvitationAttempt: Sendable {
    /// Nobody is signed in on this phone, or the server has ended the session.
    case noSession
    /// The server took the answer.
    case answered
    /// The answer did not go through.
    case failed(Error)
}

/// What the app does after an answer from a notification.
struct InvitationActionPlan: Equatable, Sendable {
    /// The invitation's row in the bell is marked read: the server answered.
    var markRead = false
    /// A line to post as a notification that opens the clinic, or nil.
    var notice: String? = nil
    /// Nothing was sent. The push goes to the app, which opens its clinic
    /// once someone is signed in, and the invitation is shown again.
    var handToApp = false
}

enum InvitationActions {
    static let categoryId = "INVITATION"
    static let acceptId = "ACCEPT"
    static let declineId = "DECLINE"

    /// How long an answer from the notification may take before it counts as
    /// no signal. iOS gives a background action about 30 seconds; this leaves
    /// time to tell her.
    static let answerLimit: Duration = .seconds(20)

    /// Registered once at launch (PushAppDelegate). The titles are the clinic
    /// page's own buttons. Neither opens the app; both need the phone
    /// unlocked; Decline is red.
    static var category: UNNotificationCategory {
        UNNotificationCategory(
            identifier: categoryId,
            actions: [
                UNNotificationAction(identifier: acceptId, title: "Accept", options: [.authenticationRequired]),
                UNNotificationAction(identifier: declineId, title: "Decline",
                                     options: [.authenticationRequired, .destructive]),
            ],
            intentIdentifiers: [],
            options: [])
    }

    /// true for Accept, false for Decline, nil for everything else: a plain
    /// tap, a dismissal, or a button on anything that is not an invitation.
    /// The only way into respond_to_invitation from a notification.
    static func answer(forAction action: String, category: String) -> Bool? {
        guard category == categoryId else { return nil }
        switch action {
        case acceptId: return true
        case declineId: return false
        default: return nil
        }
    }

    /// Reading the session failed. With no signal the player is still signed
    /// in on this phone (supabase-swift keeps a session it could not refresh
    /// for lack of signal), so it is a failed answer; anything else (no
    /// stored session, a refresh the server refused) means nobody can answer
    /// from here. The same split as SessionStore.restore.
    static func attempt(afterSessionError error: Error) -> InvitationAttempt {
        RequestFailure(error).isNoAnswer ? .failed(error) : .noSession
    }

    /// The database refused the login itself: an invalid or expired token,
    /// or no token (PostgREST's JWT errors).
    private static let refusedLogin: Set<String> = ["PGRST301", "PGRST302", "PGRST303"]

    static func plan(after attempt: InvitationAttempt) -> InvitationActionPlan {
        switch attempt {
        case .answered:
            return InvitationActionPlan(markRead: true)
        case .noSession:
            return InvitationActionPlan(handToApp: true)
        case .failed(let error):
            if let refusal = error as? PostgrestError {
                // Someone else's invitation reached this phone (a sign-out that
                // could not unregister it offline). respond_to_invitation's own
                // ownership refusal, and only that one: Postgres's permission
                // error shares the code and is a refusal like any other.
                if refusal.code == "42501" && refusal.message == "not_authorized" { return InvitationActionPlan() }
                // Not a race, and nobody can answer from here: the app signs in again.
                if let code = refusal.code, refusedLogin.contains(code) { return InvitationActionPlan(handToApp: true) }
            }
            // The clinic page's words for the same error.
            let outcome = ClinicDetailModel.outcome(for: error)
            switch RequestFailure(error) {
            case .cancelled:
                return InvitationActionPlan()
            case .unreachable, .rateLimited:
                // No real answer: the invitation may still be open, so the
                // row stays unread and the line says to try again.
                return InvitationActionPlan(markRead: false, notice: outcome.notice)
            case .other:
                // The server answered and refused: the invitation changed.
                return InvitationActionPlan(markRead: true, notice: outcome.notice)
            }
        }
    }

    /// The answer, or no signal once `limit` has passed. The request is
    /// cancelled then; supabase-swift's requests stop when their task is
    /// cancelled, so this returns at the limit, not when the request gives up.
    static func settle(within limit: Duration,
                       _ work: @escaping @Sendable () async -> InvitationAttempt) async -> InvitationAttempt {
        await withTaskGroup(of: InvitationAttempt?.self) { group in
            group.addTask { await work() }
            group.addTask {
                try? await Task.sleep(for: limit)
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first ?? .failed(URLError(.timedOut))
        }
    }

    // MARK: - The notifications this posts

    /// "answer-<registration>": a second answer's line replaces the first.
    static func identifier(for registrationId: UUID) -> String {
        "answer-" + registrationId.uuidString.lowercased()
    }

    /// A line that opens the clinic behind the registration through the
    /// router, like any push. No notification_id: it is not a row in the bell.
    static func noticeRequest(_ notice: String, registrationId: UUID) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.body = notice
        content.sound = .default
        content.userInfo = ["entity_type": "registration", "entity_id": registrationId.uuidString.lowercased()]
        return UNNotificationRequest(identifier: identifier(for: registrationId), content: content, trigger: nil)
    }

    /// The invitation again, in the server's words, with its row id so the
    /// tap after sign-in marks it read, and without the buttons: Accept again
    /// with nobody signed in could only bring it back again.
    static func repostRequest(body: String, tap: PushTap) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.body = body
        content.sound = .default
        var info: [String: String] = [:]
        if let id = tap.notificationId { info["notification_id"] = id.uuidString.lowercased() }
        switch tap.target {
        case .registration(let id)?:
            info["entity_type"] = "registration"; info["entity_id"] = id.uuidString.lowercased()
        case .clinic(let id)?:
            info["entity_type"] = "clinic"; info["entity_id"] = id.uuidString.lowercased()
        case nil:
            break
        }
        content.userInfo = info
        let key: String
        if case .registration(let id)? = tap.target { key = identifier(for: id) } else { key = "answer-" + UUID().uuidString }
        return UNNotificationRequest(identifier: key, content: content, trigger: nil)
    }

    // MARK: - The answer itself

    /// Accept or Decline from the notification. Runs in the background under
    /// `hold`; the caller calls iOS's completion handler after this returns.
    @MainActor
    static func respond(accept: Bool, to tap: PushTap, body: String, hold: BackgroundHold) async {
        guard case .registration(let registrationId)? = tap.target else {
            // Nothing to answer: open it the way a plain tap would.
            NotificationRouter.shared.tapped(tap)
            return
        }
        let center = UNUserNotificationCenter.current()
        // If iOS takes the time back before there is an outcome, she is told
        // it did not go through rather than nothing: she has no other way to
        // know, and the notification she answered is gone.
        var settled = false
        hold.onExpiry = {
            guard !settled, let line = RequestFailure.unreachable.line else { return }
            settled = true
            center.add(noticeRequest(line, registrationId: registrationId))
        }

        let attempt = await settle(within: answerLimit) {
            await send(accept: accept, registrationId: registrationId)
        }
        let expiredFirst = settled
        settled = true
        let plan = plan(after: attempt)

        // Tell her first: the one thing she must not miss if time runs out.
        if !expiredFirst {
            if let notice = plan.notice {
                try? await center.add(noticeRequest(notice, registrationId: registrationId))
            }
            if plan.handToApp {
                NotificationRouter.shared.tapped(tap)
                try? await center.add(repostRequest(body: body, tap: tap))
                return
            }
        }
        if plan.markRead, let id = tap.notificationId {
            try? await NotificationRepository.markRead(id)
        }
        // The icon's number, and Home, the bell and an open clinic page.
        await PushRegistrar.shared.syncBadge()
        NotificationRouter.shared.requestReload()
    }

    /// The session first: with none, nothing may be sent (the RPC would go
    /// out with only the publishable key).
    private static func send(accept: Bool, registrationId: UUID) async -> InvitationAttempt {
        do {
            _ = try await supabase.auth.session
        } catch {
            return attempt(afterSessionError: error)
        }
        do {
            try await RegistrationRepository.respondToInvitation(registrationId: registrationId, accept: accept)
            return .answered
        } catch {
            return .failed(error)
        }
    }
}

/// Keeps the app running in the background until an answer is sent. iOS
/// gives a background action a limited time; this asks for the usual
/// allowance, runs `onExpiry` if the time runs out first, and gives it back
/// as soon as the work is done.
@MainActor
final class BackgroundHold {
    private var id: UIBackgroundTaskIdentifier = .invalid
    /// Runs once if iOS ends the allowance before `end()`.
    var onExpiry: (() -> Void)?

    init(_ name: String) {
        id = UIApplication.shared.beginBackgroundTask(withName: name) { [weak self] in
            // Called on the main thread when the allowance runs out.
            MainActor.assumeIsolated {
                self?.onExpiry?()
                self?.end()
            }
        }
    }

    func end() {
        onExpiry = nil
        guard id != .invalid else { return }
        UIApplication.shared.endBackgroundTask(id)
        id = .invalid
    }
}
