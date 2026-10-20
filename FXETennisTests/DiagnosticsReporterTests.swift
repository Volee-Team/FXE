//
//  DiagnosticsReporterTests.swift
//  FXETennisTests
//
//  Crash and hang reports (DiagnosticsReporter.swift, decision 0035). The
//  rules, written before the tests: a row carries MetricKit's JSON as JSON
//  plus the four labels; a payload over the limit is replaced by a smaller
//  object that is still JSON and within the limit, keeps MetricKit's
//  metadata and says it was truncated; data that is not JSON makes no row;
//  waiting rows survive a round trip through the file, the newest 20 kept;
//  no answer keeps a row, a server refusal drops it (too_many_reports
//  silently), and a row queued during a send is not lost.
//

import XCTest
import Supabase
@testable import FXETennis

final class DiagnosticsReporterTests: XCTestCase {

    private var store: PendingDiagnostics!

    override func setUp() {
        store = PendingDiagnostics(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("DiagnosticsTests-\(UUID().uuidString)", isDirectory: true))
    }

    override func tearDown() { try? FileManager.default.removeItem(at: store.directory) }

    private func report(_ n: Int, kind: DiagnosticReport.Kind = .crash) -> DiagnosticReport {
        DiagnosticReport(kind: kind, appVersion: "0.1.0", build: "7", osVersion: "26.0",
                         device: "iPhone17,1", payload: .object(["n": .integer(n)]))
    }

    // MARK: - Row building

