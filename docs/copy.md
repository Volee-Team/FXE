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
| Name | **FXE QC Team practice** (updated 2026-08-28: *"As long as it's labeled 'FXE QC Team practice' no one else should sign up for that"*) |
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

**Status: BUILT, 2026-08-16.** The "?" sits on every clinic card and opens a
sheet with the description; a 105 clinic additionally shows her definition of
the format. Verified on the simulator the day it landed.

---

## Existing copy that is already hers

Kept here so it is not re-invented by someone who does not know it was quoted.

| Where | Copy | Source |
|---|---|---|
| Profile setup | "Are you currently a Foxcroft East Racquet & Swim Club member?" | Developer Guide, Screen 4 |
| Profile setup | "Need Help?" (the rating explainer link) | Developer Guide, Screen 4 |
| Sign-up | "Clinic updates come through the app. Keep notifications on so you don't miss them." | Developer Guide, Screen 3 |

## Locked terminology

Never substitute a synonym. Full table in `docs/design-system.md`.

**You're In!** · **Player Pool** · **Response Needed** · **Canceled** ·
**Action Needed** · **My Clinics**

---

## Her cancellation policy and the two payment sentences (2026-09-16)

Verbatim from Tara's message of 2026-09-16 (decision 0012). The policy text is
the player-facing rule and ships word for word. The two sentences are hers
too; she said "you draft, I edit" and then wrote them, so they ship as written
and are marked for her edit. Question 46 flags the card sentence.

**Cancellation policy**

> FXE Tennis Cancellation Policy
>
> We understand that plans change! Please cancel as early as possible so we have time to adjust courts, players, and coaching staff.
>
> • Cancel more than 4 hours before clinic: No charge.
> • Cancel within 4 hours of clinic: Full clinic fee will be charged.
> • No-shows: Full clinic fee will be charged.
>
> Each player receives one courtesy late cancellation every 90 days, no questions asked.
>
> For a true illness or emergency after your courtesy cancellation has been used, please contact Tara at fersctennispro@gmail.com
>
> Thank you for helping us keep clinics organized and running smoothly!

**When adding a card** (Profile, above Add a card): *"Your card will only be charged for late cancellations or no-shows. Cancel at least 4 hours before clinic and you will not be charged."*

**When canceling within 4 hours** (above the note box): *"This cancellation is within 4 hours of clinic and the full clinic fee will apply. If there are circumstances you'd like us to consider, please leave a note below."*

**The note only Tara sees**, her ask: a place at level entry to write something like *"just coming back from a back injury so I'm a low, 3.5"*, with the app saying only Tara sees it.

## Her review of every word (2026-09-21, decision 0013)

Her first pass through `docs/tara-review/index.html`, pasted back by Alex.
Everything not listed here she marked keep. Applied verbatim, including
punctuation and the missing periods:

| Where | Was (ours) | Now (hers) |
|---|---|---|
| Sign-in, under the logo | Smart. Simple. Built for Tennis. | **Let's Play.** (Questions tab: "Let's play!", question 55) |
| Profile screen heading | Almost there | **Almost there!** |
| Under the membership question | Tara uses this to build her clinic lists. | **Members get 24-hour early access to all clinics** |
| Note box placeholder | just coming back from a back injury so I'm a low 3.5 | **Just coming back from a back injury - probably a low 3.5** |
| Under a disabled Continue | Add your name, phone and rating, and answer the membership question to continue. | **Add your name, phone number, and tennis rating. Please answer the membership question to continue** |
| Sign out hint on the profile screen | Signs you out. Your account is kept, and you can finish this later. | **Signs you out, you can finish later if needed** |
| Home and My Clinics, empty | You're not in any clinics yet. | **You're not registered for any clinics this week** (question 54: My Clinics lists every upcoming week) |
| Home, no open clinics | Nothing open right now. | **No clinics currently open for registration** |
| Cancel sheet, note box | Note (optional) | **Note for Tara (optional)** |
| After a late request | She will let you know if there is room. | **She will let you know asap if there is room in this clinic** |
| Someone acted first | That just changed. Here's the latest. | **Sorry, someone beat you to the punch. Here's the latest!** |
| Bell, empty | Nothing yet. | **No notifications yet** |
| Profile, card section | (her 09-16 sentence) | **Your card will only be charged after the clinic you attended, late cancellations, or no-shows. Cancel at least 3 hours before clinic and you will not be charged.** |
| Cancel sheet, inside the cutoff | (her 09-16 sentence, 4 hours) | same sentence with **3 hours** (*"3 hours instead of 4. Otherwise good"*) |

