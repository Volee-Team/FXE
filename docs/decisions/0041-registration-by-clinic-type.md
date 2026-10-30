# 0041. Registration by clinic type, 1-hour offers, Waitlist, 3.0+ approval (Tara, 2026-10-15)

**Status:** accepted, building. Tara's email to Alex of 2026-10-15, relayed
2026-10-16, with Kat's matching ask in the group text ("We need to put the cc
after they view the clinic list and before they can sign up"). Her words are
the source; the bullets after each are how they map onto what exists.

**Supersedes:**
- hard rule 2's "never auto-expires an invitation" (an offer now expires after
  one hour; still nothing is ever auto-promoted);
- the locked term "Player Pool" (now "Waitlist");
- the onboarding card step (decision 0015 §5's order: the card now comes at
  sign-up, after the clinic list).

## Her email, verbatim

> 1. Let people view clinics before requiring a credit card
>
> Please move the credit card step until after someone can view the clinic
> list, but before they sign up. It stopped me from even looking. Someone new
> needs to see what they're signing up for before adding their card.
>
> 1. 105 registration
>
> Let's use "Waitlist" instead of "Player Pool."
>
> * During the first 24 hours of registration, members automatically confirm
>   up to the 30-player cap.
> * Nonmembers and members signing up after that window join the waitlist for
>   me to select manually.
> * In my admin view, please show the date and exact time each player joined
>   the waitlist. I need to see who signed up first while still choosing
>   players based on levels and court combinations.
> * Cancellations should never automatically move someone into a spot. I'll
>   choose who receives the next offer.
>
> 1. 105 spot offers through push notifications
>
> When I offer someone a spot, I want them to receive a push notification on
> their phone:
> "A spot is available for 105 on [day/date] at [time]! You have 1 hour to
> accept before this offer expires."
> Please include Accept and Decline buttons so they can respond directly from
> the notification without opening the app.
>
> * Accept: They become confirmed.
> * Decline: The offer closes, and I can select someone else.
> * No response before the deadline: The offer expires, and I can select
>   someone else.
>
> Once an offer expires, the Accept button must no longer work.
> Please send another push notification when the offer expires:
> "Your offer for 105 on [day/date] at [time] has expired. You are not
> confirmed to attend. No action needed."
> This part is especially important: they should know the offer expired and
> that they should not come, without having to open the app or do anything
> else.
> I also want immediate admin push notifications, such as:
>
> * "John Doe declined his offer for 105 on [day/date] at [time]."
> * "John Doe's offer for 105 on [day/date] at [time] expired."
>
> 1. Other adult clinics
>
> For the other adult clinics, members get the first 24 hours. Eligible
> players automatically confirm first-come, first-served up to the clinic cap.
> Once full, additional players join the waitlist.
> I'll manually choose replacements when someone cancels.
>
> 1. Approval for 2.5 players to attend Ladies or Men's 3.0+ clinics
>
> I'm going to name the men's clinic Men's 3.0+, so this approval process
> should apply to both Ladies 3.0+ and Men's 3.0+.
> For a 2.5 player who hasn't been approved, please show:
> "You're currently rated 2.5. You can request approval from Tara to attend
> Ladies 3.0+ clinics. Once approved, you can sign up without requesting
> again."
> Button: Request Approval for Ladies 3.0+
> Use the same wording for the men, with:
> Button: Request Approval for Men's 3.0+
> The request should come to me for approval. Requesting approval does not
> confirm them for a clinic.
> I also want to be able to go directly into someone's profile and approve
> them myself. Their actual rating should stay 2.5, but their profile should
> clearly show:
> "Approved to attend: Ladies 3.0+"
> or
> "Approved to attend: Men's 3.0+"
> Once approved, they can sign up normally for that clinic category without
> asking each time. That approval stays until I remove it, and they should be
> notified when approved.

## What already works, and what is new

| Her rule | Today |
|---|---|
| Card after the clinic list, before sign-up | **New** (client): the onboarding card step goes; Register and Accept open the card sheet when no card is saved. The server already refuses both without a card (`card_required`) |
| "Waitlist" | **Built 2026-10-30** after her text that day (*"Players are still seeing player pool. That needs to be waitlist"*): every label on the phone, the members' site and the laptop, and the two notification sentences the server writes (`20261030000002`). The database keeps `pool` as the stored status |
| 105: members first 24 h, auto-confirm to the cap; everyone else to the waitlist | **Already the rule for every clinic** (`register_for_clinic`): the cap is the clinic's capacity, 30 when she sets 30 |
| Exact date and time each person joined the waitlist | **New** on her rosters (phone and laptop); the timestamp exists (`registrations.registered_at`, checked on hosted 2026-10-19) |
| Cancellations never auto-move anyone | **Already** (hard rule 2) |
| 105 offer push, Accept and Decline on the notification | Accept and Decline on the push **already exist** (decision 0023); her words and the 1-hour deadline are **new** |
| Offer expires after 1 hour; Accept stops working; expiry push to the player; push to Tara on decline and on expiry | **New**: an `expires_at` on the offer, refused after it, and a once-a-minute server job that expires offers and sends both pushes |
| Other clinics: members 24 h, then first come first served to the cap, then waitlist | **New**: today everyone after the member window goes to the waitlist even with room. Applies to clinics that are not a 105 (`is_105`) |
| 2.5 approval for Ladies 3.0+ and Men's 3.0+ | **New**: an approval per player per category, a request Tara sees, approve on the profile, a push when approved, sign-up refused for a 2.5 without it |

## Open (questions 118 to 125)

The parts her email leaves open are numbered in `docs/questions-for-tara.md`
with the default that is built until she answers.
