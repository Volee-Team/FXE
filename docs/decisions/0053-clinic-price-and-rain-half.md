# 0053. Change a clinic's price any time, and charge half when it rains (2026-11-07)

**Status:** accepted by John, 2026-11-07 (*"build this"*); built in
`supabase/migrations/20261107000004_clinic_price_and_rain.sql` and the laptop
site. On Tara's phone from 1.0.3 (build 17): More > Change price and Charge
half (rain) / Back to full price, with the laptop's words, and the clinic's
price line under the date. One player's own price is decision 0054.

## Her words

Tara, by text, 2026-11-07, answering question 143 ("Next update" item 3):

> Nobody will be charged ahead of time, so if it were to rain halfway through
> the clinic, I would just be able to manually change the clinic rate. It might
> just be easiest if I have the option to change the clinic rate always, even
> though I hardly will ever do that unless it rains
>
> But yes, if I could have the option to charge half, then that means
> everybody would be charged half if it were to rain

## What we chose

What anyone is charged is their registration's `price_cents_charged`, a
snapshot taken at sign-up. Both of her asks reprice the registrations on the
clinic that are not marked Paid and hold no charge
(`registration_has_live_fee`): You're In!, Waitlist, Response Needed and a late
cancel's fee alike.

- **Change price** (`admin_set_clinic_prices`): the clinic's member and
  non-member prices, any time, and every such registration with them.
- **Charge half (rain)** (`admin_set_rain_half`): a switch on the clinic.
  While on, everyone You're In! who came owes half of the clinic's price,
  rounded to the cent ($23 is $11.50). **A no-show and a late cancel still pay
  the full fee**: her answer to question 103 (2026-10-04, via Alex), when she
  first asked for a half clinic. A trigger keeps each row right while it is on
  (marked a no-show: full; unmarked: half; added after: half). Off puts the
  full price back; a price change while it is on stays half. The clinic's own
  prices do not change, so turning it off needs nothing remembered. Her
  answer to question 103 stands over 143's "everybody would be charged half":
  143 asked for the half, 103 had already said who it is for.
- **A clinic's length cannot change while it is rained out** (`rain_half_on`):
  a new length resets the prices to her table without repricing anyone
  (question 113, still open), which would leave one clinic on two rates.
- A declined charge is not a live fee, so it is repriced too, and a charge
  tried again takes the new amount.
- **Never** a registration marked Paid or already charged: money taken is a
  refund, not a reprice. **Nobody is told**; she did not ask for a message.

## Rejected

- **Halving the clinic's prices**: undoing it would need the full prices
  remembered somewhere, and a rate change after would be ambiguous.
- **Repricing at charge time** (multiplying in `money_rows`): every report and
  the charge would each have to apply it; one stored amount is what all of
  them already read.

## Tests

`tests/sql/clinic_price_and_rain.sql`, from the rule; `web/tests/admin.spec.mjs`.
