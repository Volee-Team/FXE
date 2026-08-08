//
//  NotificationCopy.swift
//  FXETennis
//
//  The single source of truth for every push and in-app notification body.
//
//  ALL PLAYER-FACING COPY BELOW IS TARA'S, VERBATIM (2026-08-02). Do not
//  "improve" it, do not fix its punctuation, do not make it consistent with
//  itself. It is her voice and it is deliberate. The only strings we authored
//  are the admin-facing ones (she said "any sensible wording") and the
//  notification titles, which APNs requires and she did not supply.
//
//  Two constraints she set:
//    1. Every message reads on a lock screen: 1 to 2 sentences.
//    2. Clinic LOCATION must never appear in any player-facing string, in any
//       form. FXE is a member club and it must not read as open to the public.
//       There is no `location` parameter anywhere in this file, by design.
//
//  Also enforced by omission: no message reveals capacity, spots remaining,
//  Player Pool size, another player's name, a court number, or another
//  player's payment status. Those are the nine hidden facts from the guide and
//  they are hidden at the database layer too. Adding a count to a body string
//  here would defeat that, so do not.
//
//  KNOWN CONTRADICTIONS with the FXE Tennis Version 1 Developer Guide are
//  documented in docs/notifications.md and marked `CONTRADICTION (a)` .. `(d)`
//  at the relevant case below. They are NOT resolved here. Read that document
//  before changing any of them.
//

import Foundation

// MARK: - Audience

/// Who a notification is addressed to.
///
/// This is not the same thing as `message_audience` in Postgres, which selects
/// a subset of a clinic's registrants for a Tara-authored clinic message. This
/// is coarser: is the reader a player or is the reader Tara.
enum NotificationAudience: String, Sendable {
    case player
    case admin
}

// MARK: - Typed parameters

/// The minimum a notification body needs to identify a clinic.
///
/// Deliberately carries no location, no capacity, and no registration counts.
/// If a future body needs one of those, that is a design conversation, not a
/// new property.
struct ClinicRef: Hashable, Sendable {
    let name: String
    /// Clinic start, stored as an absolute instant. Rendered in club-local
    /// time, never in the device's time zone: a player travelling out of state
    /// must still read the court time.
    let startsAt: Date

    init(name: String, startsAt: Date) {
        self.name = name
        self.startsAt = startsAt
    }
}

/// A player as Tara reads them in an admin notification. Never sent to another
/// player: other players' names are one of the nine hidden facts.
struct PlayerRef: Hashable, Sendable {
    let firstName: String
    let lastName: String

    var fullName: String { "\(firstName) \(lastName)" }
}

// MARK: - Payment

/// Tara's payment wording, exact and required (2026-08-02). Reproduce this
/// string character for character wherever payment is mentioned. It is not in
/// the payment-reminder push because the push has no room for it: it belongs
/// on Clinic Details and in the persisted in-app message body.
///
/// See docs/notifications.md finding (g): the split between the short push and
/// the full payment line is a decision that still needs Tara's confirmation.
enum FXEPayment {
    static let line = "Payment can be made via zelle to fersctennispro@gmail.com (preferred) or Venmo FXE Tennis"
}

// MARK: - Catalogue

/// Every notification the app can send, with its typed parameters.
///
/// `typeKey` values match the `notifications.type` text column written by the
/// SQL RPCs in `supabase/migrations/20260728000003_rpcs.sql`. The two lists are
/// coupled by hand. If you add a case here, add the matching `notify_account`
/// call there, and vice versa.
enum FXENotification: Sendable {

    // ---------------------------------------------------------- player ----

    /// Fires when a registration lands directly in You're In!, which happens
    /// two ways: a member registering inside the priority window with room
    /// available, and Tara placing someone by hand via `place_player`.
    ///
    /// It does NOT fire when a player accepts an invitation. That path sends
    /// `invitationAccepted` instead. Firing both would push twice for one
    /// event. See docs/notifications.md finding (e).
    case youreIn(clinic: ClinicRef)

    /// Fires from `invite_from_pool`, when Tara picks a specific player out of
    /// the Player Pool and the registration moves to Response Needed.
    ///
    /// CONTRADICTION (a): the copy promises an expiry ("before it expires")
    /// and there is a matching `invitationExpired` case, but the guide states
    /// invitations do not auto-expire in Version 1 and lists "Automatic
    /// invitation expiration" under Not in Version 1. Unresolved. The copy is
    /// shipped as written; nothing in the system currently expires anything.
    ///
    /// "Tap below" requires an actionable push with Accept and Decline
    /// buttons, which is an APNs notification category, not a plain alert.
    /// That part is consistent with the guide.
    case invitationReceived(clinic: ClinicRef)

