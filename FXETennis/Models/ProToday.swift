//
//  ProToday.swift
//  FXETennis
//
//  What a pro sees on the Today tab (decision 0025), and the pure rules the
//  screen applies to it, kept apart from the network so they are unit-tested
//  (ProTodayTests).
//
//  Tara, 2026-09-28: "Let the pros see who is coming to the clinics that day.
//  I don't want the pros to invite people from the player pool. See anything
//  financial at all." So the row below is the whole contract, and it matches
//  pro_today()'s columns one for one: no price, no paid flag, no charge, no
//  note, no phone or email, no Player Pool. The database decides what a pro
//  may read; this type only decodes it.
//

import Foundation

/// One row of pro_today(): one You're In! registration, or, for a clinic
/// nobody is in yet, the clinic alone with every registration field nil.
struct ProTodayRow: Decodable, Sendable, Equatable {
    let clinicId: UUID
    let clinicName: String
    let startsAt: Date
    let endsAt: Date
    let registrationId: UUID?
    let firstName: String?
    let lastName: String?
    let courtNumber: Int?
    let noShow: Bool?
    let lateCancel: Bool?

    enum CodingKeys: String, CodingKey {
        case clinicId = "clinic_id"
        case clinicName = "clinic_name"
        case startsAt = "starts_at"
        case endsAt = "ends_at"
        case registrationId = "registration_id"
        case firstName = "first_name"
        case lastName = "last_name"
        case courtNumber = "court_number"
        case noShow = "no_show"
        case lateCancel = "late_cancel"
    }
}

/// A player on a pro's list: someone You're In! for one of today's clinics.
struct ProTodayPlayer: Identifiable, Sendable, Equatable {
    /// The registration's id: what the two pro actions act on.
    let id: UUID
    let firstName: String
    let lastName: String
    let court: Int?
    let noShow: Bool

    var name: String { "\(firstName) \(lastName)" }
}

/// One of today's clinics and who is coming.
struct ProTodayClinic: Identifiable, Sendable, Equatable {
    let id: UUID
    let name: String
    let startsAt: Date
    let endsAt: Date
    var players: [ProTodayPlayer]
}

enum ProToday {

    /// The flat rows as clinics, earliest first, each with its players in
    /// court order (no court last, then by last and first name): the same
    /// order as Tara's court sheet on her roster. The server sorts too; this
    /// does not rely on it.
    static func group(_ rows: [ProTodayRow]) -> [ProTodayClinic] {
        var clinics: [UUID: ProTodayClinic] = [:]
        for row in rows {
            var clinic = clinics[row.clinicId]
                ?? ProTodayClinic(id: row.clinicId, name: row.clinicName, startsAt: row.startsAt, endsAt: row.endsAt, players: [])
            if let id = row.registrationId, !clinic.players.contains(where: { $0.id == id }) {
                clinic.players.append(ProTodayPlayer(
                    id: id,
                    firstName: row.firstName ?? "",
                    lastName: row.lastName ?? "",
                    court: row.courtNumber,
                    noShow: row.noShow ?? false))
            }
            clinics[row.clinicId] = clinic
        }
        return clinics.values
            .map { clinic in
                var c = clinic
                c.players.sort(by: courtOrder)
                return c
            }
            .sorted { ($0.startsAt, $0.id.uuidString) < ($1.startsAt, $1.id.uuidString) }
    }

    /// Court 1 to 5 first, then nobody's court; within each, last name, then
    /// first name.
    static func courtOrder(_ a: ProTodayPlayer, _ b: ProTodayPlayer) -> Bool {
        let courtA = a.court ?? Int.max, courtB = b.court ?? Int.max
        if courtA != courtB { return courtA < courtB }
        if a.lastName != b.lastName { return a.lastName < b.lastName }
        return a.firstName < b.firstName
    }

    /// Late cancel is offered where the server would accept it: inside the
    /// cutoff or after the start (registration_mark_late_cancel). Before the
    /// cutoff a cancellation is free, and it is the player's to make.
    static func canLateCancel(startsAt: Date, cutoffHours: Int, now: Date = Date()) -> Bool {
        CancelPolicy.isInsideCutoff(startsAt: startsAt, cutoffHours: cutoffHours, now: now)
    }

    static let changedUnderYou = "That just changed. Here's the latest."
    static let onlyTara = "Only Tara can change this."

    /// The server's refusals to a pro, in words that never mention money.
    /// Once Tara has charged a clinic, every row of it answers a pro
    /// clinic_locked, charged or not (20260928600001), so the answer says
    /// nothing about any one player; charged_refund_first is mapped to the
    /// same words in case it ever reaches a pro, because "Already charged" is
    /// exactly what a pro must not be told.
    static func message(for error: Error) -> String {
        message(forDescription: String(describing: error))
    }

    static func message(forDescription e: String) -> String {
        if e.contains("clinic_locked") || e.contains("charged_refund_first") { return onlyTara }
        if e.contains("not_late_yet") { return "Not late yet." }
        if e.contains("clinic_canceled") { return "That clinic is canceled." }
        if e.contains("registration_not_in") || e.contains("not_today") || e.contains("registration_not_found") {
            return changedUnderYou
        }
        // Demoted from pro while the tab was open: the tab goes at the next
        // profile load; until then, say only what is true.
        if e.contains("not_authorized") { return onlyTara }
        return "That didn't go through. Check your connection and try again."
    }
}
