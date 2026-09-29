//
//  SnapshotTests.swift
//  FXETennisTests
//
//  Instant open keeps the last good answer on the phone (Snapshot.swift).
//  The rules, written before looking at the store: a snapshot is only ever
//  read back for the person it was saved for; removing them removes every
//  one; a clinic that has ended since is not shown again; a file that no
//  longer decodes is no snapshot at all; and saving one half (the clinic
//  list) never wipes the other half (who this is).
//

import XCTest
@testable import FXETennis

final class SnapshotTests: XCTestCase {

    private var store: SnapshotStore!
    private let maria = UUID()
    private let rob = UUID()

    override func setUp() {
        store = SnapshotStore(directory: FileManager.default.temporaryDirectory
            .appendingPathComponent("SnapshotTests-\(UUID().uuidString)", isDirectory: true))
    }

    override func tearDown() { store.removeAll() }

    private func account(_ id: UUID, _ first: String) -> Account {
        Account(id: id, firstName: first, lastName: "Alvarez", email: "\(first.lowercased())@fxe.test",
                phone: nil, accountType: "adult", role: "member", cardBrand: nil, cardLast4: nil)
    }

    private func clinic(_ name: String, endsAt: Date) -> ClinicPublic {
        ClinicPublic(id: UUID(), name: name, audience: "coed", category: nil, description: nil,
                     startsAt: endsAt.addingTimeInterval(-3600), endsAt: endsAt,
                     memberOpensAt: nil, publicOpensAt: nil, closesAt: nil, status: "published",
                     canceledAt: nil, memberPriceCents: 1800, nonmemberPriceCents: 2300, durationMinutes: 60)
    }

    func testASnapshotComesBackOnlyForThePersonItWasSavedFor() {
        store.update(for: maria) { $0.account = account(maria, "Maria") }
        XCTAssertEqual(store.load(for: maria)?.account?.firstName, "Maria")
        XCTAssertNil(store.load(for: rob), "Rob signing in on Maria's phone must not open on her clinics")
    }

    func testRemoveAllLeavesNothingForAnyone() {
        store.update(for: maria) { $0.account = account(maria, "Maria") }
        store.update(for: rob) { $0.account = account(rob, "Rob") }
        store.removeAll()
        XCTAssertNil(store.load(for: maria))
        XCTAssertNil(store.load(for: rob))
    }

    func testSavingTheListKeepsWhoThisIs() {
        store.update(for: maria) {
            $0.account = account(maria, "Maria")
            $0.waiverAccepted = true
        }
        let tonight = clinic("Evening Coed", endsAt: Date().addingTimeInterval(7200))
        store.update(for: maria) { $0.clinics = [tonight] }
        let back = store.load(for: maria)
        XCTAssertEqual(back?.account?.firstName, "Maria")
        XCTAssertEqual(back?.waiverAccepted, true)
        XCTAssertEqual(back?.clinics.map(\.name), ["Evening Coed"])
    }

    func testAClinicThatHasEndedIsNotShownAgain() {
        let now = ISO8601DateFormatter().date(from: "2026-10-03T23:00:00Z")!
        let ended = clinic("Yesterday", endsAt: now.addingTimeInterval(-60))
        let ahead = clinic("Tomorrow", endsAt: now.addingTimeInterval(86_400))
        var snapshot = Snapshot(userId: maria, savedAt: now)
        snapshot.clinics = [ended, ahead]
        XCTAssertEqual(snapshot.clinicsStillAhead(at: now).map(\.name), ["Tomorrow"])
    }

    func testAFileThatNoLongerDecodesIsNoSnapshot() throws {
        store.update(for: maria) { $0.account = account(maria, "Maria") }
        let file = store.directory.appendingPathComponent("\(maria.uuidString.lowercased()).json")
        try Data("{\"version\": 1, \"userId\": 42}".utf8).write(to: file)
        XCTAssertNil(store.load(for: maria))
    }
}
