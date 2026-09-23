# Edge functions

Deno functions deployed to the Supabase project. Decision 0009 (payments)
owns the three `stripe-*` functions; `review-submit` (2026-09-21) saves
Tara's review-page answers; `delete-account` (2026-09-21, decision 0013 §5)
removes the sign-in after `delete_my_account()` has scrubbed the personal
data; `push` (2026-09-23, decision 0008) delivers each notification row to
the recipient's phones through APNs, and is built and tested against a mock
while Apple's signing key does not exist yet.

## Secrets (never in the repo, the app, or a log)

Set in the Supabase dashboard, Project Settings → Edge Functions → Secrets,
or with `supabase secrets set NAME=value`:

| Name | Who sets it | What it is |
|---|---|---|
| `STRIPE_SECRET_KEY` | Alex (test), Tara or Alex (live) | `sk_test_…` now, `sk_live_…` when Tara's account is ready |
| `STRIPE_WEBHOOK_SECRET` | Alex | `whsec_…` from the webhook endpoint Stripe creates for `…/functions/v1/stripe-webhook` |
| `STRIPE_PUBLISHABLE_KEY` | Alex | `pk_test_…` / `pk_live_…`; safe in a client, returned to the app by `stripe-setup-intent` |
| `APNS_KEY_ID` | Alex | the 10-character Key ID Apple shows next to the APNs key |
| `APNS_TEAM_ID` | Alex | FXE Tennis, LLC's 10-character Team ID (Membership page) |
| `APNS_PRIVATE_KEY` | Alex | the whole contents of `AuthKey_<KEYID>.p8`, PEM markers included. Apple lets you download it once |
| `APNS_TOPIC` | Alex | the app's bundle id (`com.fxetennis.app` until the LLC's final id) |
| `APNS_HOST` | optional | unset means `https://api.push.apple.com` (TestFlight and App Store builds). `https://api.sandbox.push.apple.com` only for a build run from Xcode |
| `PUSH_WEBHOOK_SECRET` | Alex | any long random string (`openssl rand -hex 32`); the SAME value goes into the vault as `push_webhook_secret` |

`SUPABASE_URL`, `SUPABASE_ANON_KEY` and `SUPABASE_SERVICE_ROLE_KEY` are
injected by the platform.

## The functions

| Function | Called by | Auth | Does |
|---|---|---|---|
| `stripe-setup-intent` | the iOS app, once per card | caller's JWT | creates or reuses the Stripe customer, returns a SetupIntent client secret + ephemeral key for PaymentSheet |
| `stripe-webhook` | Stripe | Stripe signature (`verify_jwt = false`) | records the card summary on `setup_intent.succeeded`, and ledger outcomes on payment / refund events |
| `stripe-charge` | the admin surfaces after `admin_charge_registration` / `admin_refund_payment` | admin JWT | turns up to 25 `pending` ledger rows per call (`.limit(25)`) into one PaymentIntent (off-session) or Refund each, with an idempotency key per row; safe to call again for the rest |
| `review-submit` | `web/review.html?t=<token>`, Tara's review page | the token in the body or query, checked against `review_links` (`verify_jwt = false`: she has no account) | `POST {token, page_version, answers}` upserts one jsonb blob per (link, page version) into `review_responses` and returns `{saved_at}`; `GET ?token=&page_version=` returns `{answers, saved_at}` so she can continue on another device; unknown or revoked token is 404, answers over 200 KB or not an object is 400. Uses `_shared/supabase.ts`, not the Stripe module. No rate limiting |
| `push` | the database: trigger `push_on_notification` posts `{notification_id}` through pg_net on every insert into `notifications` (migration 20260923000001) | `X-Push-Secret` header equal to `PUSH_WEBHOOK_SECRET` (`verify_jwt = false`: the database has no JWT) | loads the row and the account's `devices`, signs an ES256 provider token (cached 50 minutes), `POST /3/device/<token>` per device with the row's `body` verbatim and the unread count as the badge. Writes `delivered_at` on any 200, else `delivery_error` (`no_device`, `apns_not_configured`, or Apple's reason). Deletes a token Apple answers 410 or `BadDeviceToken` for. A delivered row is skipped, so a retry never double-sends |
| `delete-account` | the iOS app, Delete my account | caller's JWT | calls `delete_my_account()` (blanks name, phone, email, level note and card summary; keeps registrations, payments and Tara's notes), then soft-deletes the auth user through Supabase's admin API. Admins are refused by the RPC. Never writes the auth schema in SQL |

