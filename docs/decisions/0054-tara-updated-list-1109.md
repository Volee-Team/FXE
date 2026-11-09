# 0054. Tara's updated list: same-day declines, the 105 rounds, one player's price, warned at the cap (2026-11-09)

**Status:** accepted by John, 2026-11-09 (he relayed her updated list and her
answers, and asked for everything in 1.0.3, build 17); built in
`supabase/migrations/20261109000001_tara_items_0054.sql`, the laptop site and
Tara's phone (1.0.3, build 17). Items 1 to 6 of the same list are decisions
0051 to 0053.

## Her words

Her "Next update (notes taken 11/6/26)" list, updated, relayed by John on
2026-11-09:

> 7. If someone is invited to same day clinic and denies it, don't put them
>    back on waitlist. Their name can be removed
> 8. Can there be a place in every 105 on the app for me to make 2-3 rounds of
>    105. Like a message board or something like
>
>    Round 1
>    Coirt 1: player a,bc / player d,e,f
>    Coirt 2
>    3
>    4
>    5
>
>    Round 2
>    Etc
>
>    Round 3
>    Etc
> 9. I should be able to take someone out of clinic. Like cancel them from my
>    phone. I can from pc
> 10. I'd like the option to change the pricing if possible. I'm gonna need
>    this for the junior, so might be a good idea just to implement it in the
>    adults as well. For instance, some people sign up for an hour and a half
>    clinic and can only stay for an hour, so they ask to be charged for an
>    hour. I hate this, but I'm sure it's gonna happen
> 11. Making sure the app will prevent me from adding people or accepting
>    people if we've reached our cap

Her answers the same day, by text, to the questions John sent:

> Warn me!
> Just me and pros for rounds
> Hmmm pick from roster great
> I would type amount: for example 1.5 hour clinic is $28 for non. If we get
> 45 mins I would charge $14

Item 9 was already on her phone (the Court menu's "Remove from clinic", since
2026-09-10); John sent her the steps. Nothing was built for it.

## What we chose

7. **A decline on the clinic's own day ends it.** `respond_to_invitation`: a
   decline whose clinic starts on today's New York date is canceled, not put
   back on the Waitlist, with `canceled_by` empty so her history line does not
   count it as the player canceling (the same as a decline of an invitation to
   someone who never asked, decision 0051). Her notice reads "{name} declined
   {clinic}." without "and is back on the Waitlist". "Same day clinic" read as
   the clinic's calendar day in New York: on clinic day her Waitlist tap is an
   invitation (decision 0047), which is when this happens.
11. **"Warn me!": Tara is warned, never stopped; a player's Accept is
    stopped.** Her question ("Are you sure you want to add Jane Doe? Your
    clinic is full (12/12).") now also comes before Add guest on the phone;
    the laptop already asked before Add player and Add guest, and both count
    guests (`clinic_taken`). The phone has no Add player, so there is nothing
    to warn there. The server half: a player's Accept into a clinic whose You're
    In! plus guests is at capacity is refused with `clinic_full`, **unless the
    clinic was already full when the invitation went out**
    (`registrations.invited_when_full`, stamped by a trigger on every path
    into Response Needed): then Tara saw her warning and chose to go over. The
    invitation stays open, so the player can accept once a spot frees, or
    decline (hard rule 2: nothing expires). An Accept takes the clinic FOR
    UPDATE, so two Accepts cannot both take the last spot
    (`tests/sql/accept_full_race.sh`, red with the old FOR SHARE: 3 in a
    clinic of 2). Invitations already open when this shipped and whose clinic
    was full then are stamped as sent past the cap, so they keep the Accept
    they were sent with.
    **What the 1.0.0 to 1.0.3 apps show:** "That clinic is full now." on the
    clinic page and as the notice after Accept on the lock screen (their
    `clinic_full` line since 1.0.0; the members' site says the same). No
    misleading text, so no app had to ship first (decision 0048's lesson).
    One bit of capacity reaches that player (the clinic is full right now),
    the same bit a full clinic's Register already tells them by landing them
    on the Waitlist.
8. **The 105 rounds.** `clinic_round_spots`: up to 3 rounds, courts 1 to 5,
   two sides of up to 3 (her example), each spot one of the clinic's You're
   In! registrations or live guests ("pick from roster"). 105s only (`is_105`:
   the name or the category). Tara writes (`admin_set_round_court`, one court
   of one round at a time; someone picked on another court of the same round
   moves); Tara and a pro read (`clinic_rounds`, a pro only for a clinic in
   their week); players and signed-out callers read nothing (closed table, no
   grant: like a court, a round says who plays with whom, hard rule 1).
   Someone who leaves You're In! after being placed keeps the spot, marked
   gone: the phone and laptop say "{name} left the clinic." and open the spot,
   and the summary reads "(left)", so she sees the gap instead of a silent
   hole. A layout she rewrites, not history, so a court is replaced whole
   (hard rule 4 is for business rows; nothing is owed or told from a round).
   - Phone: a Rounds button on her 105 clinic page (a sheet with Round 1 to 3
     and six pickers per court) and the rounds as text under it; a read-only
     Rounds button on a 105 in the pro's week.
   - Laptop: a Rounds button on a 105's card and the same pickers in a dialog.
   - **Open for Tara:** whether pros may edit rounds. She said "Just me and
     pros for rounds", and on 11-06 that pros only "assign courts and see who
     is in the clinic", so they read and do not write.
10. **One player's price, typed.** `admin_set_registration_price`: Tara types
    the amount ($0.01 to $1,000) for one registration that can still owe
    (You're In!, Waitlist, Response Needed, or a late cancel), never one
    marked Paid or holding a live fee (refund first). `price_set_by_admin`
    keeps it through a clinic price change and the rain half (`reprice_clinic`
    and `keep_rain_price` skip it); "Use the clinic's price" puts the
    clinic's back (half while it rains). A no-show keeps her amount too: she
    set it for that person. Her roster says "Price set: $14"; the Money tab,
    Charge and the reports already read `price_cents_charged`. Nobody is
    told. Phone: Set price in the Court menu before the clinic and beside
    Charge after it; laptop: Set price on the You're In! row.
    - The juniors' pricing (her "I'm gonna need this for the junior") is the
      juniors' own design; this is the per-person override she asked for.

Also in 1.0.3, build 17, so Tara has everything on her phone: guests
(decision 0052) and the clinic's price and rain half (decision 0053).

## Rejected

- **Refusing Tara at the cap.** Her answer was "Warn me!"; capacity has never
  stopped her (place_player, her answer to question 4).
- **Refusing every Accept at the cap, including invitations she sent past
  it:** she would warn, choose to go over, and then watch the player be told
  "That clinic is full now."
- **Rounds as a free-text note:** "pick from roster great"; free text would
  also miss someone leaving.
- **Typing a length instead of an amount for one player:** she answered
  "I would type amount".

## Tests

`tests/sql/tara_items_0054.sql` (50 rows, from her words; item 7's three
rows were red on the old function: "pool false", and "... and is back on
the Waitlist."), `tests/sql/accept_full_race.sh` (red with FOR SHARE),
`pro_role.sql` and `registration_note.sql` naming the new functions,
`ClinicExtrasTests` (unit), `testAdminC2_GuestRoundsAndPriceOnA105` (UI), and
the laptop's "one player's price and the 105 rounds" tests.
