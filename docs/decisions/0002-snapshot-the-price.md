# 0002 — Copy the price onto the registration

**Date:** 2026-08-10 · **Status:** Active

## Decision

When a registration is created, copy three facts onto its row: the price
charged, whether the player was a member at that moment, and how long the
clinic was. Never recompute any of them from the clinic afterwards.

## Why

Tara reconciles real money against these numbers. She needs to know what
*should* have been Zelled so she can settle with the club.

Reading the price off the clinic looks equivalent and is not. Edit a clinic's
price in September and August's revenue silently changes. Correct a
self-reported `is_member` flag and what that person owed in July changes with
it. Her books and the club's drift apart and neither side can see why.

Money is a historical fact. A player who joins the club in October still owed
the non-member rate in September.

## Rejected

**Read from the clinic.** Simpler, and wrong for the reason above.

**Freeze clinics after their first registration.** Stops the drift, but Tara
fixes typos in prices and times constantly. Making her program immutable to
protect a report is the tail wagging the dog.

## How we would know this was wrong

If Tara ever says "no, if I change the price it should update everyone who
already signed up." She has never said anything like it, and the reconciliation
use case points hard the other way.

## Pinned by

`tests/sql/pricing_and_revenue.sql` — `price_edit_does_not_rewrite_history`,
`membership_fix_does_not_rewrite_history`, `was_member_snapshot_frozen`.
