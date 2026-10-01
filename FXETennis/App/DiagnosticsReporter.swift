//
//  DiagnosticsReporter.swift
//  FXETennis
//
//  Crash and hang reports, to our own database (decision 0035).
//
//  Until 2026-10-01 a crash on a member's phone reached us only if she told
//  Tara. Apple's MetricKit hands the app a diagnostic for every crash, hang,
//  CPU exception, excessive disk write and slow launch, on the next launch
//  (or at once on iOS 15+). This file subscribes at launch and sends each one
//  to `report_app_diagnostic`, which files it under the signed-in account.
//
//  WHAT IS SENT. MetricKit's own JSON (call stacks as binary UUIDs and
//  offsets, exception codes, its metadata), plus the app version, build, iOS
//  version and model identifier. Nothing about the person, nothing they
//  typed or saw. MetricKit sends nothing anywhere itself; this file is the
//  only thing that moves a report off the phone, and only to our backend.
//
//  WHEN. Signed in: at once. Signed out, offline, or the server not
//  answering: the rows wait in a small file (Application Support, excluded
//  from backup, like Snapshot.swift) and go on the next signed-in launch.
//  The account a report lands under is whoever is signed in when it is
//  SENT, which on a shared phone may not be who was using it when it
//  crashed; the account exists for the server's rate limit, not to say whose
//  phone it was, and the server unlinks it after a day (20261001000002).
//
//  NEVER SEEN. Nothing here shows anything, blocks anything or logs
//  anything; a report that cannot be sent is simply tried again later. The
//  server's quiet refusal, too_many_reports (20 a day per account), is
//  dropped, because a crash loop is already visible in the twenty that landed.
//

import Foundation
import MetricKit
import Supabase
import UIKit

// MARK: - One row

/// One row for `report_app_diagnostic`, as it waits on the phone.
struct DiagnosticReport: Codable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable {
        case crash, hang, cpu, disk, launch
    }

    /// The phone's own identity for the row, so a send that finishes while
    /// another report is being queued removes exactly this one.
    var id = UUID()
    var kind: Kind
    var appVersion: String?
    var build: String?
    var osVersion: String?
    var device: String?
    var payload: AnyJSON
    /// Sends that failed for a reason the phone cannot read (not a network
    /// failure, not a server refusal). At `maxAttempts` the row is dropped,
    /// not carried forever.
    var attempts = 0

    /// The server refuses a payload over 64 KB of its text form. The phone
    /// stops at 60 KB, leaving room for the ways Postgres prints JSON longer
    /// than Swift does (a space after every colon and comma, which
    /// `serverSize` counts, and number formats, which it cannot).
    static let maxPayloadBytes = 60 * 1024
    static let maxAttempts = 5

    /// The row for one diagnostic, or nil when MetricKit's data is not JSON.
    static func make(kind: Kind, json: Data,
                     appVersion: String?, build: String?, osVersion: String?, device: String?,
                     limit: Int = maxPayloadBytes) -> DiagnosticReport? {
        guard let decoded = try? JSONDecoder().decode(AnyJSON.self, from: json) else { return nil }
        return DiagnosticReport(kind: kind, appVersion: appVersion, build: build,
                                osVersion: osVersion, device: device,
                                payload: fitted(decoded, limit: limit))
    }

    /// An upper bound on the payload's size as Postgres measures it,
    /// octet_length(payload::text). jsonb prints ": " and ", " where compact
    /// JSON has ":" and ",", so every colon and comma in the compact form
    /// (inside strings too, which only overcounts) adds a byte.
    static func serverSize(of payload: AnyJSON) -> Int {
        guard let data = try? compactEncoder.encode(payload) else { return Int.max }
        let separators = data.reduce(0) { $0 + ($1 == UInt8(ascii: ":") || $1 == UInt8(ascii: ",") ? 1 : 0) }
        return data.count + separators
    }

    /// The payload, or when it is over `limit`, a smaller object that keeps
    /// MetricKit's metadata whole and the start of the rest as text, marked
    /// truncated with the original size. Always valid JSON, always within
    /// `limit` (a cut-off string of JSON is not JSON, and jsonb would refuse
    /// it).
    static func fitted(_ payload: AnyJSON, limit: Int) -> AnyJSON {
        let size = serverSize(of: payload)
        if size <= limit { return payload }
        let text = (try? compactEncoder.encode(payload)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        var metadata: AnyJSON?
        if case let .object(object) = payload { metadata = object["diagnosticMetaData"] }

        func candidate(_ count: Int, keepMetadata: Bool) -> AnyJSON {
            var object: [String: AnyJSON] = ["truncated": .bool(true), "original_bytes": .integer(size)]
            if keepMetadata, let metadata { object["diagnosticMetaData"] = metadata }
            if count > 0 { object["head"] = .string(String(text.prefix(count))) }
            return .object(object)
        }
        for keepMetadata in [true, false] {
            var count = limit
            while count > 0 {
                let attempt = candidate(count, keepMetadata: keepMetadata)
                if serverSize(of: attempt) <= limit { return attempt }
                count /= 2
            }
            let bare = candidate(0, keepMetadata: keepMetadata)
            if serverSize(of: bare) <= limit { return bare }
        }
        return .object(["truncated": .bool(true)])
    }

    private static let compactEncoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()
}

