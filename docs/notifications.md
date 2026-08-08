# FXE Tennis: Notification Catalogue

Source of truth for code: `FXETennis/Models/NotificationCopy.swift`.
Source of truth for copy: Tara, 2026-08-02.

All player-facing copy below is hers, verbatim. Punctuation, capitalisation, and
the missing terminal periods are reproduced as she wrote them. Admin-facing copy
is ours: she said "any sensible wording" for notifications to herself.

Two rules constrain every string in this file:

1. It has to read on a lock screen. Tara's stated limit is 1 to 2 sentences.
2. Clinic location never appears, in any form, anywhere player-facing. FXE is a
   member club and must not read as open to the public. There is no `location`
   parameter in the catalogue, by design.

By omission, no string reveals capacity, spots remaining, Player Pool size,
another player's name, a court number, or another player's payment status.
Those are the nine hidden facts from the Developer Guide, and they are hidden at
the database layer as well. Do not add a count to a body string here.

---

## The catalogue

`{clinic}`, `{day}`, `{time}`, `{date}`, and `{player}` are substituted at send
time. Times render in `America/New_York`, never in the device time zone: a
player travelling out of state must still read the court time.

### Player-facing

| # | Notification | Trigger event | Recipient | Exact copy |
|---|---|---|---|---|
| 1 | You're In | Registration resolves to You're In!, by member priority or by Tara placing the player by hand. Does **not** fire on invitation accept. | The registering player's account | `You're all set for {clinic} on {day} at {time}. Looking forward to seeing you on court!` |
| 2 | Invitation Received | Tara invites a player out of the Player Pool (`invite_from_pool`). | The invited player's account | `Good News! A spot is available for {clinic}. Tap below to accept before it expires` |
| 3 | Invitation Accepted | Player taps Accept (`respond_to_invitation`, accept). | The accepting player's account | `Awesome! Your spot is confirmed. See you soon!` |
| 4 | Invitation Expired | **Not wired.** No expiry mechanism exists. See contradiction (a). | The invited player's account | `Your invitation has expired, but we hope to see you next time!` |
| 5 | Added to Player Pool | First registration resolves to Player Pool. Not on decline, not on invitation cancel. See finding (i). | The registering player's account | `Thanks for registering! I personally create each clinic based on playing levels and will send confirmations once lineups are set ASAP` |
| 6 | Removed from Player Pool | Tara removes a pooled player (admin `cancel_registration`). | The removed player's account | `You've been removed from the Player Pool for {clinic}. Hope to see you at another clinic soon!` |
| 7 | Clinic Canceled | Tara cancels a clinic (`cancel_clinic`). Sent to You're In!, Player Pool, and Response Needed. | Every account with a live registration | `Unfortunately today's {clinic} has been canceled due to weather.` |
| 8 | Payment Reminder | Tara taps the unpaid reminder. Sent only where `paid = false`. | Unpaid registrants | `Just a quick reminder for payment from {clinic} on {date}. Thank you!` |
| 9 | New Announcement | Tara publishes a news post (`publish_news`). | Accounts matching the post's audience | `News from FXE!` |
| 10 | Registration Is Open | **Not wired.** Requires a scheduled job at window open. See contradiction (c). | Undecided, see (c) | `Registration is LIVE!! Hope to see you on the court` |
| 11 | Registration Canceled | Player cancels their own registration. | The cancelling player's account | `You've canceled your registration for {clinic}. Hope to see you back on the court soon!` |
| 12 | Clinic Message | Tara sends a clinic message (`send_clinic_message`). | The audience she selected | Pass-through. Tara's typed body is the copy. |

### Admin-facing (to Tara)

| # | Notification | Trigger event | Recipient | Exact copy |
|---|---|---|---|---|
| 13 | Player Accepted | Player accepts an invitation. | Every admin account | `{player} accepted their spot in {clinic}.` |
| 14 | Player Declined | Player declines an invitation. | Every admin account | `{player} declined {clinic} and is back in the Player Pool.` |
| 15 | Player Canceled | Player cancels a registration. Also raises Action Needed. | Every admin account | `{player} canceled {clinic}.` |

### Measured lengths

