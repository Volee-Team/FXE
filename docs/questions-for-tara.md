# FXE Tennis v1: Questions for Tara

These are the things the Developer Guide does not answer that change how the app gets built. Each one has a **default** listed. If a default is fine, just say "default" and we will build it that way. Anything you have an opinion on, overrule us.

Anything not on this list, we are deciding ourselves and you do not need to think about it.

---

## A. Registration windows and timing

**1. Are Thursday 8:00 AM and Friday 8:00 AM fixed for every clinic, or set per clinic?**
Why it matters: if it is always the same, we compute it automatically from the clinic date and you never touch it. If it varies, you get two time fields on every clinic form.
*Default: fixed rule, computed automatically, with an override field for special events.*
*ANSWERED: default built (decision 0001; override fields on the clinic form).*

**2. Thursday 8:00 AM of which week?**
For a Saturday clinic, is registration the Thursday two days before? What about a Monday clinic: the previous Thursday, or the Thursday four days earlier?
*Default: the most recent Thursday before the clinic date.*
*ANSWERED 2026-08-02 (decision 0001), confirmed 2026-08-27 (0007 §2): per service week, Thursday 08:00 members and Friday 08:00 everyone, derived from the week's Sunday. The default above was wrong on Fridays and Saturdays.*

**3. What does "registration close" actually stop?**
Does it stop new Player Pool entries too, or only new You're In! registrations? Can someone join the Player Pool an hour before the clinic starts?
*Default: registration close stops everything, and if you leave it blank the Pool stays open until the clinic starts.*
*ANSWERED 2026-08-27 (0007 §5): registration closes 3 hours before start for everyone, You're In! and Pool alike; inside that a player can send Tara a late request. Nothing is ever left blank.*

**4. Confirming the time zone is Eastern (Charlotte).**
*Default: yes, all times are Charlotte local, and the app handles daylight saving automatically.*
*Default built. Not explicitly confirmed; low risk.*

---

## B. Capacity and invitations

**5. When you invite someone from the Player Pool, should the app stop you if the clinic is already at capacity?**
In other words, is internal capacity a hard limit or a guideline you can go over when you decide to?
*Default: it is a guideline. We show you the count, we never block you.*
*ANSWERED 2026-08-02 (decision 4): guideline, never blocks.*

**6. Can you put a player straight into You're In! without them registering in the app?**
Real situation: someone calls you or grabs you at the club and you just want to add them. The guide does not mention this and we think you will want it in week one.
*Default: yes, you can add any player to any clinic directly, and you can move anyone between statuses by hand.*
*ANSWERED 2026-08-02 (decision 3): yes, built as place_player.*

**7. When a You're In! player cancels, does that spot open back up automatically for the next member who registers?**
*Default: yes, the spot is live, so a member registering in the priority window can take it.*
*Default built. Not explicitly confirmed.*

---

## C. Members and ratings

**8. Member status is self-reported. A non-member can tick "yes" and get Thursday priority. Is that acceptable?**
We can leave it as your correction (you fix it in the player directory when you notice), or we can make member status something only you can set.
*Default: players self-report, and you can override it on their profile at any time.*
*ANSWERED 2026-08-02 (decision 5): self-reported at sign-up, Tara overrides. Since 2026-09-02 a player cannot change it after sign-up.*

**9. What is the adult rating scale, exactly?**
NTRP 2.5 / 3.0 / 3.5 / 4.0 / 4.5+? Something FXE-specific? We need the exact list of options.
*ANSWERED 2026-08-02 (decisions 6+7): NTRP 2.0–5.0 in half steps, same chart as Volee, "5.0+" display only.*

**10. What should the "Need Help?" rating guide say?**
Please write the actual text you want players to read, one or two lines per rating level. This is player-facing copy so it should be in your voice, not ours.
*ANSWERED 2026-08-27 (0007 §3): Volee's guide stays.*

---

## D. Clinics

**11. What are the clinic categories?**
The create-clinic form has both "audience" and "category". Audience we understand as Ladies, Men, Coed, Juniors. What goes in category? (Drill, Cardio, Match Play, Clinic, Camp, Private Group, something else?) Give us the full list.
*ANSWERED 2026-08-02 (decision 8): no list, no filter; category stays free text. Audience is Ladies / Men / Coed in v1 (decision 9).*

