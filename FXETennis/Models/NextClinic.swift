//
//  NextClinic.swift
//  FXETennis
//
//  The answer to "when's my next clinic?" (Siri, Spotlight and the Shortcuts
//  app; NextClinicIntent). Data and the locked status words only: the
//  clinic's name, its day and time in club time, and You're In!, Player Pool
//  or Response Needed. Nothing about where, ever (hard rule 1, decision 10).
//  Pure, so the rule is unit-tested (NextClinicTests).
//

import Foundation

enum NextClinic {

    /// The soonest clinic this player holds a live spot in (You're In!,
    /// Player Pool or Response Needed) that has not ended and is not canceled.
    static func pick(clinics: [ClinicPublic], registrations: [MyRegistration],
                     now: Date) -> (clinic: ClinicPublic, status: RegistrationStatus)? {
        let live = Dictionary(
            registrations.filter { $0.status != .canceled }.map { ($0.clinicId, $0.status) },
            uniquingKeysWith: { a, _ in a })
        guard let next = clinics
            .filter({ $0.endsAt > now && !$0.isCanceled && live[$0.id] != nil })
            .min(by: { $0.startsAt < $1.startsAt }),
              let status = live[next.id]
        else { return nil }
        return (next, status)
    }

    /// "Saturday Members Only, Sunday, Oct 4 at 4:49 PM. You're In!"
    static func line(for clinic: ClinicPublic, status: RegistrationStatus) -> String {
        let when = "\(FXENotification.day(clinic.startsAt)), \(FXENotification.date(clinic.startsAt)) at \(FXENotification.time(clinic.startsAt))"
        return "\(clinic.name), \(when). \(status.display.label)"
    }

    static let noneLine = "No upcoming clinics."
    static let signedOutLine = "Open FXE Tennis and sign in first."
}
