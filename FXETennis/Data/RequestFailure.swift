//
//  RequestFailure.swift
//  FXETennis
//
//  What kind of failure a request met, read from what the phone and the
//  server actually reported (a URLError code, an HTTP status, a Postgres
//  code), never from searching an error's text for a word.
//
//  Why (MVP audit, 2026-09-27, items 9 and 15). At the courts with one bar:
//    * iOS says "The Internet connection appears to be offline.", which does
//      not contain the word "network" that sign-in looked for, so it said
//      "Something went wrong.";
//    * a Register tap that timed out read "Sorry, someone beat you to the
//      punch", so she did not retry and lost her place;
//    * a failed profile load was treated as "no profile", which sent a
//      returning member to the sign-up form.
//  And at the launch party, everyone on the club Wi-Fi shares one address, so
//  GoTrue's per-address limit answers 429, which also read "Something went
//  wrong." with no reason to wait.
//
//  The one rule callers need: `.unreachable` and `.rateLimited` mean the
//  request did not get a real answer, so nothing about the person's data may
//  be concluded from it (keep what was known, say so, offer a retry).
//

import Foundation
import Supabase

enum RequestFailure: Equatable, Sendable {
    /// No usable answer: offline, timed out, the host could not be found or
    /// reached, a Wi-Fi sign-in page intercepted the connection, or the server
    /// answered 5xx or 408 (it is there but cannot serve the request now).
    case unreachable
    /// Refused because too many requests came at once (HTTP 429).
    case rateLimited
    /// Cancelled because the screen that asked went away. Say nothing.
    case cancelled
    /// The server answered: a real refusal, or something unexpected.
    case other

    init(_ error: Error) {
        self = Self.classify(error)
    }

    /// The one plain line a person reads for this kind of failure, or nil when
    /// the screen's own words fit better (a refusal it knows how to explain).
    var line: String? {
        switch self {
        // Already approved: in the web admin's friendly() and the snapshot.
        case .unreachable: return "Couldn't reach the server. Check your connection."
        // New chrome, listed in docs/copy-review.md for Alex's tick.
        case .rateLimited: return "Too many requests. Try again in a minute."
        case .cancelled, .other: return nil
        }
    }

    /// True when the request got no real answer, so a missing row cannot be
    /// read into it.
    var isNoAnswer: Bool { self == .unreachable || self == .rateLimited }

    // MARK: - Classification

    static func classify(_ error: Error) -> RequestFailure {
        if error is CancellationError { return .cancelled }
        // URLSession's errors, including an NSError in NSURLErrorDomain,
        // which Swift bridges to URLError here.
        if let url = error as? URLError { return classify(urlCode: url.code) }
        if let auth = error as? AuthError {
            if case let .api(_, code, _, response) = auth {
                return classify(status: response.statusCode, errorCode: code.rawValue)
            }
            return .other
        }
        if let http = error as? HTTPError {
            return classify(status: http.response.statusCode, errorCode: nil)
        }
        if let function = error as? FunctionsError {
            switch function {
            case .relayError: return .unreachable
            case let .httpError(code, _): return classify(status: code, errorCode: nil)
            }
        }
        // PostgREST decodes its JSON error body into this, which carries a
        // Postgres or PGRST code but not the HTTP status.
        if let postgrest = error as? PostgrestError {
            return classify(postgresCode: postgrest.code)
        }
        return .other
    }

    /// URLSession codes that mean "no usable answer came back". The same
    /// family supabase-swift itself treats as retryable, plus the certificate
    /// failures a Wi-Fi sign-in page causes by intercepting HTTPS.
    static let unreachableCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut,
        .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed,
        .dataNotAllowed, .internationalRoamingOff, .callIsActive,
        .cannotLoadFromNetwork, .badServerResponse,
        .secureConnectionFailed, .serverCertificateUntrusted,
        .serverCertificateHasBadDate, .serverCertificateHasUnknownRoot,
        .serverCertificateNotYetValid,
    ]

    static func classify(urlCode: URLError.Code) -> RequestFailure {
        if urlCode == .cancelled { return .cancelled }
        return unreachableCodes.contains(urlCode) ? .unreachable : .other
    }

    /// An HTTP status, with GoTrue's error code when there is one.
    static func classify(status: Int, errorCode: String?) -> RequestFailure {
        if status == 429 || errorCode == "over_request_rate_limit" { return .rateLimited }
        if status == 408 || (500...599).contains(status) { return .unreachable }
        return .other
    }

    /// A code from PostgREST's error body. PGRST000 to PGRST003 are PostgREST
    /// failing to reach Postgres or to get a connection (503/504). From
    /// Postgres: class 08 (connection), class 53 (out of resources), 57P01 to
    /// 57P03 (shutting down or starting up) and 57014 (statement timeout: the
    /// statement was cancelled, so nothing it did was kept). Every other code
    /// is the database answering, e.g. P0001 for a refusal like
    /// `registration_closed`.
    static func classify(postgresCode code: String?) -> RequestFailure {
        guard let code else { return .other }
        if ["PGRST000", "PGRST001", "PGRST002", "PGRST003"].contains(code) { return .unreachable }
        if code.hasPrefix("08") || code.hasPrefix("53") || code.hasPrefix("57P") || code == "57014" {
            return .unreachable
        }
        return .other
    }
}