**12. Do junior clinics need to be split by age or level?**
Right now all juniors are one bucket. If a parent of a 9 year old and a parent of a 16 year old both browse "Juniors" they see the same list. Do you want age-group labels or filters (for example 8U, 10U, 12U, High School), or is the clinic name enough?
*Default: the clinic name carries it, no extra filters.*
*DEFERRED 2026-08-27 (0007 §6): juniors return November or spring; nothing to decide now.*

**13. Why is clinic location hidden from players?**
We are following the rule, we just want to make sure we understand it. Is it because everything is at FXE so the location is obvious, or is there another reason?
*ANSWERED 2026-08-02 (decision 10): FXE is a member club; location appears nowhere player-facing.*

**14. What happens to a clinic after it happens?**
Does it just disappear from the player's list automatically at the end time? Do you ever need to mark it complete or take attendance?
*Default: it moves to Past automatically at the end time. No attendance in v1.*
*CONFIRMED 2026-09-16: "Correct."*
*Default built, with one difference: a finished clinic drops off the players' list (no Past section); Tara's Manage list has Past. Re-asked as 09-12 short-list item 10.*

---

## E. Payment

**15. Confirming: price is per clinic, per player, and the app only tracks a Paid yes/no checkbox.**
No packages, no punch cards, no monthly billing, no running balance.
*Default: yes, exactly that.*
*SUPERSEDED 2026-09-12 (decision 0009): still per clinic per player, but a card on file and a payments ledger now exist; see §I.*

**16. Where should your payment info appear?**
Venmo handle on every clinic page, only in the unpaid reminder message, or in both?
*Default: both, and we will put the exact text you give us.*
*ANSWERED 2026-08-02 (decision 11): her exact Zelle/Venmo line; shown in both places.*

**17. If you cancel a clinic that people already paid for, does the app need to do anything?**
*Default: nothing. The Paid checkbox stays as it was and you handle refunds or credits outside the app.*
*Re-asked as Q31 with the opposite default now that cards exist; Q31 governs. Today cancel_clinic refunds nothing.*

---

## F. Messages and notifications

**18. If you send a clinic message to only the Unpaid players, should it stay visible on the clinic page to everyone afterwards?**
The guide says every message stays on Clinic Details for later reference, but it also says messages can be targeted at one group. Those two rules collide.
*Default: a targeted message is only ever visible to the group you sent it to. Messages sent to Everyone are visible to everyone.*
*ANSWERED 2026-08-02 (decision 12): a targeted message is visible only to its group. Built.*

**19. Push notifications are the only way the app reaches anyone. If a player denies notification permission at signup, they get nothing, including clinic cancellations and your invitations.**
Do you want a flag on their profile so you can see who has notifications turned off and text them the old way?
*Default: yes, we will show you a small "notifications off" indicator on the player profile.*
*OVERRULED 2026-08-02 (decision 13): Tara does not want to see who has notifications off. No marker, no column. The app tells the player instead, at sign-up and whenever permission is denied.*

**20. What should each notification actually say?**
There are about ten of them: invitation received, you're in, clinic canceled, clinic time changed, unpaid reminder, new news post, player canceled (to you), player accepted (to you), player declined (to you), invitation still unanswered. Write them how you want them to read, or tell us to draft them and you will edit.
*Default: we draft, you edit.*
*ANSWERED 2026-08-02 (decision 14) and 2026-08-27 (0007 §4): she wrote them; docs/notifications.md holds them verbatim. First person OK, "personal but not cheesy".*

---

## G. How you work

**21. Do you want to run the admin side from your phone, or would you rather do the weekly setup on a laptop?**
The guide specs a phone admin. Honest read: creating a week of clinics, searching players, and assigning courts are all noticeably better on a bigger screen. We can build a simple web admin you open in a browser, keep everything in the phone app, or do both (phone for game-day actions, laptop for setup).
This is the single biggest question on this list. It changes what we build.
*ANSWERED 2026-08-02 (decision 1): both. Built: Manage tab on the phone, web admin for setup.*

**22. Will there ever be a second admin, like an assistant coach?**
Not building it now either way. We just want to know whether to design for it so it is cheap later.
*Default: design for it, build one admin.*
*Default built (accounts.role). Not confirmed; nothing to build.*

---

## H. Business and legal

