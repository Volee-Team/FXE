# 0046. Everyone else opens Friday at noon (2026-11-01)

**Status:** accepted by John, 2026-11-01; built in
`supabase/migrations/20261101000001_public_opens_friday_noon.sql`.

## Her words

Tara, relayed by John on 2026-11-01, after he confirmed the app opened
non-members at Friday 8am: *"she wants to switch it to friday noon"*.

## The rule

| Who | Opens (New York time) | Was |
|---|---|---|
| Member | Thursday 8:00 AM, the Thursday before the service week | unchanged |
| Everyone else | **Friday 12:00 PM**, the Friday before the service week | Friday 8:00 AM |

Members' head start grows from 24 to 28 hours. Everything else in decision
0001 stands: one pair of moments per Sunday-to-Saturday week, a clinic's own
weekday has no effect, the values are stored on the clinic row, and Tara can
override any one clinic. Decision 0045 (members are in whenever there is room)
is unchanged.

## What changed

- `public.public_opens_at()` returns noon instead of 08:00. Every admin path
  that stores a window takes its default from it (`admin_upsert_clinic`,
  `create_clinic_from_template`, `admin_copy_week`), so new clinics get noon.
- **Backfill.** A clinic already created moves to noon only when its stored
  public open is exactly the old default (Friday 08:00 of its week) and that
  moment is still ahead. A time Tara typed herself is left alone (hard rule 6),
  and a week already open to everyone is not closed to non-members again for
  four hours.
- `register_for_clinic` reads the stored column, so it needed no change; nor
  did the app or the members' site, which also read the stored value. The app
  changes are comments only.

## Still open

**Question 134:** members stay Thursday 8:00 AM. Built default: yes, she only
asked about non-members.

## Tests

- `tests/sql/registration_window_rule.sql`: every public expectation is now
  Friday 12:00, transcribed from the rule, and `member_head_start_is_always_28h`
  replaces the 24-hour check. 16 checks went red against the old function and
  all 45 are green on the new one.
- `tests/sql/schema_decisions.sql`: `tara_member_head_start_is_28h` (was
  `_24h`), red at 24.0 on the old function.
- `tests/sql/copy_week.sql`: the copied Saturday clinic's public open is
  Friday 2026-10-30 16:00Z (noon EDT), red at 12:00Z on the old function.
- `tests/sql/public_open_backfill.sh` (new): plants three rows, runs the real
  migration file over them in one transaction and rolls back. The default row
  moves to noon with its member open untouched; a hand-set row and an
  already-open row stay. Each guard was shown red by running a copy of the
  migration without it (no backfill, no equality guard, no `now()` guard).