The database never talks to Stripe; the app never holds a key that can move
money; the only writer of ledger status is the webhook (plus `stripe-charge`
moving pending → processing and recording a synchronous decline).

## Run locally

```bash
supabase start
supabase functions serve            # serves them all on :54321/functions/v1/
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
supabase functions deploy review-submit --no-verify-jwt
supabase functions deploy delete-account
supabase functions deploy push --no-verify-jwt
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


## Testing without Apple

`tests/push/run.sh` drives push delivery end to end against
`tests/push/mock-apns.ts`, a small Deno server that answers the way APNs
documents it does, keyed on the device token's prefix (`good…` 200, `gone…`
410 Unregistered, `bad…` 400 BadDeviceToken). It verifies every provider
token's ES256 signature against the key `make-env.sh` generated for that run,
so a wrongly signed JWT fails here instead of on the first real invitation.
Checks: the secret header, unknown rows, no device, one good device (headers,
verbatim body, badge), pruning of gone and bad tokens, idempotency, a player
unable to read the audit columns through PostgREST, the trigger doing nothing
without vault secrets, and, with them, the trigger delivering through pg_net
with nobody calling the function by hand. CI runs it on every PR ("Push
pipeline (mocked)").

```bash
bash tests/push/make-env.sh > /tmp/push.env
deno run --allow-net --allow-read --allow-write tests/push/mock-apns.ts /tmp/push.env /tmp/mock-apns.json &
supabase functions serve --env-file /tmp/push.env &
bash tests/push/run.sh /tmp/push.env /tmp/mock-apns.json
```

On a Mac the edge runtime reaches the mock at `host.docker.internal` (the
default); CI passes the docker network's gateway address instead. The key is
a throwaway P-256 key generated each run in the same PKCS#8 shape as Apple's
`.p8`; nothing key-shaped is committed. What the mock cannot prove: that Apple
accepts the real key, team and topic over HTTP/2, and that a real device
token reaches a real lock screen.

## What Alex does when the key arrives

Once FXE Tennis, LLC's developer account is active:

1. **Create the key.** developer.apple.com → Certificates, Identifiers &
   Profiles → Keys → +, tick Apple Push Notifications service (APNs), pick
   Sandbox & Production. Download `AuthKey_<KEYID>.p8` (Apple offers it
   once; keep it in the password manager, never the repo). Note the Key ID
   and the Team ID.
2. **Set the function's secrets:**
   ```bash
   supabase secrets set APNS_KEY_ID=<KEYID> APNS_TEAM_ID=<TEAMID> APNS_TOPIC=com.fxetennis.app
   supabase secrets set APNS_PRIVATE_KEY="$(cat AuthKey_<KEYID>.p8)"
   supabase secrets set PUSH_WEBHOOK_SECRET=$(openssl rand -hex 32)   # keep this value for step 4
   ```
3. **Deploy:** `supabase functions deploy push --no-verify-jwt`.
4. **Tell the database where to post**, once, in the hosted SQL editor:
   ```sql
   select vault.create_secret('https://amnaxvznkadkgzdxzegw.supabase.co/functions/v1/push', 'push_function_url');
   select vault.create_secret('<the PUSH_WEBHOOK_SECRET value from step 2>', 'push_webhook_secret');
   ```
   Until both exist the trigger does nothing, which is why the migration is
   safe to push before any of this.
5. **One real invitation on a real phone**, Alex's (decision 0008: the first
   real push goes to Alex, not Tara): install the TestFlight build, allow
   notifications, have Tara's account invite Alex's player from a Player
   Pool, and watch the lock screen. Then
   `select delivered_at, delivery_error from notifications order by created_at desc limit 5;`
   in the SQL editor says whether Apple took it, and if not, why.
