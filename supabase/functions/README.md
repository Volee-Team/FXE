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
| `stripe-charge` | the admin surfaces after `admin_charge_registration` / `admin_refund_payment` | admin JWT | turns up to 25 `pending` ledger rows per call (`.limit(25)`) into one PaymentIntent (off-session) or Refund each, with an idempotency key per row; safe to call again for the rest |

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

## Testing without a Stripe account

`tests/stripe/run.sh` drives the whole pipeline against
[stripe-mock](https://github.com/stripe/stripe-mock), Stripe's own mock server:
SetupIntent → signed webhook writes the card summary → Tara's charge goes
pending → processing → succeeded and marks the registration paid → refund
unmarks it → a decline lands as failed with the reason → unsigned or
wrongly signed webhooks change nothing. Same PASS/FAIL lines as the probes.
CI runs it on every PR ("Stripe pipeline (mocked)").

```bash
docker run -d --name stripe-mock --network supabase_network_FXE-Tennis stripe/stripe-mock
bash tests/stripe/make-env.sh > /tmp/mock.env
supabase functions serve --env-file /tmp/mock.env   # another shell
bash tests/stripe/run.sh
```

On a Mac where the image will not pull (Docker Hub hung for an hour on
2026-09-12), run the binary on the host instead and point the functions at
`host.docker.internal`:

```bash
brew install stripe/stripe-mock/stripe-mock && stripe-mock -http-port 12111 &
bash tests/stripe/make-env.sh host.docker.internal > /tmp/mock.env
supabase functions serve --env-file /tmp/mock.env
bash tests/stripe/run.sh
```

`make-env.sh` invents the secret key each run (stripe-mock takes any
`sk_test_` plus letters and digits) so no key-shaped string is ever in the
repo: GitHub's push protection refused the first draft, which carried Stripe's
public example key, and that refusal was the right call. `STRIPE_API_HOST`
is honoured by `_shared/stripe.ts` only when set; hosted never sets it. What the
mock cannot prove: Stripe's real decisions (3-D Secure, declines, real ids).
That needs the test keys and a test card, the same script with
`stripe listen --forward-to` for the webhooks.