Gone by her word: the courtesy sentence (*"NOT DOING THIS ANYMORE"*), the
"Late, courtesy used." notification suffix, and the Zelle reminder, Paid and
Remind unpaid controls (*"I don't want this to be an option. Everyone using
the app has to input a credit card"*), which now sit behind `zelle_allowed`.

Her policy text above is therefore superseded on three lines: **3 hours**
where it says 4, no courtesy paragraph, and no emergency-email paragraph. She
has not rewritten the block itself; question 56 asks for the new text, and
until then the app shows only her two sentences, not the block.

## The Adult Tennis Participation Waiver (2026-09-21)

`FXE_Adult_Tennis_Participation_Waiver.docx`, version date September 2026,
sent by Tara on 2026-09-21 in answer to question 45. Stored verbatim in
`waivers` (migration 20260921000002) and shown by `WaiverView`. Her last page
is the mechanism: required checkbox, typed full legal name, email from the
account, time from the app, version with the record. The checkbox sentence
below is hers and is the only waiver copy in the app besides the text.

> **Adult Tennis Participation Waiver and Release**
>
> FXE Tennis LLC and Foxcroft East Racquet and Swim Club
>
> Please read carefully. This agreement affects your legal rights. By signing electronically, you agree to its terms for adult participation in tennis clinics, lessons, matches, events, and related activities organized, hosted, or provided by FXE Tennis, LLC or Foxcroft East Racquet and Swim Club.
>
> IMPORTANT NOTICE: This agreement includes an assumption of risk and a release of claims, including claims based on ordinary negligence, to the fullest extent permitted by North Carolina law.
>
> 1  Activities and Released Parties
>
> I wish to participate in adult tennis and related activities, including clinics, lessons, drills, games, matches, tournaments, social events, fitness or conditioning activities, and use of tennis courts, facilities, equipment, parking areas, walkways, and surrounding premises (collectively, the Activities). In this agreement, the Released Parties are FXE Tennis, LLC; Foxcroft East Racquet and Swim Club; and each of their respective owners, officers, directors, board members, employees, tennis professionals, coaches, agents, independent contractors, volunteers, members, affiliates, successors, assigns, and premises owners or lessors.
>
> 2  Acknowledgment of Risks
>
> I understand that tennis and related activities involve inherent and other risks that can cause property damage, illness, serious injury, disability, or death. Risks include, without limitation, strenuous physical exertion; rapid movement, twisting, falls, overuse, and loss of balance; contact with racquets, balls, nets, fences, court fixtures, equipment, other participants, instructors, spectators, or objects; uneven, wet, slippery, cracked, hot, or otherwise hazardous surfaces; weather, heat, humidity, lightning, and other environmental conditions; equipment failure or misuse; acts or omissions of other participants; and delayed access to medical care. I understand that this list is not complete and that unexpected risks may arise.
>
> 3  Voluntary Participation and Fitness
>
> I am at least 18 years old and voluntarily choose to participate. I am responsible for deciding whether I am physically and medically able to participate and for seeking medical advice when appropriate. I will stop participating and notify a tennis professional if I experience pain, dizziness, breathing difficulty, or another concerning symptom. I will follow reasonable safety rules and instructions, use appropriate footwear and equipment, and avoid participating while impaired by alcohol, drugs, illness, or medication that makes participation unsafe.
>
> 4  Assumption of Risk
>
> I knowingly and voluntarily accept and assume all known and unknown risks of the Activities, whether inherent or arising from the condition of the premises, equipment, weather, the conduct of participants or others, or the ordinary negligence of any Released Party, to the fullest extent permitted by law.
>
> 5  Release and Waiver of Claims
>
> To the fullest extent permitted by law, I release, waive, and discharge the Released Parties from claims, demands, causes of action, liabilities, damages, losses, or expenses arising out of or related to my participation in the Activities, including claims for personal injury, illness, death, or property damage caused in whole or in part by the ordinary negligence of a Released Party. This release does not apply to gross negligence, willful or wanton misconduct, intentional wrongdoing, or any liability that cannot legally be released.
>
> 6  Responsibility for My Conduct
>
> I am responsible for my own conduct and property. To the fullest extent permitted by law, I agree to indemnify and hold the Released Parties harmless from third-party claims, liabilities, damages, or expenses, including reasonable attorneys' fees, caused by my negligent or intentional conduct, my violation of safety rules or instructions, or my material breach of this agreement. This provision does not require me to indemnify a Released Party for that party's gross negligence, willful or wanton misconduct, or intentional wrongdoing.
>
> 7  Emergency Care
>
> If I become injured or ill and cannot make decisions for myself, I authorize the Released Parties to contact emergency services and arrange reasonably necessary emergency assistance. I understand that the Released Parties are not required to provide medical care and that I am responsible for costs charged by medical providers, emergency responders, or transportation services.
>
> 8  Duration and Revocation
>
> This agreement begins when I sign it and remains effective until I revoke it in writing by delivering notice to FXE Tennis, LLC. Revocation applies only to Activities occurring after the revocation is received and does not affect the agreement's application to Activities that occurred before then. I understand that I may be required to accept a current waiver before participating in future Activities.
>
> 9  North Carolina Law and Severability
>
> This agreement is governed by North Carolina law. Any provision found unenforceable will be enforced to the maximum extent permitted, and the remaining provisions will continue in effect. This agreement is intended to be as broad as North Carolina law permits.
>
> 10  Electronic Agreement
>
> I consent to using an electronic record and electronic signature. By checking the required box and entering my legal name, I intend to sign this agreement electronically. I understand that my electronic acceptance may be stored with the agreement version, date and time, account information, and available technical records.
>
> Participant Acknowledgment
>
> BY SIGNING, I CONFIRM THAT I HAVE READ AND UNDERSTAND THIS AGREEMENT, HAVE HAD THE OPPORTUNITY TO ASK QUESTIONS, AND VOLUNTARILY AGREE TO ALL OF ITS TERMS.
>
> Required checkbox: **I have read and agree to the Adult Tennis Participation Waiver and Release.**

## Still open with Tara

1. ~~The NTRP rating guide~~ **CLOSED 2026-08-27**: *"Rating guide is good
   where it's at if it's volee material."*
2. **Notification wording**, question 14. Tone settled 2026-08-27 ("First person
   is ok. I want it to sound personal but not cheesy") — the exact words in
   `docs/notifications.md` still deserve her eye. See `docs/copy-review.md` §E.
3. ~~The Venmo / Zelle payment line~~ **CLOSED 2026-08-02** (decision 11 in
   `CLAUDE.md`): her exact string, lower-case "zelle" and no terminal period,
   lives in `app_settings.payment_instructions` and is pinned character for
   character by `tests/sql/schema_decisions.sql`. Read it through
   `payment_instructions()`, never hardcode it.
5. ~~The splash line "Smart. Simple. Built for Tennis."~~ **CLOSED 2026-09-21**:
   "Let's Play." (question 55 confirms the capitalisation).
4. **Clinic categories**, question 8. Her real schedule suggests the axis is
   format and level ("105", "3.0+"), not "Drill / Cardio / Match Play". Worth
   re-asking now that "105" is understood.