**23. Whose Apple Developer account does this app live under, and who owns the App Store listing?**
Volee is under John's account. FXE should probably be its own, under FXE or under you. This has to be settled before we can submit.
*ANSWERED 2026-08-02 (decision 16): FXE Tennis, LLC. Enrollment in review. Alex's own Apple ID has no developer account; he holds John's Volee login and it is deliberately not used for FXE (an Individual account shows John as the seller). Decided 2026-08-16 and 08-19.*

**24. The app stores children's first name, last name, and age under a parent account. Does FXE have parent consent language already, from club registration forms or waivers?**
Apple requires a privacy policy URL and an accurate privacy declaration, and apps handling kids' data get looked at more carefully. We need to know what already exists so we are not writing policy from scratch.
*DEFERRED with juniors (0004, 0007 §6). Waiver wording still pending (decision 16). Short-list item 12.*

**25. Who writes the privacy policy and terms of service, and is there an FXE website we can host them on?**
*HALF ANSWERED 2026-08-02 (decision 16): reuse Volee's policy. Open: a URL to host it. Short-list item 13.*

**26. Final logo asset and exact brand colors.**
We need the gator-with-tennis-ball logo as a PNG or SVG with a transparent background, and the exact navy, cream, and green you want (hex codes if the club has them, otherwise send an image and we will pull them).
*ANSWERED 2026-08-02/08-12 (decisions 15, 22, 23): crossed-racquets mark (in repo), her hex codes in Brand.swift. Still open: the warm-white background #FAF7F1 is our choice awaiting her OK.*

---

## One correction we are making on our own

The guide says a child profile stores **age**. We are going to ask for **birthday** instead and calculate age from it. Reason: a stored age is silently wrong within a year, so a 9 year old stays 9 in your directory forever. Parents type a birthday once and the age is always right. The form will say "Birthday" instead of "Age". Tell us if you would rather it ask for age anyway.
*(Moot until juniors return; the column already stores a birthday.)*

---

## I. Payments and cancellations (added 2026-09-12)

Context: Tara wrote that seven players canceled an hour before a clinic and she
wants to charge them but feels bad sending Venmo requests. Charging someone
without them tapping anything means keeping a card on file at sign-up, which
players agree to once. Apple takes nothing on this (clinics are a real-world
service); Stripe takes about 3% per card payment. Every question below has a
default we would otherwise pick, so "yes" is a complete answer.

**27. Cancellation cutoff: how close to the start is a cancellation charged?**
*ANSWERED 2026-09-12: 4 hours, honor system (decision 0010). Free before; inside 4 hours the player has to say it is an emergency, with a very concise message.*

**28. Is the late-cancellation charge the full clinic price, or a fixed amount?**
*Default: full price of that clinic ($18/$23 or $22/$28).*
*ANSWERED 2026-09-16 (decision 0012): "Full price as you listed - yes, def full."*

**29. A no-show, meaning they never canceled and never came: charged the same as a late cancel?**
*Default: yes, same as a late cancel, marked by you after the clinic.*
*ANSWERED 2026-09-16 (decision 0012): full fee, marked by her on the clinic list, charged with the others.*

**30. Player Pool and Response Needed players who drop out: charged anything?**
*Default: never. Only You're In! players owe money.*

**31. When YOU cancel a clinic, does everyone get an automatic refund of anything already paid?**
*Default: yes, automatic, same day, no action from you.*
*ANSWERED 2026-09-16 (decision 0012): no refunds, because nothing is charged before the clinic ends.*
*(Not built until she answers.)*

**32. Card on file at sign-up: every player must add a card before they can register?**
*Default: yes. A player without a card can browse but not register. Members you trust can still pay Zelle if you mark them paid by hand.*
*ANSWERED 2026-09-16 (decision 0012): "Gosh I say yes."*
*(Not built until she answers.)*

**33. When is the regular clinic fee charged: at registration, or after the clinic?**
*Default: charged when they land in You're In! (or accept an invitation), refunded automatically if they cancel before the cutoff.*
*ANSWERED 2026-09-16 (decision 0012): after the clinic, everyone who came.*

**34. Should the app ever charge a card without you seeing it first, or should every charge wait for your tap?**
*Default: the regular fee is automatic; a late-cancel or no-show charge waits for your tap on the roster, so you can waive it for a good reason.*
*ANSWERED 2026-09-16 (decision 0012): the courtesy is automatic; the charge is her one tap per clinic (question 43 confirms the tap).*