Rendered with a realistic clinic name ("Ladies Cardio Tennis"). Budget is 140
characters, which is roughly what survives on a collapsed lock-screen banner
before iOS truncates.

| # | Chars | Sentences |
|---|---|---|
| 1 | 103 | 2 |
| 2 | 94 | 3 |
| 3 | 46 | 3 |
| 4 | 62 | 1 |
| 5 | 133 | 2 |
| 6 | 106 | 2 |
| 7 | 76 | 1 |
| 8 | 80 | 2 |
| 9 | 14 | 1 |
| 10 | 51 | 2 |
| 11 | 99 | 2 |
| 13 | 56 | 1 |
| 14 | 73 | 1 |
| 15 | 42 | 1 |

Every one fits. #5 at 133 is the closest to the edge and is the one to re-check
if a clinic name ever runs long.

---

## Contradictions

Not resolved. Each needs a decision before the matching code is written.

### (a) Invitations expire, and also do not expire

**What she said.** Notification 2: "Tap below to accept before it expires."
Notification 4 exists at all: "Your invitation has expired, but we hope to see
you next time!"

**What the guide says.** Three separate places, all one direction:

- Section 6, Invitation rules: "Invitations do not auto-expire in Version 1."
- Section 6, next line: "Tara can cancel an outstanding invitation manually."
- Section 12, Not in Version 1: "Automatic invitation expiration."
- Future Version Priorities lists "Reminder for unanswered invitations" as a
  Version 2 candidate, which only makes sense if nothing expires in Version 1.

Our own hard rule 2 in `CLAUDE.md` restates it: the app "never auto-expires an
invitation."

These cannot both hold. Either something expires, or the word is decoration.

**Options.**

1. **Copy only, no timer.** Ship her wording as urgency. Wire notification 4 to
   `cancel_invitation`, which today notifies nobody at all, so the player is
   currently left staring at a Response Needed card that silently vanished.
   Cost: about an hour, mostly the missing notify call. Consequence: "expired"
   becomes a polite euphemism for "Tara took the spot back," which is arguably
   the kinder sentence anyway.
2. **A real expiry clock.** Add `registrations.expires_at`, set it in
   `invite_from_pool`, sweep with pg_cron on a conditional
   `UPDATE ... WHERE status = 'response_needed' AND expires_at < now()`, notify,
   and render a live countdown on the invitation card. Cost: roughly 6 to 8
   hours including a probe for the sweep-versus-accept race, which is a genuine
   one. Consequence: it moves a decision from Tara to a cron job, against the
   product rule that Tara decides and the app organises. It also needs the
   guide's Version 1 exclusion formally overruled.
3. **Optional per-invitation deadline, off by default.** All of option 2's
   machinery plus an admin control. Cost: 8 to 10 hours. Buys flexibility she
   has not asked for.

**Recommendation: option 1.** The guide excludes expiry in three places, and an
automatic expiry gives someone's spot away without Tara. Her sentence still does
its real job, which is making people answer quickly. If invitations do sit
unanswered in practice, option 2 is the natural Version 2 feature, and the guide
already files it there.

**Question for her.** Do you want invitations to genuinely run out on a clock,
say 24 hours, or is "before it expires" just there to make people answer fast
while you still decide by hand when to take a spot back?

### (b) Removing someone from the Player Pool

**What she said.** Notification 6: "You've been removed from the Player Pool for
{clinic}."

**What the guide says.** It supports her. Section 11, Edge cases: "Tara removes
a player: Notify the player, preserve history, and surface replacement need in
Action Needed." No contradiction on the concept.

**What the schema says.** Also supports it. `cancel_registration` accepts an
admin caller (`owns_player(...) or is_admin()`), the conditional update covers
`pool` among the live statuses, and `canceled_by` records who did it.

**The real defect this copy exposes.** `cancel_registration` notifies only the
admins, on every path, with the body "{player} canceled." When Tara is the
caller, that means Tara notifies herself that the player cancelled, and the
player who was actually removed is told nothing. The guide explicitly requires
the opposite. This is a bug her copy caught.

**Options.**

1. Branch inside `cancel_registration`: if the caller is an admin who does not
   own the player, notify the player with notification 6 and skip the
   self-notification. Cost: about an hour, plus a probe.
