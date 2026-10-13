# Stripe end to end, in test mode, on the real app

Tara's ask (2026-09-26, "FXE Final Updates" p.3 1a): *"We need to test the
flow from clinic registration, to payment, confirming the payment in Tara's
account and need to test a refund."* This is that test. It runs against
**Stripe's real test mode** (the sandbox), so no real money moves.

Since 2026-10-12 this run is the rehearsal before the live switch (checklist
A13, which closes A2). The model runs it on a local copy of the app (the
local database, the simulator and the local admin site) with a **restricted
sandbox key** carrying exactly the live key's permissions. Payments are
switched on in that local database only: never on hosted while the keys are
sandbox, because a real card is declined in test mode (checklist A9). After
the live switch, one real charge and refund on Alex's own card on hosted
closes it (checklist A10).

What is already proven without Stripe: `tests/stripe/run.sh`, against
Stripe's own mock server on every PR. What only this run proves: Stripe's
real answers (real ids, real declines, 3-D Secure, the webhook signature
from Stripe's servers), and that the restricted key is missing no
permission (a missing one does not show as an error: decision 0019 retries
it as pending).

## Before

1. Alex has made the sandbox restricted key and saved it to the file the
   model names (`docs/for-alex.md`, the rehearsal section, checklist A13).
   Never pasted into the chat.
2. The model has the Stripe CLI forwarding sandbox webhooks to the local
   functions (`stripe listen --forward-to`, `supabase/functions/README.md`)
   and has switched payments on in the local database (`payments_enabled`
   true; `card_required` is already true, so from that moment nobody
   registers without a card, admins excepted).

## The run (about 20 minutes)

| # | Who | Does | Expect |
|---|---|---|---|
| 1 | Player, phone | Profile → Payment method → tick the permission box → Add a card: `4242 4242 4242 4242`, any future date, any CVC, any ZIP | Profile shows `•••• 4242` |
| 2 | Stripe dashboard (sandbox) | Customers | The player's email with a Visa ending 4242 |
| 3 | Tara, admin site | Create a clinic that ends within the hour, and add the player with Add player if registration is not open | The player under You're In! |
| 4 | Tara, admin site or phone, after the end time | The green **Charge $N** button on the player's row (decision 0037: one tap per person; there is no Charge clinic button) | The row reads Processing, then Charged on the phone (Paid on the laptop). Money tab: a row for the player, Clinic fee, Paid within a few seconds. The Money numbers and the board report do not move: a test-mode charge is not money (20260927200001) |
| 5 | Stripe dashboard | Payments | One succeeded payment for $18 (member, 60 min) or the matching price |
| 6 | Tara, admin site | Money tab → Refund on that row, then Really refund? (two clicks) | A refund row, Paid. The clinic row never showed paid: in test mode no fee marks anyone paid, and no refund unmarks them (20260927200001) |
| 7 | Stripe dashboard | Payments → that payment | Refunded |
| 8 | Player, phone | Replace the card with `4000 0000 0000 0341` (Stripe's "attaches fine, every charge declines" card) and repeat 3 and 4 | Money tab: Failed, "Declined:" with the reason, the player's name in bold. The roster row shows Declined beside a Charge button again |
| 9 | Player, phone | Replace the card with `4000 0025 0000 3155` (Stripe's 3-D Secure card) and repeat 3 and 4 | Saving the card opens the bank's 3-D Secure page and returns to the app; Profile shows `•••• 3155`. Stripe documents that a card set up this way is charged later without asking again, so row 4's outcome repeats |

Record the outcome of each row in the CLAUDE.md changelog entry for the day,
with the Stripe payment id of row 5 (an id, not a card number).

On hosted, the switch to live money (`stripe_cutover_to_live()`, procedure
in `supabase/functions/README.md`) clears every sandbox card and hides
sandbox rows from the Money tab's card list; the board report never counts
them.

## When the money reaches Tara's bank (her question 1c)

Test mode never pays out. In live mode, Stripe's standard schedule for a US
account pays out automatically every business day, each payment arriving
about **two business days** after the charge. The **first** payout on a new
account takes longer, typically 7 to 14 days, while Stripe reviews it. The
exact schedule for her account is on stripe.com → Settings → Payouts, where
checklist A14 sets it to Daily; the model has not seen her account, so that
page is the answer of record.

What Stripe keeps: 2.9% + 30¢ per successful card charge (US cards). On an
$18 clinic that is 82¢, so $17.18 reaches her. Refunds do not return Stripe's
fee.
