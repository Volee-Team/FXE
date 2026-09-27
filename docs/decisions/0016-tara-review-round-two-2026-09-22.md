# 0016: Tara's second review (2026-09-22): four sentences reworded, a super admin, guests billed to the member

**Date:** answered 2026-09-22, read and applied 2026-09-27 · **Status:** Active · **Supersedes:** "Need Help?" (Screen 4), "Set by Tara" (2026-09-02), the charge summary line and "Still owed" (2026-09-16)

## How this arrived, and why it sat for five days

Tara answered round two of her review page (`web/review.html`, page version 2,
link "Tara Link") on 2026-09-22 at 16:28 UTC. Her answers saved to
`review_responses` on hosted as designed. **Nobody read them until 2026-09-27**,
when round three was about to be sent over the top of them and Alex asked
*"is she not responding to the same questions over and over again??"* She was
about to be.

The failure is a missing mechanism, not a missing habit: the page saves
silently and nothing tells anyone a response arrived. The fix is in the same
change as this record (see "Mechanism" below).

## What she said

Every line below is hers, from the saved response. Everything she did not mark
is "keep", 98 lines, including every sentence she wrote herself.

**Words she changed:**

| Was | Her answer |
|---|---|
| "Need Help?" (the rating guide button at sign-up) | Change, no replacement written |
| "This cancellation is within 3 hours of clinic and the full clinic fee will apply. If there are circumstances you'd like us to consider, please leave a note below." | *"This cancellation is within 3 hours of clinic and the full clinic fee will apply. If an emergency, please leave a note below."* |
| "She will let you know asap if there is room in this clinic" | *"She will let you know as soon as possible if there is room in this clinic"* |
| "Your card will only be charged after the clinic you attended, late cancellations, or no-shows. Cancel at least 3 hours before clinic and you will not be charged." | *"Your card will only be charged after a clinic you attended, a late cancellation or no-show. Cancel at least 3 hours before clinic and you will not be charged."* |
| "Cards aren't set up yet." | *"Let's only do if stripe is connected"* |
| "Set by Tara" | *"I'm confused by this. Let's talk"* |
| "Charged 6. Already charged 0. No card 1." | Change, no replacement written |
| "Expected / Collected / Still owed" | *"Shouldn't really be "still owed" correct?"* |

**Two product asks, written against Words items:**

1. Against the web admin's tabs: *"Just note: I want to have "super admin"
   capabilities. So only I can charge people and see how much money is being
   made. The pros have "admin" capabilities and they are not allowed to have
   capabilities to charge people but can label them as no show, late
   cancellation, and see the clinic list. Also want to make sure that there is
   a spot for me (seems like yes) to put a number next to each name for what
   court they are on,"*
2. Against the player-search hint: *"We need to talk about this… these people
   "should" have the app in order to come. But sometimes won't and that's ok
   but the person inviting them will get charged. We need to put that
   somewhere or make that easy. Not sure where w the flow of things…"*

**Questions tab and Try-it tab:** empty. Questions 52 to 57 were answered
through the Words tab instead (below).

## What this decides

| # | Decision | Where |
|---|---|---|
| 1 | Her three rewordings ship verbatim | `ClinicDetailView.swift` (late-cancel sheet, late-request line), `CardOnFileView.swift` |
| 2 | "Need Help?" becomes **"Rating Guide"**, the title of the sheet it opens, which she kept on the same page. Question 69 shows it to her | `CompleteProfileView.swift` |
| 3 | "Set by Tara" becomes **"Only Tara can change this."** Plain chrome saying why the membership line has no control. Question 70 shows it to her; she asked to talk, so Alex raises it with her | `EditProfileView.swift` |
| 4 | The charge summary becomes sentences, zero counts left out: "Charged 6 cards. 1 player has no card on file." | `AdminClinicDetailView.swift` (`ChargeSummary`, unit-tested), `web/index.html` |
| 5 | "Still owed" becomes **"Not charged yet"**. She is right that nobody owes anything: cards are charged by her tap after the clinic, so the number is fees not yet charged, not a debt | `web/index.html` Money tab |
| 6 | "Cards aren't set up yet." is read as a note to us: show it only while Stripe is not connected. That is already when it shows (it answers `stripe_not_configured`), and Stripe has been connected since 2026-09-27, so no player sees it. Closes question 57 | none |
| 7 | Questions 53, 54 and 55 are answered **keep**: "Tara has your message.", "You're not registered for any clinics this week", "Let's Play." | none |
| 8 | **Super admin and pros**: recorded as a v1 ask. What a pro can do is her answer, not ours; question 71 asks it with the narrowest default. Court numbers already exist on every You're In! row (web dropdown, phone menu) | `docs/questions-for-tara.md` §N, `docs/launch-checklist.md` |
| 9 | **Guests billed to the member who brings them**: recorded as a v1 ask; question 72 asks the flow with a default | same |

## Rejected

- **Drafting her missing sentences ourselves and shipping them as hers.** Items
  2 and 3 are chrome that names the thing (hard rule 13), marked as ours, and
  put back in front of her as Keep or Change.
- **Re-sending the whole word list.** Round three (page version 3) showed her
  all 120 strings again plus 17 questions, most of which she had answered. Alex,
  2026-09-27: *"why tf are we giving her so many if she did this like last
  week"*. Round four shows only what is new or changed since 2026-09-22, and
  only the questions still open.
- **Building the pro role on a guess.** "Label them as no show, late
  cancellation, and see the clinic list" is specific, but whether a pro sees
  private notes, courts, payment state, or can message and invite changes the
  information-hiding model, which is the part of this system that must never be
  guessed (hard rules 1 and 14).

## Mechanism

A response that nobody reads is the same as no response. `review-watch`
(`.github/workflows/review-watch.yml`) checks hosted every two hours for a
review response newer than the last one seen and opens a GitHub issue naming
the link and the time, never the content (the repository is public), labelled
`tara-answers`. The session-start hook prints every open `tara-answers` issue at
the top of the session. Closing the issue is the acknowledgement: close it once
her answers are recorded in a decision.

## How we would know this was wrong

She sees "Rating Guide", "Only Tara can change this." or the charge sentences
and marks them Change again, or a pro is given a login before question 71 is
answered.
