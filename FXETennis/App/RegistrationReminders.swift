//
//  RegistrationReminders.swift
//  FXETennis
//
//  The notification center half of "Remind me" (2026-09-28). Every decision
//  is in Models/RegistrationReminder.swift and unit-tested; this file only
//  asks iOS what is waiting, adds, and removes.
//
//  Kept true without anyone watching: Home and the Clinics tab reconcile the
//  waiting reminders every time their list loads (`reconcilesReminders`), and
//  the clinic page does for its one clinic, so a reminder moves when Tara
//  moves an opening, and goes when the clinic is canceled, is already open,
//  or the player holds a spot in it. Sign-out removes them all: on a shared
//  phone the next person must not be reminded of someone else's clinic.
//

import SwiftUI
import UserNotifications

@MainActor
enum RegistrationReminders {
    private static var center: UNUserNotificationCenter { .current() }

    /// Whether a reminder is waiting for this clinic.
    static func isSet(for clinicId: UUID) async -> Bool {
        let identifier = RegistrationReminder.identifier(for: clinicId)
        return await center.pendingNotificationRequests().contains { $0.identifier == identifier }
    }

    /// Schedules the reminder for this player's opening. False when there is
    /// nothing to remind about (already open) or iOS refused it.
    static func set(for clinic: ClinicPublic, isMember: Bool) async -> Bool {
        guard let when = RegistrationReminder.fireDate(for: clinic, isMember: isMember, now: .now) else { return false }
        do {
            try await center.add(RegistrationReminder.request(for: clinic, at: when))
            return true
        } catch {
            return false
        }
    }

    static func cancel(for clinicId: UUID) {
        center.removePendingNotificationRequests(withIdentifiers: [RegistrationReminder.identifier(for: clinicId)])
    }

    /// Moves or drops waiting reminders the clinics just loaded show to be stale.
    static func reconcile(clinics: [ClinicPublic], registered: Set<UUID>, isMember: Bool) async {
        let waiting = await center.pendingNotificationRequests().compactMap(RegistrationReminder.pending(from:))
        guard !waiting.isEmpty else { return }
        let changes = RegistrationReminder.changes(pending: waiting, clinics: clinics, registered: registered,
                                                   isMember: isMember, now: .now)
        for change in changes {
            switch change {
            case .schedule(let clinic, let when):
                try? await center.add(RegistrationReminder.request(for: clinic, at: when))
            case .remove(let clinicId):
                cancel(for: clinicId)
            }
        }
    }

    /// Sign-out: every reminder belonged to the person leaving.
    static func removeAll() async {
        let ours = await center.pendingNotificationRequests()
            .map(\.identifier)
            .filter { $0.hasPrefix(RegistrationReminder.identifierPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: ours)
    }
}

private struct ReminderInputs: Equatable {
    let clinics: [ClinicPublic]
    let registered: Set<UUID>
    let isMember: Bool
}

extension View {
    /// Reconciles waiting "Remind me" reminders with a clinic list each time
    /// it changes (and once when it first appears, which finds nothing to do
    /// with an empty list).
    func reconcilesReminders(clinics: [ClinicPublic], registered: Set<UUID>, isMember: Bool) -> some View {
        task(id: ReminderInputs(clinics: clinics, registered: registered, isMember: isMember)) {
            await RegistrationReminders.reconcile(clinics: clinics, registered: registered, isMember: isMember)
        }
    }
}