// MARK: - What happens to a send

enum DiagnosticSendOutcome: Equatable {
    case sent
    /// The server answered and will never take this row: drop it.
    case drop
    /// No usable answer, or not signed in yet: keep it for next time, as
    /// often as it takes (a member offline at the courts for a week loses
    /// nothing).
    case keep
    /// Something nobody here understands: keep it, but count the try, so a
    /// row that can never be sent is dropped after `maxAttempts`.
    case retry

    /// Read from what the request met, never from guessing: no answer keeps
    /// the row; the server's own refusals drop it, except the two that mean
    /// "not yet" (no session, or an account still being made).
    static func after(_ error: Error) -> DiagnosticSendOutcome {
        let failure = RequestFailure(error)
        if failure.isNoAnswer || failure == .cancelled { return .keep }
        if let postgrest = error as? PostgrestError {
            switch postgrest.message {
            case "not_authenticated", "account_not_found": return .keep
            default: return .drop   // too_many_reports, payload_too_large, invalid_kind
            }
        }
        return .retry
    }
}

// MARK: - The waiting file

/// Reports not yet sent, newest kept when there are too many.
struct PendingDiagnostics {
    let directory: URL
    /// The server takes 20 a day per account; more than that waiting would
    /// only be refused.
    static let maxKept = 20

    static let shared: PendingDiagnostics = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return PendingDiagnostics(directory: base.appendingPathComponent("Diagnostics", isDirectory: true))
    }()

    private var file: URL { directory.appendingPathComponent("pending.json") }

    func load() -> [DiagnosticReport] {
        guard let data = try? Data(contentsOf: file),
              let reports = try? JSONDecoder().decode([DiagnosticReport].self, from: data)
        else { return [] }
        return reports
    }

    func append(_ new: [DiagnosticReport]) {
        save(load() + new)
    }

    func remove(_ id: UUID) {
        save(load().filter { $0.id != id })
    }

    /// Counts one more failed send against a row; drops it at the limit.
    func recordAttempt(_ id: UUID) {
        save(load().compactMap { report in
            guard report.id == id else { return report }
            var tried = report
            tried.attempts += 1
            return tried.attempts >= DiagnosticReport.maxAttempts ? nil : tried
        })
    }

    func save(_ reports: [DiagnosticReport]) {
        let kept = Array(reports.suffix(Self.maxKept))
        if kept.isEmpty {
            try? FileManager.default.removeItem(at: file)
            return
        }
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var dir = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
            let data = try JSONEncoder().encode(kept)
            #if os(iOS)
            try data.write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: file, options: [.atomic])
            #endif
        } catch {
            // Nowhere to keep it: the report is lost, the app is not.
        }
    }
}

// MARK: - Sending

