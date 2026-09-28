//
//  InvitationActionTests.swift
//  FXETennisTests
//
//  Accept and Decline on the invitation push itself (2026-09-28). Expected
//  values from the rules, not the code:
//
//    Hard rule 2: only the player's own explicit tap on Accept accepts, and
//      only Decline declines. A plain tap on the notification, a dismissal,
//      or an action on anything that is not an invitation answers nothing.
//    The buttons answer without opening the app, and only on an unlocked
//      phone (the lead's spec: .authenticationRequired, Decline destructive).
//    MVP audit item 9 (docs/decisions/0020): only a real refusal from the
//      server is a race. "Sorry, someone beat you to the punch. Here's the
//      latest!" (Tara's line) is for the invitation having changed; no
//      signal says so ("Couldn't reach the server. Check your connection."),
//      because the invitation may still be open and she has to try again.
//    Someone else's invitation on a shared phone (not_authorized) says
//      nothing: it was never this person's to answer.
//    Nobody signed in: nothing can be sent, so the push is handed to the app,
//      which opens its clinic once someone signs in.
//

import XCTest
import Supabase
import UserNotifications
@testable import FXETennis

final class InvitationActionTests: XCTestCase {

    private let registrationId = UUID(uuidString: "e0000000-0000-0000-0000-000000000001")!
    private let notificationId = UUID(uuidString: "f0000000-0000-0000-0000-000000000001")!
    private let raceLine = "Sorry, someone beat you to the punch. Here's the latest!"
    private let offlineLine = "Couldn't reach the server. Check your connection."

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    // MARK: - hard rule 2: which taps answer

    func testOnlyAcceptAcceptsAndOnlyDeclineDeclines() {
        XCTAssertEqual(InvitationActions.answer(forAction: "ACCEPT", category: "INVITATION"), true)
        XCTAssertEqual(InvitationActions.answer(forAction: "DECLINE", category: "INVITATION"), false)
    }

    func testAPlainTapOrADismissalAnswersNothing() {
        XCTAssertNil(InvitationActions.answer(forAction: UNNotificationDefaultActionIdentifier, category: "INVITATION"),
                     "a tap on the notification opens it; it must never accept")
        XCTAssertNil(InvitationActions.answer(forAction: UNNotificationDismissActionIdentifier, category: "INVITATION"))
        XCTAssertNil(InvitationActions.answer(forAction: "SOMETHING_ELSE", category: "INVITATION"))
    }

    func testAnActionOnANotificationThatIsNotAnInvitationAnswersNothing() {
        XCTAssertNil(InvitationActions.answer(forAction: "ACCEPT", category: ""))
        XCTAssertNil(InvitationActions.answer(forAction: "ACCEPT", category: "REMINDER"))
    }

    // MARK: - the category

    func testTheCategoryHasAcceptAndDeclineBehindTheLock() {
        let category = InvitationActions.category
        XCTAssertEqual(category.identifier, "INVITATION")
        XCTAssertEqual(category.actions.map(\.identifier), ["ACCEPT", "DECLINE"])
        XCTAssertEqual(category.actions.map(\.title), ["Accept", "Decline"])
        XCTAssertEqual(category.actions[0].options, [.authenticationRequired])
        XCTAssertEqual(category.actions[1].options, [.authenticationRequired, .destructive])
        // Answered where it lands: neither button opens the app.
        XCTAssertFalse(category.actions.contains { $0.options.contains(.foreground) })
    }

    /// The host app registered it at launch, or iOS shows no buttons at all.
    func testTheCategoryIsRegisteredAtLaunch() async {
        let registered = await UNUserNotificationCenter.current().notificationCategories()
        let invitation = registered.first { $0.identifier == "INVITATION" }
        XCTAssertNotNil(invitation, "PushAppDelegate must register INVITATION in didFinishLaunching")
        XCTAssertEqual(invitation?.actions.map(\.identifier), ["ACCEPT", "DECLINE"])
    }

    // MARK: - what happens after the answer

    func testATakenAnswerMarksTheRowReadAndSaysNothing() {
        XCTAssertEqual(InvitationActions.plan(after: .answered),
                       InvitationActionPlan(markRead: true, notice: nil, handToApp: false))
    }

