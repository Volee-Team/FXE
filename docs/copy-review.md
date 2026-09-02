# Copy review checklist

**Every word in the product that Tara did not write.** Tick each one: keep,
reword, or replace with her words. Generated from source on 2026-08-27, not from
memory.

Regenerate any time: `python3 scripts/extract-copy.py --report`

70 user-visible strings across 12 files. Most are chrome and need nothing. The
**34 below are prose we invented** and are the ones to actually read.

> **Why this exists.** Alex, 2026-08-16: *"text should either come straight from
> tara or made by u and checked by me first."* Then on 2026-08-27 Tara read
> *"You're in the Player Pool. Tara picks from here."* in the walkthrough. Mine,
> invented, one turn after the rule was written. The gate missed it because it
> only scanned Swift and that string was in a web page. Now it scans everything.

---

## New since the last review — 2026-09-01, awaiting Alex

Written by me for the Action Needed / Money / password-reset work. Rule 13:
mine until Alex ticks them. Nothing here is attributed to Tara.

| ✓ | String | Where |
|---|---|---|
| ☐ | Forgot password? · Check your email for a reset link. | Sign-in, iOS and web |
| ☐ | Choose a new password · Checking your reset link… · Pick something you'll remember. At least 8 characters. · New password · Type it again · Save password | `web/reset.html` |
| ☐ | Saved. You can sign in with it now, on your phone or here. | `web/reset.html` |
| ☐ | This link has expired or was already used. Go back and request a new one. · Those don't match. · That didn't save. Try again. | `web/reset.html` |
| ☐ | Put them in · No room · Seen | Action Needed buttons, web and iOS |
| ☐ | N asking to get in after close · N cancellations or replies to see | Action Needed rows, iOS |
| ☐ | That clinic is full now. · Someone already handled that one. | Web, when approving a late request fails |
| ☐ | Members, 60 min · Members, 90 min · Non-members, 60 min · Non-members, 90 min · Expected · Collected · Still owed · Couldn't load the numbers. | Money panel, web |
| ☐ | No court · Court 1 … Court 5 · Court | Court dropdown, web and iOS |
| ☐ | Remind unpaid (N) · Send a payment reminder to N unpaid? · Send reminder · Reminder sent to N. · The reminder didn't send. Check your connection and try again. | Unpaid reminder button, web and iOS |
| ☐ | **Just a reminder that {clinic} ({date}) hasn't been paid yet. {Tara's payment line} Thanks!** | The reminder players receive. Sent in Tara's name, so this one matters most. Her payment line is her own text from the database |
| ☐ | This week · Next week · Week of {date} | Clinic list headers, iOS |
| ☐ | Notifications · Nothing yet. · Mark all read · Done · Couldn't load notifications. Pull to try again. | Notification center, iOS |
| ☐ | Edit details · Set by Tara · Save · Cancel · Saving… | Profile editing, iOS |
| ☐ | Players · Search by name · Show inactive players · Type at least two letters of a name. · Make member · Make non-member · Deactivate · Reactivate · Note · Save note · Private note · Only you can see this. · Saved. · Has a note · Couldn't search right now. Check your connection and try again. | Player directory, web and iOS |

---

## A. Sentences a player reads (12) — the ones that matter most

| ✓ | String | Where | Note |
|---|---|---|---|
| ☐ | **Smart. Simple. Built for Tennis.** | Sign-in | From the AI mockups, so not really hers either. Keep? |
| ☐ | **Almost there** | Profile setup | Ours |
| ☐ | **Tara uses this to build her clinic lists.** | Profile setup | Ours, and it makes a claim about how she works |
| ☐ | **Optional. Tara can set this for you later.** | Profile setup | Ours, promises something on her behalf |
| ☐ | Add your name and answer the membership question to continue. | Profile setup | Ours, functional |
| ☐ | Signs you out. Your account is kept, and you can finish this later. | Profile setup | Ours, VoiceOver only |
| ☐ | **You're not in any clinics yet.** | Home | Ours |
| ☐ | **Nothing open right now.** | Home | Ours |
| ☐ | **This clinic has been canceled.** | Clinic detail | Ours. Tara may want a reason shown |
| ☐ | **No description yet.** | "?" sheet | Ours. Shows when she hasn't written one |
| ☐ | **FROM TARA** | Clinic detail | Ours. Labels her messages to players |
| ☐ | Clinic updates come through the app. Keep notifications on so you don't miss them. | Sign-up | From her Developer Guide Screen 3, closest to hers |

## B. Error messages a player sees (3)

| ✓ | String | Note |
|---|---|---|
| ☐ | That email or password didn't work. | Ours |
| ☐ | Couldn't reach the server. Check your connection. | Ours |
| ☐ | Something went wrong. Please try again. | Ours |

## C. The walkthrough Tara already saw (3) — **the ones Alex caught**

Not in the app. These were in the clickable prototype only, so the gate never
scanned them and Tara read them anyway.

| ✓ | String | Verdict |
|---|---|---|
| ☒ | **You're in the Player Pool. Tara picks from here.** | **Invented. Alex flagged it. Remove or replace** |
| ☒ | Registration cancelled. | Invented |
| ☒ | Clinic saved as a draft. | Invented |

## D. Web admin, which only Tara reads (10)

Lower stakes: she is the only audience, and it is operational rather than
promotional. Still ours.

| ✓ | String |
|---|---|
| ☐ | Admin sign-in. |
| ☐ | No clinics yet. Use "New clinic" to add your first one. |
| ☐ | Description (players see this under the "?") |
| ☐ | That account is not an administrator. |
| ☐ | A clinic needs a name. |
| ☐ | Max players must be at least 1. |
| ☐ | Length must be more than 0 minutes. |
| ☐ | Write a message first. |
| ☐ | Registration opens automatically: members Thursday 8am, everyone else Friday 8am, for the whole week this clinic falls in. Prices come from the clinic length. |
| ☐ | Unknown player |

## E. Notifications (14) — tone approved, wording still unread

Tara, 2026-08-27: *"First person is ok. I want it to sound personal but not
cheesy."* So the register is settled and the exact words are not. Full text in
`docs/notifications.md`; three speak in her voice.

The one most worth her eye, because it is the longest and most "her":

> Thanks for registering! I personally create each clinic based on playing
> levels…

## F. Settled, no action

* **NTRP rating guide** (13 strings) — Tara 2026-08-27: *"Rating guide is good
  where it's at if it's volee material."* Closed.
* **Locked terminology** — You're In! · Player Pool · Response Needed · Canceled
  · Action Needed · My Clinics. Changing these is a decision, not an edit.
* **Chrome** (~30) — Home, Clinics, Manage, Profile, Register, Accept, Decline,
  Save, Cancel, Done, Invite, Message, Need Help?, and similar. Plain by design.

---

## The rule going forward

`docs/copy-approved.txt` snapshots all 66 strings. The `copy-gate` CI job fails
on any addition or edit and prints the diff. Regenerating it is not a formality:
read the new lines, decide whether each is Tara's or plain chrome, and commit the
snapshot with the change so the words appear in review.
