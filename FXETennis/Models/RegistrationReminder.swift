//
//  RegistrationReminder.swift
//  FXETennis
//
//  "Remind me" on a clinic that has not opened for this player yet
//  (2026-09-28): a notification on this phone at the moment registration
//  opens to them, members at the clinic's member_opens_at (Thursday 8:00 by
//  the window rule), everyone else at public_opens_at (Friday 8:00). Both are
//  stored on the clinic row, so Tara's override of one clinic is what counts.
//  The same moment ClinicPublic.door switches from "opens" to Register.
//
//  The words are Tara's, verbatim: notification 10, "Registration is LIVE!!
//  Hope to see you on the court" (FXENotification.registrationIsOpen, the
//  one copy of it), under the clinic's name. A tap opens that clinic through
//  the router, like a push: entity_type 'clinic', and no notification_id,
//  because a reminder on this phone is not a row in the bell.
//
//  Opt-in, one clinic at a time, for the person who asked. It is not the
//  broadcast Tara's notification 10 was written for; which window and which
//  audience that would use is still her question (docs/notifications.md (c)).
//
//  Everything here is pure and unit-tested (RegistrationReminderTests); the
//  notification center calls are in App/RegistrationReminders.swift.
//

import Foundation
import UserNotifications

enum RegistrationReminder {

    static let identifierPrefix = "open-"

    /// "open-<clinic id>", one per clinic: setting it again replaces it.
    static func identifier(for clinicId: UUID) -> String {
        identifierPrefix + clinicId.uuidString.lowercased()
    }

    // MARK: - When

    /// When this player's reminder goes off: the moment the clinic opens to
    /// them, while that is still ahead. nil for a canceled clinic, one
    /// already open to them, closed, or started. Rounded up to the whole
    /// second the trigger can express, so it never goes off before the door
    /// opens.
    static func fireDate(for clinic: ClinicPublic, isMember: Bool, now: Date) -> Date? {
        guard case .opens(let opens) = clinic.door(isMember: isMember, now: now) else { return nil }
        return Date(timeIntervalSince1970: opens.timeIntervalSince1970.rounded(.up))
    }

    // MARK: - The button

    /// The page offers "Remind me" unless notifications are off. Home already
    /// says so (NotificationsOffLine), so the page shows nothing new.
    static func offersButton(status: UNAuthorizationStatus) -> Bool {
        status != .denied
    }

    /// A permission under which iOS will show the reminder. Not determined
    /// means ask first.
    static func canSchedule(status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    // MARK: - The notification

    static func request(for clinic: ClinicPublic, at date: Date) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = clinic.name
        content.body = FXENotification.registrationIsOpen.body
        content.sound = .default
        content.userInfo = ["entity_type": "clinic", "entity_id": clinic.id.uuidString.lowercased()]
        return UNNotificationRequest(identifier: identifier(for: clinic.id), content: content,
                                     trigger: UNCalendarNotificationTrigger(dateMatching: components(of: date),
                                                                            repeats: false))
    }

    /// The exact moment, wherever the phone is: the components carry their
    /// zone (UTC), so a player who flies west before Thursday is still
    /// reminded at 8:00 New York, the moment registration opens. Without the
    /// zone, iOS reads them in the phone's current zone (the first red run
    /// fired four hours late on this New York Mac).
    static func components(of date: Date) -> DateComponents {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        var parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        parts.calendar = calendar
        parts.timeZone = calendar.timeZone
        return parts
    }

    // MARK: - What is waiting

    /// One reminder waiting in the notification center, as read back.
    struct Pending: Equatable, Sendable {
        let clinicId: UUID
        let fireDate: Date?
        let title: String
    }

    /// A waiting request, if it is one of these reminders.
    static func pending(from request: UNNotificationRequest) -> Pending? {
        guard request.identifier.hasPrefix(identifierPrefix),
              let clinicId = UUID(uuidString: String(request.identifier.dropFirst(identifierPrefix.count)))
        else { return nil }
        let fires = (request.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate()
        return Pending(clinicId: clinicId, fireDate: fires, title: request.content.title)
    }

    enum Change: Equatable {
        case schedule(ClinicPublic, at: Date)
        case remove(UUID)
    }

    /// What to do with the waiting reminders, given clinics just loaded.
    ///   * the clinic is canceled, already open, or the player now holds a
    ///     spot in it (Tara put her in): remove;
    ///   * its opening moved (Tara's override, or a membership change) or its
    ///     name changed: schedule again at the new moment;
    ///   * the clinic is not in the list: leave it. The list stops five
    ///     weeks out, and no row is not "canceled" (MVP audit item 9).
    /// Never adds a reminder nobody asked for.
    static func changes(pending: [Pending], clinics: [ClinicPublic], registered: Set<UUID>,
                        isMember: Bool, now: Date) -> [Change] {
        pending.compactMap { waiting in
            guard let clinic = clinics.first(where: { $0.id == waiting.clinicId }) else { return nil }
            guard !registered.contains(clinic.id),
                  let wanted = fireDate(for: clinic, isMember: isMember, now: now) else {
                return .remove(clinic.id)
            }
            if waiting.fireDate == wanted && waiting.title == clinic.name { return nil }
            return .schedule(clinic, at: wanted)
        }
    }
}
