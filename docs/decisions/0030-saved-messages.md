# 0030: Tara's saved messages: her words, kept and offered back

**Date:** 2026-09-28 · **Status:** Active · **Source:** the roadmap's "Tara's
tools" list (2026-09-28): "Her saved messages: sentences she sends often, kept
in her words, sent in one tap." · **Built in:**
`supabase/migrations/20260928900001_message_templates.sql`,
`web/saved-messages.js`, the Message Players sheet
(`FXETennis/Views/Components/SavedMessagesControls.swift`)

## What we chose

1. **The app stores what she typed and offers it back. It never writes one.**
   No seed row, no default, no suggestion, no server-side text (hard rule 13).
   A fresh database shows "No saved messages yet."
2. **Where.** In the two places she already writes a clinic message: the web
   Message dialog on a clinic card and Message Players on the phone's roster.
   A **Saved** list (web) or menu (phone) above the box, newest first;
   choosing one fills the box; she still picks the audience and taps Send,
   and the send is still `send_clinic_message` with recipients resolved by
   the database. **Save this message** under the box keeps the current text.
   **Remove** beside each (web) or in a Remove submenu naming each (phone).
3. **The server.** `message_templates` (id, body, created_at, archived_at),
   RLS on with no policy, nothing granted to any client role (hard rule 11);
   `service_role` DML written out like every table. Three functions, each
   opening with `require_admin()`, revoked from `public, anon, authenticated`
   and granted to `authenticated`: `admin_message_templates()`,
   `admin_save_message_template(p_body)`, `admin_archive_message_template(p_id)`.
4. **Kept once, by the index, not by a read.** A unique index on `md5(body)`
   over live rows; the save is `insert ... on conflict do nothing` and then a
   read of the live row. Two saves at the same moment (phone and laptop, a
   double click) cannot both insert: the second waits for the first, then
   returns its row. md5 rather than the text because a btree entry is capped
   near 2.7 kB and 1000 accented or emoji characters can be 4 kB.
5. **Remove archives** (hard rule 4) by a conditional update (`where
   archived_at is null`, hard rule 3). It answers true when this call removed
   it and false when it was already removed elsewhere; the client just
   reloads, and the list is the truth. An id that was never a saved message
   raises `message_template_not_found`, because that is a bug. Saving the same
   words after a Remove makes a new live row; the removed one stays.

## Choices the spec left to me

- **Whitespace at the two ends is trimmed; nothing inside is touched.** So
  "See you at 9 " and "See you at 9" are one saved message, not two that look
  the same in the list; case, punctuation and inner spacing are her words and
  stay (a different case is a different message).
- **The table check is stricter than the spec's literal one.** The spec wrote
  `check (length(trim(body)) between 1 and 1000)`. Postgres `trim()` strips
  spaces only, so a body of one newline passed it (mutant M6 below: the probe
  inserted `E'\n'` under that check). The constraint is `body =
  btrim(body, E' \t\n\r') and length(body) between 1 and 1000`: what is stored
  is already trimmed, which also keeps the md5 index honest for any writer
  that is not the function.
- **1000 counts characters, as Postgres `length()` does**, and both clients
  count the same way: Unicode scalars in Swift (`unicodeScalars.count`, not
  `String.count`, which counts 👍🏽 as one where Postgres counts two) and code
  points in JavaScript (`[...text].length`, not `.length`). Save this message
  is off outside 1 to 1000, so the server's two refusals (`message_empty`
  22023, `message_too_long` 22001) cannot be reached from either screen and
  need no words.
- **`created_at` is `not null`**, and the list breaks a tie on `id`, so the
  order is the same on every read.
- **The functions return the table's row type**, like `send_clinic_message`:
  admin-only, and it avoids PL/pgSQL's OUT-parameter name clashes.
- **Remove on the phone is a submenu**, so one stray tap in a menu never
  removes a message; on the web it is one click, because nothing is lost (the
  row is archived) and a confirmation would be a new word.
- **Pros never see them.** The pro role (branch `pro-role`, decision 0025)
  keeps `is_admin()` false for a pro, so `require_admin()` refuses one. The
  probe does not name the pro: it loops over every non-admin value of
  `account_role`, so the day that branch merges the pro is attacked too.
- **No Restore.** The spec asked for none; the archived rows are there if
  Tara ever wants one.

## Rejected

- **Check-then-insert for "kept once"** (read "is it there?", then insert).
  Passes every single-session test and fails under two saves at once:
  `message_template_race.sh` is red with it (two live rows, two ids).
- **Insert without ON CONFLICT, with the index.** The second of two saves at
  once gets a unique violation instead of the row (red in the race probe).
- **Unique on the text itself.** Past about 2.7 kB the index refuses the row.
- **Storing the text exactly as sent, spaces and all.** Duplicates that differ
  by a trailing space or newline, which look identical in the list.
- **Seeding a few example messages** for local development. They would be
  words Tara did not write (hard rule 13), and `seed.sql` is for fake people,
  not fake copy.
- **A Remove confirmation, a "Saved." toast or a "too long" sentence.** Each is
  new chrome for Alex's tick; the list itself shows what happened.

## How we would know this was wrong

Tara finds two copies of one message in her list (the index or the trim is
not doing its job), a message she removed comes back without her saving it
again, or anyone but her can read one. The probe (`message_templates.sql`, 46
checks) and the race probe pin each; red first under the mutants recorded in
the PR: grants on the table (5 rows), grants with RLS off (8), no
`require_admin` (7), PUBLIC execute (2), Remove as a delete (4), an
unconditional stamp (2), the spec's literal check (2), that check plus no trim
(7), the limit in bytes (1), oldest first (1), no unique index (1, and the race
probe), no ON CONFLICT (the race probe).

## Open, for Tara if she wants it

- Should choosing a saved message **replace** what is in the box (built) or be
  added to it?
- Past 1000 characters Save this message is simply off, with no sentence.
