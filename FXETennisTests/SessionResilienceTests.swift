//
//  SessionResilienceTests.swift
//  FXETennisTests
//
//  The rules (MVP audit items 7 and 9):
//    * a profile load that FAILED says nothing about the person: whatever was
//      known stays, and the prices, the Register button and the greeting keep
//      working;
//    * a load that worked and found no accounts row is unfinished sign-up;
//    * at launch, with nothing known yet, a failed load shows the approved
//      connection line with Try again, never the sign-up form;
//    * the server refusing a registration for the waiver or the card reopens
//      that step; a timeout is not "someone beat you to the punch".
//

import XCTest
import Supabase
@testable import FXETennis

@MainActor
final class SessionResilienceTests: XCTestCase {

    private let maria = Account(id: UUID(), firstName: "Maria", lastName: "Lopez", email: "maria@fxe.test",
                                phone: nil, accountType: "adult", role: "member", cardBrand: nil, cardLast4: nil)
    private var mariaPlayer: PlayerProfile {
        PlayerProfile(id: UUID(), accountId: maria.id, kind: "adult", firstName: "Maria", lastName: "Lopez",
                      dateOfBirth: nil, adultRating: 3.5, isMember: true, isActive: true, levelNote: nil)
    }

    // MARK: profile loads

    func testAFailedReloadKeepsWhoYouAre() {
        let session = SessionStore()
        XCTAssertEqual(session.apply(.success((maria, [mariaPlayer]))), .loaded)
        let result = session.apply(.failure(URLError(.notConnectedToInternet)))
        XCTAssertEqual(result, .failed(.unreachable))
        XCTAssertEqual(session.account?.firstName, "Maria", "The account survives a failed reload")
        XCTAssertEqual(session.activePlayer?.isMember, true,
                       "activePlayer survives, so prices stay member prices and Register still works")
    }

    func testNoRowIsUnfinishedSignUp() {
        let session = SessionStore()
        XCTAssertEqual(session.apply(.success((nil, []))), .noProfile)
        session.route(after: .noProfile)
        XCTAssertEqual(session.phase, .needsProfile)
    }

    func testNoSignalAtLaunchIsNotTheSignUpForm() {
        let session = SessionStore()
        session.route(after: session.apply(.failure(URLError(.timedOut))))
        XCTAssertEqual(session.phase, .loadFailed)
        XCTAssertEqual(session.loadFailureLine, "Couldn't reach the server. Check your connection.")
    }

    func testAnUnexplainedFailureAtLaunchStillHasALine() {
        let session = SessionStore()
        session.route(after: session.apply(.failure(PostgrestError(code: "42501", message: "permission denied"))))
        XCTAssertEqual(session.phase, .loadFailed)
        XCTAssertEqual(session.loadFailureLine, "Something went wrong. Please try again.")
    }

    func testAFailedLoadWithSomeoneKnownStaysSignedIn() {
        let session = SessionStore()
        session.route(after: session.apply(.success((maria, [mariaPlayer]))))
        XCTAssertEqual(session.phase, .signedIn)
        session.route(after: session.apply(.failure(URLError(.networkConnectionLost))))
        XCTAssertEqual(session.phase, .signedIn)
        XCTAssertEqual(session.activePlayer?.firstName, "Maria")
    }

    func testTheWaiverRefusalReopensTheSheet() async {
        let session = SessionStore()
        session.waiverAccepted = true
        await session.reopen(.waiver)
        XCTAssertEqual(session.waiverAccepted, false, "false is what presents WaiverGate")
    }

    // MARK: a load that outlives a sign-out (review, 2026-09-27)

    /// The rule: a profile load in flight when Sign out is tapped belongs to
    /// the person who left. Its answer must not bring their data back or
    /// route the app back into it.
    func testALoadThatStartedBeforeSignOutIsDropped() async {
        let session = SessionStore()
        let started = session.generation
        await session.signOut()
        XCTAssertEqual(session.apply(.success((maria, [mariaPlayer])), from: started), .superseded)
        XCTAssertNil(session.account, "the previous person's account is not put back")
        XCTAssertNil(session.activePlayer)
        session.route(after: .superseded)
        XCTAssertEqual(session.phase, .signedOut)
    }

    func testALoadThatStartedAfterSignOutCounts() async {
        let session = SessionStore()
        await session.signOut()
        XCTAssertEqual(session.apply(.success((maria, [mariaPlayer])), from: session.generation), .loaded)
        XCTAssertEqual(session.account?.firstName, "Maria")
    }

    // MARK: where a load sends the app when the sign-in has gone (review, 2026-09-27)