    /// Fires from `respond_to_invitation(accept: true)`, to the player who
    /// accepted. Tara separately receives `playerAccepted`.
    case invitationAccepted

    /// CONTRADICTION (a), continued. There is no expiry mechanism, so today
    /// the only event that could plausibly emit this is Tara manually calling
    /// `cancel_invitation`, which currently notifies nobody at all. Wiring it
    /// there is the cheap reading of her intent, but it makes the word
    /// "expired" a euphemism for "Tara took it back". Her decision.
    case invitationExpired

    /// Fires when a registration lands in Player Pool ON FIRST REGISTRATION
    /// only. Player Pool is also reached by declining an invitation and by
    /// Tara cancelling one, and "Thanks for registering!" is wrong for both.
    /// The trigger is narrowed on purpose. See docs/notifications.md finding (i).
    case addedToPlayerPool

    /// CONTRADICTION (b): fires when Tara removes a player from the Pool. The
    /// guide does cover this ("Tara removes a player: notify the player"), and
    /// the schema supports it, but `cancel_registration` currently notifies
    /// only the admins, never the player, whoever triggered it. That is a real
    /// defect this copy exposes.
    case removedFromPlayerPool(clinic: ClinicRef)

    /// Fires from `cancel_clinic`, to everyone in a live status: You're In!,
    /// Player Pool, and Response Needed.
    ///
    /// CONTRADICTION (d): Tara's sentence hardcodes both "today's" and "due to
    /// weather". Neither is always true. `reason` is a parameter whose default
    /// reproduces her sentence exactly, so the default path is verbatim and a
    /// different reason is expressible. "today's" is left hardcoded and is NOT
    /// resolved: a clinic cancelled three days out will read wrong. Her call.
    case clinicCanceled(clinic: ClinicRef, reason: String = "weather")

    /// Fires from the unpaid-reminder button, to registrations with
    /// `paid = false`. Never states a balance, never names anyone else.
    case paymentReminder(clinic: ClinicRef)

    /// Fires from `publish_news`, to the accounts matching the post's audience.
    /// The body is intentionally content-free: the title and body of the post
    /// live on the News screen, and the push is only a nudge to open it.
    case newAnnouncement

    /// CONTRADICTION (c): a broadcast at registration-window open. Nothing in
    /// the design has a scheduler, so this case has no trigger today. It also
    /// does not say WHICH window opened, and there are two per clinic (member
    /// Thursday, public Friday). Shipped as copy only until that is decided.
    case registrationIsOpen

    /// Fires from `cancel_registration` when the PLAYER cancelled their own
    /// registration. Confirms an action they just took in the app, so it is a
    /// weak candidate for a push. See docs/notifications.md finding (h).
    case registrationCanceled(clinic: ClinicRef)

    /// A clinic message Tara composed herself, passed straight through. There
    /// is no catalogue copy for this because the body IS the copy. Present so
    /// that every row written to `notifications` is representable here.
    case clinicMessage(body: String)

    // ----------------------------------------------------------- admin ----
    //
    // Tara: "Notifications to Tara herself: any sensible wording." These are
    // ours. They name a player, which is allowed only because the reader is
    // the admin.

    case playerAccepted(player: PlayerRef, clinic: ClinicRef)
    case playerDeclined(player: PlayerRef, clinic: ClinicRef)
    case playerCanceled(player: PlayerRef, clinic: ClinicRef)

    // MARK: Audience

    var audience: NotificationAudience {
        switch self {
        case .youreIn, .invitationReceived, .invitationAccepted, .invitationExpired,
             .addedToPlayerPool, .removedFromPlayerPool, .clinicCanceled,
             .paymentReminder, .newAnnouncement, .registrationIsOpen,
             .registrationCanceled, .clinicMessage:
            return .player
        case .playerAccepted, .playerDeclined, .playerCanceled:
            return .admin
        }
    }

    // MARK: Type key

    /// Persisted in `notifications.type`. Stable string, safe to key analytics
    /// and deep links off. Changing one of these is a migration, not an edit.
    var typeKey: String {
        switch self {
        case .youreIn:               return "youre_in"
        case .invitationReceived:    return "invitation_received"
        case .invitationAccepted:    return "invitation_accepted_player"
        case .invitationExpired:     return "invitation_expired"
        case .addedToPlayerPool:     return "added_to_pool"
        case .removedFromPlayerPool: return "removed_from_pool"
        case .clinicCanceled:        return "clinic_canceled"
        case .paymentReminder:       return "payment_reminder"
        case .newAnnouncement:       return "news_published"
        case .registrationIsOpen:    return "registration_open"
        case .registrationCanceled:  return "registration_canceled"
        case .clinicMessage:         return "clinic_message"
        case .playerAccepted:        return "invitation_accepted"
        case .playerDeclined:        return "invitation_declined"
        case .playerCanceled:        return "player_canceled"
        }
    }

