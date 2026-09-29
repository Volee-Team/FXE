//
//  Snapshot.swift
//  FXETennis
//
//  Instant open (2026-09-28): the last good answer for the person signed in on
//  this phone, kept so the app opens on their clinics at once and still has
//  something to show with one bar of signal at the courts. The server stays
//  the truth: every launch and every screen still loads fresh and replaces
//  what the snapshot showed, usually within a second.
//
//  WHOSE IT IS. A snapshot is filed under the auth user id and read only for
//  the session stored on this phone, so a shared phone never opens on
//  someone else's clinics. Sign out, a session the server has ended, and
//  account deletion all remove every snapshot (SessionStore). It holds only
//  what the person can already see: their own account and player, their own
//  registrations, and the public schedule from clinics_public. Nothing of
//  the nine hidden facts ever reaches the phone, so nothing of them is here.
//
//  WHERE. Application Support, excluded from backups (a cache has no business
//  in iCloud), written atomically with complete-until-first-unlock
//  protection. A file that no longer decodes (an older app's shape) is
//  treated as no snapshot, never as an error.
//

import Foundation
import Supabase

struct Snapshot: Codable {
    /// Bumped when the shape changes in a way decoding would not catch.
    static let currentVersion = 1

    var version = Snapshot.currentVersion
    var userId: UUID
    var savedAt: Date
    // Who this is (SessionStore).
    var account: Account?
    var players: [PlayerProfile] = []
    var waiverAccepted: Bool?
    var cardConsent: Bool?
    var cardsRequired = false
    // What they saw (ClinicsViewModel).
    var clinics: [ClinicPublic] = []
    var registrations: [MyRegistration] = []

    /// The clinics still worth showing at `now`: clinics_public drops a clinic
    /// once it has ended, and a snapshot from yesterday must not bring one back.
    func clinicsStillAhead(at now: Date) -> [ClinicPublic] {
        clinics.filter { $0.endsAt > now }
    }
}

struct SnapshotStore {
    let directory: URL

    /// The app's store. Tests make their own in a temporary directory.
    static let shared: SnapshotStore = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return SnapshotStore(directory: base.appendingPathComponent("Snapshots", isDirectory: true))
    }()

    private func url(for userId: UUID) -> URL {
        directory.appendingPathComponent("\(userId.uuidString.lowercased()).json")
    }

    func load(for userId: UUID) -> Snapshot? {
        guard let data = try? Data(contentsOf: url(for: userId)),
              let snapshot = try? JSONDecoder().decode(Snapshot.self, from: data),
              snapshot.version == Snapshot.currentVersion,
              snapshot.userId == userId
        else { return nil }
        return snapshot
    }

    /// Read, change, write back; starts a fresh snapshot when there is none.
    func update(for userId: UUID, now: Date = .now, _ change: (inout Snapshot) -> Void) {
        var snapshot = load(for: userId) ?? Snapshot(userId: userId, savedAt: now)
        change(&snapshot)
        snapshot.userId = userId
        snapshot.savedAt = now
        save(snapshot)
    }

    func save(_ snapshot: Snapshot) {
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var dir = directory
            var values = URLResourceValues()
            values.isExcludedFromBackup = true
            try? dir.setResourceValues(values)
            let data = try JSONEncoder().encode(snapshot)
            #if os(iOS)
            try data.write(to: url(for: snapshot.userId), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
            #else
            try data.write(to: url(for: snapshot.userId), options: [.atomic])
            #endif
        } catch {
            // A cache that cannot be written is only a slower next launch.
        }
    }

    /// Every snapshot on this phone, whoever it belonged to.
    func removeAll() {
        try? FileManager.default.removeItem(at: directory)
    }
}

extension SnapshotStore {
    /// Whose snapshot applies now: the user of the session stored on this
    /// phone, read without a network call; nil when signed out.
    static var currentUserId: UUID? { supabase.auth.currentUser?.id }
}
