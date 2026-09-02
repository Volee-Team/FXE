# What's next, and what we need from Tara

Living file. Updated 2026-09-01. If something here is done, move it out; if
something new blocks, add it. This exists because the answer to "what's next"
kept living in chat and dying with the session.

---

## Blocked on Tara

Ordered by what it unblocks, not by how hard it is to answer.

Nothing. Every question she has been asked is answered (2026-09-01).

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
| FXE Tennis, LLC Developer Program enrollment | **In review.** Tara sending photo ID, employment verification, and a business doc (Certificate of Formation is usually easiest) |
| Company email at own domain | **Done.** `fersc.com` accepted |
| D-U-N-S 11-654-7195 | Done |
| Team ID, bundle id, App Store Connect record | Waiting on enrollment |
| Privacy policy at a URL | Needed for external TestFlight and App Store, not internal |

## Blocked on nothing: what to build

Done since the last edit (2026-09-01, all merged and live): web admin, clinic
and template CRUD, Action Needed, Money, password reset, court dropdowns,
one-tap unpaid reminder, player directory with private notes, the anon
EXECUTE lockdown, and the first real nightly backup artifact.

1. **Tara's real clinics in hosted.** Hers to create at
   `fxe-tennis-admin.vercel.app`; asked 2026-09-01.
2. **Week grouping on the clinic list** (player side): the list is flat.
3. **`docs/architecture.md` rewrite** from the live schema and file tree.
4. **Push notifications** — zero code anywhere. `supabase/functions/` is empty.
5. **Crash reporting** — none, before real members are on it.
6. **Privacy policy + account deletion** — required before children's data in v1.1.

## The honest state of the iOS app

Works: sign in, sign up, browse, register, cancel, leave pool, accept/decline,
clinic messages, the "?" explainer, and an admin tab where Tara can invite from
the Player Pool, mark paid, and message a clinic.

Missing: creating or editing a clinic, push notifications, News, profile
editing, a date floor on the clinic list.
