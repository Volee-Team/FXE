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

/// Tara's Zelle/Venmo payment line (2026-08-02) used to be reproduced here and
/// shown on every clinic's page. Removed 2026-09-26: "Remove all 'pay via
/// zelle' language from the app" (Final Updates p.1; decision 0013 made the
/// card the only way to pay). The string itself stays in
/// app_settings.payment_instructions, unsent, behind zelle_allowed = false.

// MARK: - Catalogue

/// Every notification in Tara's catalogue, with its typed parameters, kept as
/// the record of her wording. The server writes and sends them (first
/// `supabase/migrations/20260728000003_rpcs.sql`; the bodies of #1, #3, #5, #6
/// and the three admin cases are written in her words by
/// `20260928000001_notifications_in_her_words.sql` and pinned character for
/// character by `tests/sql/notification_copy.sql`). The app itself sends only
/// `registrationIsOpen` (RegistrationReminder.swift) and uses the formatters.
/// The type keys, titles and lock-screen measuring that used to sit here were
/// never read and were removed on 2026-11-17 (decision 0059).
enum FXENotification: Sendable {

    // ---------------------------------------------------------- player ----

    /// Fires when a registration lands directly in You're In!, which happens
    /// two ways: a member registering inside the priority window with room
    /// available, and Tara placing someone by hand via `place_player`.
    ///
    /// It does NOT fire when a player accepts an invitation. That path sends
    /// `invitationAccepted` instead. Firing both would push twice for one
    /// event. See docs/notifications.md finding (e).
    ///
    /// Wired 2026-09-28 (20260928000001). From `place_player` only when the
    /// placement is what put them in, in a published clinic that has not
    /// started, and not for a late request Tara approved (`resolve_late_request`
    /// sends its own answer).
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
    /// accepted. Tara separately receives `playerAccepted`. Wired 2026-09-28.
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
    /// Wired 2026-09-28: `register_for_clinic` sends it, nothing else does.
    case addedToPlayerPool

    /// CONTRADICTION (b): fires when Tara removes a player from the Pool. The
    /// guide does cover this ("Tara removes a player: notify the player").
    /// Fixed in two halves: 20260927100002 stopped an admin's removal from
    /// notifying the admins as if the player had canceled, and 20260928000001
    /// sends the player this, from `cancel_registration` by an admin who does
    /// not own the player, for the Pool of a published clinic. Removal from
    /// You're In! still sends nothing: she has no words for it.
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
    // the admin. The SQL writes exactly these since 20260928000001, with the
    // late-fee and note suffixes after playerCanceled's.

    case playerAccepted(player: PlayerRef, clinic: ClinicRef)
    case playerDeclined(player: PlayerRef, clinic: ClinicRef)
    case playerCanceled(player: PlayerRef, clinic: ClinicRef)

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
            return "You've been removed from the Waitlist for \(clinic.name). "
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
            return "\(player.fullName) declined \(clinic.name) and is back on the Waitlist."

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
