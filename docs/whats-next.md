# What's next, and what we need from Tara

Living file. Updated 2026-08-26. If something here is done, move it out; if
something new blocks, add it. This exists because the answer to "what's next"
kept living in chat and dying with the session.

---

## Blocked on Tara

Ordered by what it unblocks, not by how hard it is to answer.

| # | Question | Why it blocks | Our current assumption |
|---|---|---|---|
| 2 | **The late-request path.** Inside the 3-hour close, a player should be able to message her to ask in when the clinic is not full. What should that message say, and does she want it as a notification or in the app? | Half of her own answer to the close-time question | Not built. Registration simply closes |

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

## Blocked on Apple / business

| | Status |
|---|---|
| FXE Tennis, LLC Developer Program enrollment | **In review.** Tara sending photo ID, employment verification, and a business doc (Certificate of Formation is usually easiest) |
| Company email at own domain | **Done.** `fersc.com` accepted |
| D-U-N-S 11-654-7195 | Done |
| Team ID, bundle id, App Store Connect record | Waiting on enrollment |
| Privacy policy at a URL | Needed for external TestFlight and App Store, not internal |

## Blocked on nothing: what to build

1. **Web admin** — the way Tara sees this NOW, with no Apple account involved.
   Already an accepted ADR (`docs/web-admin.md`), approved by her as the laptop
   half of a split admin surface. Hosted free, talks to the same Supabase.
2. **Clinic and template CRUD** — the one remaining piece needing new backend.
   She asked directly: *"show me how I can easily change the schedule within the
   app as the super admin."* Today nothing can create or edit a clinic from any
   client, and `clinic_templates` has no write path at all.
3. **Tara's real admin account and clinics in hosted.** ~~Blocked~~ UNBLOCKED
   2026-09-01: hosted now has every migration, the web admin is live at
   `fxe-tennis-admin.vercel.app`, and her email self-promotes to admin on
   sign-up. The remaining step is HERS: open the site, Create account, build
   the week from templates.
4. **Push notifications** — zero code anywhere. `supabase/functions/` is empty.
5. **Crash reporting** — none, before real members are on it.
6. **Privacy policy + account deletion** — required before children's data in v1.1.

## The honest state of the iOS app

Works: sign in, sign up, browse, register, cancel, leave pool, accept/decline,
clinic messages, the "?" explainer, and an admin tab where Tara can invite from
the Player Pool, mark paid, and message a clinic.

Missing: creating or editing a clinic, push notifications, News, profile
editing, a date floor on the clinic list.