2. Split into a separate `remove_registration(p_registration)` admin RPC.
   Cleaner boundary, a little more surface. Cost: about two hours.

**Recommendation: option 1.** Same transition, same row, same race conditions.
A second RPC would duplicate the conditional update for no gain.

**Also worth her knowing, though it is ours to fix.** `leave_pool` deletes the
registration row outright rather than cancelling it, which conflicts with hard
rule 4, archive and never delete. It is the player's own withdrawal, so nothing
is lost that Tara needs, but the inconsistency should be a deliberate choice
rather than an accident.

### (c) A broadcast when registration opens

**What she said.** Notification 10: "Registration is LIVE!! Hope to see you on
the court."

**What the guide says.** Nothing about a broadcast. The closest entries are
about the client refreshing itself, not about reaching anyone:

- Section 11: "Registration opens while screen is open: preferred, the button
  updates automatically."
- Section 12, Optional only if easy: "Automatic refresh when registration
  opens."

**What the design says.** Nothing. There is no scheduler anywhere in the system.
Every notification we have is emitted synchronously inside an RPC that a human
just called. This is the only entry in her list that fires with nobody touching
the app.

**Three things her one sentence does not settle.**

- **Which window.** Every clinic has two: members Thursday 8:00 AM, everyone
  Friday 8:00 AM. One blast or two? If one, members lose the point of priority.
  If two, everyone gets two pushes per clinic per week.
- **Which recipients.** A Ladies clinic blasted to the whole club is spam to
  half of it. Audience filtering exists on clinics (`ladies` / `men` / `coed`),
  but the link from clinic audience to a player's eligibility is not built.
- **How many.** Six clinics opening the same Thursday morning is six pushes at
  8:00 AM unless they are batched into one.

**Cost.** The mechanism itself is cheap: `clinics.open_notified_at` as an
idempotency marker so a cron retry cannot double-send, plus a pg_cron job every
five minutes selecting published clinics whose window just crossed. Roughly 4
hours. The batching and audience-targeting questions above are what actually add
work, and they are hers to answer first.

**Recommendation.** Build it, but as **one batched digest per window per
audience**, not one push per clinic. Members get a Thursday 8:00 AM message,
everyone gets Friday 8:00 AM. Her sentence works unchanged as a digest headline
because it names no clinic.

**Question for her.** Should "Registration is LIVE" go out Thursday when members
open, Friday when everyone opens, or both, and should it be one message covering
the whole week or one per clinic?

### (d) "Due to weather" is hardcoded

**What she said.** Notification 7: "Unfortunately today's {clinic} has been
canceled due to weather."

**What the guide says.** Section 10: "Cancel Clinic: confirm, cancel clinic,
notify all affected statuses, preserve the clinic record." No reason is
mentioned, captured, or stored anywhere.

**What the schema says.** `cancel_clinic(p_clinic uuid)` takes no reason.
`clinics` has `canceled_at` and no `cancel_reason`. The notification body is
hardcoded.

**Two problems in one sentence, not one.**

- **"due to weather"** is false whenever it is not the weather. Coach illness,
  a court closure, and low signup are all real, and all reach the player as a
  weather claim.
- **"today's"** is false whenever she cancels ahead of time, which is the
  normal case. A Thursday clinic cancelled on Tuesday reads "today's Ladies
  Cardio Tennis has been canceled," on Tuesday.

**Options.**

1. Leave both hardcoded. Cost: zero. She sends a manual clinic message when the
   sentence is wrong, which is most cancellations that are not same-day rain.
2. Parameterise the reason only. `cancel_clinic(p_clinic, p_reason text default
   'weather')` plus a `clinics.cancel_reason` column, and a short reason picker
   in the admin UI. The default reproduces her sentence exactly. Cost: about two
   hours.
3. Parameterise the reason and derive the day phrase, so it reads "today's" only
   when the clinic is actually today and otherwise names the day. Cost: about
   three hours.

**Recommendation: option 3, and it is already half done.** The reason is a
parameter in the catalogue today, defaulting to `"weather"` so the default path
is her sentence character for character. The "today's" half is deliberately left
wrong and un-fixed, because rewriting her phrasing is her call, not ours.

**Question for her.** When you cancel for something other than rain, do you want
to type the reason yourself, or should it just say the clinic is canceled with
no reason given?

