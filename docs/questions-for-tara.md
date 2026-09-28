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
*Update 2026-09-21: the iOS UI stopped offering the switch on 2026-09-02 ("Set by Tara"), but the column grant survived until `revoke update (is_member)` landed in 20260921000001; `admin_set_membership` is now the only write path.*

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
*Update 2026-09-21: a PAST section was added under My Clinics (`my_past_clinics`, migration 20260921000004), showing each player their own outcome: Played · $18, Played, No-show, Canceled, Canceled late. Tara's Manage list has Past too.*

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
*ANSWERED 2026-08-02/08-12 (decisions 15, 22, 23): crossed-racquets mark (in repo), her hex codes in Brand.swift. Still open: the cream ground #F7F4EC is our choice awaiting her OK (the older #FAF7F1 belonged to palette A and is gone).*

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
*ANSWERED 2026-09-12: 4 hours, honor system (decision 0010). **SUPERSEDED 2026-09-21 (decision 0013): 3 hours** ("3 hours instead of 4. Otherwise good"), which is also the registration close. Free before; inside 4 hours the player has to say it is an emergency, with a very concise message.*

**28. Is the late-cancellation charge the full clinic price, or a fixed amount?**
*Default: full price of that clinic ($18/$23 or $22/$28).*
*ANSWERED 2026-09-16 (decision 0012): "Full price as you listed - yes, def full."*

**29. A no-show, meaning they never canceled and never came: charged the same as a late cancel?**
*Default: yes, same as a late cancel, marked by you after the clinic.*
*ANSWERED 2026-09-16 (decision 0012): full fee, marked by her on the clinic list, charged with the others.*

**30. Player Pool and Response Needed players who drop out: charged anything?**
*Default: never. Only You're In! players owe money.*
*ANSWERED 2026-09-12 and 2026-09-16 (decisions 0010, 0012): never. A Pool or Response Needed row holds no spot, so leaving it is not a late cancel and nothing is charged; `late_cancellation.sql` asserts it.*

**31. When YOU cancel a clinic, does everyone get an automatic refund of anything already paid?**
*Default: yes, automatic, same day, no action from you.*
*ANSWERED 2026-09-16 (decision 0012): no refunds, because nothing is charged before the clinic ends.*

**32. Card on file at sign-up: every player must add a card before they can register?**
*Default: yes. A player without a card can browse but not register. Members you trust can still pay Zelle if you mark them paid by hand.*
*ANSWERED 2026-09-16 (decision 0012): "Gosh I say yes."*
*Built 2026-09-16: `app_settings.card_required` is `true` and `register_for_clinic` raises `card_required`; the app says "Add a card on your Profile to register." The gate is inert until `payments_enabled` is true.*

**33. When is the regular clinic fee charged: at registration, or after the clinic?**
*Default: charged when they land in You're In! (or accept an invitation), refunded automatically if they cancel before the cutoff.*
*ANSWERED 2026-09-16 (decision 0012): after the clinic, everyone who came.*

**34. Should the app ever charge a card without you seeing it first, or should every charge wait for your tap?**
*Default: the regular fee is automatic; a late-cancel or no-show charge waits for your tap on the roster, so you can waive it for a good reason.*
*ANSWERED 2026-09-16 (decision 0012): the courtesy is automatic; the charge is her one tap per clinic (question 43 confirms the tap).*
*The automatic courtesy in that answer was withdrawn 2026-09-21 (decision 0013); the tap is confirmed by question 43.*

**35. Do you want Zelle to stay as an option once cards work?**
*Default: yes, for members who prefer it; you mark those paid by hand as today.*
*ANSWERED 2026-09-21 (decision 0013 §3): no. "Everyone using the app has to input a credit card." `zelle_allowed` is false; the Paid toggle and reminder are hidden.*

**36. Stripe account: can you create one at stripe.com this week? It asks for your bank account, a business address, and your SSN or an EIN. Your personal details work now; it can switch to the LLC later.**
*Default: you create it and Alex adds the two keys to the app; nobody else ever sees them.*
*ANSWERED 2026-09-16: she gave Alex the business details directly. They live in Stripe's form and nowhere else.*

