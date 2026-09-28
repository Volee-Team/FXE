//
//  RequestFailureTests.swift
//  FXETennisTests
//
//  The rule (MVP audit items 9 and 15): a request that got no real answer
//  (offline, timed out, the host unreachable, a Wi-Fi sign-in page, a 5xx)
//  is "unreachable" and reads "Couldn't reach the server. Check your
//  connection."; a 429 is "rate limited" and reads the rate-limit line; a
//  cancelled request says nothing; anything the server actually answered is
//  "other". Expected values are written from that rule and from Apple's and
//  PostgREST's published code lists, not from the implementation.
//

import XCTest
import Supabase
@testable import FXETennis

final class RequestFailureTests: XCTestCase {

    private func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: URL(string: "https://example.invalid")!, statusCode: status,
                        httpVersion: nil, headerFields: nil)!
    }

    // MARK: the phone's own errors

    func testOfflineIsUnreachable() {
        // iOS's text for this one is "The Internet connection appears to be
        // offline." It has no word "network" in it, which is how the old
        // word match missed it.
        XCTAssertEqual(RequestFailure(URLError(.notConnectedToInternet)), .unreachable)
    }

    func testTimeoutsAndLostConnectionsAreUnreachable() {
        XCTAssertEqual(RequestFailure(URLError(.timedOut)), .unreachable)
        XCTAssertEqual(RequestFailure(URLError(.networkConnectionLost)), .unreachable)
        XCTAssertEqual(RequestFailure(URLError(.cannotFindHost)), .unreachable)
        XCTAssertEqual(RequestFailure(URLError(.cannotConnectToHost)), .unreachable)
        XCTAssertEqual(RequestFailure(URLError(.dnsLookupFailed)), .unreachable)
    }

    func testAWiFiSignInPageIsUnreachable() {
        // A captive portal intercepts HTTPS, so the certificate does not match.
        XCTAssertEqual(RequestFailure(URLError(.serverCertificateUntrusted)), .unreachable)
        XCTAssertEqual(RequestFailure(URLError(.secureConnectionFailed)), .unreachable)
    }

    func testAnNSErrorInTheURLDomainIsReadByItsCode() {
        let bridged = NSError(domain: NSURLErrorDomain, code: NSURLErrorNotConnectedToInternet)
        XCTAssertEqual(RequestFailure(bridged), .unreachable)
    }

    func testCancellationSaysNothing() {
        XCTAssertEqual(RequestFailure(CancellationError()), .cancelled)
        XCTAssertEqual(RequestFailure(URLError(.cancelled)), .cancelled)
        XCTAssertNil(RequestFailure.cancelled.line)
    }

    func testAMalformedURLIsNotAConnectionProblem() {
        XCTAssertEqual(RequestFailure(URLError(.badURL)), .other)
    }

    // MARK: the server's answers

    func testGoTrueRateLimitIsRateLimited() {
        // GoTrue's answer to the 31st sign-in in five minutes from one address.
        let limited = AuthError.api(message: "Request rate limit reached",
                                    errorCode: .overRequestRateLimit,
                                    underlyingData: Data(), underlyingResponse: response(429))
        XCTAssertEqual(RequestFailure(limited), .rateLimited)
    }

    func testAny429IsRateLimited() {
        let email = AuthError.api(message: "Email rate limit exceeded",
                                  errorCode: .overEmailSendRateLimit,
                                  underlyingData: Data(), underlyingResponse: response(429))
        XCTAssertEqual(RequestFailure(email), .rateLimited)
        XCTAssertEqual(RequestFailure(HTTPError(data: Data(), response: response(429))), .rateLimited)
        XCTAssertEqual(RequestFailure(FunctionsError.httpError(code: 429, data: Data())), .rateLimited)
    }

    func testWrongPasswordIsAnAnswerNotAnOutage() {
        let wrong = AuthError.api(message: "Invalid login credentials",
                                  errorCode: .invalidCredentials,
                                  underlyingData: Data(), underlyingResponse: response(400))
        XCTAssertEqual(RequestFailure(wrong), .other)
    }

    func testServerErrorsAreUnreachable() {
        XCTAssertEqual(RequestFailure(HTTPError(data: Data(), response: response(502))), .unreachable)
        XCTAssertEqual(RequestFailure(HTTPError(data: Data(), response: response(503))), .unreachable)
        XCTAssertEqual(RequestFailure(HTTPError(data: Data(), response: response(504))), .unreachable)
        XCTAssertEqual(RequestFailure(HTTPError(data: Data(), response: response(408))), .unreachable)
        XCTAssertEqual(RequestFailure(FunctionsError.relayError), .unreachable)
        let gotrue = AuthError.api(message: "Unexpected error", errorCode: .unexpectedFailure,
                                   underlyingData: Data(), underlyingResponse: response(504))
        XCTAssertEqual(RequestFailure(gotrue), .unreachable)
    }

    func testAClientErrorIsAnAnswer() {
        XCTAssertEqual(RequestFailure(HTTPError(data: Data(), response: response(404))), .other)
        XCTAssertEqual(RequestFailure(FunctionsError.httpError(code: 400, data: Data())), .other)
    }

    func testARefusalFromTheDatabaseIsAnAnswer() {
        // register_for_clinic raises with SQLSTATE P0001.
        XCTAssertEqual(RequestFailure(PostgrestError(code: "P0001", message: "registration_closed")), .other)
        XCTAssertEqual(RequestFailure(PostgrestError(code: "42501", message: "not_authorized")), .other)
    }

    // MARK: the gateway, not PostgREST

    /// Supabase's API gateway answers a 502 or a 504 itself, with a JSON body
    /// that has a "message" and no "code". supabase-swift decodes any JSON
    /// body with a "message" into PostgrestError, so it arrives with code
    /// nil. PostgREST always sends a code, so code nil means the request
    /// never reached the database: a Register tap that timed out at the
    /// gateway must not read "someone beat you to the punch" (review, 2026-09-27).
    private func gatewayError(_ body: String) throws -> PostgrestError {
        try JSONDecoder().decode(PostgrestError.self, from: Data(body.utf8))
    }

    func testAGateway502IsUnreachable() throws {
        let bad = try gatewayError(#"{"message":"An invalid response was received from the upstream server"}"#)
        XCTAssertNil(bad.code, "the premise: a gateway body decodes with no code")
        XCTAssertEqual(RequestFailure(bad), .unreachable)
    }

    func testAGateway504IsUnreachable() throws {
        let timeout = try gatewayError(#"{"message":"The upstream server is timing out"}"#)
        XCTAssertEqual(RequestFailure(timeout), .unreachable)
        XCTAssertEqual(ClinicDetailModel.outcome(for: timeout).notice,
                       "Couldn't reach the server. Check your connection.")
    }

    /// Changed deliberately on 2026-09-27: this is the gateway's own answer to
    /// a wrong key, code nil like the 502 and 504 above, and cannot be told
    /// apart from them by code. "Couldn't reach the server" is truer than
    /// "someone beat you to the punch", which is what .other led to.
    func testTheGatewaysBadKeyAnswerIsNotARace() {
        XCTAssertEqual(RequestFailure(PostgrestError(code: nil, message: "Invalid API key")), .unreachable)
    }

    func testTheDatabaseBeingUnavailableIsUnreachable() {
        // PostgREST cannot reach Postgres, or cannot get a connection.
        XCTAssertEqual(RequestFailure(PostgrestError(code: "PGRST000", message: "Could not connect")), .unreachable)
        XCTAssertEqual(RequestFailure(PostgrestError(code: "PGRST003", message: "Timed out acquiring connection")), .unreachable)
        // Postgres out of connections, shutting down, statement timeout.
        XCTAssertEqual(RequestFailure(PostgrestError(code: "53300", message: "too many connections")), .unreachable)
        XCTAssertEqual(RequestFailure(PostgrestError(code: "57P01", message: "terminating connection")), .unreachable)
        XCTAssertEqual(RequestFailure(PostgrestError(code: "57014", message: "canceling statement due to statement timeout")), .unreachable)
    }

    // MARK: the words

    func testTheLinesAreTheApprovedOnes() {
        XCTAssertEqual(RequestFailure.unreachable.line, "Couldn't reach the server. Check your connection.")
        XCTAssertEqual(RequestFailure.rateLimited.line, "Too many attempts. Try again in a minute.")
        XCTAssertNil(RequestFailure.other.line)
    }

    // MARK: sign-in's message, end to end

    func testSignInOfflineSaysTheConnectionLine() {
        XCTAssertEqual(SessionStore.friendly(URLError(.notConnectedToInternet)),
                       "Couldn't reach the server. Check your connection.")
        XCTAssertEqual(SessionStore.friendly(URLError(.timedOut)),
                       "Couldn't reach the server. Check your connection.")
    }

    func testSignInRateLimitedSaysToWait() {
        let limited = AuthError.api(message: "Request rate limit reached",
                                    errorCode: .overRequestRateLimit,
                                    underlyingData: Data(), underlyingResponse: response(429))
        XCTAssertEqual(SessionStore.friendly(limited), "Too many attempts. Try again in a minute.")
    }

    /// GoTrue's reset-email limit is hourly, so the reset must not promise a
    /// minute. Its request limit on the same endpoint still clears in one.
    func testAResetEmailLimitDoesNotPromiseAMinute() {
        let email = AuthError.api(message: "email rate limit exceeded",
                                  errorCode: .overEmailSendRateLimit,
                                  underlyingData: Data(), underlyingResponse: response(429))
        XCTAssertEqual(SessionStore.resetFriendly(email), "Too many reset emails. Try again later.")
        // An older GoTrue sends the sentence with no error code.
        let bare = AuthError.api(message: "Email rate limit exceeded", errorCode: .unknown,
                                 underlyingData: Data(), underlyingResponse: response(429))
        XCTAssertEqual(SessionStore.resetFriendly(bare), "Too many reset emails. Try again later.")
        let requests = AuthError.api(message: "Request rate limit reached",
                                     errorCode: .overRequestRateLimit,
                                     underlyingData: Data(), underlyingResponse: response(429))
        XCTAssertEqual(SessionStore.resetFriendly(requests), "Too many attempts. Try again in a minute.")
    }

    func testSignInWrongPasswordStillSaysSo() {
        let wrong = AuthError.api(message: "Invalid login credentials",
                                  errorCode: .invalidCredentials,
                                  underlyingData: Data(), underlyingResponse: response(400))
        XCTAssertEqual(SessionStore.friendly(wrong), "That email or password didn't work.")
    }

    func testAWiFiSignInPageAtSignInIsAConnectionProblem() {
        // What a club Wi-Fi sign-in page does to HTTPS. Read by its code, not
        // its text: under the old word match it said "Something went wrong."
        XCTAssertEqual(SessionStore.friendly(URLError(.serverCertificateUntrusted)),
                       "Couldn't reach the server. Check your connection.")
    }
}
