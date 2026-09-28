//
//  ClinicCalendarEvent.swift
//  FXETennis
//
//  "Add to Calendar" on the clinic page (2026-09-28): offered while the
//  player holds You're In! for a clinic that has not started, and prefilled
//  with the clinic's name, its start and end, in the club's zone.
//
//  Hard rule 1. A calendar entry is player-facing, and it leaves the app: it
//  syncs to other devices, other calendars, sometimes other people. So
//  NOTHING goes in its location, URL or notes. Location is one of the nine
//  hidden facts (Tara's decision 10: FXE is a member club and must not read
//  as open to everyone), and the description stays in the app. The player
//  sees the entry in Apple's editor before it is saved and can add anything
//  she likes there herself; the app adds nothing.
//
//  Pure and unit-tested (ClinicCalendarEventTests); the editor itself is
//  Views/Components/AddToCalendarSheet.swift.
//

import Foundation
import EventKit

enum ClinicCalendarEvent {

    /// Only You're In!, and only before the clinic starts. Not the Pool or
    /// Response Needed (no spot yet), and not a canceled clinic.
    static func offered(status: RegistrationStatus?, clinic: ClinicPublic, now: Date) -> Bool {
        status == .in_ && !clinic.isCanceled && now < clinic.startsAt
    }

    /// The entry the editor opens with. Nothing is saved until the player
    /// taps Add in Apple's editor.
    static func make(for clinic: ClinicPublic, in store: EKEventStore) -> EKEvent {
        let event = EKEvent(eventStore: store)
        event.title = clinic.name
        event.startDate = clinic.startsAt
        event.endDate = clinic.endsAt
        // The club's zone, so a player travelling still reads the court time.
        event.timeZone = ServiceWeek.timeZone
        event.isAllDay = false
        // Deliberately never set (hard rule 1): location, structuredLocation,
        // url, notes.
        return event
    }
}