**37. The exact sentence a player reads when they add a card and agree to the cancellation rule. Your words, or shall we draft one for you to edit?**
*Default: we draft, you edit, nothing ships until you say so.*
*ANSWERED 2026-09-16 (decision 0012): her text ships verbatim, marked for her edit: "Your card will only be charged for late cancellations or no-shows. Cancel at least 4 hours before clinic and you will not be charged." Note: her regular-fee answer (Q41) charges every attendee, so this sentence understates what the card is charged for; question 46.*
*SUPERSEDED 2026-09-21 by her question-46 rewrite (decision 0013), which is what ships: "Your card will only be charged after the clinic you attended, late cancellations, or no-shows. Cancel at least 3 hours before clinic and you will not be charged."*

## J. After Tara's 4-hour answer (added 2026-09-12)

Her words: *"honor system for canceling, unless it's an emergency, someone sick
in your household, etc ... very concise message - the threshold will be 4
hours, so before 4 hours anything can be cancelled but after that you have to
say it's an emergency to cancel."* These are the gaps that remain.

**38. Inside 4 hours, is saying it is an emergency the ONLY way to cancel?**
*Default: yes. The app asks for the short message, and the cancellation goes through. Without the message it does not.*
*ANSWERED 2026-09-16 (decision 0012): no. The emergency claim is gone; inside 4 hours the cancel goes through, the note is optional, and the app applies one courtesy per 90 days.*
*SUPERSEDED 2026-09-21 (decision 0013): no courtesy at all (`courtesy_cancel_days = 0`), and the window is 3 hours.*

**39. Emergency cancels: never charged, or yours to decide one by one?**
*Default: yours. The roster shows the message next to the name and a Charge button. Nothing is charged unless you tap.*
*ANSWERED 2026-09-16 (decision 0012): the app applies the courtesy; after it is used the full fee applies, and she can still not charge a row.*
*SUPERSEDED 2026-09-21 (decision 0013): "No courtesy anymore." The full fee applies every time; she can still skip a row when she charges.*

**40. The sentence the app shows inside 4 hours, above the message box. Your words?**
*Default: we draft, you edit, nothing ships until you say so.*
*ANSWERED 2026-09-16 (decision 0012): her text ships verbatim, marked for her edit: "This cancellation is within 4 hours of clinic and the full clinic fee will apply. If there are circumstances you'd like us to consider, please leave a note below."*
*Amended 2026-09-21 (decision 0013) to three hours; ships verbatim: "This cancellation is within 3 hours of clinic and the full clinic fee will apply. If there are circumstances you'd like us to consider, please leave a note below."*

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
*ANSWERED 2026-09-22 (decision 0016): "I'm confused by this. Let's talk". Replaced with "Only Tara can change this."; question 70 shows it to her, and Alex raises it when they talk.*

**53. After a player messages you inside the 3-hour close, the app says "Tara has your message." You chose Change and left it blank. What should it say?**
*Default: keep "Tara has your message." Status: open, asked 2026-09-21.*
*ANSWERED 2026-09-22 (decision 0016): keep.*

**54. "You're not registered for any clinics this week" now shows under My Clinics, which lists every upcoming clinic, not only this week's. Keep it, or "You're not registered for any clinics"?**
*Default: keep your words. Status: open, asked 2026-09-21.*
*ANSWERED 2026-09-22 (decision 0016): keep.*

**55. The line under the logo: "Let's Play." or "Let's play!"?**
*Default: "Let's Play." Status: open, asked 2026-09-21.*
*ANSWERED 2026-09-22 (decision 0016): "Let's Play.", kept.*

**56. Your cancellation policy text still says 4 hours, the courtesy paragraph, and the emergency email. The app shows only your two sentences today. Do you want the block rewritten (3 hours, no courtesy) shown somewhere, and if so, where and in what words?**
*Default: not shown until you rewrite it. Status: open, asked 2026-09-21.*
*WITHDRAWN 2026-09-27: the default stands and is not re-asked. Alex, 2026-09-27: "why tf are we giving her so many if she did this like last week". Round four asks only what is still open.*

