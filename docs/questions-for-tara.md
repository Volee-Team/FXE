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
*ANSWERED 2026-08-02 (decision 16): FXE Tennis, LLC. Enrollment in review.*

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

**29. A no-show, meaning they never canceled and never came: charged the same as a late cancel?**
*Default: yes, same as a late cancel, marked by you after the clinic.*

**30. Player Pool and Response Needed players who drop out: charged anything?**
*Default: never. Only You're In! players owe money.*

**31. When YOU cancel a clinic, does everyone get an automatic refund of anything already paid?**
*Default: yes, automatic, same day, no action from you.*
*(Not built until she answers.)*

**32. Card on file at sign-up: every player must add a card before they can register?**
*Default: yes. A player without a card can browse but not register. Members you trust can still pay Zelle if you mark them paid by hand.*
*(Not built until she answers.)*

**33. When is the regular clinic fee charged: at registration, or after the clinic?**
*Default: charged when they land in You're In! (or accept an invitation), refunded automatically if they cancel before the cutoff.*

**34. Should the app ever charge a card without you seeing it first, or should every charge wait for your tap?**
*Default: the regular fee is automatic; a late-cancel or no-show charge waits for your tap on the roster, so you can waive it for a good reason.*

**35. Do you want Zelle to stay as an option once cards work?**
*Default: yes, for members who prefer it; you mark those paid by hand as today.*

**36. Stripe account: can you create one at stripe.com this week? It asks for your bank account, a business address, and your SSN or an EIN. Your personal details work now; it can switch to the LLC later.**
*Default: you create it and Alex adds the two keys to the app; nobody else ever sees them.*

**37. The exact sentence a player reads when they add a card and agree to the cancellation rule. Your words, or shall we draft one for you to edit?**
*Default: we draft, you edit, nothing ships until you say so.*

## J. After Tara's 4-hour answer (added 2026-09-12)

Her words: *"honor system for canceling, unless it's an emergency, someone sick
in your household, etc ... very concise message - the threshold will be 4
hours, so before 4 hours anything can be cancelled but after that you have to
say it's an emergency to cancel."* These are the gaps that remain.

**38. Inside 4 hours, is saying it is an emergency the ONLY way to cancel?**
*Default: yes. The app asks for the short message, and the cancellation goes through. Without the message it does not.*

**39. Emergency cancels: never charged, or yours to decide one by one?**
*Default: yours. The roster shows the message next to the name and a Charge button. Nothing is charged unless you tap.*

**40. The sentence the app shows inside 4 hours, above the message box. Your words?**
*Default: we draft, you edit, nothing ships until you say so.*

**41. The regular clinic fee: charge the card automatically when someone is In, or keep Zelle as the normal way to pay and use the card only for late cancels and no-shows?**
*Default: card automatically when they are In (question 33). Say "Zelle stays normal" and the card is only for the late ones.*

**42. Courts stay on reservemycourt.com for now, nothing to build there in v1?**
*Default: yes. It goes on the list for later, with the rest of the club (treats, pool, merch, cabanas).*

