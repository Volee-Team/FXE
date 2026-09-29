# 0025: The pro role

**Date:** 2026-09-28 · **Status:** Active; five defaults wait on Tara (below) · **Source:** Tara, 2026-09-28 (decision 0024) and 2026-09-22 (decision 0016)

Tara's words. 2026-09-28: *"For right now, I'm going to be the only one that
sees everything. Let the pros see who is coming to the clinics that day. I
don't want the pros to invite people from the player pool. See anything
financial at all."* She added that eventually two of her pros, named, will
see more (their names are left out of this record: the repo is public).
2026-09-22: *"I want to have 'super admin' capabilities. So only I can
charge people and see how much money is being made. The pros have 'admin'
capabilities and they are not allowed to have capabilities to charge people
but can label them as no show, late cancellation, and see the clinic list."*
The 09-28 answer is the later one and narrows the 09-22 one ("see everything"
stays hers), so it wins where they differ.

## What we chose

1. **Tara stays the only admin.** `is_admin()` is unchanged. A pro is an
   account whose `role` is the new enum value `pro` (migration
   20260928600001), asked by `is_pro()`, which is false for a deleted account.
2. **A pro gets three functions and nothing else.** No policy, view or grant
   mentions a pro, so from every table and view a pro reads exactly what a
   member reads. The three:
   - `pro_today()`: today's clinics by the New York date, published and not
     canceled, and for each You're In! row only the registration id, first and
     last name, court, and the no-show and late-cancel flags. Never the Player
     Pool, Response Needed, a canceled row, another day, a price, the Paid
     flag, a charge, a card, a note, a phone, an email or the capacity. The
     column list is the contract; the probe asserts it exactly.
   - `pro_set_no_show()` and `pro_mark_late_cancel()`: Tara's two
     transitions, with her guards (only You're In!, late cancel inside the
     cutoff or after the start, never once charged, never on a canceled
     clinic), refused on any clinic that is not today's. The row records the
     pro as `canceled_by`. Like Tara's, they tell nobody.
3. **Tara's two RPCs and the pro's share one transition each.** The bodies of
   `admin_set_no_show` and `admin_mark_late_cancel` moved unchanged into the
   internal `registration_set_no_show` and `registration_mark_late_cancel`,
   which both roles call after their own gate. Tara's behaviour is identical
   (her probes pass unchanged); a rule change to either transition reaches
   both roles at once.
4. **Nothing a pro is told mentions money, not even through a refusal.**
   The pro's functions return nothing. Tara's rules refuse a row that holds a
   live fee; answered row by row, that refusal (under any name) told a pro who
   was charged and whose card was declined (the sql-auditor, 2026-09-28,
   demonstrated it with payments on). So once any row of a clinic holds a live
   fee, every mark a pro tries on that clinic answers `clinic_locked` ("Only
   Tara can change this."), charged rows and uncharged alike, and a charge
   that commits while a mark waits is caught by a second look after the row
   lock (`tests/sql/pro_mark_race.sh`). A pro learns "Tara has charged this
   clinic" and nothing per player. The late-cancel alert on the phone is
   Tara's without "The fee applies."
5. **Only Tara changes a role, only between member and pro.**
   `admin_set_pro(account, bool)` is a conditional update that touches only a
   live member or pro account; it refuses an admin, a deleted account and her
   own. The account trigger (hard rule 8's backstop) now refuses any role
   change other than member <-> pro whoever makes it, so no future code path
   can demote Tara or make anyone an admin.
6. **Where it shows.** A pro's phone has a Today tab where Tara's has Manage;
   a player's has neither; Tara does not get Today. Tara ticks Pro on the web
   admin's Players tab. A pro who signs in to the web admin is turned away like
   any member.
7. **"Today" is New York's date**, the zone every registration rule uses,
   whatever the phone's zone. At midnight the list turns over; a clinic that
   ran late into the next day is yesterday's.
8. **Room for "see more" later.** A pro's reach is a list of functions that
   ask `is_pro()`. Giving one pro more is new functions (or a second role
   value), not a change to this one; per-pro permissions were not built.

## Rejected

- **Letting pros call Tara's `admin_set_no_show` and `admin_mark_late_cancel`
  directly.** Both return the whole `registrations` row, with the price and
  the Paid flag: a return value would have handed a pro exactly the money
  Tara excluded, the leak class of 2026-09-27 (court numbers read back from
  cancel and accept). Blanking those columns for a pro would leak the next
  column anyone adds.
- **Making pros admins and hiding things in the app.** Hard rule 1: hiding in
  SwiftUI hides nothing, and every admin RPC, view and edge function would
  have let a pro in.
- **A `pro` flag on `players`, or a separate permissions table.** A role on
  `accounts` sits under hard rule 8's three layers already; a flag elsewhere
  would need its own. Per-pro permissions are more than was asked.
- **A view for the pro instead of a function.** A view needs a grant to
  `authenticated`, so members would reach it and it would lean on its `where`
  alone; four views here are auto-updatable, and a view's `where` does not
  stop an insert (hard rule 11). A function that raises for anyone but a pro
  has no such edge.
- **Seeding today's clinic at noon.** The brief asked for noon. A clinic sits
  on every player's Clinics list until it ends, so a noon clinic would be the
  first card from midnight to 13:00: registrable before 09:00, closed but
  listed until 13:00, when `testMemberCanSignInBrowseAndRegister` opens the
  first card and expects Register. Any clinic dated today is unfinished for
  part of today; at 00:30 to 01:30 that part is smallest: from midnight to
  01:30 New York it is still the first card, so the UI tests should not run
  in those ninety minutes (the sql-auditor measured it). Recorded in
  `supabase/seed.sql`.

## Waiting on Tara (defaults built, hard rule 14)

For the lead to put to her in `docs/questions-for-tara.md`, each with the
default we built:

1. Do pros sign the waiver and add a card like members? **Default: yes.** A
   pro keeps every member obligation; the pro role only adds the Today tab.
2. When a pro marks a No-show or a late cancellation, do you want to be told?
   **Default: no.** You see it on the roster, and Charge clinic charges it.
3. May a pro leave a note with a late cancellation (only you read it)?
   **Default: yes**, optional, as yours is.
4. Once you have charged a clinic, may a pro still change Came / No-show or
   mark a late cancellation there? **Default: no**; only you can, as today
   (a pro sees "Only Tara can change this." on every row of that clinic).
5. When a No-show is disputed, do you need to know who marked it, you or a
   pro? **Default: not recorded.** A late cancellation already records who
   made it; a No-show does not, and recording it is a new column
   (the sql-auditor's note, 2026-09-28).

## How we would know this was wrong

- `tests/sql/pro_role.sql` goes red: it attacks every function that asks
  `is_admin()` or `require_admin()`, every admin view, every relation a client
  can read (the pro must read what a member reads), every place `is_pro` or
  `'pro'` could hide in a function, policy or view, and every role change;
  `tests/sql/pro_mark_race.sh` goes red on what only a second session can
  show (a cancel or a charge landing while a mark waits). Both were proven
  red first, against twelve mutations and three, and one mutation exposed a
  blind spot in the first draft (a relation readable through column grants
  only was never counted; fixed). The sql-auditor then found the leak in
  item 4 that the first version had shipped with; the probe now asserts the
  property (a charged and an uncharged row answer alike) rather than a word.
- A pro reports seeing a price, a Player Pool, a phone number, or tomorrow's
  clinic; or Tara reports a pro changed something she did not expect.
- Tara asks for a pro to see more: then this record gets a successor, not an
  exception.
