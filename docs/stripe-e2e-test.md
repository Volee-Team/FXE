# Stripe end to end, in test mode, on the real app

Tara's ask (2026-09-26, "FXE Final Updates" p.3 1a): *"We need to test the
flow from clinic registration, to payment, confirming the payment in Tara's
account and need to test a refund."* This is that test. It runs against
hosted with **Stripe test mode**, so no real money moves, and with **Alex's
own account**, never a made-up one (no fixtures in hosted, CLAUDE.md).

What is already proven without Stripe: `tests/stripe/run.sh`, 34 checks
against Stripe's own mock server on every PR. What only this run proves:
Stripe's real answers (real ids, real declines, 3-D Secure, the webhook
signature from Stripe's servers).

## Before

1. Alex has done `docs/for-alex.md` item 1 (three secrets on hosted).
2. The model has checked the three names with `supabase secrets list` and
   pushed the migration that switches payments on (`payments_enabled` true;
   `card_required` is already true, so from that moment nobody registers
   without a card, admins excepted).
3. John has uploaded a TestFlight build from `main` that includes the card
   step at sign-up, or Alex runs the Release build from Xcode on his phone.

## The run (about 20 minutes, Alex and Tara, or Alex alone with the admin site)

| # | Who | Does | Expect |
|---|---|---|---|
| 1 | Alex, phone | Sign in with your own account. Profile → Payment method → tick the permission box → Add a card: `4242 4242 4242 4242`, any future date, any CVC, any ZIP | Profile shows `•••• 4242` |
| 2 | Alex, stripe.com (Test mode) | Customers | Your email with a Visa ending 4242 |
| 3 | Tara, admin site | Create a clinic that ends within the hour (or use "Test Clinic"), and add Alex with Add player if registration is not open | Alex under You're In! |
| 4 | Tara, admin site, after the end time | Charge clinic on that clinic's card | Money tab: a row for Alex, Clinic fee, Succeeded within a few seconds |
| 5 | Alex, stripe.com | Payments | One succeeded payment for $18 (member, 60 min) or the matching price |
| 6 | Tara, admin site | Money tab → Refund on that row | Row becomes a refund, Succeeded; the clinic row shows unpaid again |
| 7 | Alex, stripe.com | Payments → that payment | Refunded |
| 8 | Alex, phone | Replace the card with `4000 0000 0000 0341` (Stripe's "attaches fine, every charge declines" card) and repeat 3 and 4 | Money tab: Failed, with the reason and Alex's name |

Record the outcome of each row in the CLAUDE.md changelog entry for the day,
with the Stripe payment id of row 5 (an id, not a card number).

## When the money reaches Tara's bank (her question 1c)

Test mode never pays out. In live mode, Stripe's standard schedule for a US
account pays out automatically every business day, each payment arriving
about **two business days** after the charge. The **first** payout on a new
account takes longer, typically 7 to 14 days, while Stripe reviews it. The
exact schedule for her account is on stripe.com → Settings → Payouts once it
is activated; the model has not seen her account, so that page is the answer
of record.

What Stripe keeps: 2.9% + 30¢ per successful card charge (US cards). On an
$18 clinic that is 82¢, so $17.18 reaches her. Refunds do not return Stripe's
fee.
