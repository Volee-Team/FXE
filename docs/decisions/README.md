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
| [0003](0003-payments.md) | Zelle + a report for v1, Stripe in v1.1 | 2026-08-10 | Superseded in part by 0009 (Stripe moved into v1 with a card on file) and by 0013 (Zelle is not a payment path; the card is the only way to pay). `revenue_summary()` stands |
| [0004](0004-adults-only-v1.md) | Adults only in v1, juniors stay in the schema | 2026-08-02 | Active |
| [0005](0005-clinic-messaging.md) | Clinic messaging targets You're In!, Player Pool, or Both | 2026-08-12 | Active |
| [0006](0006-three-tabs-no-news.md) | Three tabs, News deferred, no Community tab | 2026-08-12 | Active |
| [0007](0007-tara-answers-2026-08-27.md) | Tara's answers: 3h close, 24h member head start, juniors to Nov/spring; §1 and §5 follow-ups closed 2026-08-28 (note at top of file) | 2026-08-27 | Active |
| [0008](0008-push-notifications.md) | Push: APNs from an edge function on a notifications webhook; device registration now, delivery when Apple issues the key; the app's receiving half (addendum 2026-09-27) | 2026-09-02 | Active |
| [0009](0009-payments-stripe-card-on-file.md) | Stripe direct with a card on file; every money event a row; policy as settings pending Tara's answers | 2026-09-12 | Active |
| [0010](0010-cancellation-four-hour-honor-system.md) | Cancellation is a 4-hour honor system: free before, a concise emergency note after, charging is Tara's tap | 2026-09-12 | Superseded: the emergency note by 0012, the 4-hour figure by 0013; the honor-system principle and Tara's tap stand |
| [0012](0012-cancellation-policy-and-charging.md) | Tara's cancellation policy verbatim: 4 hours, one courtesy per 90 days, cards charged after the clinic, card required to register | 2026-09-16 | Active, §2 and §6 superseded by 0013 |
| [0013](0013-tara-review-2026-09-21.md) | Tara's first full review: no courtesy, 3 hours, card only, the waiver signed in the app, deletion keeps history, her words on every screen | 2026-09-21 | Active |
| [0014](0014-testflight-through-johns-account.md) | Internal TestFlight builds from John's Apple account until the LLC is enrolled; `main` is the only source of a build | 2026-09-21 | Active until the LLC enrollment |
| [0015](0015-final-updates-2026-09-26.md) | Kat and Tara's Final Updates: straight header, court photo, Home by enrolment, card with permission at onboarding, no Zelle words, back-to-back 105 rule for non-members, board report, decline reasons | 2026-09-26 | Active |
| [0016](0016-tara-review-round-two-2026-09-22.md) | Tara's second review, read five days late: three sentences reworded, Rating Guide and Only Tara can change this, no "still owed", a super admin above the pros, guests billed to the member; a watcher so answers are never missed again | 2026-09-22 | Active |
| [0017](0017-reset-links-and-scanner-proof-reset.md) | Tara makes a one-time reset link for a member (no email needed), every link audited; the reset page takes scanner-proof token-hash links; Gmail app password as the free SMTP | 2026-09-27 | Active |
| [0018](0018-money-integrity.md) | One fee per player per clinic; a charged row is not relabelled; a canceled clinic is never charged; Tara's Late cancel; Money numbers from the ledger; only clinics ended after payments went on are owed | 2026-09-27 | Active, defaults pending questions 80 to 84 |
| [0019](0019-stripe-test-and-live.md) | Test-mode money is never money; the key swap by migration; when a charge is failed, retried or held, and Tara resolves held ones; deletion removes the Stripe customer | 2026-09-27 | Active |
| [0020](0020-when-things-go-wrong.md) | No signal is not "no profile"; failures classified by code; reload on return; a way out of every onboarding step; Larger Text; the web's bounded week; supabase-js vendored | 2026-09-27 | Active; item 5's mechanism superseded by 0023 |
| [0021](0021-payouts-and-chargebacks.md) | Payouts read from Stripe at the moment, never stored; chargebacks recorded on the fee from Stripe's webhooks; a lost one subtracts what Stripe withdrew and never makes the player owe again | 2026-09-28 | Active, default pending question 89 |
| [0022](0022-notifications-in-her-words.md) | Tara's notification catalogue wired verbatim from the database functions: when each message is sent and when it is not; one message per event under a double tap; no accepting, inviting or approving into a clinic that is canceled or over | 2026-09-28 | Active, defaults pending questions 79, 88, 90, 91 |
| [0023](0023-first-open-polish.md) | Accept and Decline from the lock screen; Add to Calendar with nothing about where; Remind me at this player's opening; text that follows Larger Text live; a readable clock on navy; the guide's type for page titles | 2026-09-28 | Active |
| [0024](0024-tara-review-round-four-2026-09-28.md) | Tara's round four: a pro role (today's rosters, Came / No-show, nothing financial), a declined card blocks sign-up and says why, Resolved for declines she won't chase, her uninvite message, a Contact Tara link, a QR code, the party moves to 2026-11-06 | 2026-09-28 | Active |
| [0011](0011-no-email-verification-v1.md) | No email verification in v1; hosted "Confirm email" is OFF by hand, and every new project needs the same flip | 2026-08-16 | Active |

Tara's own numbered decisions (1–23, calls of 2026-08-02 and 2026-08-12) are
tabled in CLAUDE.md; a bare "decision 17" in a record means that list. Not yet
recorded here: the 2026-08-15 admin-tab call (`MainTabView.swift` header) and
the 2026-08-28 Queen City label answer (`docs/whats-next.md`).

**Keeping this index complete is part of writing the record.** 0005 sat
unindexed from the day it was written until 2026-08-13, which meant the one place
you go to find a decision did not know it existed. A decision nobody can find has
the same value as a decision nobody wrote.
