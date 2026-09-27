//
//  RegistrationMoments.swift
//  FXETennis
//
//  The moments at which what a player can do with a clinic changes on its
//  own, with nobody pulling to refresh: registration opens for them, it
//  closes, the clinic starts. Screens redraw at each one (a SwiftUI
//  TimelineView), so at Thursday 8:00 the Register button appears on the
//  second (MVP audit item 8, 2026-09-27). Before this, a member waiting on
//  the clinic page saw "Registration opens Thu 8:00 AM" and no button until
//  she pulled, while members who pulled took the seats and the earlier
//  Player Pool places.
//
//  Display only, like `isOpenForRegistration`: register_for_clinic decides.
//

import Foundation

extension ClinicPublic {
    /// This viewer's opening (members Thursday 8:00, everyone Friday 8:00,
    /// per service week, stored on the row), the close, and the start: those
    /// still after `now`, soonest first. None for a canceled clinic, which
    /// has nothing to open.
    func upcomingMoments(isMember: Bool, after now: Date = .now) -> [Date] {
        guard !isCanceled else { return [] }
        let opens = isMember ? memberOpensAt : publicOpensAt
        return [opens, closesAt, startsAt]
            .compactMap { $0 }
            .filter { $0 > now }
            .sorted()
    }
}

enum RedrawSchedule {
    /// A TimelineView schedule for these moments. Each moment is followed by
    /// a second redraw one second later: a screen that compares against the
    /// clock and happened to redraw a hair before the moment would otherwise
    /// wait for the next moment (the close, hours away) to show Register.
    static func at(_ moments: [Date]) -> [Date] {
        Array(Set(moments.flatMap { [$0, $0.addingTimeInterval(1)] })).sorted()
    }
}