    func testRowCarriesTheJSONAndTheLabels() throws {
        let json = Data(#"{"diagnosticMetaData":{"appBuildVersion":"7"},"callStackTree":{"callStacks":[]}}"#.utf8)
        let row = try XCTUnwrap(DiagnosticReport.make(kind: .hang, json: json, appVersion: "0.1.0", build: "7",
                                                      osVersion: "26.0", device: "iPhone17,1"))
        XCTAssertEqual(row.kind, .hang)
        XCTAssertEqual(row.appVersion, "0.1.0")
        XCTAssertEqual(row.build, "7")
        XCTAssertEqual(row.osVersion, "26.0")
        XCTAssertEqual(row.device, "iPhone17,1")
        XCTAssertEqual(row.payload, .object([
            "diagnosticMetaData": .object(["appBuildVersion": .string("7")]),
            "callStackTree": .object(["callStacks": .array([])]),
        ]))
    }

    func testDataThatIsNotJSONMakesNoRow() {
        XCTAssertNil(DiagnosticReport.make(kind: .crash, json: Data("not json".utf8),
                                           appVersion: nil, build: nil, osVersion: nil, device: nil))
    }

    func testTheKindsAreExactlyTheServers() {
        // The server's check: crash, hang, cpu, disk, launch.
        XCTAssertEqual(DiagnosticReport.Kind.allCases.map(\.rawValue), ["crash", "hang", "cpu", "disk", "launch"])
    }

    // MARK: - Size

    func testServerSizeCountsTheSpacesPostgresAdds() {
        // Compact {"a":1,"b":2} is 13 bytes; jsonb prints {"a": 1, "b": 2}, 16.
        XCTAssertEqual(DiagnosticReport.serverSize(of: .object(["a": .integer(1), "b": .integer(2)])), 16)
    }

    func testSmallPayloadIsUntouched() {
        let payload: AnyJSON = .object(["callStackTree": .string("short")])
        XCTAssertEqual(DiagnosticReport.fitted(payload, limit: 1000), payload)
    }

    func testOversizePayloadIsCutToValidJSONWithinTheLimitKeepingMetadata() throws {
        let metadata: AnyJSON = .object(["osVersion": .string("iPhone OS 26.0"), "appBuildVersion": .string("7")])
        let big: AnyJSON = .object([
            "diagnosticMetaData": metadata,
            "callStackTree": .string(String(repeating: "frame,", count: 20_000)),   // 120 KB
        ])
        let limit = DiagnosticReport.maxPayloadBytes
        XCTAssertGreaterThan(DiagnosticReport.serverSize(of: big), limit)

        let fitted = DiagnosticReport.fitted(big, limit: limit)
        XCTAssertLessThanOrEqual(DiagnosticReport.serverSize(of: fitted), limit)
        guard case let .object(object) = fitted else { return XCTFail("not an object: \(fitted)") }
        XCTAssertEqual(object["truncated"], .bool(true))
        XCTAssertEqual(object["original_bytes"], .integer(DiagnosticReport.serverSize(of: big)))
        XCTAssertEqual(object["diagnosticMetaData"], metadata)
        let head = try XCTUnwrap(object["head"]?.stringValue)
        XCTAssertFalse(head.isEmpty)
        // It round-trips as JSON, which a cut-off JSON string would not.
        let data = try JSONEncoder().encode(fitted)
        XCTAssertEqual(try JSONDecoder().decode(AnyJSON.self, from: data), fitted)
    }

    func testMakeAppliesTheLimit() throws {
        let json = Data(("{\"callStackTree\":\"" + String(repeating: "x", count: 100_000) + "\"}").utf8)
        let row = try XCTUnwrap(DiagnosticReport.make(kind: .cpu, json: json, appVersion: nil, build: nil,
                                                      osVersion: nil, device: nil))
        XCTAssertLessThanOrEqual(DiagnosticReport.serverSize(of: row.payload), DiagnosticReport.maxPayloadBytes)
        XCTAssertLessThan(DiagnosticReport.maxPayloadBytes, 65_536, "the phone must stop under the server's 64 KB")
    }

    // MARK: - The waiting file

    func testPendingFileRoundTrip() {
        XCTAssertEqual(store.load(), [])
        let rows = [report(1), report(2, kind: .launch)]
        store.append(rows)
        XCTAssertEqual(store.load(), rows)
        store.remove(rows[0].id)
        XCTAssertEqual(store.load(), [rows[1]])
        store.remove(rows[1].id)
        XCTAssertEqual(store.load(), [])
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.directory.appendingPathComponent("pending.json").path))
    }

    func testPendingFileKeepsTheNewestTwenty() {
        let rows = (1...25).map { report($0) }
        store.append(rows)
        XCTAssertEqual(store.load(), Array(rows.suffix(20)))
    }

    func testPendingDirectoryIsExcludedFromBackup() throws {
        store.append([report(1)])
        let values = try store.directory.resourceValues(forKeys: [.isExcludedFromBackupKey])
        XCTAssertEqual(values.isExcludedFromBackup, true)
    }

    func testAFileThatDoesNotDecodeIsEmpty() throws {
        try FileManager.default.createDirectory(at: store.directory, withIntermediateDirectories: true)
        try Data("garbage".utf8).write(to: store.directory.appendingPathComponent("pending.json"))
        XCTAssertEqual(store.load(), [])
    }

    func testRepeatedUnreadableFailuresDropTheRow() {
        let row = report(1)
        store.append([row])
        for _ in 1..<DiagnosticReport.maxAttempts { store.recordAttempt(row.id) }
        XCTAssertEqual(store.load().first?.attempts, DiagnosticReport.maxAttempts - 1)
        store.recordAttempt(row.id)
        XCTAssertEqual(store.load(), [])
    }

    // MARK: - What a send's failure means

    func testOutcomes() {
        XCTAssertEqual(DiagnosticSendOutcome.after(URLError(.notConnectedToInternet)), .keep)
        XCTAssertEqual(DiagnosticSendOutcome.after(URLError(.timedOut)), .keep)
        XCTAssertEqual(DiagnosticSendOutcome.after(PostgrestError(code: "P0001", message: "too_many_reports")), .drop)
        XCTAssertEqual(DiagnosticSendOutcome.after(PostgrestError(code: "22023", message: "payload_too_large")), .drop)
        XCTAssertEqual(DiagnosticSendOutcome.after(PostgrestError(code: "22023", message: "invalid_kind")), .drop)
        XCTAssertEqual(DiagnosticSendOutcome.after(PostgrestError(code: "42501", message: "not_authenticated")), .keep)
        XCTAssertEqual(DiagnosticSendOutcome.after(PostgrestError(code: "P0002", message: "account_not_found")), .keep)
        // A gateway body with no code never reached the database.
        XCTAssertEqual(DiagnosticSendOutcome.after(PostgrestError(message: "upstream timeout")), .keep)
    }

    // MARK: - The outbox

    func testSignedOutSendsNothingAndKeepsEverything() async {
        let sent = Sent()
        let outbox = DiagnosticsOutbox(store: store, isSignedIn: { false }, send: { await sent.add($0) })
        await outbox.enqueue([report(1)])
        let count = await sent.rows.count
        XCTAssertEqual(count, 0)
        XCTAssertEqual(store.load().count, 1)
    }

    func testSignedInSendsAndEmptiesTheFile() async {
        let sent = Sent()
        let outbox = DiagnosticsOutbox(store: store, isSignedIn: { true }, send: { await sent.add($0) })
        let rows = [report(1), report(2)]
        await outbox.enqueue(rows)
        let got = await sent.rows
        XCTAssertEqual(got, rows)
        XCTAssertEqual(store.load(), [])
    }

    func testOfflineKeepsTheRowsForNextTime() async {
        let outbox = DiagnosticsOutbox(store: store, isSignedIn: { true }, send: { _ in throw URLError(.notConnectedToInternet) })
        let rows = [report(1), report(2)]
        await outbox.enqueue(rows)
        XCTAssertEqual(store.load(), rows)   // attempts not counted for no answer
    }

    func testTooManyReportsIsDroppedSilently() async {
        let outbox = DiagnosticsOutbox(store: store, isSignedIn: { true },
                                       send: { _ in throw PostgrestError(code: "P0001", message: "too_many_reports") })
        await outbox.enqueue([report(1), report(2)])
        XCTAssertEqual(store.load(), [])
    }

    func testARowQueuedDuringASendIsKept() async {
        let late = report(99)
        let store = self.store!
        let outbox = DiagnosticsOutbox(store: store, isSignedIn: { true }, send: { row in
            // MetricKit delivering more while the first send is on the wire.
            if row.payload == .object(["n": .integer(1)]) { store.append([late]) }
            throw URLError(.timedOut)
        })
        await outbox.enqueue([report(1)])
        XCTAssertEqual(store.load().map(\.id).last, late.id)
        XCTAssertEqual(store.load().count, 2)
    }
}

private actor Sent {
    var rows: [DiagnosticReport] = []
    func add(_ row: DiagnosticReport) { rows.append(row) }
}
