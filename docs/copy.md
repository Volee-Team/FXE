# Copy: Tara's words, verbatim

**This file is the source of truth for anything a player reads.** `CLAUDE.md`
has pointed here since the repo was created; the file did not exist until
2026-08-16, which is the whole reason clinic descriptions were invented
placeholders for three weeks.

## The rule

> **Do not invent copy.** If Tara has not written it, ask her. If it is chrome
> (a button that says "Save", a field labelled "Phone"), keep it plain and
> boring. Everything a member actually reads about tennis is hers.

Her voice is doing real work. "Lots of balls, constant action" tells a nervous
3.0 player what the hour will feel like in a way no spec sentence does. When
copy below is edited, it is edited **by her**, and the change gets a date.

Transcribed exactly as she sent it, including her capitalisation and her
exclamation marks. Where she wrote a phrase two ways, both are preserved rather
than normalised.

---

## What "105" is

Source: Tara to Alex, 2026-08-15, by text.

"105" appeared five times in her real weekly schedule (`docs/taras-real-week.md`)
with no definition anywhere in the spec or the Developer Guide, so it was
question 1 back to her. Her answer:

> 105 is a fast-paced doubles game for ladies and coed players. With a maximum
> of six players per court, a pro feeds the ball, keeps score, and keeps the
> action moving as players rotate in and out. Fast points, lots of balls, great
> music, and nonstop movement!

Her own framing: *"'105' is a game that just about everyone knows about."* So it
is a **format**, not a level and not an audience. It combines with both: "Coed
105", "level 4.0+ 105".

---

## Clinic descriptions

Source: Tara to Alex, 2026-08-15. These go in `clinics.description` and
`clinic_templates.description`.

### Ladies 3.0+

> A fast-paced clinic for 3.0+ players focused on live-ball doubles play. Pros
> feed plenty of points while players rotate through courts, work with different
> pros, and focus on doubles strategy, positioning, and movement. Lots of balls,
> constant action, and great preparation for match play

### All-Level Ladies

> A fast-paced doubles clinic for all levels, from beginner through 4.5. Players
> are grouped on courts with similar-level players while pros feed live points,
> work on doubles strategy and positioning, and keep everyone moving. Lots of
> balls, lots of action, and great preparation for doubles match play

### All-Level Men's

> A fast-paced doubles clinic for all levels, from beginner through 4.5. Players
> are grouped on courts with similar-level players while pros feed live points,
> work on doubles strategy and positioning, and keep everyone moving. Lots of
> balls, lots of action, and great preparation for doubles match play!

**Note, deliberately not "fixed":** All-Level Ladies and All-Level Men's are the
same sentence, differing only in the final exclamation mark. That is how she sent
them. Do not merge them into one shared string to save duplication: they are two
clinics with two audiences, and she may edit one without the other.

### FXE Queen City Team Ladies Practice

Source: same message. A clinic she added while writing the descriptions.

> Queen city team players

Her instruction in full: *"I added another clinic that is for Queen city team
practice. It is Tuesdays from 10:30 to 11:30 AM and only Queen city team players
can join. I'll just need to manually figure that one out but you can add that in
as long as you're doing it if you don't mind! Just put Queen city team players
for the description. FXE Queen city team ladies practice."*

| | |
|---|---|
| Name | FXE Queen City Team Ladies Practice |
| Day / time | Tuesdays, 10:30–11:30 AM |
| Duration | 60 min |
| Audience | Ladies |
| Description | Queen city team players |
| Eligibility | **Queen City team players only** |

**The eligibility rule is not built and must not be faked.** There is no team
membership concept in the schema, and inventing one is a schema decision, not a
copy decision. Her own words are *"I'll just need to manually figure that one
out"*, so v1 behaviour is: the clinic exists, anyone can register, and Tara
selects from the Player Pool as she does for everything else. That is already
how hard rule 2 works, so it needs no new mechanism, only the description
telling players who it is for.

If it later needs enforcing, that is a real feature (a team roster, or a private
clinic flag) and gets its own decision record.

---

## The "?" explainer, her idea

She asked, unprompted:

> Should you put a "?" w the description by each clinic?

**Yes, and it is a good instinct.** It is the same affordance already used for
the NTRP rating on the profile screen, so a player learns the pattern once.
Every clinic name is a piece of club shorthand ("105", "3.0+", "All-Level") that
a brand new member does not know, and the alternative to a "?" is putting a
paragraph on every row, which contradicts the standing rule that player screens
must never feel like long blocks of writing.

**Status: not built yet.** The description reaches the clinic detail screen; the
"?" affordance on the list does not exist. Tracked in `docs/backlog.md`.

---

## Existing copy that is already hers

Kept here so it is not re-invented by someone who does not know it was quoted.

| Where | Copy | Source |
|---|---|---|
| Profile setup | "Are you currently a Foxcroft East Racquet & Swim Club member?" | Developer Guide, Screen 4 |
| Profile setup | "Need Help?" (the rating explainer link) | Developer Guide, Screen 4 |
| Sign-up | "Clinic updates come through the app. Keep notifications on so you don't miss them." | Developer Guide, Screen 3 |
| Splash | "Smart. Simple. Built for Tennis." | Wireframe mockups |

## Locked terminology

Never substitute a synonym. Full table in `docs/design-system.md`.

**You're In!** · **Player Pool** · **Response Needed** · **Canceled** ·
**Action Needed** · **My Clinics**

---

## Still open with Tara

1. **The NTRP rating guide**, `for-tara.md` question 7: a line or two per level in
   her own words. This is what a nervous new player reads before self-rating, so
   it should sound like her. Currently mirrored from Volee.
2. **Notification wording**, question 14. Roughly ten messages. Drafts exist in
   `docs/notifications.md` and have never been through her.
3. **The Venmo / Zelle payment line**, question 11. Served from the database via
   `payment_instructions()` so it changes without a release, but the string
   itself is still ours.
4. **Clinic categories**, question 8. Her real schedule suggests the axis is
   format and level ("105", "3.0+"), not the "Drill / Cardio / Match Play" the
   form implies. Worth re-asking now that "105" is understood.
