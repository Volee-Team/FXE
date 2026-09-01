# Tara's real week, and the workflow the app is replacing

**Source:** email Tara sent 2026-08-08, forwarded to Alex, captured here
2026-08-13. Subject: "FXE - Ladies Tennis August 9th - 14th".

This is the first piece of *real* operational data the project has had. Every
clinic in `supabase/seed.sql` up to now was invented by us. This is what she
actually runs.

> **Privacy: the source email is NOT reproduced here.** It was addressed to
> roughly 300 real club members by name and email address. Those are real people
> who gave Tara an address for clinic scheduling, not for a GitHub repository.
> Only the schedule and the workflow are recorded below. **Do not paste that
> recipient list into this repo, into a prompt, or into the database.** When the
> roster does need to enter the system it enters as accounts those members
> create themselves, or with Tara's explicit consent as their program
> administrator, not as a bulk import from an email header.

---

## The actual schedule, week of Sunday 2026-08-09

| Day | Time | Clinic as she wrote it | Length |
|---|---|---|---|
| Sunday Aug 9 | 5:00–6:00pm | Coed "105" | 60 min |
| Sunday Aug 9 | 6:00–7:30pm | Coed "105" | 90 min |
| Tuesday Aug 11 | 8:00–9:00am | 3.0+ ladies clinic | 60 min |
| Tuesday Aug 11 | 6:00–7:30pm | coed "105" | 90 min |
| Wednesday Aug 12 | 6:00–7:00pm | ladies clinic | 60 min |
| Thursday Aug 13 | 8:00–9:00am | all level ladies clinic | 60 min |
| Friday Aug 14 | 8:00–9:00am | "105" | 60 min |
| Friday Aug 14 | 9:00–10:00am | level 4.0+ "105" | 60 min |

Eight clinics, six days, no Saturday and no Monday that week.

## What this confirms

**The service week is real.** The schedule runs Sunday through Friday and is
sent as one unit on the preceding Saturday morning. Decision 0001 (registration
opens per service week, Sunday–Saturday, not per clinic) was a guess at the
time. This is evidence it matches how she already thinks.

**The member / non-member split is real.** Her covering note: *"These are the
NONmembers I send to every week."* She maintains a separate non-member list and
mails it separately, which is exactly the two-tier priority the app models with
`member_opens_at` and `public_opens_at`.

**Her current workflow is the app's flow, done by hand.** From the email:

> *"Let me know what works and I will 'like' your message as confirmation you
> are IN and we are expecting you."*

Read that against the locked terminology:

| Tara does today | The app calls it |
|---|---|
| Mails the week's schedule to the list | Clinics published, registration open |
| Player replies "I'm in for Tuesday" | Register → **Player Pool** |
| Tara "likes" the message | Tara invites → player is **You're In!** |
| Nothing | **Response Needed** (the app adds an explicit accept step) |

She is already the selection step. Hard rule 2 (nothing is ever auto-promoted,
Tara chooses every player) is not a constraint we imposed on her: it is a
description of what she does. That is a good sign the model is right.

**Durations are 60 and 90 minutes.** Both already representable;
`clinics_public` exposes `duration_minutes`.

**Clinic naming is freeform and level-first.** "3.0+ ladies clinic", "all level
ladies clinic", "level 4.0+ 105". The name carries the level, which supports
decision 0006's reasoning that the clinic name does the work and separate level
filters are not needed in v1.

**No prices appear in the weekly email.** Consistent with pricing living on the
clinic record rather than in her communication.

## What this raises, unanswered

1. **What is "105"?** It appears five times, always in quotes, sometimes with a
   level ("level 4.0+ 105") and sometimes with an audience ("Coed 105"), and
   once alone. It is not in the Developer Guide, the spec, or any of our docs.
   It looks like a program or format name rather than a level. **This is
   question 1 for Tara** and it blocks naming the templates correctly.
2. **Is "ladies clinic" with no level a distinct offering** from "all level
   ladies clinic", or the same thing written two ways? Affects whether they are
   one template or two.
3. **The clinic categories question is still open** (`for-tara.md` question 8).
   This email suggests the real axis is level and format, not "Drill / Cardio /
   Match Play". Worth re-asking with this data in hand rather than in the
   abstract.
4. **What do members receive?** She says this list is non-members. Members
   presumably get a separate mail, or the club sends it. The app assumes one
   published schedule both tiers see, differing only in when they may register.
   Worth confirming that is right.
5. **"This will change come end of August."** The non-member list turns over.
   Ask what changes: the people, the schedule, or both.

## Juniors, and a date

The same email advertises the **junior fall session starting 2026-08-24**, ages
3.5+, sign-up by emailing Tara, with details at **fersc.com**.

Two consequences:

* Decision 0004 defers juniors out of v1 and expects them "before winter time".
  Her own fall session starts **2026-08-24**, which is sooner than that framing
  implies. Juniors are not a winter problem. Worth confirming whether the app is
  expected to handle the fall junior session or whether that one stays on email.
* **fersc.com exists.** Foxcroft East Racquet & Swim Club has a live site. That
  is relevant to the Apple Developer Program organisation enrollment, which
  wants a website for the legal entity, and it is worth checking whether FXE
  Tennis, LLC should point at fersc.com or at its own page.

## How this should be used

These eight clinics plus their templates are the natural first real content in
the hosted database. Per CLAUDE.md they must go in **through the app's own
admin path**, not a hand-written INSERT, so that the path gets exercised. That
admin path now EXISTS (2026-08-28): the web admin is live, her email
self-promotes to admin at sign-up, and the template picker makes each clinic a
three-click create. The remaining step is hers to take.
