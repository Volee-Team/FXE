# What's next, and what we need from Tara

Living file. Updated 2026-08-26. If something here is done, move it out; if
something new blocks, add it. This exists because the answer to "what's next"
kept living in chat and dying with the session.

---

## Blocked on Tara

Ordered by what it unblocks, not by how hard it is to answer.

| # | Question | Why it blocks | Our current assumption |
|---|---|---|---|
| 1 | **Queen City: should the app actually stop non-team players registering?** | Decides whether "private clinic" is a real schema feature or just a description | We do NOT enforce it. Anyone may register; Tara picks from the Player Pool. Her own words: *"I'll just need to manually figure that one out"* |
| 2 | **Do members get a different email from the non-member list, or the same schedule?** | Decides whether one published schedule serves both tiers | One schedule, both tiers see it, differing only in when registration opens |
| 3 | **The rating guide, in her words** (`for-tara.md` q7) | It is what a nervous new member reads before self-rating, and self-rating decides which clinic they land in | Currently **copied verbatim from Volee** and reads like a chart, not like her. `docs/copy-audit.md` §1 |
| 4 | **Notification wording** (`for-tara.md` q14) | Push is the only way the app reaches anyone | 14 messages drafted by us. **Three speak as her, in first person.** `docs/copy-audit.md` §2 |
| 5 | **When does registration close?** (`closes_at`) | Nothing sets it, so registration never closes and finished clinics stay bookable | Unset. Options: at clinic start, some hours before, or only when full |
| 6 | **Junior fall session starts Aug 24.** Does the app handle it, or does that stay on email? | Decision 0004 deferred juniors to winter; her own session is sooner | Stays on email for now |
| 7 | **"Smart. Simple. Built for Tennis."** on the sign-in screen: keep it? | It came from the AI mockups, so it may not feel like hers | Keeping it until told otherwise |
| 8 | **Clinic categories** (`for-tara.md` q8) | The form has a "category" field with no agreed values | Her real schedule suggests the axis is format and level ("105", "3.0+"), not "Drill / Cardio / Match Play" |

**Answered already, do not re-ask:**
* What "105" is — answered 2026-08-15, in `docs/copy.md`
* Her real weekly list — the Aug 9-14 email IS it, captured in `docs/taras-real-week.md`
* Clinic descriptions — sent 2026-08-15, in `docs/copy.md`

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
3. **Tara's real admin account and clinics in hosted.** Hosted is empty: 0
   accounts, 0 clinics. Until this happens every client shows her nothing.
4. **Push notifications** — zero code anywhere. `supabase/functions/` is empty.
5. **Crash reporting** — none, before real members are on it.
6. **Privacy policy + account deletion** — required before children's data in v1.1.

## The honest state of the iOS app

Works: sign in, sign up, browse, register, cancel, leave pool, accept/decline,
clinic messages, the "?" explainer, and an admin tab where Tara can invite from
the Player Pool, mark paid, and message a clinic.

Missing: creating or editing a clinic, push notifications, News, profile
editing, a date floor on the clinic list.
