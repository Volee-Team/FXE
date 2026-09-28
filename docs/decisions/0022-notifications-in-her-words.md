# 0022: Tara's notification catalogue, wired in her words

**Date:** 2026-09-28 · **Status:** Active, four defaults pending questions 79, 88, 90 and 91 · **Source:** Tara's catalogue (`docs/notifications.md`), Alex 2026-09-27 (*"we want everything 100% functional + even better to wow people on the first opening"*), branch `notif-her-words`, migration `20260928000001_notifications_in_her_words.sql`

## What we chose

Her words, character for character, from the database functions that cause
each event, so a push, the bell and the lock screen all say the same thing.
`tests/sql/notification_copy.sql` compares every body exactly (no substring
matching), with the day and time worked out by hand for a Thursday 9:00 AM
and a Friday 8:30 PM that is already Saturday in UTC.

| Hers | When it is sent | When it is not |
|---|---|---|
| #1 You're In ("You're all set for {clinic} on {day} at {time}. Looking forward to seeing you on court!") | `register_for_clinic` lands in You're In!; `place_player` puts someone in | a draft, a canceled clinic, one already started (a walk-up is on court); an approved late request (see 3) |
| #3 Invitation Accepted, to the player ("Awesome! Your spot is confirmed. See you soon!") | the player accepts | the clinic was canceled first ("confirmed" would be false); never #1 as well |
| #5 Added to Player Pool | a player's own registration lands in the Pool | a decline, a withdrawn invitation, Tara placing someone in the Pool |
| #6 Removed from Player Pool | an admin removes someone from the Pool of a published clinic | the player leaves on their own; Tara's removal from You're In! sends nothing (question 79) |
| #13 to #15, to Tara | acceptances, declines and cancellations, in the catalogue's wording; the late-fee and note endings kept | |

1. `{day}` is the full weekday and `{time}` is `h:mm AM`, both in New York
   time, whatever the phone's zone.
2. `place_player` takes two locks (the clinic row, then the player's row), so
   a double tap, or an Accept arriving at the same moment, sends one #1, not
   two (`tests/sql/place_player_race.sh`, red without either lock).
3. An approved late request sends one message, the existing "You're in for
   {clinic}.", not that and #1 (question 90).
4. The push carries `category: INVITATION` on an invitation, so the lock
   screen offers Accept and Decline (decision 0023), and `thread-id`, the
   clinic's id, so a clinic's messages group together.
5. **A transition looks at whether the clinic is still happening.** An
   Accept is refused once the clinic is canceled (`clinic_canceled`,
   20260928300001) or has ended (`clinic_ended`, 20260928400001); Tara's
   Invite and late-request Approve are refused once it is canceled. Declines
   stay possible. Each takes the clinic's lock before the registration's, the
   order every writer uses; `tests/sql/accept_cancel_race.sh` is red without
   the lock and with a weaker one. Found by the sql-auditor reviewing the
   first of the two migrations: with the Accept on the lock screen, a stale
   invitation tapped days later landed a player in a finished clinic and got
   them charged. Not Tara's policy, except where the Accept cut-off sits
   (start or end), which is question 91; a behaviour change Alex can veto.

## Rejected

- **Composing the words in the app.** Two copies drift; the push, which the
  server sends, would then disagree with the bell.
- **#1 for every placement, including drafts and started clinics.** A walk-up
  Tara adds on court does not need a phone buzzing in their bag.

## How we would know this was wrong

A player gets two messages for one tap, a message that names the wrong day,
or a "confirmed" for a clinic that was canceled.
