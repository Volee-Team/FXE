# 0035: Crash and hang reports, through Apple's MetricKit, into our own database

**Date:** 2026-10-01 · **Status:** Active · **Source:** the main session's
brief for the 2026-11-06 launch: today, if the app crashes on a member's
phone, nobody finds out unless she tells Tara.

## What we chose

1. **MetricKit, Apple's own framework.** iOS collects a diagnostic for every
   crash, hang, CPU exception, excessive disk write and slow launch, and
   hands it to the app itself on the next launch (or at once on iOS 15+).
   `FXETennis/App/DiagnosticsReporter.swift` subscribes at launch
   (`PushAppDelegate`) and sends each one to our backend. MetricKit sends
   nothing anywhere on its own; that file is the only thing that moves a
   report off the phone.
2. **One table, one write, one read** (`20261001000001_app_diagnostics.sql`):
   `app_diagnostics` with no client privilege at all; the phone writes only
   through `report_app_diagnostic`, which takes the account from
   `auth.uid()`; an admin reads through `admin_app_diagnostics`, newest
   first, with `account_id` and no name or email.
3. **Bounded, because a member can write here.** The payload is at most
   64 KB of its text form (`octet_length(payload::text)`, checked by the RPC
   and by the table), each label at most 100 characters, and 20 rows per
   account per rolling 24 hours, counted under a per-account advisory lock so
   two calls at once cannot both pass at 19. The 21st is refused with
   `too_many_reports`, which the phone drops without a word: a crash loop is
   already visible in the twenty that landed.
4. **The phone keeps the payload under 60 KB itself**, so the server never
   has to refuse for size: a larger one becomes a smaller object that keeps
   MetricKit's metadata whole, the start of the rest as text, `truncated` and
   the original size. Always valid JSON (a cut-off string of JSON is not, and
   jsonb would refuse it). The 4 KB margin is for the ways Postgres prints
   JSON longer than Swift does; the spaces after colons and commas are
   counted exactly, number formats are not.
5. **Nothing is lost to a bad signal.** Signed out, offline, or no answer:
   the rows wait in a small JSON file in the app's Application Support folder, excluded
   from backup like the snapshot (decision 0028), newest 20 kept, and go on
   the next signed-in launch. A row that fails for a reason the phone cannot
   read is tried five times and then dropped, so one bad row cannot block
   the rest forever.
6. **Nothing is shown, blocked or logged.** No copy at all; nothing in front
   of a player (hard rule 13 has nothing to approve).
7. **`account_id` is who sent it, not who crashed.** A report that waited
   while signed out goes up under the next person to sign in on that phone.
   It exists for the rate limit. `on delete set null`, so the column is
   nullable: a crash report is a fact about a build, not the personal
   history hard rule 4 keeps, and it must never block a hard delete (account
   deletion, `20260921000003`, is a soft delete that keeps the row anyway).

## Rejected

- **Sentry, Firebase Crashlytics, Bugsnag.** A third-party SDK in the binary,
  a third party receiving data from members' phones, a new processor to name
  in the privacy policy and in App Store privacy labels, and another account
  for Alex to hold. They do symbolicate and group crashes for you, which
  MetricKit does not; at this club's size, reading a handful of reports by
  hand is cheaper than a vendor.
- **Xcode Organizer's crash reports alone.** They exist and cost nothing, but
  only from users who opted in to share analytics with developers, only for
  App Store and TestFlight builds, and only in Xcode on the account holder's
  Mac. Worth reading as well; not enough on their own.
- **An edge function instead of an RPC.** One more deploy and secret for no
  gain: the RPC already knows the caller from the JWT and runs the checks.
- **Accepting reports from signed-out phones.** Would need anon EXECUTE,
  which nothing in this schema has (`grants_are_explicit.sql`), and would let
  anyone with the publishable key fill the table. Waiting until sign-in costs
  a delay, not a report.

## How we would know this was wrong

- Reports arrive that nobody reads: the read needs a screen (a web admin
  panel) or a scheduled summary, not this RPC alone.
- Many reports arrive truncated: raise the cap (the table check and the RPC
  together) or store the call stack tree separately.
- A report is ever found to carry something about a person: stop sending
  that field on the phone, and delete the rows.

## Open

- **Privacy policy.** It lists what we collect and does not yet name crash
  diagnostics; the sentence is for Alex to approve before the policy is
  published (the main session has the proposed wording).
- **Retention.** Rows are kept forever today. A purge after, say, 180 days in
  the nightly `retention` job is cheap once someone picks the number.
- **Not verified end to end on a device.** MetricKit does not deliver on the
  simulator without Xcode's Debug → Simulate MetricKit Payloads; the pure
  parts are unit-tested and the RPC is probed, the hop between them is not.
