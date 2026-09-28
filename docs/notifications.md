# FXE Tennis: Notification Catalogue

Source of truth for copy: Tara, 2026-08-02.

`FXETennis/Models/NotificationCopy.swift` transcribes this catalogue, but
nothing calls it (`grep -rl 'FXENotification\|NotificationCopy\|FXEPayment' FXETennis FXETennisTests` finds only the file itself, 2026-09-28). Every
notification that actually reaches a player is a `notifications` row written
by a SQL RPC with its body built in SQL. Since 2026-09-28
(`20260928000001_notifications_in_her_words.sql`) those bodies are her words
for #1, #3, #5 and #6 and the catalogue's for #13, #14 and #15; #2 and #7 are
still ours. See "What fires today" below before trusting the trigger column.

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

## What fires today (2026-09-28)

The catalogue below is what she wrote and what should fire. This table is what
the database does, from `pg_get_functiondef` on every function in `public`
that calls `notify_account` (nine, enumerated by `notification_targets.sql`).
Everything else in the catalogue is **not wired**, whichever the trigger
column says. Rows marked "hers" carry her sentence character for character,
pinned by `tests/sql/notification_copy.sql`; the others are ours, written in
SQL before her copy arrived, and per rule 13 each needs either her wording or
her yes before it reaches a real player.

