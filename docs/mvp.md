# MVP: what is critical, and what is not

Draft for Tara, Kat and Alex to argue with (Alex, 2026-09-22: *"we need to
define w tara and kat: what is CRITICAL to get us to an MVP, then have some
people start testing it and get full launch HOPEFULLY by the planned launch
party oct 16"*). Every row below is a fact about the code today; the column
"MVP?" is the proposal, and it is theirs to change. Owners and detail live in
`docs/launch-checklist.md`; this page is the short version for the call.

## What a member can do today (built, on TestFlight)

| Feature | State | MVP? |
|---|---|---|
| Sign up, sign in, forgot password | built | yes |
| Profile: name, phone, rating (required), member yes/no, note for Tara | built | yes |
| Waiver signed once, in the app | built | yes |
| Browse clinics by week, prices by membership, the "?" explainer | built | yes |
| Register: You're In! or Player Pool by the Thursday/Friday rule | built | yes |
| Cancel, leave the Pool, accept or decline an invitation | built | yes |
| Cancel inside 3 hours: fee applies, optional note to Tara | built | yes |
| Message Tara after registration has closed | built | yes |
| Clinic messages from Tara, the bell, notifications in the app | built | yes |
| My Clinics with Past | built | yes |
| Card on file (Stripe PaymentSheet) | built, off until Stripe keys | **decide** |
| Delete my account | built | yes (Apple requires it) |
| Push notifications on the lock screen | client built; sender waits on Apple's key | **decide**: without it, updates are only in the app |

## What Tara can do today

| Feature | State | MVP? |
|---|---|---|
| Web admin: templates, publish the week, edit, cancel a clinic | built | yes |
| Roster: invite from the Pool, courts, remove, Came/No-show | built (web and phone) | yes |
| Message a clinic by audience | built | yes |
| Walk-up straight into a clinic; late requests | built | yes |
| Players directory with her private note, membership override | built | yes |
| Money: expected/collected/owed, the card ledger | built | yes |
| Charge clinic (one tap after it ends), refunds | built, off until Stripe keys | **decide** |
| Manage cards in Stripe's dashboard | link on Money (2026-09-22) | yes, if payments are in |

## Not built, and a decision each

| Item | Why it is not in | Decide |
|---|---|---|
| Push delivery (APNs) | needs the Apple Developer key; the LLC enrollment is in Apple's queue | in MVP or not? If in, MVP waits on Apple |
| Payments switched on | needs Stripe keys (Alex, "prob tomorrow") and Tara's Stripe account | if in, Q56's policy text and the card sentence go live |
| Registration-is-open reminders | needs a scheduler and Tara's answer on timing | later |
| Juniors, News, Community | deferred by Tara (decisions 0004, 0006) | later |
| Privacy policy at a URL | Apple needs it for external TestFlight and the store | needed before launch, not before internal testing |

## The path to October 16

1. This week: Kat's style guide lands; the TestFlight round-two fixes ship; the MVP list above is settled.
2. Then: a testing group on TestFlight (internal, through John's account) for two weeks, with Tara's real templates and clinics in the admin.
3. Then: the LLC enrollment (or John's account as the fallback) carries the public TestFlight and the store listing; privacy policy URL; the Stripe switch if payments are in.
4. Launch party, 2026-10-16.
