# 0051. Tara's "Next update" list: message one player, invite anyone, the full question, the pros' week (2026-11-07)

**Status:** accepted by John, 2026-11-07 (*"yeah start on 5, 1, 6 and 2"*);
built in `supabase/migrations/20261107000002_tara_next_update.sql`, the app and
the laptop site. Items 3 (half charge for rain) and 4 (adding someone who is
not in the app) wait on her answers (questions 143 and 144).

## Her words

"Next update (notes taken 11/6/26)", relayed by John on 2026-11-07:

> 1. Allow me to message the people on the waitlist. Allow me to send a message
>    to anyone whenever they are (meaning in a clinic, not registered, on a
>    waitlist, etc).
> 2. Allow me to invite anyone to a clinic that is not on a waitlist
> 5. Alert admin (me) when clinic is full before I start inviting someone. For
>    example: clinic is 25/25. I invite someone, a message comes up that says
>    "are you sure you want to invite ___ your clinic is full.
> 6. Allow pros to have access to the week ahead and what players are signed
>    up. Not just day of (right now their tab says TODAY. Have it say manage or
>    whatever like mine but their ONLY capabilities are to assign courts and see
>    who is in the clinic. I don't want the pro status people to be able to
>    invite anyone, charge anyone, etc. just want them to see what's ahead for
>    the week

And on her screenshot of Message Players' To menu: *"For instance, here -
option to message individual"*.

## What we chose

1. **Messaging the Waitlist already existed** (To: Waitlist on a clinic's
   Message). New: **one player**. On a clinic's Message, the To menu has "One
   player" and a second menu of everyone on that clinic who is not canceled;
   the message is kept on that clinic's page for that player only (a
   `clinic_messages` row of the new audience `player` and one recipient). On
   the Players tab, "Message {first name}" reaches anyone, in a clinic or not,
   as a notification. Both are `admin_message_player`; the group sender refuses
   the `player` audience.
2. **Invite anyone** (More > Invite a player on the phone; the same on the
   laptop). Always an invitation, never a placement: they did not ask to come,
   so they accept or decline ("A spot opened in ... Accept or decline.", her
   invitation words). Someone already In, waiting or invited is marked
   "Already on this clinic", and the server refuses them too. A decline ends it
   (canceled) instead of putting them on a Waitlist they never joined; Tara
   reads "{name} declined {clinic}." without "and is back on the Waitlist".
   The registration's source is the new `invite`, which is how the decline
   tells the two apart. Add player (straight in) is unchanged.
5. **The full question**: before Invite or Move In from the Waitlist and before
   Invite a player, when You're In! is at capacity: "Are you sure you want to
   invite Jane Doe? Your clinic is full (25/25)." A question, never a refusal:
   capacity never blocks her (her answer to for-tara.md question 4).
6. **The pros' week**: the tab is named Manage, like hers, and lists today and
   the six days after, by day ("Today", "Tomorrow", "Wednesday, Nov 11"), with a
   court menu on every You're In! row (`pro_week`, `pro_assign_court`). Came /
   No-show and Late cancel stay on today's clinics, as before: she said what
   pros must not do (invite, charge), and taking away the marks she gave them
   on 09-22 was not asked. Still no Waitlist, no price, no invite, no message.
   `pro_week`'s columns are `pro_today`'s exactly (decision 0025: the column
   list is the contract), and `pro_today` stays for the 1.0.x apps.

## Rejected

- **Reusing the Waitlist invite for anyone** (`place_player` with Response
  Needed): no invitation notice, and a decline would have put them on the
  Waitlist.
- **A new notification type for one-player messages**: the 1.0.x apps show any
  type, but `clinic_message` is what the bell, the push and the copy catalogue
  already know as "Tara's own words".
- **Letting a pro set courts on any clinic**: the week is what she asked for;
  the server refuses the rest with one answer, `not_this_week`.

## Tests

`tests/sql/next_update_1107.sql` (written from the rule; red before the
migration because none of the functions existed). `ClinicFullTests`, the week
cases in `ProTodayTests`, and `ProFlowUITests` (the pro gives Theo a court and
takes it back). The laptop site's tests are in `web/tests/admin.spec.mjs`.
