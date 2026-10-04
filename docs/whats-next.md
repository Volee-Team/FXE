# State of the app

**This file holds no tasks.** Everything left to do before launch, with its
owner and status, is in `docs/launch-checklist.md`, the one list (Alex,
2026-09-27: *"i like having one thing to totally trust"*). This page says
where things stand. Updated 2026-09-28; launch target 2026-11-06 (Tara moved the party, decision 0024).

## Where things stand, 2026-09-27

- **On testers' phones:** TestFlight build 2, from John's account (decision
  0014). **Next:** build 4 (the MVP audit's fixes), once the `mvp-fixes` PR
  merges; John uploads it (checklist C8).
- **Hosted:** 45 of 45 migrations paired as of 2026-09-27 (`supabase migration
  list --linked`); `20260928000001` (Tara's notification words),
  `20260928200001` (disputes) and `20260928300001` (no accepting a canceled
  clinic) go with their PR; every edge function deployed; Stripe's sandbox keys and
  webhook secret in place (checklist A1); **payments switched off** until
  Alex says go (A9); a signed-out caller reaches nothing (122 targets closed, with the web admin's functions answering the browser's preflight).
- **Admin site:** https://fxe-tennis-admin.vercel.app, verified byte for byte
  against `main` on 2026-09-27; the privacy draft is kept off it until
  approved.
- **Waiting on others:** Apple's LLC approval (C1), Tara's answers 52 to 68
  (G2), Kat's style calls (G3), the MVP call (G1).

## The honest state of the iOS app

Works, and tested (probes, unit tests, browser tests in CI; the 23 UI tests
on the simulator before each TestFlight build): sign up with profile, waiver
and (once payments are on) a card with the permission box; sign in; the
front page (your clinics, then what is open to you now); browse by week;
register (You're In! or Player Pool by the Thursday/Friday rule, the
back-to-back 105 rule for non-members); cancel, with the 3-hour rule and an
optional note to Tara; leave the Pool; accept or decline an invitation;
message Tara after registration closes; clinic messages; the "?" explainer;
the bell and its notification center; My Clinics with Past, from Profile;
edit profile; delete my account; and Tara's Manage tab (invite from the Pool,
cancel an invitation, courts, Came or No-show, remove a player, cancel a
clinic, message a clinic, late requests, the players directory with private
notes, the Stripe link); and a pro's Today tab (decision 0025, branch
`pro-role`): today's clinics, who is You're In! and on which court, Came or
No-show and Late cancel, nothing else, with Tara ticking Pro on the web
admin's Players tab.

**Does not work yet, and why:**
- **Forgot password:** the app side works, but the email never reaches a
  member. Hosted has no email sender of its own, and Supabase's built-in one
  delivers only to the Supabase project's own team (checklist D1). Found
  2026-09-27; this page and `docs/mvp.md` had said it worked.
- **Card payments:** built and deployed; the switch is off (A9), and the real
  card sheet has only ever run against Stripe's mock, never Stripe itself (A2).
- **Push on the lock screen:** built and deployed; waits on Apple's key (C3).
  Notifications show inside the app meanwhile. The app's receiving end is in
  the build since 2026-09-27: a banner while it is open, a tap opens the
  clinic (an invitation lands on Accept and Decline), and the icon's number
  is the bell's.

Missing on the phone by design: creating or editing a clinic (web only),
News (deferred, decision 0006).

Testing today: 46 Playwright tests, 23 XCUITests (9 player flows, 7 on
Tara's side, 2 on a pro's, and 5 accessibility checks: Apple's audit on the
player's, Tara's and the pro's screens, the status bar and the Return key),
234 unit tests, 44 SQL probes, a 94-check Stripe pipeline and a 57-check push pipeline
against mocks in CI.
Since 2026-09-28 (decision 0026): a card
Stripe declines holds no spot until a card is saved again, and says why in
Tara's words; her Resolved clears a decline from her lists.

**Answered already, do not re-ask.** Six of the eight closed on 2026-08-27; see
`docs/decisions/0007`.

* What "105" is — 2026-08-15, in `docs/copy.md`
* Her real weekly list — the Aug 9-14 email IS it, in `docs/taras-real-week.md`
* Clinic descriptions — 2026-08-15, in `docs/copy.md`
* **Queen City eligibility** — not enforced, and the ambiguity is resolved
  (2026-08-28): *"Queen City means our FXE Queen City team. No nonmembers or
  anyone other than those on the team will be able to practice at that time. As
  long as it's labeled 'FXE QC Team practice' no one else should sign up for
  that. And if they do - I'll let them know."* So: normal Player Pool behaviour,
  the LABEL is the control, and she polices exceptions by hand. The clinic name
  must be exactly **FXE QC Team practice**
* **Member head start** — 24 hours, same email, same schedule. Confirms decision 0001
* **Rating guide** — stays as Volee material, she is happy with it
* **Notification tone** — first person approved, "personal but not cheesy"
* **Registration close** — 3 hours before start, and she expects to adjust it
* **Juniors** — November or the spring session, not a fall problem
* **The late-request path** — built 2026-08-28 without waiting on her wording:
  a player inside the 3-hour close taps "Message Tara" and types their own
  message; she sees it under Action Needed with Put them in / No room
  (2026-09-01). No invented copy, because the message is theirs

