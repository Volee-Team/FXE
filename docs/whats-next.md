# What's next, and what we need from Tara

Living file. Updated 2026-09-21. Alex's target (2026-09-10): *"in the next week or two, get 95% of everything regarding the app/distribution/users"*, so about 2026-09-24; payments by October 1 (Tara). If something here is done, move it out; if
something new blocks, add it. This exists because the answer to "what's next"
kept living in chat and dying with the session.

---

## Blocked on Tara

Ordered by what it unblocks, not by how hard it is to answer.

| # | Question | Why it blocks | Our current assumption |
|---|---|---|---|
| 52–57 | **After her review of every word** (`docs/questions-for-tara.md` §L): the "Set by Tara" caption, the blank replacement for "Tara has your message.", "this week" under My Clinics, "Let's Play." vs "Let's play!", whether her policy block gets rewritten and shown, and whether "Stripe needs to be connected" was a note to us | Nothing blocks: every default is the current text | Keep as is |
| 27–51 | **Answered.** §I/§J on 2026-09-12 and 2026-09-16 (decisions 0010, 0012), §K on 2026-09-21 (decision 0013: no courtesy, 3 hours, card only, waiver, keep history on deletion, Saturday and short weeks as built, her tap charges) | | |

**Blocked on Alex (2026-09-12), two asks, both spelled out in `docs/launch-checklist.md`:**

1. **Stripe test keys** (§B): a Stripe *test-mode* account, its secret key and webhook secret set as Supabase Edge Function secrets (dashboard only, never the repo). Everything else on the payments path is built and deployed: schema, ledger, RPCs, three edge functions, the card screen on Profile, the Money tab ledger. Until the key exists, Add a card answers "Cards aren't set up yet."
2. **The public half of the backup key** into `.github/backup-recipient.txt` (§D10): the `age1...` line, pasted into the file or into chat. The nightly backup fails until it is there, and the old unencrypted artifacts are gone (2026-09-18), so right now there is no backup at all.
3. **Share Tara's review page** (`docs/tara-review/index.html`, published at https://claude.ai/artifact/1H3fCuvG7pkc9scTAJmfkL): open it, use the page's share menu to make a link, text it to her. Her answers come back as one pasted block from the page's "Copy my answers".

Dropped 2026-09-18: the `fxe-ci` Supabase project (§F option 3 chosen, no money for now; UI tests run on a laptop before each TestFlight build).

Also his: a tick through `docs/copy-review.md` for the connective words in the unpaid reminder. Tara's keep-or-change on the same strings supersedes his tick wherever she answers.

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

## Ask Kat (via Alex)

- Her "tagged / tag spec / what tool" line: release tags (answered: one per TestFlight upload, launch-checklist §C10) or analytics tagging (not built; roadmap Parked)? `docs/kat-due-diligence.md` maps all 18 of her questions to where each answer lives.

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
You're In! cancel without a note. Testing: 14 Playwright tests, 13 XCUITests
(5 on Tara's side), 23 unit tests, 23 SQL probes, and a 27-check Stripe
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