| Producer (RPC) | `type` | Recipient | Body as written in SQL | Catalogue # |
|---|---|---|---|---|
| `register_for_clinic` | `youre_in` / `added_to_pool` | The player whose spot it is, whoever tapped Register | #1 / #5, hers | 1, 5 |
| `place_player` | `youre_in` | The player, only when Tara's placement is what put them in: not when they were already in, not for a draft, canceled or already-started clinic, and not when `resolve_late_request` is placing an approved late asker (that answer is its own row). Into the Pool: nothing | #1, hers | 1 |
| `invite_from_pool` | `invitation_received` | The invited player | `A spot opened in {clinic}. Accept or decline.` | 2 (different words, contradiction (a)) |
| `cancel_clinic` | `clinic_canceled` | Every live registration | `{clinic} has been canceled.` | 7 (different words, contradiction (d)) |
| `send_clinic_message` | `clinic_message` | The audience she picked | Her typed body, pass-through | 12 |
| `respond_to_invitation` | `invitation_accepted_player` | The player who accepted (never #1 as well; not when Tara has canceled the clinic, where "Your spot is confirmed" would be false; a decline sends the player nothing) | #3, hers | 3 |
| `respond_to_invitation` | `invitation_accepted` / `invitation_declined` | Every admin | `{player} accepted their spot in {clinic}.` / `{player} declined {clinic} and is back in the Player Pool.` | 13, 14 |
| `cancel_registration` | `player_canceled` | Every admin, only when the player canceled their own spot (since 20260927100002 an admin's removal does not reach the admins; `admin_mark_late_cancel` tells nobody) | `{player} canceled {clinic}.` plus ` Late, fee applies.` on a late cancel, plus ` Note: "{cancel_note}"` when a note was left (the ` Late, courtesy used.` branch is still in the SQL but unreachable since `courtesy_cancel_days = 0`, decision 0013) | 15 |
| `cancel_registration` | `removed_from_pool` | The player, when Tara (an admin who does not own the player) removes them from the Player Pool of a published clinic. Her removal from You're In! sends nothing. **No screen offers this removal yet**: the phone has Remove only on You're In! rows and the web admin not at all (`docs/backlog.md`) | #6, hers | 6 |
| `request_late_spot` | `LATE_REQUEST` | Every admin | `{player} is asking to join {clinic}.` plus the quoted message if any | not in her list |
| `resolve_late_request` | `LATE_REQUEST_APPROVED` / `LATE_REQUEST_DECLINED` | The requesting player | `You're in for {clinic}.` / `Tara couldn't fit you into {clinic} this time.` | not in her list; see finding (e) |

`{day}` and `{time}` in #1 are built in SQL from the clinic's start in New
York, `to_char(starts_at at time zone 'America/New_York', 'FMDay')` and
`'FMHH12:MI AM'`, the same "Thursday" and "9:00 AM" that `NotificationCopy.swift`
renders with `EEEE` and `h:mm a`: no padded weekday, no leading zero, and an
8:30 PM Friday clinic is not read as Saturday in UTC. Every new row names the
registration it is about.

No producer exists for 4, 9 (`publish_news` notifies nobody), 10, or 11 (a
player's own `cancel_registration` notifies only the admins).
`cancel_invitation` and `leave_pool` notify nobody, and neither does Tara's
removal of someone from You're In! (no words for it, contradiction (b)). The
payment reminder (8) is not a `notify_account` call at all: it is a clinic
message, see below.

Push delivery is a separate question: these rows are readable in the app's
notification center (2026-09-02). Since 2026-09-23 every row inserted here is
also handed to the `push` edge function, which sends the row's body verbatim
to the recipient's phones and records `delivered_at` or `delivery_error` on
it (decision 0008). Since 2026-09-28 the push also carries
`category: INVITATION` on an invitation (finding (l)) and `thread-id`, the
clinic's id, on every row about a clinic, so a clinic's notifications group
together on the lock screen. That path is built and tested against a mock but
sends nothing yet: it stays silent until Apple issues the signing key and the
two vault secrets are set (`supabase/functions/README.md`).

---

## The catalogue

`{clinic}`, `{day}`, `{time}`, `{date}`, and `{player}` are substituted at send
time. Times render in `America/New_York`, never in the device time zone: a
player travelling out of state must still read the court time.

### Player-facing

| # | Notification | Trigger event | Recipient | Exact copy |
|---|---|---|---|---|
| 1 | You're In | **Wired 2026-09-28.** `register_for_clinic` when the registration lands in You're In! (member priority), and `place_player` when Tara's placement puts in someone who was not already in (a published clinic that has not started; not an approved late request, which sends its own answer). **Not** on invitation accept: that is #3, finding (e). | The registering player's account | `You're all set for {clinic} on {day} at {time}. Looking forward to seeing you on court!` |
| 2 | Invitation Received | Tara invites a player out of the Player Pool (`invite_from_pool`). Wired, but with our body, not hers: see What fires today. | The invited player's account | `Good News! A spot is available for {clinic}. Tap below to accept before it expires` |
| 3 | Invitation Accepted | **Wired 2026-09-28.** `respond_to_invitation` on Accept, to the player, unless Tara has canceled the clinic in the meantime; Tara gets #13 either way. | The accepting player's account | `Awesome! Your spot is confirmed. See you soon!` |
| 4 | Invitation Expired | **Not wired.** No expiry mechanism exists. See contradiction (a). | The invited player's account | `Your invitation has expired, but we hope to see you next time!` |
| 5 | Added to Player Pool | **Wired 2026-09-28.** `register_for_clinic` when the registration lands in the Player Pool (full, or after the members' head start). Not on decline, not on invitation cancel, not on Tara placing someone into the Pool. See finding (i). | The registering player's account | `Thanks for registering! I personally create each clinic based on playing levels and will send confirmations once lineups are set ASAP` |
| 6 | Removed from Player Pool | **Wired 2026-09-28, server half.** `cancel_registration` when Tara (an admin who does not own the player) removes someone from the Player Pool of a published clinic. A player's own cancel sends Tara #15 instead. No screen offers Remove on a Pool row yet, so nothing reaches it today (`docs/backlog.md`). See contradiction (b). | The removed player's account | `You've been removed from the Player Pool for {clinic}. Hope to see you at another clinic soon!` |
| 7 | Clinic Canceled | Tara cancels a clinic (`cancel_clinic`). Sent to You're In!, Player Pool, and Response Needed. Wired, but with our body, not hers: see What fires today and contradiction (d). | Every account with a live registration | `Unfortunately today's {clinic} has been canceled due to weather.` |
| 8 | Payment Reminder | **Switched off 2026-09-21 (decision 0013).** Built 2026-09-01 as a `send_clinic_message` with audience `unpaid`; the Remind unpaid control is rendered on neither admin surface while `app_settings.zelle_allowed` is `false`, which it is. | Unpaid registrants | Her sentence was `Just a quick reminder for payment from {clinic} on {date}. Thank you!`. The code still holds `Just a reminder that {clinic} ({date}) hasn't been paid yet. {payment line} Thanks!` (`web/index.html`, `AdminRepository.swift`) behind the `zelle_allowed` gate. See (g). |
| 9 | New Announcement | **Not wired.** `publish_news` notifies nobody, and News has no surface (decision 0006). | Accounts matching the post's audience | `News from FXE!` |
| 10 | Registration Is Open | **Not wired.** Requires a scheduled job at window open. See contradiction (c). | Undecided, see (c) | `Registration is LIVE!! Hope to see you on the court` |
| 11 | Registration Canceled | **Not wired.** A player's own `cancel_registration` notifies only the admins. See (h), which recommends in-app only. | The cancelling player's account | `You've canceled your registration for {clinic}. Hope to see you back on the court soon!` |
| 12 | Clinic Message | Tara sends a clinic message (`send_clinic_message`). | The audience she selected | Pass-through. Tara's typed body is the copy. |

### Admin-facing (to Tara)

| # | Notification | Trigger event | Recipient | Exact copy |
|---|---|---|---|---|
| 13 | Player Accepted | Player accepts an invitation. Wired in this wording since 2026-09-28 (it read `{player} accepted.`). | Every admin account | `{player} accepted their spot in {clinic}.` |
| 14 | Player Declined | Player declines an invitation. Wired in this wording since 2026-09-28 (it read `{player} declined.`). | Every admin account | `{player} declined {clinic} and is back in the Player Pool.` |
| 15 | Player Canceled | Player cancels a registration. Also raises Action Needed. Wired in this wording since 2026-09-28 (it read `{player} canceled.`), followed by the late-fee and note suffixes (2026-09-12). | Every admin account | `{player} canceled {clinic}.` |

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

**Half fixed 2026-09-27** (20260927100002, option 1's first half). The
self-notification is gone: when the caller is an admin who does not own the
player, `cancel_registration` skips the admin fan-out, so Tara's Remove no
longer reads in her own Action Needed as "{player} canceled."
`late_cancellation.sql` asserts who was told per registration.

**Player half, 2026-09-28** (`20260928000001`, option 1's second half). Her
catalogue already carries the words for removal from the Player Pool, so Tara
removing someone from the Pool of a published clinic now sends them #6, and a
player canceling their own Pool entry still sends Tara #15 and never #6
(`notification_copy.sql`). Removal from You're In! still tells the player
nothing: her #6 covers the Pool only, and there are no words for the other.
The server half is all there is so far: the phone offers Remove only on You're
In! rows and the web admin not at all, so until a Pool row gets a Remove, no
one can send #6 (`docs/backlog.md`).

**Question 79's context.** Question 79 (asked 2026-09-27) asks whether the app
should tell a player when Tara takes them out of a clinic, takes back an
invitation, or puts them in herself, with "nothing is sent" as the default
until she answers. Her catalogue (2026-08-02) already has a sentence for two
of those three: #1 for a spot in You're In! (the trigger this catalogue wrote
for it, alongside her words, names Tara placing the player by hand), and #6
for being taken out of the Player Pool. Those two are wired (2026-09-28), on
the strength of her catalogue. Taking back an invitation (#4 would say
"expired", contradiction (a)) and removal from You're In! (no words) stay
unsent and open under 79, whose "nothing is sent" default no longer describes
the other two.

**Fixed 2026-09-21** (20260921000001). `leave_pool` used to delete the
registration row outright, against hard rule 4; it now cancels the row
conditionally on `status = 'pool'`, stamped and never late, so archive-never-
delete holds on every exit path.

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
confirmations. Enforced in SQL since 2026-09-28 and pinned by
`notification_copy.sql` (`accept_sends_no_1`).

The same shape turned up when #1 was wired: `resolve_late_request` puts an
approved late asker in through `place_player` and then sends its own answer
(`You're in for {clinic}.`), so a plain #1 from `place_player` would have been
a second row for the same tap. `place_player` skips #1 for a late request
approved in the same transaction; the asker gets one row, as before. Whether
that one row should be her #1 rather than our `You're in for {clinic}.` is
open.

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

The catalogue keeps them apart: notification 8 is the short push, and the
payment line is a separate string for Clinic Details and for the persisted
in-app message body, where there is room. This preserves both of her
requirements but it is an inference, not something she said.

**What was built (2026-09-01).** The reminder is a clinic message, not a push,
so the lock-screen budget did not apply, and the Zelle line rides inside it:
`Just a reminder that {clinic} ({date}) hasn't been paid yet. {payment line}
Thanks!`. Both clients read the line through the `payment_instructions()` RPC
(`FXETennis/Data/Repositories.swift`, `web/index.html`), as CLAUDE.md requires;
`FXEPayment.line` in `NotificationCopy.swift` is a second, unused copy of the
same string (`grep -rn FXEPayment.line FXETennis` finds no caller) and should
go when that file is either wired or deleted.

**Question for her, still open for the push.** When a push exists, should the
Zelle line ride inside it, where the lock screen will cut it off, or sit on the
clinic page and in the message the player opens?

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
Enforced since 2026-09-28: only `register_for_clinic` sends #5, and
`notification_copy.sql` pins that a decline, a withdrawn invitation and Tara's
placement into the Pool send none.

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

~~`accounts.push_enabled` should stay in the schema: the app still needs to know
its own permission state to nag the user, which is what she asked for instead.
What has to go is any admin surface reading it.~~ **Resolved.** The column was
dropped in 20260802000002 (`information_schema.columns` has no `push_enabled`
on `accounts`, 2026-09-12) and the nag is client-side, where iOS already knows
its own permission state: `FXETennis/Views/NotificationPermissionView.swift`
(2026-09-02). CLAUDE.md's decision 13 records the overrule of both documents.

### (l) "Tap below" is an actionable push, not a plain alert

Notification 2 promises buttons. That requires an APNs notification category
with Accept and Decline actions registered at launch, and a notification service
handling the responses without opening the app. The guide agrees: "The player
receives a push notification with Accept and Decline." Recording it here because
it is a real implementation requirement hiding inside two words of copy, and
because the same two words are the ones that also promise an expiry.

**Server half, 2026-09-28.** The `push` function sends every
`invitation_received` row with `category: INVITATION`, pinned by
`tests/push/run.sh`. The app half, registering that category with Accept and
Decline actions and handling the response, is not built: no
`UNNotificationCategory` exists under `FXETennis/` (2026-09-28). Until it is,
iOS shows the invitation as a plain alert, which is today's behaviour.

### (m) "{day}" is a weekday, and a clinic can be a week away on the same one

Found by the sql-auditor on 2026-09-28, once #1 was wired. Members register
from 8:00 AM on a Thursday for the whole of the next service week, so a
member who signs up that morning for next week's Thursday clinic reads "You're
all set for ... on Thursday at 9:00 AM" on a Thursday, a week early. Tara
placing someone a week or more ahead reads the same way. Her `{day}` is built
as the weekday alone, as `NotificationCopy.swift` renders it; nothing here
changes her words.

**Question for her.** When the clinic is a week or more away, should the
message name the date as well ("on Thursday, October 8 at 9:00 AM"), or is the
day enough? Default until she answers: the day alone, as she wrote it.