    /// The rule: once supabase-swift has dropped the stored session (the
    /// server ended it, or the account was deleted), nothing about this
    /// person can be loaded again, so the app signs out rather than showing
    /// Try again forever or staying signed in with nobody in it.
    func testAFailedLoadWithTheSessionGoneSignsOut() {
        XCTAssertEqual(SessionStore.next(after: .failed(.other), knowsSomeone: true, hasAuthSession: false), .signOut)
        XCTAssertEqual(SessionStore.next(after: .failed(.unreachable), knowsSomeone: false, hasAuthSession: false), .signOut)
    }

    func testNoProfileWithTheSessionGoneSignsOut() {
        XCTAssertEqual(SessionStore.next(after: .noProfile, knowsSomeone: false, hasAuthSession: false), .signOut)
    }

    /// Signed in, then a reload finds no accounts row while the sign-in is
    /// still there: finish sign-up, never "signed in with no account".
    func testNoProfileWithASessionIsUnfinishedSignUp() {
        XCTAssertEqual(SessionStore.next(after: .noProfile, knowsSomeone: false, hasAuthSession: true), .show(.needsProfile))
    }

    func testAFailedLoadWithTheSessionKeptIsUnchanged() {
        XCTAssertEqual(SessionStore.next(after: .failed(.unreachable), knowsSomeone: true, hasAuthSession: true), .show(.signedIn))
        XCTAssertEqual(SessionStore.next(after: .failed(.unreachable), knowsSomeone: false, hasAuthSession: true), .loadFailed(.unreachable))
        XCTAssertEqual(SessionStore.next(after: .loaded, knowsSomeone: true, hasAuthSession: true), .show(.signedIn))
        XCTAssertEqual(SessionStore.next(after: .superseded, knowsSomeone: false, hasAuthSession: false), .stay)
    }

    // MARK: what a failed action says, and what it reopens

    private struct ServerRefusal: Error, CustomStringConvertible {
        let description: String
    }

    func testWaiverRequiredReopensTheWaiver() {
        let refusal = PostgrestError(code: "P0001", message: "waiver_required")
        XCTAssertEqual(ClinicDetailModel.outcome(for: refusal),
                       .init(notice: "Sign the waiver first.", reopens: .waiver))
    }

    func testCardRequiredReopensTheCardStep() {
        let refusal = PostgrestError(code: "P0001", message: "card_required")
        XCTAssertEqual(ClinicDetailModel.outcome(for: refusal),
                       .init(notice: "Add a card on your Profile to register.", reopens: .card))
    }

    func testATimeoutIsNotARace() {
        XCTAssertEqual(ClinicDetailModel.outcome(for: URLError(.timedOut)),
                       .init(notice: "Couldn't reach the server. Check your connection.", reopens: nil))
        XCTAssertEqual(ClinicDetailModel.outcome(for: URLError(.notConnectedToInternet)),
                       .init(notice: "Couldn't reach the server. Check your connection.", reopens: nil))
    }

    func testARealRefusalIsStillARace() {
        // An invitation answered or withdrawn meanwhile: a genuine race.
        let refusal = PostgrestError(code: "P0001", message: "invitation_no_longer_available")
        XCTAssertEqual(ClinicDetailModel.outcome(for: refusal),
                       .init(notice: "Sorry, someone beat you to the punch. Here's the latest!", reopens: nil))
    }

    /// Already in (a double tap, or a second phone) is not losing: no line,
    /// the reload shows her own You're In! (review, 2026-10-04).
    func testAlreadyRegisteredSaysNothing() {
        let refusal = PostgrestError(code: "P0001", message: "already_registered")
        XCTAssertEqual(ClinicDetailModel.outcome(for: refusal), .init(notice: nil, reopens: nil))
    }

    /// Closed between the draw and the tap reads as closed, not as a race.
    func testRegistrationClosedSaysClosed() {
        let refusal = PostgrestError(code: "P0001", message: "registration_closed")
        XCTAssertEqual(ClinicDetailModel.outcome(for: refusal),
                       .init(notice: "Registration has closed for this clinic.", reopens: nil))
    }

    func testTheBackToBack105LineIsKept() {
        let refusal = ServerRefusal(description: "PostgrestError(code: P0001, message: back_to_back_105)")
        XCTAssertEqual(ClinicDetailModel.outcome(for: refusal).notice,
                       "Non-members can take one 105 a day until 48 hours before.")
    }

    func testALeavingScreenSaysNothing() {
        XCTAssertEqual(ClinicDetailModel.outcome(for: CancellationError()), .init(notice: nil, reopens: nil))
    }
}
