# Edge functions

Deno functions deployed to the Supabase project. Decision 0009 (payments)
owns the three `stripe-*` functions; nothing else lives here yet (push
delivery, decision 0008, will add `push` once Apple issues the key).

## Secrets (never in the repo, the app, or a log)

Set in the Supabase dashboard, Project Settings → Edge Functions → Secrets,
or with `supabase secrets set NAME=value`:

| Name | Who sets it | What it is |
|---|---|---|
| `STRIPE_SECRET_KEY` | Alex (test), Tara or Alex (live) | `sk_test_…` now, `sk_live_…` when Tara's account is ready |
| `STRIPE_WEBHOOK_SECRET` | Alex | `whsec_…` from the webhook endpoint Stripe creates for `…/functions/v1/stripe-webhook` |
| `STRIPE_PUBLISHABLE_KEY` | Alex | `pk_test_…` / `pk_live_…`; safe in a client, returned to the app by `stripe-setup-intent` |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
injected by the platform.

## The three functions

| Function | Called by | Auth | Does |
|---|---|---|---|
| `stripe-setup-intent` | the iOS app, once per card | caller's JWT | creates or reuses the Stripe customer, returns a SetupIntent client secret + ephemeral key for PaymentSheet |
| `stripe-webhook` | Stripe | Stripe signature (`verify_jwt = false`) | records the card summary on `setup_intent.succeeded`, and ledger outcomes on payment / refund events |
| `stripe-charge` | the admin surfaces after `admin_charge_registration` / `admin_refund_payment` | admin JWT | turns every `pending` ledger row into one PaymentIntent (off-session) or Refund, with an idempotency key per row |

The database never talks to Stripe; the app never holds a key that can move
money; the only writer of ledger status is the webhook (plus `stripe-charge`
moving pending → processing and recording a synchronous decline).

## Run locally

```bash
supabase start
supabase functions serve            # serves all three on :54321/functions/v1/
stripe listen --forward-to localhost:54321/functions/v1/stripe-webhook
```

`stripe listen` prints the `whsec_…` for local use. With `STRIPE_SECRET_KEY`
unset the functions load and refuse unauthenticated calls but every Stripe
call fails, which is the intended state until the test keys exist.

## Deploy

```bash
supabase functions deploy stripe-setup-intent
supabase functions deploy stripe-webhook --no-verify-jwt
supabase functions deploy stripe-charge
```
