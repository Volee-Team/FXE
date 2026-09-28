//
//  RegistrationReminderTests.swift
//  FXETennisTests
//
//  "Remind me" (2026-09-28). The rule: the reminder goes off at the moment
//  registration opens for THIS player, members at their Thursday 8:00
//  opening, everyone else at the Friday 8:00 one (CLAUDE.md, the window rule;
//  both stored on the clinic row, so Tara's override is what counts). None
//  once it is open, when the moment is past, or for a canceled clinic. Its
//  words are Tara's, verbatim (notification 10, docs/notifications.md), and a
//  tap opens the clinic through the same router as a push.
//
//  Expected dates worked by hand for the week of Sunday 2026-10-04: members
//  Thu 10-01 08:00 EDT = 12:00Z, public Fri 10-02 08:00 EDT = 12:00Z; a
//  Tuesday 18:00 EDT clinic starts 22:00Z and closes 3 hours before, 19:00Z.
//

import XCTest
import UserNotifications
@testable import FXETennis

final class RegistrationReminderTests: XCTestCase {
    private let iso = ISO8601DateFormatter()
    private func at(_ s: String) -> Date { iso.date(from: s)! }
    private let clinicId = UUID(uuidString: "d0000000-0000-0000-0000-000000000005")!

    private var memberOpens: Date { at("2026-10-01T12:00:00Z") }
    private var publicOpens: Date { at("2026-10-02T12:00:00Z") }
    private var wednesday: Date { at("2026-09-30T16:00:00Z") }

    private func clinic(name: String = "Tuesday Ladies 3.0+", status: String = "published",
                        memberOpensAt: Date? = nil, publicOpensAt: Date? = nil,
                        startsAt: Date? = nil) -> ClinicPublic {
        let starts = startsAt ?? at("2026-10-06T22:00:00Z")
        return ClinicPublic(id: clinicId, name: name, audience: "ladies", category: nil,
                            description: "Drills and points.", startsAt: starts,
                            endsAt: starts.addingTimeInterval(5400),
                            memberOpensAt: memberOpensAt ?? memberOpens,
                            publicOpensAt: publicOpensAt ?? publicOpens,
                            closesAt: starts.addingTimeInterval(-3 * 3600), status: status, canceledAt: nil,
                            memberPriceCents: 2200, nonmemberPriceCents: 2800, durationMinutes: 90)
    }

    // MARK: - when it goes off

    func testAMemberIsRemindedAtThursdayEight() {
        XCTAssertEqual(RegistrationReminder.fireDate(for: clinic(), isMember: true, now: wednesday),
                       at("2026-10-01T12:00:00Z"))
    }

    func testANonMemberIsRemindedAtFridayEightNotThursday() {
        XCTAssertEqual(RegistrationReminder.fireDate(for: clinic(), isMember: false, now: wednesday),
                       at("2026-10-02T12:00:00Z"))
    }

    func testOnceOpenForThisPlayerThereIsNothingToRemind() {
        let thursdayNine = at("2026-10-01T13:00:00Z")
        XCTAssertNil(RegistrationReminder.fireDate(for: clinic(), isMember: true, now: thursdayNine))
        // Still a day away for a non-member at the same moment.
        XCTAssertEqual(RegistrationReminder.fireDate(for: clinic(), isMember: false, now: thursdayNine),
                       at("2026-10-02T12:00:00Z"))
    }

    func testAtEightOClockItIsAlreadyOpen() {
        XCTAssertNil(RegistrationReminder.fireDate(for: clinic(), isMember: true, now: memberOpens))
    }

    func testAMomentInThePastIsNeverScheduled() {
        let saturday = at("2026-10-03T14:00:00Z")
        XCTAssertNil(RegistrationReminder.fireDate(for: clinic(), isMember: true, now: saturday))
        XCTAssertNil(RegistrationReminder.fireDate(for: clinic(), isMember: false, now: saturday))
        let afterTheStart = at("2026-10-06T23:00:00Z")
        XCTAssertNil(RegistrationReminder.fireDate(for: clinic(), isMember: false, now: afterTheStart))
    }

    func testACanceledClinicIsNeverRemindedOf() {
        XCTAssertNil(RegistrationReminder.fireDate(for: clinic(status: "canceled"), isMember: true, now: wednesday))
        XCTAssertNil(RegistrationReminder.fireDate(for: clinic(status: "canceled"), isMember: false, now: wednesday))
    }

