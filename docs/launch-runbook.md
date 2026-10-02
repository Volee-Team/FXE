# Launch runbook: the pre-mortem, the dress rehearsal, and the day

Written 2026-10-01 for the launch party on 2026-11-06 (decision 0024). Alex
asked for "ZERO margin for error on the first launch". No process gives zero;
what this page does is name every way the day could go wrong, ahead of time,
and give each one either a fix that is already built or a person who owns it.
The tasks themselves live in `docs/launch-checklist.md`; this page links to
its rows and adds nothing to do that is not there.

Three industry practices, briefly, since the names are worth knowing:

- **Pre-mortem** (Gary Klein): before launch, imagine it is the day after and
  it went badly, and write down why. People name risks they would not raise
  in a "what could go wrong?" meeting, because the failure is already given.
- **Game day** (dress rehearsal): run the real system with real people on a
  real scenario before the day it counts, so the first time anything happens
  is not in front of the club.
- **Runbook**: what each person does, in order, on the day and when something
  breaks, written down so nobody improvises under pressure.

## 1. Pre-mortem: "It is 2026-11-07 and the launch went badly. Why?"

Each line: what went wrong, how likely, what already stops it, who owns the
rest. Re-read this page at the dress rehearsal and the day before.

| # | What went wrong | Already in place | Still open, and whose |
|---|---|---|---|
| 1 | **Members could not install the app.** The App Store listing needs the LLC's Apple account, still in Apple's queue (C1); without it the only way in is TestFlight's public link, which needs Apple's beta review first (C11) | The QR code points at `/app`, which forwards wherever the install link is, so the printed card never changes (I6) | Alex: submit external TestFlight for review **by 2026-10-23** whatever happens with the LLC, so a link exists two weeks out. Deferred 2026-10-01 ("not this moment"); this is the date it stops being optional |
| 2 | **Real cards could not be charged.** Tara's Stripe activation (business, EIN, bank) was not finished, or Stripe held the account for review | Payments are a switch (`payments_enabled`); with it off, nobody needs a card and nothing is charged, and Tara can take Zelle as before | Tara: activate by **2026-11-04** (A7, A11). Alex: transfer Stripe ownership (step 2d). The fallback is the switch off at the party, decided in advance, not on the night |
| 3 | **Thursday 8:00 rush broke registration.** Everyone taps Register at the same moment | Capacity is decided in one locked place (`register_for_clinic`, `FOR UPDATE`), tested by `capacity_race.sh`; the nightly keep-warm job stops the free project pausing | The rush is tested at 200 at once locally (section 4 of this page). Alex: decide whether to put the project on Supabase Pro for the launch month (no pausing, daily backups, more connections, about $25) |
| 4 | **The app crashed for some members and nobody knew** | Apple's crash reports reach John's App Store Connect for TestFlight builds only when testers share them | Crash reports to our own database (decision 0035, in progress 2026-10-01) |
| 5 | **It broke on an older iPhone.** Members' phones run iOS 17 and 18; the team's run iOS 26 | Supports iOS 17.0 and up; the screens that differ by iOS version were written with both branches | The whole UI suite on iOS 18.6 and 17.5 simulators, including the smallest screen (iPhone SE) and the largest text size, recorded per iOS version by `scripts/run-ui-tests.sh` (2026-10-01) |
| 6 | **Members missed messages.** Push never reached a lock screen | Push is built end to end and tested against a mock Apple server; the in-app bell holds everything regardless | John: the push key (C3); then one real invitation to Alex's phone |
| 7 | **"Forgot password" emails never arrived** | Custom Gmail sender, read back through the management API; a reset sent from the app to Alex's address was stamped by the server (2026-10-01) | Alex: confirm the email arrived and the link worked (step 6); one more test with a non-Gmail address (iCloud or Outlook) to check spam handling. Tara can always hand out a one-time reset link from the Players tab, no email needed (decision 0017) |
| 8 | **Sign-up was too long and people gave up** (account, profile, waiver, card) | Each step is one screen; the waiver and card steps say why they refuse | The dress rehearsal (section 2) times a real sign-up on a stranger's phone |
| 9 | **Tara's real week was not in the app**, so the first thing members saw was an empty list | Copy to next week makes a week from the last one in two clicks (decision 0027) | Tara: enter her real templates and the first real week (D5) before the rehearsal |
| 10 | **A bad build reached members and could not be taken back** | TestFlight keeps earlier builds: a tester can reinstall the previous one from the TestFlight app; every upload is tagged (C10) | Never upload a build the day before the party. The last build is the one the rehearsal used |
| 11 | **Someone could see what they should not** (a court, a count, another member) | Enforced in the database (hard rule 1), pinned by `information_hiding.sql` and checked on production every night by `hosted-watch.yml` (2026-10-01) | Nothing open |
| 12 | **The database was lost or corrupted** | Nightly encrypted backup, restored once in a drill (2026-09-22) | Repeat the restore drill the week before the party, so the backup is known good on data that matters |
| 13 | **Nobody knew who to call** | This page | Section 3 |

## 2. The dress rehearsal (game day), target the week of 2026-10-26

A real week, on the live system, with 5 to 10 people who are not the team,
on their own phones, about ten days before the party so there is time to fix
what it finds.

Before it: Tara's real templates and that week's clinics are in (D5); the
build the members will get is on TestFlight; payments in the mode they will
be in at the party.

The script, each line watched by someone and timed:

1. A newcomer installs from the QR code, signs up, signs the waiver, adds a
   card. Time it. Anything they ask out loud goes in the backlog.
2. Thursday 8:00: members register at the same moment for a clinic with
   fewer spots than people. Some land in You're In!, the rest in the Player
   Pool. Nobody sees a count.
3. Tara invites one person from the Pool; they Accept from the notification.
4. Someone cancels inside 3 hours; Tara sees the late cancel.
5. Tara cancels a clinic; everyone in it is told.
6. After the clinic: Came / No-show, then Charge clinic. The charges show on
   the Money tab and in Stripe.
7. Someone uses Forgot password.
8. Afterwards: every finding gets a row in the backlog with an owner, and the
   pre-mortem table above is re-read.

## 3. On the day (2026-11-06)

| When | Who | What |
|---|---|---|
| Morning | Model | `hosted-watch.yml` has run (06:17 New York); its result read; the nightly backup ran; `hosted-smoke.sh` by hand |
| Morning | Alex | One sign-in on his own phone, one look at Home |
| Before the party | Tara | The week's clinics are published; the QR card is printed |
| During | Alex | The phone with the admin login, for anyone stuck: Tara's Reset link for passwords, her Players tab for membership |
| During | Model, on call through Alex | Anything broken: diagnose from the logs and the database, fix through a PR, never by hand on production (Build & Run in `CLAUDE.md`) |
| After | Everyone | What went wrong goes in the backlog the same night |

**If payments misbehave on the night:** the switch is `payments_enabled` in
`app_settings`, which only a migration can change today (no admin control;
backlog). Turning it off is a one-line migration pushed by the model, about
ten minutes through CI. Decide before the party whether that is fast enough
or whether Tara needs a switch of her own.

**If the app will not open for everyone:** check the Supabase status page
and the project's state in the dashboard first (a paused free project
answers with an error, not silence; the keep-warm job exists to prevent
it), then the admin site, which uses the same backend.
