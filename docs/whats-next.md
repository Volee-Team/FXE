# What's next, and what we need from Tara

Living file. Updated 2026-09-12. If something here is done, move it out; if
something new blocks, add it. This exists because the answer to "what's next"
kept living in chat and dying with the session.

---

## Blocked on Tara

Ordered by what it unblocks, not by how hard it is to answer.

| # | Question | Why it blocks | Our current assumption |
|---|---|---|---|
| 27–42 | **Payments and cancellations** (`questions-for-tara.md` §I is 27–37, §J is 38–42). Answered 2026-09-12: the cutoff is 4 hours and it is an honor system with a concise emergency note (decision 0010). Still open: the late charge amount, no-shows, whether the regular fee goes on the card, card required at sign-up, refunds on her cancel, her Stripe account, and the two sentences | Nothing can charge anyone until she answers: `payments_enabled` stays false | The defaults written beside each question |

**Blocked on Alex (2026-09-12), two asks, both spelled out in `docs/launch-checklist.md`:**

1. **Stripe test keys** (§B): a Stripe *test-mode* account, its secret key and webhook secret set as Supabase Edge Function secrets (dashboard only, never the repo). Everything else on the payments path is built and deployed: schema, ledger, RPCs, three edge functions, the card screen on Profile, the Money tab ledger. Until the key exists, Add a card answers "Cards aren't set up yet."
2. **A `fxe-ci` Supabase project in the FXE org** (§F): the only way the 13 XCUITests can run on every PR, because the macOS runner has no Docker for the local stack. Two minutes in the dashboard and two GitHub secrets; the workflow is ours to write once they exist.

Also his: a tick through `docs/copy-review.md` for the connective words in the unpaid reminder.

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

## Blocked on Apple / business

| | Status |
|---|---|
| FXE Tennis, LLC Developer Program enrollment | **In review.** fersc.com email accepted; ID and business docs submitted (same state as `docs/roadmap.md`) |
| Company email at own domain | **Done.** `fersc.com` accepted |
| D-U-N-S 11-654-7195 | Done |
| Team ID, bundle id, App Store Connect record | Waiting on enrollment |
| Privacy policy at a URL | Needed for external TestFlight and App Store, not internal |

## Blocked on nothing: what to build

Done since 2026-09-01 (all merged; hosted pushed through 20260912000005):
on the phone, the bell opens a notification center with read state in the
database, My Clinics is its own screen grouped by week, players edit their own
name, phone and rating, Tara cancels a clinic or removes a player from the
roster's More menu, a notification row opens the clinic it is about, the push
client half (permission sheet, APNs registration, `register_device` /
`unregister_device`, decision 0008), week grouping on the clinic list with a
five-week ceiling, and the 4-hour cancel note sheet (decision 0010). On the
web, three tabs (This week · Players · Money), canceled clinics hidden behind
a toggle, templates archived and restored instead of deleted, "Edited <date>"
under every note, the card-payments ledger on the Money tab, and Charge fee /
Charge late cancel / Refund as Tara's tap, rendered only while
`payments_enabled` is true. Underneath: the whole payments foundation
(decision 0009: ledger, card summary on accounts, `admin_charge_registration`
/ `admin_refund_payment`, the ledger-drives-Paid trigger, `service_role`
grants), the three Stripe edge functions deployed, the card screen on Profile
with PaymentSheet, `payments_ledger`, and `cancel_registration` refusing a late
You're In! cancel without a note. Testing: 12 Playwright tests, 13 XCUITests
(5 on Tara's side), 23 unit tests, 18 SQL probes, and a 27-check Stripe
pipeline against stripe-mock in CI. `docs/architecture.md` was regenerated
2026-09-01 and refreshed 2026-09-12. Nothing charges anyone: the switch is off.

1. **Tara's real clinics in hosted.** Hers to create at
   `fxe-tennis-admin.vercel.app`; asked 2026-09-01.
2. **Push notifications** — client half built 2026-09-02 (decision 0008). What remains needs the Apple Developer account: the APNs key, then the `push` edge function, the webhook, and the audit columns.
3. **Crash reporting** — none, before real members are on it.
4. **Account deletion in the app** — App Store guideline 5.1.1(v); what it deletes is a Tara question (`docs/launch-checklist.md` §C). Privacy policy needs a URL (Volee's can be reused, decision 16).
5. **XCUITests in CI** — waits on the `fxe-ci` project above.

## The honest state of the iOS app

Works: sign in, sign up, forgot password, browse by week with a date floor
and a five-week ceiling, register, cancel (with the 4-hour note inside the
cutoff), leave pool, accept/decline, the late request ("Message Tara" after
the close), clinic messages, the "?" explainer, the bell and its notification
center, My Clinics, profile editing, a card on file behind Stripe's
PaymentSheet (answers "Cards aren't set up yet." until the key exists), and an
admin tab where Tara can invite from the Player Pool, cancel an invitation,
assign courts, mark paid, send the unpaid reminder, message a clinic, answer
late requests, remove a player, cancel a clinic, and search the directory with
private notes.

Missing on the phone: creating or editing a clinic (web only), push delivery
(rows are written, nothing sends), News (deferred, decision 0006), and the
persistent notice while notification permission is denied (decision 0008
item 3, not built).
