# 0021: Payouts on the Money tab, and chargebacks recorded from Stripe

**Date:** 2026-09-28 · **Status:** Active, one default pending question 89 · **Source:** Alex, 2026-09-27 (the admin should let Tara run everything, payouts included, without opening Stripe; checklist H7), branch `payouts-disputes`

## What we chose

1. **Payouts come from Stripe, read at the moment, never stored.** A new edge
   function, `stripe-payouts`, answers an admin with the balance (available,
   pending), the next deposit and the last ten. It asks `is_admin()` as the
   caller, writes nothing, and passes on four fields per payout (amount,
   currency, bank day, status): no bank account, description or id, and never
   Stripe's error text, which can quote the end of the key. The bank day is
   sent as a plain date, because Stripe's midnight-UTC timestamp reads as the
   evening before in a New York browser. The Money tab asks when it opens, not
   on every reload, and says "Test mode" while the keys are sandbox.
2. **A chargeback (Stripe calls it a dispute) is recorded on the fee it is
   about**, from the three `charge.dispute.*` webhook events, matched by the
   PaymentIntent (or its metadata, for a held charge Tara marked "Went
   through"). Eight columns on `payments`, written only by the service role
   through `stripe_record_dispute`; no client can read them. Stripe sends
   events late, twice and out of order, so the guards sit inside the UPDATE:
   an older event changes nothing, a replay writes the same values, a decided
   dispute is never reopened, and a second dispute on the same payment is
   refused and logged (Stripe's own email still reaches the account).
3. **Open disputes are Tara's to answer, in Stripe.** Action Needed shows
   "{First Last} disputed a charge" with the clinic, the amount and the
   respond-by date, on the web and on the phone, with the Stripe link. The app
   does not answer disputes.
4. **The money rule.** A lost dispute is subtracted from Charged (Money tab)
   and Collected by card (board report) by **what Stripe actually withdrew**,
   read from the dispute's balance transactions, not by the disputed amount,
   and in the clinic's month like a refund. Stripe withdraws nothing more for a
   charge already refunded, so a refund and a lost dispute never both come off
   the same money. Open disputes, won ones and closed inquiries subtract
   nothing. Stripe's dispute fee is not counted (the reports are gross).
5. **A lost dispute does not make the player owe again, and does not touch
   Paid.** The fee stays "charged" to decision 0018's one definition, so Charge
   clinic never charges that player a second time; re-charging a card after the
   bank sided with the cardholder is Tara's call, not the app's. Whether Paid
   should clear is question 89; the default leaves it.

## Also fixed on the way

The web admin's Action Needed named a parameter `money`, which hid the
`money()` formatter: the first open card decline would have thrown and left
This week blank. Payments were off on hosted, so no decline existed yet. A
browser test now opens the page with a decline in Action Needed.

## Rejected

- **Storing payouts in our database.** They are Stripe's record; a copy goes
  stale and adds a table the club does not need.
- **Subtracting the disputed amount.** Double-counts a charge that was also
  refunded (the auditor's finding; `money_reports.sql` pins the hand-worked
  numbers, 5800 not 8200).
- **A separate disputes table keyed by dispute id.** Only needed if Stripe can
  open two disputes on one charge, which could not be confirmed; the refusal
  and the log line make that case visible if it happens.

## How we would know this was wrong

Tara sees a deposit in her bank that the Payouts card did not show, a
dispute email from Stripe with no Action Needed row, or a board report whose
Collected by card disagrees with Stripe's own payout total for the month.