**35. Do you want Zelle to stay as an option once cards work?**
*Default: yes, for members who prefer it; you mark those paid by hand as today.*

**36. Stripe account: can you create one at stripe.com this week? It asks for your bank account, a business address, and your SSN or an EIN. Your personal details work now; it can switch to the LLC later.**
*Default: you create it and Alex adds the two keys to the app; nobody else ever sees them.*
*ANSWERED 2026-09-16: she gave Alex the business details directly. They live in Stripe's form and nowhere else.*

**37. The exact sentence a player reads when they add a card and agree to the cancellation rule. Your words, or shall we draft one for you to edit?**
*Default: we draft, you edit, nothing ships until you say so.*
*ANSWERED 2026-09-16 (decision 0012): her text ships verbatim, marked for her edit: "Your card will only be charged for late cancellations or no-shows. Cancel at least 4 hours before clinic and you will not be charged." Note: her regular-fee answer (Q41) charges every attendee, so this sentence understates what the card is charged for; question 46.*

## J. After Tara's 4-hour answer (added 2026-09-12)

Her words: *"honor system for canceling, unless it's an emergency, someone sick
in your household, etc ... very concise message - the threshold will be 4
hours, so before 4 hours anything can be cancelled but after that you have to
say it's an emergency to cancel."* These are the gaps that remain.

**38. Inside 4 hours, is saying it is an emergency the ONLY way to cancel?**
*Default: yes. The app asks for the short message, and the cancellation goes through. Without the message it does not.*
*ANSWERED 2026-09-16 (decision 0012): no. The emergency claim is gone; inside 4 hours the cancel goes through, the note is optional, and the app applies one courtesy per 90 days.*

**39. Emergency cancels: never charged, or yours to decide one by one?**
*Default: yours. The roster shows the message next to the name and a Charge button. Nothing is charged unless you tap.*
*ANSWERED 2026-09-16 (decision 0012): the app applies the courtesy; after it is used the full fee applies, and she can still not charge a row.*

**40. The sentence the app shows inside 4 hours, above the message box. Your words?**
*Default: we draft, you edit, nothing ships until you say so.*
*ANSWERED 2026-09-16 (decision 0012): her text ships verbatim, marked for her edit: "This cancellation is within 4 hours of clinic and the full clinic fee will apply. If there are circumstances you'd like us to consider, please leave a note below."*

**41. The regular clinic fee: charge the card automatically when someone is In, or keep Zelle as the normal way to pay and use the card only for late cancels and no-shows?**
*Default: card automatically when they are In (question 33). Say "Zelle stays normal" and the card is only for the late ones.*
*ANSWERED 2026-09-16 (decision 0012): "I want to charge everyone's card everytime they come to clinic", after the clinic is over.*

**42. Courts stay on reservemycourt.com for now, nothing to build there in v1?**
*Default: yes. It goes on the list for later, with the rest of the club (treats, pool, merch, cabanas).*
*ANSWERED 2026-09-16: "Correct."*

## K. After Tara's 2026-09-16 answers (decision 0012)

**43. Charging after a clinic: you tap "Charge clinic" once you've marked any no-shows, or should the app charge everyone automatically at the end time?**
*Default: your tap. Nothing is charged until you press it, and the roster shows who will be charged what.*
*ANSWERED 2026-09-21 (decision 0013): "I'll do this - I'll tap charge - app does nothing automatically w payments." Built as her tap.*

**44. The one courtesy every 90 days covers a late cancellation only; a no-show is always the full fee. Right?**
*Default: yes, as your policy lists them separately.*
*ANSWERED 2026-09-21 (decision 0013): "No courtesy anymore." The courtesy is switched off entirely (courtesy_cancel_days = 0).*

**45. The waiver page you sent is the tennis camp (parent/guardian) form. Is there an adult version for clinics, or should the app show that one?**
*Default: we show nothing until there is an adult version; juniors are later anyway.*
*ANSWERED 2026-09-21 (decision 0013): "Sent to you in text": FXE_Adult_Tennis_Participation_Waiver.docx, version September 2026, in `docs/copy.md` and the `waivers` table; signed in the app before the first spot.*

