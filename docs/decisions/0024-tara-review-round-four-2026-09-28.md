# 0024: Tara's round-four answers: pros, a declined card, "Resolved", her uninvite message, a QR code, and the party moves to November 6

**Date:** 2026-09-28 · **Status:** Active · **Source:** Tara's review page, round four (link "Tara Link #2", page version 4), saved to hosted `review_responses` at 17:12 UTC on 2026-09-28; read the same day through the management API (issue #79). Her words are quoted exactly, curly apostrophes and missing full stops included.

## What she said, and what we do with it

### The party

> "Party is changing to Nov 6" · "If the app is ready before the party - let’s do it."

The launch target moves from 2026-10-16 to **Friday 2026-11-06**. The app can go to members before then. The real-money gate (checklist A11) was "Tara's Stripe live by 10-14, two days before the party"; it moves with the party to **2026-11-04** unless Alex says otherwise.

### Words (Keep / Change)

| String | Her answer | What we do |
|---|---|---|
| Rating Guide | "Correct. Words do not change. Tool tip next to “rating” language" | The words stay. The guide opens from a "?" placed right beside the rating label, as it already does on Profile, instead of a text link at the far right of the sign-up and Edit details forms. VoiceOver still reads it as "Rating Guide" |
| Tick the box to continue. | "Check the box to continue" | Replaced, exactly: no full stop |
| Only Tara can change this. | "Remove “set my Tara” from view by user." | Removed from every player screen. Membership still shows ("FXE Member" / "Non-member"); it simply has no caption |
| Charged 6 cards. 1 player has no card on file. | "If the card is not charged, there must be a problem with the card (expiration date, overdrafted, etc) otherwise there is always a card on file" | The summary after Charge clinic leads with what was charged and what was declined, with the reason. The "no card on file" clause stays only for the case that can still happen: someone who registered before cards were required |
| The other eleven | keep | Unchanged |

### Questions

| # | Her answer | Status |
|---|---|---|
| 71, the pros | "For right now, I’m going to be the only one that sees everything. Let the pros see who is coming to the clinics that day. I don’t want the pros to invite people from the player pool. See anything financial at all." Four pros named with their email addresses (kept on hosted, not copied here: this repository is public). "Eventually I will have Thomas see more and Jess see more" | **Answered.** A pro role: sees today's clinics and who is in them, marks Came / No-show and a late cancellation (her 2026-09-22 answer, decision 0016); never invites, never sees money, notes or anything financial. Tara alone makes someone a pro, and is still the only admin. Built so that more can be granted to one pro later |
| 72, guests | "The guest always is charged Nonmember price, correct. If in the app the player can click a button that says “imvite a friend” (and they can send the app to them or ask me to write their friends name in.. that’s perfect.) and notify them they (the person inviting the guest) will be charged for their guest. Idk if that makes sense" | **Answered in principle.** Non-member price, billed to the member who brings them. The flow (an Invite a friend button that shares the app or asks Tara to add the friend by name) is designed in `docs/guests.md` before it is built, because it moves money; the one sentence the member sees about being charged is question 93 |
| 74, back-to-back 105s | "Correct." | **Answered**: as built (decision 0015 §13) |
| 75, how members find out | "I’m almost done w taking sign ups via text. All email. Def want a QR code and I will be emailing membership about the app and my email dist of members." | **Answered.** A QR code that points at one link we control, which forwards to wherever the app is installed from (TestFlight's public link now, the App Store later), so the code she prints or emails never has to change |
| 76, reaching her | "Yes" | **Answered**: a Contact Tara link on Profile that opens an email to fersctennispro@gmail.com |
| 77, the waiver after deletion | "Yes" | **Answered**: as built |
| 78, a declined card | "Cannot sign up without proper, transactional card. App needs to tell them why their card isn’t working, yes." | **Answered, and it changes the default.** After a charge is declined, that player cannot register until they save a card again, and the app tells them why (the same reason words she approved for her own screen, such as "Declined: Insufficient funds (NSF)") |
| 79, telling a player when she moves them | "Yes if I “uninvited them” it’s The levels didn’t line up for this clinic, so we’ve released your spot. We keep each court close in level so everyone gets a great practice. We’ll catch you at the next clinic!" | **Answered for taking back an invitation**: that message, verbatim, to the player whose invitation she withdraws. Taking someone out of You're In! is not an "uninvite", and the same words would be wrong when a player asked her in person to drop them, so that case is question 92 |
| 80, late cancel then back in | "Once always" | **Answered**: as built (decision 0018) |
| 82, a clinic canceled for rain | "Never charged" | **Answered**: as built |
| 83, a declined card she won't chase | "Can we have a button that says “resolved” and it clears - for me only to see ofc" | **Answered**: a Resolved button on each declined card in her Action Needed, web and phone. It clears the row for her; the payment's history keeps the decline |
| 84, deleted before she charges | "Let it go. I’ll always charge after clinic and I’ll hunt them down if they delete their card after playing." | **Answered**: as built |
| 86, receipts | "No receipts" | **Answered**: none |
| 88, the day or the date | "Well they can’t sign up for a clinic that far in advance so this isn’t relevant" | **Answered**: the day only, as written |
| 89, a lost chargeback and Paid | "What you said yes" | **Answered**: Paid stays |
| 90, approving a late request | "You’re in for" | **Answered**: the current line |
| 91, accepting after the start | "Correct" | **Answered**: an Accept works until the clinic ends |
| 73, the board's 10% | (no answer) | Still open |

## Rejected

- **Sending her uninvite message when she removes someone from You're In!** Her words are about withdrawing an invitation. The same sentence would tell a player who asked to be dropped that "the levels didn’t line up". Question 92 asks.
- **Letting pros sign in to the laptop admin.** She wants them to see "who is coming to the clinics that day"; that is courtside work, the phone's job (decision 1). The laptop stays hers alone.
- **Putting the pros' names and emails in this repository.** It is public. They are in her saved answers on hosted, and she makes each pro herself once they have signed up.

## How we would know this was wrong

A pro sees a price, a card, a note or the Player Pool's Invite; a player with a declined card registers anyway, or is blocked without being told why; a player whose invitation was withdrawn gets no message, or gets hers for something else.