    // MARK: Trigger

    /// The event that emits this notification, in one line, as documentation.
    /// Kept next to the copy so the two cannot drift apart in review.
    var trigger: String {
        switch self {
        case .youreIn:
            return "Registration resolves to You're In!, by member priority or by Tara placing the player."
        case .invitationReceived:
            return "Tara invites a player from the Player Pool (invite_from_pool)."
        case .invitationAccepted:
            return "Player accepts an invitation (respond_to_invitation, accept)."
        case .invitationExpired:
            return "NOT WIRED. No expiry mechanism exists. See contradiction (a)."
        case .addedToPlayerPool:
            return "First registration resolves to Player Pool. Not on decline, not on invitation cancel."
        case .removedFromPlayerPool:
            return "Tara removes a pooled player (admin cancel_registration)."
        case .clinicCanceled:
            return "Tara cancels a clinic (cancel_clinic). Sent to You're In!, Player Pool, and Response Needed."
        case .paymentReminder:
            return "Tara taps the unpaid reminder. Sent only to registrations with paid = false."
        case .newAnnouncement:
            return "Tara publishes a news post (publish_news), to the matching audience."
        case .registrationIsOpen:
            return "NOT WIRED. Requires a scheduled job at window open. See contradiction (c)."
        case .registrationCanceled:
            return "Player cancels their own registration (cancel_registration by the owner)."
        case .clinicMessage:
            return "Tara sends a clinic message (send_clinic_message), to the chosen audience."
        case .playerAccepted:
            return "Player accepts an invitation. Sent to every admin."
        case .playerDeclined:
            return "Player declines an invitation. Sent to every admin."
        case .playerCanceled:
            return "Player cancels a registration. Sent to every admin, and raises Action Needed."
        }
    }

    // MARK: Title

    /// APNs requires a title. Tara did not supply these, so they are ours and
    /// they are placeholders pending her review. Kept short: the title steals
    /// lock-screen room from her body copy.
    var title: String {
        switch self {
        case .youreIn:               return "You're In!"
        case .invitationReceived:    return "Spot Available"
        case .invitationAccepted:    return "You're In!"
        case .invitationExpired:     return "Invitation Expired"
        case .addedToPlayerPool:     return "Player Pool"
        case .removedFromPlayerPool: return "Player Pool"
        case .clinicCanceled:        return "Clinic Canceled"
        case .paymentReminder:       return "Payment Reminder"
        case .newAnnouncement:       return "FXE Tennis"
        case .registrationIsOpen:    return "Registration Open"
        case .registrationCanceled:  return "Registration Canceled"
        case .clinicMessage:         return "FXE Tennis"
        case .playerAccepted:        return "Invitation Accepted"
        case .playerDeclined:        return "Invitation Declined"
        case .playerCanceled:        return "Player Canceled"
        }
    }

    // MARK: Body

    /// The notification body. Player-facing strings are Tara's, verbatim.
    var body: String {
        switch self {

        case let .youreIn(clinic):
            return "You're all set for \(clinic.name) on \(Self.day(clinic.startsAt)) at "
                + "\(Self.time(clinic.startsAt)). Looking forward to seeing you on court!"

        case let .invitationReceived(clinic):
            // No terminal period in her draft. Left as written.
            return "Good News! A spot is available for \(clinic.name). Tap below to accept before it expires"

        case .invitationAccepted:
            return "Awesome! Your spot is confirmed. See you soon!"

        case .invitationExpired:
            return "Your invitation has expired, but we hope to see you next time!"

        case .addedToPlayerPool:
            // First person singular is deliberate. Tara speaks as herself here.
            return "Thanks for registering! I personally create each clinic based on playing levels "
                + "and will send confirmations once lineups are set ASAP"

        case let .removedFromPlayerPool(clinic):
            return "You've been removed from the Player Pool for \(clinic.name). "
                + "Hope to see you at another clinic soon!"

        case let .clinicCanceled(clinic, reason):
            // Default reason "weather" reproduces her sentence exactly.
            return "Unfortunately today's \(clinic.name) has been canceled due to \(reason)."

        case let .paymentReminder(clinic):
            // Her placeholder is "(Clinic name and date)", so both go in.
            return "Just a quick reminder for payment from \(clinic.name) on "
                + "\(Self.date(clinic.startsAt)). Thank you!"

        case .newAnnouncement:
            return "News from FXE!"

        case .registrationIsOpen:
            return "Registration is LIVE!! Hope to see you on the court"

        case let .registrationCanceled(clinic):
            return "You've canceled your registration for \(clinic.name). "
                + "Hope to see you back on the court soon!"

        case let .clinicMessage(body):
            return body

        case let .playerAccepted(player, clinic):
            return "\(player.fullName) accepted their spot in \(clinic.name)."

        case let .playerDeclined(player, clinic):
            return "\(player.fullName) declined \(clinic.name) and is back in the Player Pool."

        case let .playerCanceled(player, clinic):
            return "\(player.fullName) canceled \(clinic.name)."
        }
    }
}