    func testTarasOverrideOnTheRowIsWhatCounts() {
        // She moved this clinic's member opening to Wednesday 10:00 EDT.
        let moved = clinic(memberOpensAt: at("2026-09-30T14:00:00Z"))
        XCTAssertEqual(RegistrationReminder.fireDate(for: moved, isMember: true, now: at("2026-09-29T12:00:00Z")),
                       at("2026-09-30T14:00:00Z"))
    }

    func testTheReminderIsNeverBeforeTheDoorOpens() {
        // A stored moment with a fraction of a second: the reminder is the
        // next whole second, never the one before.
        let odd = clinic(memberOpensAt: at("2026-10-01T12:00:00Z").addingTimeInterval(0.4))
        XCTAssertEqual(RegistrationReminder.fireDate(for: odd, isMember: true, now: wednesday),
                       at("2026-10-01T12:00:01Z"))
    }

    // MARK: - the button

    func testDeniedShowsNothingNew() {
        XCTAssertFalse(RegistrationReminder.offersButton(status: .denied),
                       "Home already has the notifications-off line")
        XCTAssertTrue(RegistrationReminder.offersButton(status: .notDetermined), "asks first, then schedules")
        XCTAssertTrue(RegistrationReminder.offersButton(status: .authorized))
        XCTAssertTrue(RegistrationReminder.offersButton(status: .provisional))
    }

    func testOnlyAPermissionThatDeliversCanSchedule() {
        XCTAssertTrue(RegistrationReminder.canSchedule(status: .authorized))
        XCTAssertTrue(RegistrationReminder.canSchedule(status: .provisional))
        XCTAssertTrue(RegistrationReminder.canSchedule(status: .ephemeral))
        XCTAssertFalse(RegistrationReminder.canSchedule(status: .notDetermined))
        XCTAssertFalse(RegistrationReminder.canSchedule(status: .denied))
    }

    // MARK: - the notification

    func testTheReminderSaysTarasWordsAndOpensTheClinic() {
        let request = RegistrationReminder.request(for: clinic(), at: memberOpens)
        XCTAssertEqual(request.identifier, "open-d0000000-0000-0000-0000-000000000005")
        XCTAssertEqual(request.content.title, "Tuesday Ladies 3.0+")
        XCTAssertEqual(request.content.body, "Registration is LIVE!! Hope to see you on the court",
                       "Tara's notification 10, verbatim: no period, two exclamation marks")
        XCTAssertEqual(request.content.userInfo["entity_type"] as? String, "clinic")
        XCTAssertEqual(request.content.userInfo["entity_id"] as? String, "d0000000-0000-0000-0000-000000000005")
        XCTAssertNil(request.content.userInfo["notification_id"], "a local reminder is not a row in the bell")
        let tap = PushTap(userInfo: request.content.userInfo)
        XCTAssertEqual(tap.target, .clinic(clinicId))
        XCTAssertNil(tap.notificationId)
    }

    func testNothingInTheReminderIsHidden() {
        let content = RegistrationReminder.request(for: clinic(), at: memberOpens).content
        // Hard rule 1: the only words are the clinic's name and Tara's line.
        XCTAssertEqual(content.subtitle, "")
        XCTAssertFalse(content.body.contains("Drills"), "no description")
        XCTAssertEqual(Set(content.userInfo.keys.compactMap { $0 as? String }), ["entity_type", "entity_id"])
    }