    func testAnInvitationThatChangedGetsTarasLine() {
        // respond_to_invitation's conditional UPDATE matched no row.
        let changed = PostgrestError(code: "P0001", message: "invitation_no_longer_available")
        XCTAssertEqual(InvitationActions.plan(after: .failed(changed)),
                       InvitationActionPlan(markRead: true, notice: raceLine, handToApp: false))
    }

    // 20260928300001 and 20260928400001: an Accept on the lock screen for a
    // clinic Tara canceled, or one that is already over. Nobody beat anyone
    // to it, so the notice is the page's own approved words, and the row is
    // read (the answer is final: refusing again tomorrow would change nothing).
    func testACanceledClinicSaysCanceledNotARace() {
        let canceled = PostgrestError(code: "P0001", message: "clinic_canceled")
        XCTAssertEqual(InvitationActions.plan(after: .failed(canceled)),
                       InvitationActionPlan(markRead: true, notice: "This clinic has been canceled.", handToApp: false))
    }

    func testAFinishedClinicSaysClosedNotARace() {
        let ended = PostgrestError(code: "P0001", message: "clinic_ended")
        XCTAssertEqual(InvitationActions.plan(after: .failed(ended)),
                       InvitationActionPlan(markRead: true, notice: "Registration has closed for this clinic.", handToApp: false))
    }

    func testAnInvitationThatIsGoneGetsTarasLine() {
        let gone = PostgrestError(code: "P0002", message: "registration_not_found")
        XCTAssertEqual(InvitationActions.plan(after: .failed(gone)),
                       InvitationActionPlan(markRead: true, notice: raceLine, handToApp: false))
    }

    func testNoSignalIsNotARaceAndLeavesTheInvitationUnread() {
        for error in [URLError(.notConnectedToInternet), URLError(.timedOut)] {
            XCTAssertEqual(InvitationActions.plan(after: .failed(error)),
                           InvitationActionPlan(markRead: false, notice: offlineLine, handToApp: false),
                           "\(error.code): the invitation may still be open; she must know to try again")
        }
    }

    func testARateLimitSaysSo() {
        let limited = HTTPError(data: Data(), response: response(429))
        XCTAssertEqual(InvitationActions.plan(after: .failed(limited)),
                       InvitationActionPlan(markRead: false, notice: "Too many attempts. Try again in a minute.",
                                            handToApp: false))
    }

    func testSomeoneElsesInvitationOnASharedPhoneSaysNothing() {
        let notMine = PostgrestError(code: "42501", message: "not_authorized")
        XCTAssertEqual(InvitationActions.plan(after: .failed(notMine)),
                       InvitationActionPlan(markRead: false, notice: nil, handToApp: false))
    }

    /// Only respond_to_invitation's own not_authorized means "someone else's
    /// invitation". Postgres's permission error (a grant gone missing) is a
    /// refusal like any other: the page's words, never silence, or she would
    /// think she had answered (review, 2026-09-28).
    func testAPermissionErrorIsNotMistakenForSomeoneElsesInvitation() {
        let denied = PostgrestError(code: "42501", message: "permission denied for function respond_to_invitation")
        XCTAssertEqual(InvitationActions.plan(after: .failed(denied)),
                       InvitationActionPlan(markRead: true, notice: raceLine, handToApp: false))
    }

    /// The database refused the login itself (an expired or invalid token:
    /// PostgREST's PGRST301 to PGRST303). The invitation may be open; that is
    /// not a race. Nobody can answer from here, so it goes to the app.
    func testALoginTheDatabaseRefusedGoesToTheApp() {
        for code in ["PGRST301", "PGRST302", "PGRST303"] {
            let refused = PostgrestError(code: code, message: "JWT expired")
            XCTAssertEqual(InvitationActions.plan(after: .failed(refused)),
                           InvitationActionPlan(markRead: false, notice: nil, handToApp: true), code)
        }
    }

    // MARK: - the time iOS allows

