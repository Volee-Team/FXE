# 0055. A membership correction moves the player's clinics not yet over (2026-11-11)

**Status:** accepted by John, 2026-11-11 (he relayed Tara's report and asked
for the fix in build 17); built in
`supabase/migrations/20261111000001_membership_reprices.sql`. Narrows the
membership clause of decision 0002; its price clause was narrowed by 0053.

## Her words

Relayed by John on 2026-11-11: *"[a player] is a member and getting charged
nonmember prices. Can you check on this?"*

## What happened

The player signed up as a non-member and registered for six clinics on
11-07. Tara made her a member before 11-10. Every registration keeps the
`was_member` and price it was made with (0002), and `admin_set_membership`
changed `players.is_member` alone, so four clinics were charged the
non-member price after she was a member ($22 over in all) and an 11-13 clinic
sat at $28 instead of $22.

## Decision

When Tara changes a player's membership, every registration of theirs on a
clinic that has not ended, not canceled, that can still owe (not canceled, or
a late cancel), not marked Paid and holding no charge (pending, processing or
succeeded) takes the new answer: `was_member`, and the clinic's price for it,
the rain half included. A price she typed (0054) keeps its amount and takes
the new `was_member`. Both ways: made a non-member, the clinics to come cost
the non-member price.

A clinic that has ended keeps what it was, charged or not. 0002 still holds
for history: "A player who joins the club in October still owed the
non-member rate in September", and a closed period's reports never move.
Tara changes one past row by hand with Set price.

Money already taken is a refund, not a reprice. Refunds are whole charges in
the app; part of a charge is refunded in Stripe's dashboard, which the
webhook records as a partial refund and leaves Paid alone.

## Rejected

**Everything not yet charged, past clinics included.** The first draft. The
sql-auditor showed it rewrote the board report and the board share for a
closed month whenever an old row was never marked Paid (the Zelle-era
clinics, a waived or declined card).

**Leave it to Tara row by row.** She did not know the prices had not
followed, and nothing on her screen said so.

## Known gap

A registration being made at the same moment Tara changes the membership
(`register_for_clinic`, `place_player`, `admin_invite_player` read
`is_member` without a lock) can keep the old answer. Milliseconds, both
people acting at once; noted in the backlog, not built.

## Pinned by

`tests/sql/membership_reprice.sql`.
