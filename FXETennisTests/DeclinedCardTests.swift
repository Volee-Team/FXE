//
//  DeclinedCardTests.swift
//  FXETennisTests
//
//  A declined card (decision 0024, Tara's question 78, 2026-09-28): "Cannot
//  sign up without proper, transactional card. App needs to tell them why
//  their card isn’t working, yes." The rules, from her answer and decision
//  0026, with the expected values written out by hand:
//
//    * The player is told why in the words Tara approved for her own screen,
//      after "Declined: " as her Money tab writes them:
//      insufficient_funds -> "Declined: Insufficient funds (NSF)".
//    * Stripe asks that a card reported lost or stolen, and a charge it
//      stopped as fraud, be shown to the cardholder as a plain decline; a
//      code with no approved words is a plain decline too, never Stripe's
//      raw code: "Declined: Card declined".
//    * Register or Accept refused with card_declined says that line (the
//      code rides in the refusal's hint) and opens the card step; it is not
//      "someone beat you to the punch".
//    * The card step opened for a decline closes itself once the decline is
//      cleared (a new card saved), and never opens for an admin.
//    * The account decodes the decline from the server's JSON, and an
//      account without the two fields still decodes (an older schema).
//

import XCTest
import Supabase
@testable import FXETennis

@MainActor
final class DeclinedCardTests: XCTestCase {

    // MARK: - the words

    func testTheReasonIsInTheWordsTaraApproved() {
        XCTAssertEqual(CardDecline.line("insufficient_funds"), "Declined: Insufficient funds (NSF)")
        XCTAssertEqual(CardDecline.line("expired_card"), "Declined: Card expired")
        XCTAssertEqual(CardDecline.line("do_not_honor"), "Declined: Card declined by bank")
        XCTAssertEqual(CardDecline.line("incorrect_cvc"), "Declined: Wrong security code")
        XCTAssertEqual(CardDecline.line("authentication_required"), "Declined: Needs the cardholder to approve")
        XCTAssertEqual(CardDecline.line("card_declined"), "Declined: Card declined")
    }

    func testLostStolenAndFraudAreShownAsAPlainDecline() {
        for code in ["lost_card", "stolen_card", "fraudulent", "merchant_blacklist", "pickup_card", "generic_decline"] {
            XCTAssertEqual(CardDecline.line(code), "Declined: Card declined", code)
        }
    }

    func testACodeWithNoApprovedWordsIsAPlainDeclineNeverTheRawCode() {
        XCTAssertEqual(CardDecline.line("try_again_later"), "Declined: Card declined")
        XCTAssertEqual(CardDecline.line(nil), "Declined: Card declined")
        XCTAssertEqual(CardDecline.line(""), "Declined: Card declined")
    }

    // MARK: - the refusal

    func testTheRefusalSaysWhyAndOpensTheCardStep() {
        let refusal = PostgrestError(hint: "insufficient_funds", code: "P0001", message: "card_declined")
        XCTAssertEqual(ClinicDetailModel.outcome(for: refusal),
                       .init(notice: "Declined: Insufficient funds (NSF)", reopens: .cardDeclined))
    }

    func testARefusalWithNoReasonStillSaysDeclined() {
        let refusal = PostgrestError(code: "P0001", message: "card_declined")
        XCTAssertEqual(ClinicDetailModel.outcome(for: refusal),
                       .init(notice: "Declined: Card declined", reopens: .cardDeclined))
    }

    func testARefusalForAStolenCardDoesNotSayStolen() {
        let refusal = PostgrestError(hint: "stolen_card", code: "P0001", message: "card_declined")
        XCTAssertEqual(ClinicDetailModel.outcome(for: refusal).notice, "Declined: Card declined")
    }

    func testNoCardIsStillAskedForACard() {
        let refusal = PostgrestError(code: "P0001", message: "card_required")
        XCTAssertEqual(ClinicDetailModel.outcome(for: refusal),
                       .init(notice: "Add a card on your Profile to register.", reopens: .card))
    }

    func testAcceptFromTheLockScreenSaysWhyToo() {
        let refusal = PostgrestError(hint: "expired_card", code: "P0001", message: "card_declined")
        XCTAssertEqual(InvitationActions.plan(after: .failed(refusal)).notice, "Declined: Card expired")
    }

    // MARK: - the card step

    private func account(declined: Bool, admin: Bool = false) -> Account {
        Account(id: UUID(), firstName: "Maria", lastName: "Alvarez", email: "maria@fxe.test", phone: nil,
                accountType: "adult", role: admin ? "admin" : "member", cardBrand: "visa", cardLast4: "4242",
                cardDeclinedAt: declined ? Date() : nil, cardDeclineCode: declined ? "insufficient_funds" : nil)
    }

    func testADeclinedCardAloneDoesNotTakeOverTheApp() {
        let session = SessionStore()
        session.cardsRequired = true
        session.account = account(declined: true)
        XCTAssertFalse(session.cardStepDue, "a card is on file: onboarding has nothing to ask")
        XCTAssertFalse(session.cardStepShown, "browsing, My Clinics and cancelling still work")
    }

    func testTheRefusalOpensTheStepAndANewCardClosesIt() {
        let session = SessionStore()
        session.cardsRequired = true
        session.account = account(declined: true)
        session.cardChangeRequested = true
        XCTAssertTrue(session.cardStepShown)
        session.account = account(declined: false)      // the webhook saved a new card
        XCTAssertFalse(session.cardStepShown, "the step closes itself once the decline is cleared")
        XCTAssertFalse(session.cardChangeRequested, "and a decline next month does not reopen it unasked")
    }

    func testTheStepNeverOpensForAnAdmin() {
        let session = SessionStore()
        session.cardsRequired = true
        session.account = account(declined: true, admin: true)
        session.cardChangeRequested = true
        XCTAssertFalse(session.cardStepShown)
    }

    // MARK: - decoding

    func testTheAccountDecodesTheDecline() throws {
        let json = #"{"id":"22222222-2222-2222-2222-222222222222","first_name":"Maria","last_name":"Alvarez","email":"m@x.test","phone":null,"account_type":"adult","role":"member","card_brand":"visa","card_last4":"4242","card_declined_at":"2026-09-28T23:59:59.123456+00:00","card_decline_code":"insufficient_funds"}"#
        let decoded = try PostgrestClient.Configuration.jsonDecoder.decode(Account.self, from: Data(json.utf8))
        XCTAssertTrue(decoded.isCardDeclined)
        XCTAssertEqual(decoded.cardDeclineCode, "insufficient_funds")
    }

    func testAnAccountWithoutTheFieldsStillDecodes() throws {
        let json = #"{"id":"22222222-2222-2222-2222-222222222222","first_name":"Maria","last_name":"Alvarez","email":"m@x.test","phone":null,"account_type":"adult","role":"member","card_brand":null,"card_last4":null}"#
        let decoded = try PostgrestClient.Configuration.jsonDecoder.decode(Account.self, from: Data(json.utf8))
        XCTAssertFalse(decoded.isCardDeclined)
    }
}