/// Sends what is waiting, one row at a time, one flush at a time.
actor DiagnosticsOutbox {
    static let shared = DiagnosticsOutbox(
        store: .shared,
        isSignedIn: { supabase.auth.currentUser != nil },
        send: { try await DiagnosticsOutbox.sendToServer($0) }
    )

    private let store: PendingDiagnostics
    private let isSignedIn: @Sendable () -> Bool
    private let send: @Sendable (DiagnosticReport) async throws -> Void
    private var flushing = false

    init(store: PendingDiagnostics,
         isSignedIn: @escaping @Sendable () -> Bool,
         send: @escaping @Sendable (DiagnosticReport) async throws -> Void) {
        self.store = store
        self.isSignedIn = isSignedIn
        self.send = send
    }

    /// Writes the new reports to the file first, so a crash during the send
    /// loses nothing, then tries to send.
    func enqueue(_ reports: [DiagnosticReport]) async {
        guard !reports.isEmpty else { return }
        store.append(reports)
        await flush()
    }

    /// Sends every waiting row while signed in. Stops at the first row that
    /// gets no usable answer (the rest would meet the same network). The file
    /// is re-read after every send, so a report queued meanwhile is kept.
    func flush() async {
        guard !flushing, isSignedIn() else { return }
        flushing = true
        defer { flushing = false }
        var tried = Set<UUID>()
        while let next = store.load().first(where: { !tried.contains($0.id) }) {
            tried.insert(next.id)
            do {
                try await send(next)
                store.remove(next.id)
            } catch {
                switch DiagnosticSendOutcome.after(error) {
                case .sent, .drop:
                    store.remove(next.id)
                case .keep:
                    return
                case .retry:
                    store.recordAttempt(next.id)
                    return
                }
            }
        }
    }

    private static func sendToServer(_ report: DiagnosticReport) async throws {
        struct P: Encodable {
            let p_kind: String
            let p_app_version: String?
            let p_build: String?
            let p_os_version: String?
            let p_device: String?
            let p_payload: AnyJSON

            // Every key written, nulls included: Swift's synthesized
            // Encodable omits a nil optional, and PostgREST then looks for a
            // function with fewer arguments and answers 404 (2026-09-01).
            func encode(to encoder: Encoder) throws {
                var c = encoder.container(keyedBy: CodingKeys.self)
                try c.encode(p_kind, forKey: .p_kind)
                try c.encode(p_app_version, forKey: .p_app_version)
                try c.encode(p_build, forKey: .p_build)
                try c.encode(p_os_version, forKey: .p_os_version)
                try c.encode(p_device, forKey: .p_device)
                try c.encode(p_payload, forKey: .p_payload)
            }
            enum CodingKeys: String, CodingKey {
                case p_kind, p_app_version, p_build, p_os_version, p_device, p_payload
            }
        }
        _ = try await supabase.rpc("report_app_diagnostic", params: P(
            p_kind: report.kind.rawValue, p_app_version: report.appVersion, p_build: report.build,
            p_os_version: report.osVersion, p_device: report.device, p_payload: report.payload
        )).execute()
    }
}

// MARK: - MetricKit

/// Subscribed once at launch (PushAppDelegate). MetricKit calls it on a
/// queue of its own; it hands the rows to the outbox and returns.
final class DiagnosticsReporter: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticsReporter()

    func start() {
        MXMetricManager.shared.add(self)
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        let reports = payloads.flatMap(Self.reports(from:))
        guard !reports.isEmpty else { return }
        Task.detached(priority: .background) {
            await DiagnosticsOutbox.shared.enqueue(reports)
        }
    }

    private static func reports(from payload: MXDiagnosticPayload) -> [DiagnosticReport] {
        let info = Bundle.main.infoDictionary
        let appVersion = info?["CFBundleShortVersionString"] as? String
        let build = info?["CFBundleVersion"] as? String
        let osVersion = UIDevice.current.systemVersion
        let device = modelIdentifier()

        var out: [DiagnosticReport] = []
        func add(_ kind: DiagnosticReport.Kind, _ diagnostics: [MXDiagnostic]?) {
            for diagnostic in diagnostics ?? [] {
                if let report = DiagnosticReport.make(kind: kind, json: diagnostic.jsonRepresentation(),
                                                      appVersion: appVersion, build: build,
                                                      osVersion: osVersion, device: device) {
                    out.append(report)
                }
            }
        }
        add(.crash, payload.crashDiagnostics)
        add(.hang, payload.hangDiagnostics)
        add(.cpu, payload.cpuExceptionDiagnostics)
        add(.disk, payload.diskWriteExceptionDiagnostics)
        add(.launch, payload.appLaunchDiagnostics)
        return out
    }

    /// "iPhone17,1", not the marketing name: what Apple's crash tools key on.
    static func modelIdentifier() -> String {
        if let simulated = ProcessInfo.processInfo.environment["SIMULATOR_MODEL_IDENTIFIER"] {
            return simulated
        }
        var system = utsname()
        uname(&system)
        return withUnsafeBytes(of: &system.machine) { raw in
            String(decoding: raw.prefix(while: { $0 != 0 }), as: UTF8.self)
        }
    }
}