// MARK: - Club-local formatting

extension FXENotification {

    /// Every clinic time in every notification renders in club-local time.
    /// A fixed offset would break twice a year, so the zone is named.
    static let clubTimeZone = TimeZone(identifier: "America/New_York")!

    private static func formatter(_ format: String) -> DateFormatter {
        let f = DateFormatter()
        // POSIX locale so the format string is interpreted literally rather
        // than being re-ordered by the device's regional settings.
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = clubTimeZone
        f.dateFormat = format
        return f
    }

    /// "Thursday"
    static func day(_ date: Date) -> String { formatter("EEEE").string(from: date) }

    /// "9:00 AM"
    static func time(_ date: Date) -> String { formatter("h:mm a").string(from: date) }

    /// "Aug 7"
    static func date(_ date: Date) -> String { formatter("MMM d").string(from: date) }
}

// MARK: - Lock-screen budget

extension FXENotification {

    /// Characters of body text that survive on a collapsed iOS lock-screen
    /// banner before the system truncates. Two lines at typical Dynamic Type.
    /// Approximate by nature: treat it as a review threshold, not a hard gate.
    static let lockScreenBudget = 140

    /// Sentence count, counting a run of terminators ("LIVE!!") as one.
    ///
    /// Tara's stated rule is 1 to 2 sentences. Two of her own drafts are three
    /// short sentences, so this is reported, never enforced. The operative
    /// constraint is `characterCount`, which is what actually truncates.
    var sentenceCount: Int {
        var count = 0
        var inTerminatorRun = false
        var sawText = false
        for character in body {
            if character == "." || character == "!" || character == "?" {
                if !inTerminatorRun && sawText {
                    count += 1
                    sawText = false
                }
                inTerminatorRun = true
            } else {
                inTerminatorRun = false
                if !character.isWhitespace { sawText = true }
            }
        }
        // A trailing fragment with no terminator is still a sentence, which is
        // how her INVITATION RECEIVED and REGISTRATION IS OPEN drafts end.
        if sawText { count += 1 }
        return count
    }

    var characterCount: Int { body.count }

    var fitsLockScreen: Bool { characterCount <= Self.lockScreenBudget }
}

// MARK: - Test surface

extension FXENotification {

    /// One instance of every case, with fixed sample data, so a unit test can
    /// assert the lock-screen budget across the whole catalogue without the
    /// test having to know how to build each case.
    ///
    /// Sample clinic name is deliberately long-ish. A short name would hide a
    /// truncation problem that a real name such as "Tuesday Night Ladies
    /// Cardio Tennis" would expose.
    static func catalogueSamples(
        clinic: ClinicRef = ClinicRef(
            name: "Ladies Cardio Tennis",
            // 2026-08-06 09:00 America/New_York, a Thursday. Chosen inside EDT
            // so a formatter that silently fell back to UTC would render
            // "1:00 PM" and fail the test loudly.
            startsAt: Date(timeIntervalSince1970: 1_786_021_200)
        ),
        player: PlayerRef = PlayerRef(firstName: "Jake", lastName: "Miller")
    ) -> [FXENotification] {
        [
            .youreIn(clinic: clinic),
            .invitationReceived(clinic: clinic),
            .invitationAccepted,
            .invitationExpired,
            .addedToPlayerPool,
            .removedFromPlayerPool(clinic: clinic),
            .clinicCanceled(clinic: clinic),
            .paymentReminder(clinic: clinic),
            .newAnnouncement,
            .registrationIsOpen,
            .registrationCanceled(clinic: clinic),
            .clinicMessage(body: "Courts are wet. We start 15 minutes late."),
            .playerAccepted(player: player, clinic: clinic),
            .playerDeclined(player: player, clinic: clinic),
            .playerCanceled(player: player, clinic: clinic)
        ]
    }
}
