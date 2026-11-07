//
//  ClinicFull.swift
//  FXETennis
//
//  Tara, 2026-11-06 ("Next update", item 5): "Alert admin (me) when clinic is
//  full before I start inviting someone. For example: clinic is 25/25. I
//  invite someone, a message comes up that says 'are you sure you want to
//  invite ___ your clinic is full.'"
//
//  A question, never a refusal: capacity never blocks her (place_player; her
//  for-tara.md answer to question 4). The counts are the ones on her screen.
//

import Foundation

enum ClinicFull {
    /// True when You're In! has reached the clinic's capacity. No capacity set
    /// means no limit, so never full.
    static func isFull(inCount: Int, capacity: Int?) -> Bool {
        guard let capacity else { return false }
        return inCount >= capacity
    }

    /// What she is about to do, in the words on the button she tapped.
    enum Action: Sendable { case invite, moveIn }

    /// "Are you sure you want to invite Jane Doe? Your clinic is full (25/25)."
    static func question(_ action: Action, name: String, inCount: Int, capacity: Int) -> String {
        let what: String
        switch action {
        case .invite: what = "invite \(name)"
        case .moveIn: what = "move \(name) in"
        }
        return "Are you sure you want to \(what)? Your clinic is full (\(inCount)/\(capacity))."
    }

    /// The server's refusals to an invite of someone not on the Waitlist
    /// (admin_invite_player), in words.
    static func inviteError(_ error: Error, name: String) -> String {
        let e = String(describing: error)
        if e.contains("already_registered") { return "\(name) is already on this clinic." }
        if e.contains("clinic_not_published") { return "Publish the clinic first." }
        if e.contains("clinic_ended") { return "That clinic is over." }
        if e.contains("clinic_canceled") { return "That clinic is canceled." }
        if e.contains("player_not_found") { return "That player's account was deleted." }
        if e.contains("waiver_required") { return "\(name) hasn't signed the waiver yet." }
        return "That didn't go through. Check your connection and try again."
    }
}
