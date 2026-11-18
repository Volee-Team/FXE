# 0057. One account, several players: what the apps on phones see stays the same (2026-11-15)

**Status:** accepted by John, 2026-11-15 (*"get started on juniors and plan
for that to be as 1.0.5"*). Built in
`supabase/migrations/20261115000001_one_account_many_players.sql`. The first
step of juniors (`docs/juniors/plan.md`, phase 0). Amends decision 0004: the
junior columns stop being unused.

## The problem

Since July every account has had exactly one `players` row, the adult, and
code everywhere quietly relies on it. Tara's juniors document (spec 01) has a
parent add children under their own account. An audit on 2026-11-14 read the
latest definition of every SQL object, the app, both websites and the edge
functions. It found 16 places that break, pick the wrong row or open a hole
once an account also owns a child. The list is in the plan, phase 0. The
worst:

- **The iPhone app takes the first row as "me".** Row order is not stable, so
  a parent could become their child.
- **Spots are looked up by clinic alone.**
- **A parent could not delete their account.**
- **A child is an unrated second row**, which is exactly the level-check hole
  closed on 2026-11-05.

## Decision

**What an app already on a phone reads does not change.** 1.0.3 and 1.0.4
will be in use for weeks after 1.0.5 ships, so:

- A member's SELECT on `players`, and the views `my_registrations` and
  `my_past_clinics`, return the adult's rows only. Children and their bookings
  will be read through new functions that the 1.0.5 app and the members' site
  call.
- `clinics_public` lists no juniors clinic: those apps cannot register a
  child, so they would only show a Register button the server refuses.
  Juniors clinics are read through the family functions as well.
- A member's UPDATE on `players` reaches the adult row only. A child is
  edited through phase 1's functions.
- **Every account has exactly one adult**, a parent who never plays
  included (unique index). "Me" is always that row.
- **The Ladies / Men rule reads the adult's gender only.**
- **A junior plays only in a juniors clinic, and an adult never in one**
  (`wrong_player_kind`), on registrations and late requests.
  - Tara is exempt: she places anyone anywhere, as with the audience rule.
  - This also keeps a child row from ever being the way past the level
    check.
- **The calendar feed names a child's clinics** ("Sam: Red Dot").
- **A child's birthday is required while the row is active.** Deleting an
  account anonymises the child and makes the row inactive in the same
  statement.

## Rejected

- **A parent with no adult row.** The spec lets a parent who never plays
  hold children. Without an adult row, "me" is undefined in every screen that
  reads it, and `create_my_account` returns null. Keeping one adult row per
  account costs nothing: the parent's name and phone are already asked for.
- **Fixing the apps instead of the database.** It cannot reach an app already
  on someone's phone.

## Pinned by

`tests/sql/one_account_many_players.sql`, with every check but the "still
works" ones red before the migration.