---

## Further findings

Not in the brief, found while writing the catalogue.

### (e) Accepting an invitation could push twice

Notification 1 (You're In) and notification 3 (Invitation Accepted) both describe
a player who now has a spot, and accepting an invitation sets `status = 'in'`,
which is exactly the state notification 1 announces. Wired naively the player
gets two pushes for one tap.

Resolved in the catalogue without needing her: notification 1 fires only on
direct registration and on Tara placing someone by hand, notification 3 fires
only on accept. Documented in the trigger column and in code. Flagging it
because the split is not obvious from her list, where both read like
confirmations.

### (f) There is no copy for a clinic time or date change

The guide names it repeatedly. Section 7, Action Needed examples: "Clinic
canceled **or changed**." Section 8: a clinic message is for "rain delay,
start-time change." Our own `questions-for-tara.md` question 20 listed "clinic
time changed" among the ten notifications to write. Her list does not include
it.

Today a time change would go out as a free-text clinic message, which works but
means she retypes it every time. Not a contradiction, an omission.

**Question for her.** What should it say when you move a clinic's date or time?

### (g) The payment reminder does not contain the payment details

Decision 11 requires this string, exactly:

```
Payment can be made via zelle to fersctennispro@gmail.com (preferred) or Venmo FXE Tennis
```

That is 89 characters. Her payment reminder is 80. Together they are 169, well
past what a lock screen shows, and the Zelle address is the part that would be
cut.

The catalogue keeps them apart: notification 8 is the short push, and
`FXEPayment.line` is the exact required string for Clinic Details and for the
persisted in-app message body, where there is room. This preserves both of her
requirements but it is an inference, not something she said.

**Question for her.** Should the Zelle line ride inside the payment reminder
itself, where the lock screen will cut it off, or sit on the clinic page and in
the message the player opens?

### (h) Notification 11 confirms an action the player just took

The player taps Cancel Registration, confirms it on a sheet, and then their
phone buzzes to tell them they cancelled. The guide's design for this event is
the opposite direction: "Player cancellation: Tara receives a notification."

Recommendation: write it to the in-app notification list, which is a useful
record, and do not send it as a push. Cheap, and it is the kind of thing that
makes people turn notifications off. Her copy is kept either way.

### (i) "Added to Player Pool" has three possible triggers, and only one fits

A registration reaches `pool` three ways: initial registration, a player
declining an invitation, and Tara cancelling an invitation. "Thanks for
registering!" is right for the first and wrong for the other two, where the
player was already registered and has just lost something.

Narrowed to first registration only in the catalogue. The other two paths get
notifications 4 and nothing respectively, which is contradiction (a) again.

### (j) Her own copy breaks her own sentence rule, twice

She set a 1 to 2 sentence limit. Notification 2 is three sentences and
notification 3 is three sentences. Both are short, 94 and 46 characters, so
neither is a lock-screen problem.

Treating this as her rule being approximately right rather than her copy being
wrong: the catalogue measures and reports `sentenceCount`, and gates on
`characterCount` against a 140-character budget, which is what actually
truncates. Nothing is enforced against her wording.

### (k) Decision 13 contradicts our own engineering design

Not her copy, but it lands in the same area and would otherwise get built the
old way. Decision 13 says she explicitly does not want to manage or monitor who
has notifications turned off, and that the admin-facing indicator must be
removed. Two documents still specify it:

- `engineering-design.md` section 4: "Tara sees a 'notifications off' marker on
  the player's profile so she can text them."
- `questions-for-tara.md` question 19, whose default was that marker, now
  overruled.

`accounts.push_enabled` should stay in the schema: the app still needs to know
its own permission state to nag the user, which is what she asked for instead.
What has to go is any admin surface reading it. Both documents need updating so
the next session does not rebuild the indicator from the spec.

### (l) "Tap below" is an actionable push, not a plain alert

Notification 2 promises buttons. That requires an APNs notification category
with Accept and Decline actions registered at launch, and a notification service
handling the responses without opening the app. The guide agrees: "The player
receives a push notification with Accept and Decline." Recording it here because
it is a real implementation requirement hiding inside two words of copy, and
because the same two words are the ones that also promise an expiry.
