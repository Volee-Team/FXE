# 0009: Stripe with a card on file; Apple takes nothing

**Date:** 2026-09-12 · **Status:** Active · **Supersedes:** the "Stripe in v1.1" half of 0003 (the "Zelle + a report for v1" half stays true until this ships)

## What Tara asked for

2026-09-12: *"I definitely need the payment structure. I think on the app. I've
had seven cancellations for a clinic that's about to start in an hour ... I just
wanna charge them. But I can't charge them because I feel too bad to Venmo
request."* And earlier the same week: *"Can we ... have this ready to go by
October 1? Need to figure out an easy way w payment structure and them (apple?)
not taking 15-30% tho."*

Charging a player who has not tapped anything means a card on file, agreed to
once at sign-up. That is the shape this record commits to.

## What we decided

1. **Stripe, direct.** Apple's 15–30% applies to in-app purchases of digital
   goods. A tennis clinic is a real-world service; App Store Review Guideline
   3.1.3(e) requires those to be paid *outside* in-app purchase. Apple takes
   nothing. Stripe's card fee is about 2.9% + 30¢ (roughly $1 on a $23 clinic).
   Zelle stays as the free fallback, marked paid by hand as today (Q35).
2. **Card on file, collected in the app** with Stripe's PaymentSheet and a
   SetupIntent. Card numbers never touch our app code, our database, or our
   logs; Stripe holds them and we hold a customer id and "Visa ···4242" for
   display.
3. **Every money event is a row** in `public.payments`: clinic fee, late
   cancel, no show, refund, with the Stripe ids, the amount, and a status that
   only the webhook or an admin RPC can change. Reconciliation is a query, and
   Tara's Money tab reads it.
4. **The policy is settings, not code.** Cutoff hours, whether the regular fee
   is charged at registration, whether late-cancel charges wait for Tara's tap:
   `app_settings` keys with defaults matching the questions we sent her
   (Q27–Q37 in `questions-for-tara.md`). Her answers change a value, not a
   migration. Nothing charges anyone until she has answered (hard rule 14).
5. **Admin RPCs decide, an edge function executes.** `admin_charge_registration`
   and `admin_refund_payment` insert `pending` rows after `require_admin()`;
   the `stripe-charge` edge function (service role, secret key in Supabase
   secrets) performs the Stripe call and the `stripe-webhook` function records
   the outcome. The database never talks to Stripe; the app never holds a key
   that can move money.

## Rejected

- **Apple Pay / in-app purchase.** Not required, and a real cut of a small fee.
- **Payment links only (no card on file).** Solves collection, not the thing
  she asked for: charging a late cancel without chasing anyone.
- **Storing cards ourselves.** Never. PCI scope and a breach that ends the club.
- **Charging from the web admin's browser with a secret key.** The key would be
  in a page anyone can view-source.

## How we will know it was wrong

- If players refuse to add a card at sign-up in numbers, Q32's default was
  wrong and pay-per-clinic links come back as the primary path.
- If declines on off-session charges days after a clinic exceed a handful a
  month, the fee should be captured at registration instead (Q33).

## Sequence

1. This record; schema, RLS, RPCs, settings, probes (today; needs no account).
2. Alex's Stripe test account: SetupIntent + PaymentSheet in the app, webhook,
   charge function, all against test cards.
3. Tara's answers → settings values, her sentence at card entry, decision 0010.
4. Tara's Stripe account: live keys into Supabase secrets, first real charge to
   Alex's card, then October 1.