**57. "Cards aren't set up yet." (before Stripe is connected): you wrote "Stripe needs to be connected". Was that a note to us, or the words a player should see?**
*Default: a note to us; the line disappears once Stripe is live. Status: open, asked 2026-09-21.*
*ANSWERED 2026-09-22 (decision 0016): "Let's only do if stripe is connected". Read as a note to us; the line shows only while Stripe is not connected, and it is connected.*

## M. After the Final Updates (added 2026-09-26, decision 0015)

**58. The board's 10%: of what was collected by card, or of full clinic prices? Before or after Stripe's fee?**
*Default: 10% of what was collected, before Stripe's fee. The report shows both bases. Status: open, asked 2026-09-26.*
*MERGED 2026-09-27 into question 73.*

**59. Home when a player has exactly one clinic of their own: that clinic on top and the open clinics listed under it (built), or only their clinic and the blue button?**
*Default: as built. With two or more, only their clinics and the blue button. Status: open, asked 2026-09-26.*
*WITHDRAWN 2026-09-27: the default stands and is not re-asked. Alex, 2026-09-27: "why tf are we giving her so many if she did this like last week". Round four asks only what is still open.*

**60. Back-to-back 105s: the 48 hours count from the start of the earlier 105 that day, so in your example both unlock Friday 4:30 for the Sunday 4:30 and 6:00. Right?**
*Default: yes, built that way, counted on the clock: two days earlier at the same time, so on the weekends the clocks change it is still Friday 4:30, not 3:30 or 5:30. Status: open, asked 2026-09-26.*
*MERGED 2026-09-27 into question 74.*

**61. Does a Player Pool spot count as "signed up" for the 105 rule, or only You're In!?**
*Default: any spot counts, Pool included, since non-members join the Pool. Status: open, asked 2026-09-26.*
*MERGED 2026-09-27 into question 74.*

**62. Is it only 105s, or any two clinics on the same day?**
*Default: only 105s (a clinic with 105 in its name or category). Status: open, asked 2026-09-26.*
*MERGED 2026-09-27 into question 74.*

**63. The words a non-member sees when the rule stops them.**
*Default until you write it: "Non-members can take one 105 a day until 48 hours before." Status: open, asked 2026-09-26.*
*MERGED 2026-09-27 into question 74.*

**64. Could you send the court photo as the original file?** The one in the message is a screenshot and looks soft on a full screen.
*Default: keep the screenshot until then. Status: open, asked 2026-09-26.*
*MOVED 2026-09-27 to Alex (docs/for-alex.md §9): a request for a file, not a question.*

**65. The card box says "I give permission for my card to be charged", your exact words. Keep, or longer?**
*Default: keep. Status: open, asked 2026-09-26.*
*WITHDRAWN 2026-09-27: the default stands and is not re-asked. Alex, 2026-09-27: "why tf are we giving her so many if she did this like last week". Round four asks only what is still open.*

**66. A player who added a card before the permission box existed (nobody today; cards could not be added until Stripe is connected) has no permission on record. Charge them anyway, or ask them to tick the box first?**
*Default: ask first; nobody is in this position yet. Status: open, asked 2026-09-26.*
*WITHDRAWN 2026-09-27: the default stands and is not re-asked. Alex, 2026-09-27: "why tf are we giving her so many if she did this like last week". Round four asks only what is still open.*

**67. Someone is refunded in September for an August clinic, after August's report went to the board. Should the refund come off August (the report you already sent changes) or off September?**
*Default today: it comes off August, the month of the clinic, and the report prints the time it was run so a re-run can be explained. Status: open, asked 2026-09-26.*
*MERGED 2026-09-27 into question 73.*

**68. Do late-cancel and no-show fees count toward the board's 10%?**
*Default: yes, they are program income; the report shows them under "Collected by card" but not under "Fees at clinic prices". Status: open, asked 2026-09-26.*
*MERGED 2026-09-27 into question 73.*

## N. Round four, only what is still open (added 2026-09-27, decision 0016)

Round three repeated 120 strings and 17 questions she had mostly answered on
2026-09-22 (nobody had read her answers; decision 0016). Round four is the
new and changed words and these questions, nothing else.