    /// The trigger goes off at the exact moment wherever the phone is: this
    /// Mac is in New York, so a trigger that read its components in the
    /// device's zone would be hours off here.
    func testTheTriggerFiresAtTheExactMoment() throws {
        let moment = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 3 * 86_400).rounded(.down))
        let request = RegistrationReminder.request(for: clinic(), at: moment)
        let trigger = try XCTUnwrap(request.trigger as? UNCalendarNotificationTrigger)
        XCTAssertFalse(trigger.repeats)
        XCTAssertEqual(trigger.nextTriggerDate(), moment)
    }

    // MARK: - reading back what is waiting

    func testAWaitingReminderReadsBack() {
        let moment = Date(timeIntervalSince1970: (Date().timeIntervalSince1970 + 3 * 86_400).rounded(.down))
        let pending = RegistrationReminder.pending(from: RegistrationReminder.request(for: clinic(), at: moment))
        XCTAssertEqual(pending, .init(clinicId: clinicId, fireDate: moment, title: "Tuesday Ladies 3.0+"))
    }

    func testOtherNotificationsAreNotReminders() {
        let other = UNNotificationRequest(identifier: "answer-e0000000-0000-0000-0000-000000000001",
                                          content: UNMutableNotificationContent(), trigger: nil)
        XCTAssertNil(RegistrationReminder.pending(from: other))
        let garbled = UNNotificationRequest(identifier: "open-not-a-uuid", content: UNMutableNotificationContent(),
                                            trigger: nil)
        XCTAssertNil(RegistrationReminder.pending(from: garbled))
    }

    // MARK: - keeping waiting reminders true

    private func waiting(at date: Date, title: String = "Tuesday Ladies 3.0+") -> RegistrationReminder.Pending {
        .init(clinicId: clinicId, fireDate: date, title: title)
    }

    func testAnUnchangedReminderIsLeftAlone() {
        XCTAssertEqual(RegistrationReminder.changes(pending: [waiting(at: memberOpens)], clinics: [clinic()],
                                                    registered: [], isMember: true, now: wednesday), [])
    }

    func testAMovedOpeningMovesTheReminder() {
        let moved = clinic(memberOpensAt: at("2026-10-01T14:00:00Z"))
        XCTAssertEqual(RegistrationReminder.changes(pending: [waiting(at: memberOpens)], clinics: [moved],
                                                    registered: [], isMember: true, now: wednesday),
                       [.schedule(moved, at: at("2026-10-01T14:00:00Z"))])
    }

    func testAMembershipChangeMovesTheReminderToTheirOpening() {
        // Scheduled as a member for Thursday; Tara has since set her to non-member.
        XCTAssertEqual(RegistrationReminder.changes(pending: [waiting(at: memberOpens)], clinics: [clinic()],
                                                    registered: [], isMember: false, now: wednesday),
                       [.schedule(clinic(), at: publicOpens)])
    }

    func testACanceledClinicDropsItsReminder() {
        XCTAssertEqual(RegistrationReminder.changes(pending: [waiting(at: memberOpens)],
                                                    clinics: [clinic(status: "canceled")],
                                                    registered: [], isMember: true, now: wednesday),
                       [.remove(clinicId)])
    }

    func testAnAlreadyOpenClinicDropsItsReminder() {
        // Tara moved the opening to a moment that has passed.
        let openNow = clinic(memberOpensAt: at("2026-09-30T12:00:00Z"))
        XCTAssertEqual(RegistrationReminder.changes(pending: [waiting(at: memberOpens)], clinics: [openNow],
                                                    registered: [], isMember: true, now: wednesday),
                       [.remove(clinicId)])
    }

    func testHoldingASpotDropsTheReminder() {
        // Tara put her in by hand before it opened.
        XCTAssertEqual(RegistrationReminder.changes(pending: [waiting(at: memberOpens)], clinics: [clinic()],
                                                    registered: [clinicId], isMember: true, now: wednesday),
                       [.remove(clinicId)])
    }

    func testARenamedClinicIsRescheduledWithItsNewName() {
        let renamed = clinic(name: "Tuesday Ladies 3.5+")
        XCTAssertEqual(RegistrationReminder.changes(pending: [waiting(at: memberOpens)], clinics: [renamed],
                                                    registered: [], isMember: true, now: wednesday),
                       [.schedule(renamed, at: memberOpens)])
    }

    func testAClinicMissingFromTheListIsNotEvidence() {
        // Past the list's five-week horizon, or a load that brought nothing:
        // no row is not "canceled".
        XCTAssertEqual(RegistrationReminder.changes(pending: [waiting(at: memberOpens)], clinics: [],
                                                    registered: [], isMember: true, now: wednesday), [])
    }

    func testNoReminderIsEverAddedThatNobodyAskedFor() {
        XCTAssertEqual(RegistrationReminder.changes(pending: [], clinics: [clinic()],
                                                    registered: [], isMember: true, now: wednesday), [])
    }
}