    /// iOS gives a background action about 30 seconds. An answer still out
    /// when the limit passes is reported as no signal while there is time to
    /// say so (review, 2026-09-28: four requests in a row on one bar could
    /// outlast the allowance and she would be told nothing).
    func testTheLimitLeavesTimeToTellHer() {
        XCTAssertLessThanOrEqual(InvitationActions.answerLimit, .seconds(20))
        XCTAssertGreaterThanOrEqual(InvitationActions.answerLimit, .seconds(10))
    }

    func testAnAnswerStillOutAtTheLimitIsNoSignal() async {
        let started = Date()
        let attempt = await InvitationActions.settle(within: .milliseconds(200)) {
            try? await Task.sleep(for: .seconds(5))
            return .answered
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 2, "the limit must not wait for the request")
        XCTAssertEqual(InvitationActions.plan(after: attempt),
                       InvitationActionPlan(markRead: false, notice: offlineLine, handToApp: false))
    }

    func testAnAnswerInTimeIsKept() async {
        let attempt = await InvitationActions.settle(within: .seconds(5)) { .answered }
        XCTAssertEqual(InvitationActions.plan(after: attempt),
                       InvitationActionPlan(markRead: true, notice: nil, handToApp: false))
    }

    func testACancelledRequestSaysNothing() {
        XCTAssertEqual(InvitationActions.plan(after: .failed(CancellationError())),
                       InvitationActionPlan(markRead: false, notice: nil, handToApp: false))
    }

    func testNobodySignedInHandsThePushToTheApp() {
        XCTAssertEqual(InvitationActions.plan(after: .noSession),
                       InvitationActionPlan(markRead: false, notice: nil, handToApp: true))
    }

    // MARK: - reading the session first

    func testNoStoredSessionIsNobodySignedIn() {
        guard case .noSession = InvitationActions.attempt(afterSessionError: AuthError.sessionMissing) else {
            return XCTFail("a missing session must hand the push to the app")
        }
    }

    func testASessionTheServerEndedIsNobodySignedIn() {
        let refused = AuthError.api(message: "Invalid Refresh Token: Refresh Token Not Found",
                                    errorCode: .refreshTokenNotFound,
                                    underlyingData: Data(), underlyingResponse: response(400))
        guard case .noSession = InvitationActions.attempt(afterSessionError: refused) else {
            return XCTFail("a session the server refused to refresh is nobody signed in")
        }
    }

    func testASessionThatCouldNotRefreshForLackOfSignalIsNoSignal() {
        let attempt = InvitationActions.attempt(afterSessionError: URLError(.notConnectedToInternet))
        XCTAssertEqual(InvitationActions.plan(after: attempt),
                       InvitationActionPlan(markRead: false, notice: offlineLine, handToApp: false),
                       "the player is still signed in on this phone; the answer just did not go out")
    }

    // MARK: - the notifications this posts

    func testTheLineOpensTheClinicThroughTheRouter() {
        let request = InvitationActions.noticeRequest(raceLine, registrationId: registrationId)
        XCTAssertEqual(request.content.body, raceLine)
        XCTAssertNil(request.trigger, "shown at once")
        XCTAssertEqual(request.content.categoryIdentifier, "", "no buttons on the line itself")
        let tap = PushTap(userInfo: request.content.userInfo)
        XCTAssertEqual(tap.target, .registration(registrationId), "a tap opens the clinic behind the registration")
        XCTAssertNil(tap.notificationId, "a local line is not a row in the bell")
    }

    func testTheInvitationHandedToTheAppKeepsItsWordsAndItsRowButNotItsButtons() {
        let body = "Good News! A spot is available for Evening Coed. Tap below to accept before it expires"
        let tap = PushTap(userInfo: ["notification_id": notificationId.uuidString.lowercased(),
                                     "type": "invitation_received",
                                     "entity_type": "registration",
                                     "entity_id": registrationId.uuidString.lowercased()])
        let request = InvitationActions.repostRequest(body: body, tap: tap)
        XCTAssertEqual(request.content.body, body, "the server's words, unchanged")
        XCTAssertEqual(request.content.categoryIdentifier, "",
                       "without buttons: Accept again with nobody signed in would only come back")
        let again = PushTap(userInfo: request.content.userInfo)
        XCTAssertEqual(again.target, .registration(registrationId))
        XCTAssertEqual(again.notificationId, notificationId, "so the tap after sign-in marks the row read")
    }
}
