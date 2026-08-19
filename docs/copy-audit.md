# Copy audit: every word in the app that Tara did not write

**Purpose:** `docs/copy.md` holds the copy Tara wrote. This file holds the
opposite: everything a player can read that **we** invented, so she can approve,
edit, or reject it. Extracted from the source on 2026-08-16, not from memory.

138 user-visible strings across 16 files. Most are chrome and do not need her.
The ones that do are marked, and there are 34 of them.

**How to use this:** walk the "Needs Tara" sections with her. Anything she
changes moves into `docs/copy.md` under her name, and the code changes to match.
Do not edit her words here; this file is the inventory, not the source.

Regenerate after any UI work:

```bash
grep -rnE 'Text\(\s*"|Label\(\s*"|Button\(\s*"|\.navigationTitle\(\s*"' FXETennis/ | grep -v '"[a-z.]*\."'
```

---

## 1. Needs Tara: the NTRP rating guide (7 long + 6 short)

**The highest-value thing on this list.** This is what a nervous new member
reads before self-rating, and self-rating decides which clinic they land in.
`for-tara.md` question 7 asked her to write these in her own words and she has
not yet.

Right now they are **mirrored verbatim from Volee** (`NTRPRating.swift:9-13`
says so explicitly). They are a different product for a different audience, and
they read like a rating chart rather than like Tara.

