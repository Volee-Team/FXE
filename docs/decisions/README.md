# Decision records

One file per decision that would otherwise get re-litigated. Cheap to write,
and they answer the question a new person always asks: *why is it like this?*

Format: what we decided, why, what we rejected, and how to tell if it was wrong.
Numbered in order. **Never edit a decision** — if it changes, write a new one
that supersedes it, and add a line at the top of the old one pointing forward.
The history of what we believed is part of the record.

| # | Decision | Date | Status |
|---|---|---|---|
| [0001](0001-registration-is-per-week.md) | Registration opens per service week, not per clinic | 2026-08-02 | Active |
| [0002](0002-snapshot-the-price.md) | Copy the price onto the registration | 2026-08-10 | Active |
| [0003](0003-payments.md) | Zelle + a report for v1, Stripe in v1.1 | 2026-08-10 | Superseded in part by 0009 (Stripe moved into v1 with a card on file; the Zelle + report half stands until it ships) |
| [0004](0004-adults-only-v1.md) | Adults only in v1, juniors stay in the schema | 2026-08-02 | Active |
| [0005](0005-clinic-messaging.md) | Clinic messaging targets You're In!, Player Pool, or Both | 2026-08-12 | Active |
| [0006](0006-three-tabs-no-news.md) | Three tabs, News deferred, no Community tab | 2026-08-12 | Active |
| [0007](0007-tara-answers-2026-08-27.md) | Tara's answers: 3h close, 24h member head start, juniors to Nov/spring; §1 and §5 follow-ups closed 2026-08-28 (note at top of file) | 2026-08-27 | Active |
| [0008](0008-push-notifications.md) | Push: APNs from an edge function on a notifications webhook; device registration now, delivery when Apple issues the key | 2026-09-02 | Active |
| [0009](0009-payments-stripe-card-on-file.md) | Stripe direct with a card on file; every money event a row; policy as settings pending Tara's answers | 2026-09-12 | Active |
| [0010](0010-cancellation-four-hour-honor-system.md) | Cancellation is a 4-hour honor system: free before, a concise emergency note after, charging is Tara's tap | 2026-09-12 | Partial |

Tara's own numbered decisions (1–23, calls of 2026-08-02 and 2026-08-12) are
tabled in CLAUDE.md; a bare "decision 17" in a record means that list. Not yet
recorded here: the 2026-08-15 admin-tab call (`MainTabView.swift` header) and
the 2026-08-28 Queen City label answer (`docs/whats-next.md`).

**Keeping this index complete is part of writing the record.** 0005 sat
unindexed from the day it was written until 2026-08-13, which meant the one place
you go to find a decision did not know it existed. A decision nobody can find has
the same value as a decision nobody wrote.
