# 0047. Before clinic day, Tara's Waitlist tap puts the player in (2026-11-04)

**Status:** accepted by John, 2026-11-04; built in
`supabase/migrations/20261104000001_waitlist_move_in.sql`. Amends hard rule 2.

## Her words

Tara, by text, relayed by John on 2026-11-04: *"Making sure that when someone
is on the waitlist - when I move them to the clinic they automatically are
moved and get notification they're in, UNLESS it's the same day of clinic in
which case they have to accept the invitiation."*

## The rule

One button on a Waitlist row (`invite_from_pool`). What it does depends on the
clinic's day in New York, not on hours:

| Clinic's day | Button reads | Player goes to | Player is told |
|---|---|---|---|
| After today, and more than 3 hours away | **Move In** | You're In!, at once | #1, her words: "You're all set for {clinic} on {Day} at {time}. Looking forward to seeing you on court!" |
| Today, or tomorrow but under 3 hours away | Invite | Response Needed; they Accept or Decline | #2: "A spot opened in {clinic}. Accept or decline." |
| Already past | Invite | Response Needed (an accept after the end is refused, 20260928400001) | #2 |

A draft moves in like any other clinic before its day and tells nobody:
players cannot see a draft (the same condition `place_player` uses for #1).

## Why the day, and why the past keeps the invitation

- "Same day" is her phrase, so the boundary is New York midnight, not 24 hours.
  A clinic at 12:30 AM tomorrow is before clinic day (probe row
  `half_past_midnight_tomorrow_is_before_clinic_day`, red under an hours rule).
- Moving someone straight into a clinic that has ended would put them on the
  charge list. Keeping the invitation there keeps the after-the-fact refusal
  meaningful.

## The 3-hour cancel cutoff (from the sql-auditor, 2026-11-04)

A clinic at 12:30 AM is "tomorrow" at 10 PM. Moving someone in then would
start their spot inside the late-cancel window, so their first chance to
cancel a spot they never said yes to would carry the fee. A move-in therefore
also needs `cancel_cutoff_hours()` (3) still ahead; inside it, the button
invites. Built as the default, not asked: it only matters for a clinic in the
first hours after midnight.

## Declined cards

A player whose card was declined after they joined the Waitlist can still be
moved in by Tara, as with every placement of hers (decision 4; `place_player`
and the admin exemption in the Accept check). The charge after the clinic
then fails and shows in Action Needed. Unchanged from her other placements;
noted here because before this, the player's own Accept would have refused.

## Hard rule 2, amended

Before: *never confirms someone without their acceptance.* Now: Tara still
picks every Waitlist move by hand and nothing is ever promoted automatically,
but before clinic day her tap is the confirmation. On clinic day the player
must still accept.

## Rejected

- **A second button** ("Move In" beside "Invite" on every row). She asked for
  one behaviour per day, not a choice each time.
- **Using `place_player`.** It is the walk-up path: it ignores the Waitlist
  row's history and sends nothing to a clinic that has started. The Waitlist
  row moving in place keeps its registration, price and member flag.

## Tests

- `tests/sql/waitlist_move_in.sql` (new, 13 checks): straight in with her #1
  and no invitation, a second tap refused and silent, clinic day invites, 12:30
  AM tomorrow counts as before clinic day, a past day still invites, a draft
  moves in silently, a player cannot press it; 11:30 PM tonight is clinic day
  (so a rule comparing UTC dates goes red at the hours the 12:30 AM row
  cannot catch); tomorrow inside the 3-hour cutoff invites.
- `tests/sql/move_in_cancel_race.sh` (new): Tara's Move In racing her own
  cancel of the clinic leaves the player out of You're In! with no "You're
  all set"; red with the clinic lock removed.
- `after_the_fact.sql`, `notification_copy.sql`, `notification_targets.sql`
  and the seed's invitation in Maria's bell are about invitations, so their
  clinics now sit on today's date (halfway to New York midnight, so they hold
  at any hour) while Tara presses the button.
- `testAdminB_MovesFromTheWaitlistBeforeClinicDay` (was
  `testAdminB_InvitesFromThePoolAndThePlayerAccepts`): Move In, Rob in
  You're In! with no Accept to tap.
- The laptop's remove test reads the button by its new name.

## How to tell if it was wrong

Tara moving someone on the morning of a clinic and expecting them to be in
without answering, or a player who never saw the "You're all set" push and
missed a clinic they were moved into days earlier.
