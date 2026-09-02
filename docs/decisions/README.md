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
| [0003](0003-payments.md) | Zelle + a report for v1, Stripe in v1.1 | 2026-08-10 | Active |
| [0004](0004-adults-only-v1.md) | Adults only in v1, juniors stay in the schema | 2026-08-02 | Active |
| [0005](0005-clinic-messaging.md) | Clinic messaging targets You're In!, Player Pool, or Both | 2026-08-12 | Active |
| [0006](0006-three-tabs-no-news.md) | Three tabs, News deferred, no Community tab | 2026-08-12 | Active |
| [0007](0007-tara-answers-2026-08-27.md) | Tara's answers: 3h close, 24h member head start, juniors to Nov/spring | 2026-08-27 | Active |
| [0008](0008-push-notifications.md) | Push: APNs from an edge function on a notifications webhook; device registration now, delivery when Apple issues the key | 2026-09-02 | Active |

**Keeping this index complete is part of writing the record.** 0005 sat
unindexed from the day it was written until 2026-08-13, which meant the one place
you go to find a decision did not know it existed. A decision nobody can find has
the same value as a decision nobody wrote.