| Level | Current text (Volee's, not hers) |
|---|---|
| 2.0 | Very new player with minimal experience, learning basic strokes and struggling to sustain a rally |
| 2.5 | Beginner with limited consistency, can rally slowly but lacks control, directional intent, and serve reliability |
| 3.0 | Developing player who can sustain short rallies with moderate pace, working on consistency, court positioning, and basic strategy |
| 3.5 | Intermediate player with improved consistency and directional control, can rally with pace, use some spin, and demonstrate basic match strategy |
| 4.0 | Solid player with dependable strokes, can control depth and direction, handle pace, and execute point construction with moderate success |
| 4.5 | Advanced player with strong, consistent strokes, can dictate play, use spin and variety effectively, and compete with aggressive strategy |
| 5.0+ | High-level player with excellent shot tolerance, power, and precision, capable of advanced tactics and competing at elite sectional/national levels |

Short versions used on pills: "Beginner with limited consistency", "Developing
player, short rallies", "Intermediate, directional control", "Solid, dependable
strokes", "Advanced, dictates play", "High-level competitor".

**Note the coupling:** `NTRPRating.swift` says if Tara changes this wording it
must change in BOTH repos, because a player who uses Volee and FXE should read
identical words. Worth confirming that is still what she wants.

## 2. Needs Tara: notification wording (14 messages)

`for-tara.md` question 14. Drafts written by us, never through her. These are
the only way the app reaches anyone, so the tone matters more than anywhere
else. Full text in `docs/notifications.md`.

| Trigger | Title | Body (ours) |
|---|---|---|
| Registration resolves to a spot | You're In! | You're all set for {clinic} on {day} at {time} |
| Tara invites from the pool | Spot Available | Good News! A spot is available for {clinic}. Tap below to accept before it expires |
| Player accepts | You're In! | Awesome! Your spot is confirmed. See you soon! |
| Invitation expires | Invitation Expired | Your invitation has expired, but we hope to see you next time! |
| First registration lands in the pool | Player Pool | Thanks for registering! I personally create each clinic based on playing levels… |
| Tara removes a pooled player | Registration Canceled | You've been removed from the Player Pool for {clinic}. |
| Tara cancels a clinic | Clinic Canceled | Unfortunately today's {clinic} has been canceled due to {reason}. |
| Unpaid reminder | Payment Reminder | Just a quick reminder for payment from {clinic} on… |
| News published | FXE Tennis | News from FXE! |
| Registration window opens | Registration Open | Registration is LIVE!! Hope to see you on the court |
| Player cancels their own | Registration Canceled | You've canceled your registration for {clinic}. |

Three of these speak **in her voice, first person** ("I personally create each
clinic based on playing levels"). That is a claim about how she works, written
by us. It needs her sign-off more than the others do.

Two are **not wired to anything**: Invitation Expired (no expiry mechanism
exists) and Registration Open (needs a scheduled job). See `docs/backlog.md`.

## 3. Needs Tara: player-facing sentences we made up

| Where | Text | Note |
|---|---|---|
| Splash / sign-in | **Smart. Simple. Built for Tennis.** | Came from the wireframe mockups, which Tara made **with AI**. So it is not really hers either, and the mockups are a style guide, not a spec (decision 0006). Worth an explicit yes or no |
| Sign-up | Clinic updates come through the app. Keep notifications on so you don't miss them. | From Developer Guide Screen 3, so closer to hers |
| Profile setup | **Almost there** | Ours |
| Profile setup | **Tara uses this to build her clinic lists.** | Ours, and it makes a claim about her workflow |
| Profile setup | Optional. Tara can set this for you later. | Ours, and it promises something on her behalf |
| Profile setup | Add your name and answer the membership question to continue. | Ours, chrome-ish |
| Home | You're not in any clinics yet. | Ours |
| Home | Nothing open right now. | Ours |
| Clinic detail | This clinic has been canceled. | Ours |
| Clinic detail | **FROM TARA** (section heading above clinic messages) | Ours, and it labels her messages |
| Clinic detail | PAYMENT | Ours |
| Explainer | No description yet. | Ours, shown when a clinic has no description |
| Errors | That email or password didn't work. | Ours |
| Errors | Couldn't reach the server. Check your connection. | Ours |
| Errors | Something went wrong. Please try again. | Ours |

## 4. Locked, do not touch

Terminology fixed by `CLAUDE.md` and `docs/design-system.md`. Changing any of
these is a decision, not an edit.

**You're In!** · **Player Pool** · **Response Needed** · **Canceled** ·
**Action Needed** · **My Clinics**

Plus the VoiceOver strings that pair with them: "Status: you're in", "Status: in
the Player Pool", "Status: response needed", "Status: canceled".

## 5. Chrome: fine as-is, no review needed

Buttons, tabs, titles and labels that are plain by design. Listed for
completeness so nothing is unaccounted for.

Home · Clinics · Manage · Profile · Sign Out · Sign out · Done · Cancel ·
Register · Accept · Decline · Cancel Registration · Leave Player Pool ·
View All Clinics · View Open Clinics · Invite · Cancel Invite · Message ·
Message Players · To · Profile · Rating Guide · Need Help? ·
What do the ratings mean? · About this clinic · What is 105? ·
Registration open · Registration opens {date} · Your tennis rating ·
Are you currently a Foxcroft East Racquet & Swim Club member? (hers, Screen 4) ·
ACTION NEEDED · Draft · Unknown player · FXE TENNIS · FXE Tennis

## 6. Invented content that is NOT copy, and should be replaced

Not strings in the app, but fake data a reviewer will read as real. All of it is
local-only seed (`supabase/seed.sql`), never hosted.

| Invented by us | Status |
|---|---|
| **Thursday Morning Cardio** | Not a real FXE clinic. Alex flagged it 2026-08-16 |
| **Saturday Members Only** | Ours, exists to demonstrate the member priority window |
| **Sunday Social (next week)** | Ours, exists to demonstrate the "registration opens" state |
| **Coed Cardio** (template) | Ours |
| "High-energy cardio tennis, all levels welcome." | Ours |
| "Members priority window is open; public opens Friday." | Ours, a developer note |
| Maria Alvarez, Ken Whitfield, Priya Raman, Rob Delgado, Dana Okonkwo | Fake players. Fine in seed, must never reach hosted |

**Tuesday Ladies 3.0+** is the one seed clinic whose name matches something real,
and it now carries Tara's verbatim description.

Her four real clinics (Ladies 3.0+, All-Level Ladies, All-Level Men's, FXE Queen
City Team Ladies Practice) are in `docs/copy.md` and are **not yet in any
database**. Replacing the invented seed with her real week is tracked in
`docs/backlog.md`.