**69. "Need Help?" at sign-up: you marked it Change with no new words. It now says "Rating Guide", the name of the chart it opens. OK?**
*Default: "Rating Guide". Status: open, asked 2026-09-27 (Words tab).*

**70. Beside a player's membership on Edit details it said "Set by Tara" and you wrote "I'm confused by this. Let's talk". It now says "Only Tara can change this.", because members can't change their own membership (you can, on their profile). OK?**
*Default: "Only Tara can change this." Status: open, asked 2026-09-27 (Words tab; Alex also raises it with her).*

**71. You and the pros. You wrote that only you charge people and see the money, and the pros can see the clinic list and mark no-show and late cancellation. Who are the pros who need a login, and can they also: set courts, message a clinic, invite from the Player Pool, add a walk-up, see your private notes on players?**
*ANSWERED 2026-09-28 (decision 0024): only she sees everything; pros see who is coming to that day's clinics, mark Came / No-show and late cancellations, never invite from the Pool, never see anything financial. Four pros named (kept on hosted, not here: the repo is public). "Eventually I will have Thomas see more and Jess see more".*

**72. Guests who don't have the app. You wrote the member who brings them gets charged. Proposed: you (or a pro) add the guest to the clinic from the laptop, pick which member brought them, and after the clinic that member's card is charged the guest's fee. Which price does the guest pay, member or non-member? Do they take a spot like anyone else?**
*HALF ANSWERED 2026-09-28 (decision 0024): the guest always pays the non-member price, billed to the member who brings them, through an "Invite a friend" button that shares the app or asks her to add the friend by name. Flow in `docs/guests.md`; the sentence telling the member they will be charged is question 93.*

**73. The board's 10% (was 58, 67, 68). The report shows 10% of what players actually paid by card that month, late-cancel and no-show fees included, before Stripe's fee, and a refund comes off the month of the clinic. Right?**
*Default: as stated, which is what is built. Status: open, asked 2026-09-27.*

**74. Back-to-back 105s (was 60 to 63). As built: a non-member who holds any spot in a 105 that day (Player Pool included) cannot take a second 105 that day until 48 hours before the first one starts, clock time; only 105s count; they see "Non-members can take one 105 a day until 48 hours before." Right, and are those the words?**
*ANSWERED 2026-09-28 (decision 0024): "Correct." As built.*

**75. How do members find out about the app, and from which week do you stop taking sign-ups by text?**
*ANSWERED 2026-09-28 (decision 0024): all sign-ups by email now; she wants a QR code and will email the membership about the app. "If the app is ready before the party - let’s do it." The party moves to 2026-11-06.*

**76. When a member is stuck or has a question about a charge, how should the app tell them to reach you?**
*ANSWERED 2026-09-28 (decision 0024): "Yes": a Contact Tara link on Profile, emailing fersctennispro@gmail.com.*

**77. When someone deletes their account, we keep their signed waiver (typed name, email and date) as the club's record in case of an injury claim, and the privacy policy will say so. OK?**
*ANSWERED 2026-09-28 (decision 0024): "Yes". As built.*

**78. If a player's card is declined after a clinic, should the app tell them to update their card, and can they keep signing up meanwhile?**
*ANSWERED 2026-09-28 (decision 0024), changing the default: "Cannot sign up without proper, transactional card. App needs to tell them why their card isn’t working, yes." After a decline the player cannot register until they save a card again, and the app shows the reason.*

**79. When you take someone out of a clinic, take back an invitation, or put someone in yourself, should the app tell them?**
*ANSWERED 2026-09-28 (decision 0024) for taking back an invitation, with her words: "The levels didn’t line up for this clinic, so we’ve released your spot. We keep each court close in level so everyone gets a great practice. We’ll catch you at the next clinic!" Taking someone out of You're In! is question 92.*

## O. From the money fixes (added 2026-09-27, decisions 0018 and 0019)

**80. Someone cancels late and you then put them back in the same clinic: do they pay once or twice?**
*ANSWERED 2026-09-28 (decision 0024): "Once always". As built.*

