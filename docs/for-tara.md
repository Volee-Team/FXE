# FXE Tennis: A Few Questions Before We Build

> Sent 2026-08-02; kept as the record of what was asked. Answered on the
> 2026-08-02 call: 1, 3, 4, 5, 6, 8, 10, 11, 12, 14, 15, 16 (CLAUDE.md, "Tara's
> decisions"). 2: answered, and our suggestion below was wrong; see decision
> 0001. 7: answered 2026-08-27 (0007 §3). 9: deferred to November/spring (0007
> §6). 11: the "no money moves" premise is superseded by 0009. 13: overruled
> (decision 13, no notifications-off marker). 15: the tennis-ball mark was
> replaced by the crossed-racquets mark (decision 22). 16: LLC account (in
> review), privacy policy reuses Volee's, waiver wording pending. The birthday
> change is moot until juniors return.

Alex here. The developer guide is genuinely good, better than most specs I've worked from. There are about a dozen things it doesn't quite answer that change how we build. Everything else we're deciding ourselves so you don't have to think about it.

Each question has our suggested answer underneath. **If our suggestion sounds right, just say "yes."** Only slow down on the ones you have an opinion about.

---

### 1. This is the big one: phone or laptop?

The guide has you running everything from your phone. Creating a week of clinics, searching players, assigning courts, all on a phone screen.

Honest opinion: the weekly setup and the court assignments would be a lot easier on a laptop. We can build you a simple web page you open in a browser for that, and keep the phone app for game-day stuff (invites, messages, marking people paid).

**Suggestion:** phone app for everything you do at the courts, laptop page for the weekly setup. Or tell us phone-only and we'll build it that way.

---

### 2. When exactly does registration open?

Members Thursday 8 AM, non-members Friday 8 AM, we have that. But for a clinic on a **Monday**, is that the Thursday four days earlier?

**Suggestion:** always the most recent Thursday before the clinic. The app figures it out automatically, you never type it in. If a clinic ever needs a different date, you can override it.

---

### 3. Can you add someone yourself?

Someone calls you, or grabs you at the club. The guide has no way for you to just put them in a clinic without them using the app.

**Suggestion:** yes, you can add anyone to any clinic directly, and move anyone between "You're In!" and "Player Pool" by hand. You'll want this in week one.

---

### 4. Should the app ever stop you from inviting someone?

If a clinic is at capacity and you invite one more person from the Player Pool, should the app block you?

**Suggestion:** no. We show you the numbers, you make the call. It's your program.

---

### 5. People report their own member status.

Anyone can tick "yes, I'm a member" and get Thursday priority, whether they are or not.

**Suggestion:** leave it as-is, and you can correct anyone's status on their profile when you notice. Say the word if you'd rather be the only one who can set it.

---

### 6. What are the adult rating options?

We need the exact list players choose from. NTRP 2.5 / 3.0 / 3.5 / 4.0 / 4.5+? Something FXE uses instead?

---

### 7. What should the "Need Help?" rating guide say?

Please write this in your own words, a line or two per level. This is what a nervous new player reads before picking their rating, so it should sound like you, not like us.

---

### 8. What are the clinic categories?

The clinic form has "audience" (Ladies / Men / Coed / Juniors) and also "category." What goes in category? Drill, Cardio, Match Play, Camp, something else? Send us the full list.

---

### 9. Do junior clinics need age labels?

Right now all juniors see one list. A parent of a 9 year old and a parent of a 16 year old see the same thing.

**Suggestion:** the clinic name does the work (e.g. "Junior Development 8-10"). No extra filters. Tell us if you want real age groups instead.

---

### 10. Why is clinic location hidden from players?

We're following the rule either way, we just want to understand it. Is it because everything is at FXE so listing a location is clutter, or is there another reason?

---

### 11. Payment.

The app tracks a Paid checkbox only, no money moves through it.

**Suggestion:** your Venmo info shows on the clinic page and in the unpaid reminder. Send us the exact wording you want. If a clinic gets canceled, the app does nothing about refunds, you handle that yourself.

---

### 12. Targeted messages: who sees them later?

If you message only the unpaid players, should that message stay on the clinic page where everyone can read it afterwards? The guide says both things.

**Suggestion:** a message you send to one group stays visible only to that group. Messages to Everyone stay visible to everyone.

---

### 13. Push notifications are the only way the app reaches anyone.

If a player turns off notifications at signup, they get nothing. Not your invitations, not cancellations.

**Suggestion:** we put a small "notifications off" marker on their profile so you can see who to text the old way.

---

### 14. Notification wording.

There are about ten messages: invitation received, you're in, clinic canceled, time changed, unpaid reminder, new announcement, and the ones that come to you.

**Suggestion:** we write drafts, you edit them. Or write them yourself if you'd rather.

---

### 15. Logo and colors.

We need the gator-with-tennis-ball logo as a PNG or SVG with a transparent background, and your exact navy, cream, and green. Hex codes if the club has them, otherwise send an image and we'll pull the colors out of it.

---

### 16. Business side.

Three things that have to be settled before the app can go in the App Store:

- Whose Apple Developer account does FXE Tennis live under?
- The app stores kids' names and ages. Does FXE already have parent consent language from club forms or waivers?
- Who writes the privacy policy, and is there an FXE website we can put it on?

---

### One thing we're changing on our own

The guide says a child's profile stores their **age**. We're going to ask for their **birthday** instead and calculate the age from it. A stored age goes stale: a 9 year old stays 9 in your directory forever. A birthday is right every year. The form will say "Birthday."

Tell us if you'd rather it just ask for age.