**46. Your card sentence says the card is charged only for late cancellations and no-shows, but every attendee's card is charged after each clinic. Rewrite, or keep and let the cancellation policy explain?**
*Default: one sentence: "Your card is charged after each clinic you attend. Late cancellations and no-shows are charged the full fee; the policy explains."* (ours, needs your words)
*ANSWERED 2026-09-21 (decision 0013), her sentence: "Your card will only be charged after the clinic you attended, late cancellations, or no-shows. Cancel at least 3 hours before clinic and you will not be charged." Ships verbatim.*

**47. The note only you see, at level entry: should it show on your roster next to the rating, or only on the player's page?**
*Default: both, short.*
*ANSWERED 2026-09-21 (decision 0013): "Both." search_players returns it; the roster row and the player page show it.*

**48. Deleting an account. Apple requires a "Delete my account" button. When a player deletes theirs, should their history and payment record stay with you with the name removed, or go entirely?**
*Default: the rows stay, the name, phone and email are blanked (a paid clinic in March should still add up in Money in April). Status: open, asked 2026-09-18 (launch checklist D5).*
*ANSWERED 2026-09-21 (decision 0013): "Keep their history." Built: delete_my_account() plus the delete-account edge function.*

**49. A Saturday clinic opens with the week before it: the Thursday nine days out for members, the Friday for everyone. Right?**
*Default: yes, that is what is built (decision 0001; the first of the three open points under "Open questions on the window rule" in CLAUDE.md). Status: open, asked 2026-09-18.*
*ANSWERED 2026-09-21 (decision 0013): "Yes. But no Saturday clinics. The 'week' starts on a Sunday to Friday. Membership opens Thursday Sept 1 for clinics Sunday, Sept 4th - Friday, Sept 9th." Confirms decision 0001 as built; Saturday is theoretical.*

**50. A short week, say clinics only Monday to Wednesday over a holiday, still opens the Thursday and Friday before. Right?**
*Default: yes, built that way. Status: open, asked 2026-09-18.*
*ANSWERED 2026-09-21 (decision 0013): "Yes."*

**51. "Smart. Simple. Built for Tennis." under the logo on the sign-in screen came from the AI mockups, not from you. Keep, change, or drop?**
*Default: drop it; the logo needs no caption. Status: open, asked 2026-09-18.*
*ANSWERED 2026-09-21 (decision 0013): "Let's play!" on the Questions tab, "Let's Play." on the Words tab. The Words version ships; question 55 confirms which.*

## L. After her review of every word (added 2026-09-21)

**52. Under your membership line on Edit details the app says "Set by Tara". You wrote "Do we need anything?" Drop the caption, or keep it so a player knows why they can't change it?**
*Default: keep it. Status: open, asked 2026-09-21.*

**53. After a player messages you inside the 3-hour close, the app says "Tara has your message." You chose Change and left it blank. What should it say?**
*Default: keep "Tara has your message." Status: open, asked 2026-09-21.*

**54. "You're not registered for any clinics this week" now shows under My Clinics, which lists every upcoming clinic, not only this week's. Keep it, or "You're not registered for any clinics"?**
*Default: keep your words. Status: open, asked 2026-09-21.*

**55. The line under the logo: "Let's Play." or "Let's play!"?**
*Default: "Let's Play." Status: open, asked 2026-09-21.*

**56. Your cancellation policy text still says 4 hours, the courtesy paragraph, and the emergency email. The app shows only your two sentences today. Do you want the block rewritten (3 hours, no courtesy) shown somewhere, and if so, where and in what words?**
*Default: not shown until you rewrite it. Status: open, asked 2026-09-21.*

**57. "Cards aren't set up yet." (before Stripe is connected): you wrote "Stripe needs to be connected". Was that a note to us, or the words a player should see?**
*Default: a note to us; the line disappears once Stripe is live. Status: open, asked 2026-09-21.*

### How 52 to 57 are being sent

Round two of the review page (2026-09-21, later): the Words tab now shows her
applied wording tagged "Your words", the chrome that arrived with the waiver,
deletion and Past, and only these six questions. The artifact was republished
at the same link; the same page on the admin site (`web/review.html`, page
version 2) saves as she types once it is deployed.

### How 43 to 51 were sent

Not as this file. On 2026-09-18 they went to Tara as the Questions tab of her review page (`docs/tara-review/index.html`, published privately at https://claude.ai/artifact/1H3fCuvG7pkc9scTAJmfkL for Alex to share), in the plainer wording that page uses. Her answers come back as one pasted text; record them here with a date and a decision number, as 0007 and 0012 were.