**81. When a player texts you inside 3 hours that they can't come and you tap Late cancel, the full fee applies, the same as a late cancel in the app, and a plain Remove stays free. Right?**
*Default: yes, as built (her own words, 2026-09-22: pros "can label them as no show, late cancellation"). Status: open, asked 2026-09-27 (not on the page: confirms her own words).*

**82. If you cancel a clinic (say for rain), should anyone who had already canceled late for it still be charged?**
*ANSWERED 2026-09-28 (decision 0024): "Never charged". As built.*

**83. A card is declined and you decide not to chase it: how do you want to clear it from your list?**
*ANSWERED 2026-09-28 (decision 0024): a Resolved button that clears the row, for her only. The payment's history keeps the decline.*

**84. Someone plays a clinic, then deletes their account before you tap Charge: charge that clinic first, or let it go?**
*ANSWERED 2026-09-28 (decision 0024): "Let it go." As built.*

**85. Clinics charged during the test weeks, before real money is switched on: charged again for real after the switch?**
*Default: no, test charges stay as they are. Status: open, asked 2026-09-27 (not on the page: nobody is charged in the test weeks unless she chooses to).*

**86. After you charge a clinic, should Stripe email each player a receipt?**
*ANSWERED 2026-09-28 (decision 0024): "No receipts".*

**87. On the laptop, This week starts fresh every Sunday; last week's clinics move under Show earlier, except one you still need to charge. Right, or keep last week visible through Monday?**
*Default: as built. Status: open, asked 2026-09-27 (not on the page).*

## P. From wiring her notification words and the Payouts card (added 2026-09-28, decisions 0021 and 0022)

**88. Your "You're all set" message names the day ("on Thursday at 9:00 AM"). For a clinic a week or more away, should it also say the date ("on Thursday, Oct 8 at 9:00 AM")?**
*ANSWERED 2026-09-28 (decision 0024): not relevant, nobody can sign up that far ahead. The day only.*

**89. If a player's bank takes back a clinic fee (a chargeback) and the bank sides with the player, should the app un-mark them as Paid on your roster?**
*ANSWERED 2026-09-28 (decision 0024): "What you said yes". Paid stays.*

**90. When you approve a late request, the player gets "You're in for {clinic}." Should it be your "You're all set…" message instead?**
*ANSWERED 2026-09-28 (decision 0024): "You’re in for". The current line.*

**91. Someone taps Accept on your invitation after the clinic has already started. Let them in, or say no?**
*ANSWERED 2026-09-28 (decision 0024): "Correct". An Accept works until the clinic ends.*

## Q. After round four (added 2026-09-28, decision 0024)

**92. When you take someone out of You're In! yourself, should they get a message? Your "released your spot" words fit an invitation you take back, but not someone who asked you to drop them.**
*Default: nothing is sent for a removal from You're In! until you give the words. Status: open, asked 2026-09-28.*

**93. When a member brings a guest, what should the app tell the member about being charged? You wrote that they should be told they "will be charged for their guest".**
*Default: nothing is built until you give the sentence (the guest feature waits on it). Status: open, asked 2026-09-28.*

**94. When you take an invitation back, the player now gets your words ("…so we’ve released your spot… We’ll catch you at the next clinic!"). Today they also go back into the Player Pool for that clinic. Should they come off the clinic altogether instead?**
*Default: back into the Player Pool, as Cancel Invite has always done, until you say. Status: open, asked 2026-09-28.*

### How 52 to 57 are being sent

Round two of the review page (2026-09-21, later): the Words tab now shows her
applied wording tagged "Your words", the chrome that arrived with the waiver,
deletion and Past, and only these six questions. The artifact was republished
at the same link; the same page on the admin site (`web/review.html`, page
version 2) saves as she types once it is deployed.

### How 43 to 51 were sent

Not as this file. On 2026-09-18 they went to Tara as the Questions tab of her review page (`docs/tara-review/index.html`, published privately at https://claude.ai/artifact/1H3fCuvG7pkc9scTAJmfkL for Alex to share), in the plainer wording that page uses. Her answers come back as one pasted text; record them here with a date and a decision number, as 0007 and 0012 were.

