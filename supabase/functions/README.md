# Edge functions

Deno functions deployed to the Supabase project. Decision 0009 (payments)
owns the three `stripe-*` functions; `review-submit` (2026-09-21) saves
Tara's review-page answers; `delete-account` (2026-09-21, decision 0013 §5)
removes the sign-in after `delete_my_account()` has scrubbed the personal
data; `push` (2026-09-23, decision 0008) delivers each notification row to
the recipient's phones through APNs, and is built and tested against a mock
while Apple's signing key does not exist yet; `admin-reset-link`
(2026-09-27, decision 0017) makes a one-time password-reset link Tara texts to
a member, with no email involved.

## Secrets (never in the repo, the app, or a log)

Set on the dashboard's Edge Function Secrets page
(https://supabase.com/dashboard/project/amnaxvznkadkgzdxzegw/functions/secrets).
`supabase secrets set NAME=value` does the same, but typing a secret into a
terminal leaves it in the shell history, so the page is preferred. Secrets
reach the functions immediately; no redeploy. Alex's click-by-click steps
are `docs/for-alex.md` §1:

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
| `stripe-setup-intent` | the iOS app, once per card | caller's JWT | refuses with 409 `card_consent_required` unless `card_consents` holds the caller's permission to the current words (decision 0015 §7), and 403 `account_deleted` for a deleted account; then creates or reuses the Stripe customer and returns a SetupIntent client secret + ephemeral key for PaymentSheet. A stored customer is checked first: one Stripe does not have (every sandbox customer after the live swap, or one deleted in the dashboard) is replaced, and its stale card summary cleared (2026-09-27) |
| `stripe-webhook` | Stripe | Stripe signature (`verify_jwt = false`) | records the card summary on `setup_intent.succeeded`, and ledger outcomes on payment / refund events, each with the event's `livemode` (20260927200001); on `payment_intent.payment_failed` it writes Stripe's sentence to `failure_reason` and its code to `failure_code` (`decline_code`, else `code`, 20260926000010). A payment event that arrives before `stripe-charge` has stored the PaymentIntent id is attached to the row named in the PaymentIntent's `metadata.fxe_payment_id`, never to a refund row or a row that has another PaymentIntent (2026-09-27; before, it matched nothing, answered 200, and the charge sat in processing for good) |
| `stripe-charge` | the admin surfaces after `admin_charge_registration` / `admin_refund_payment` | admin JWT; CORS for the admin site (`_shared/cors.ts`: hosted answered its preflight with 405 until 2026-09-27, so the web's Charge clinic could not reach it) | turns up to 25 `pending` ledger rows per call (`.limit(25)`) into one PaymentIntent (off-session, naming the saved card explicitly: the customer's default payment method, else their first card, because a PaymentIntent does not fall back to `invoice_settings`) or Refund each, with an idempotency key per row, storing Stripe's `livemode`; safe to call again for the rest. When a call throws (`_shared/stripe-errors.ts`, 2026-09-27): a decline, a request Stripe refused, or our own refusal (`no_card_on_file`, `account_deleted`) is `failed`; anything that may have reached Stripe (dropped connection, timeout, 5xx, 429, a refused key) goes back to `pending` and is repeated under the same key, which Stripe answers with the first result; an `idempotency_error`, or a retry more than 23 hours after the row was made, is held in processing with that reason for a person. Each call first sweeps rows left in processing without a Stripe id for over 5 minutes (a call that died) back to pending. A customer Stripe does not have fails the row as `no_card_on_file` and clears the stale card, so the app asks again; a deleted account is never charged |
| `review-submit` | `web/review.html?t=<token>`, Tara's review page | the token in the body or query, checked against `review_links` (`verify_jwt = false`: she has no account) | `POST {token, page_version, answers}` upserts one jsonb blob per (link, page version) into `review_responses` and returns `{saved_at}`; `GET ?token=&page_version=` returns `{answers, saved_at}` so she can continue on another device; unknown or revoked token is 404, answers over 200 KB or not an object is 400. Uses `_shared/supabase.ts`, not the Stripe module. No rate limiting |
| `push` | the database: trigger `push_on_notification` posts `{notification_id}` through pg_net on every insert into `notifications` (migration 20260923000001) | `X-Push-Secret` header equal to `PUSH_WEBHOOK_SECRET` (`verify_jwt = false`: the database has no JWT) | loads the row and the account's `devices`, signs an ES256 provider token (cached 50 minutes), `POST /3/device/<token>` per device with the row's `body` verbatim and the unread count as the badge. Writes `delivered_at` on any 200, else `delivery_error` (`no_device`, `apns_not_configured`, or Apple's reason). Deletes a token Apple answers 410 or `BadDeviceToken` for. A delivered row is skipped, so a retry never double-sends |
| `admin-reset-link` | the web admin, Players → Reset link | caller's JWT, and `is_admin()` asked as the caller; CORS for the admin site (`_shared/cors.ts`) | `POST {player_id}`: 409 for a deleted account, 403 `admin_target` for an admin account (a leaked link would be an admin session); `auth.admin.generateLink({type: "recovery"})` (sends no email), checks the token's sign-in is that account (`identity_mismatch`), records a row in `reset_links_issued`, then returns `RESET_PAGE_URL#token_hash=…&type=recovery` (the fragment reaches no server log). The page exchanges it with `verifyOtp`; it works once, within `mailer_otp_exp`. Harness: `tests/reset/run.sh` |
| `delete-account` | the iOS app, Delete my account | caller's JWT | calls `delete_my_account()` (blanks name, phone, email, level note and card summary; keeps registrations, payments and Tara's notes), then deletes the Stripe customer (`customers.del`: the saved card goes, past payments stay in Stripe) and clears its id, then soft-deletes the auth user through Supabase's admin API. A customer Stripe no longer has counts as deleted; any other Stripe failure answers 502 `stripe_delete_failed` before the sign-in is touched, so a retry finishes the job. An account with no profile row (`account_not_found`) has nothing to scrub and still loses its sign-in. Answers `{deleted, stripe: deleted/already_gone/none}`. Admins are refused by the RPC. Never writes the auth schema in SQL |

The database never talks to Stripe; the app never holds a key that can move
money; the only writer of ledger status is the webhook (plus `stripe-charge`
moving pending → processing, recording a synchronous decline, and returning a
row to pending when a call may have reached Stripe; plus the one-off
`stripe_cutover_to_live()` below).

## Switching Stripe from the sandbox to live money

Every Stripe customer and saved card made with the test key is invisible to
the live key ("No such customer ... exists in test mode"). Left alone, every
tester would still show `•••• 4242`, pass the card requirement, and fail at
the first real charge; and sandbox "income" would sit in the board report.
`public.stripe_cutover_to_live()` (migration 20260927200001) is the data half
of the swap. It is NOT run by the migration: until the swap the testers'
sandbox cards are the only cards there are. It runs once, as postgres (the
SQL editor) or service_role, and refuses a second run (`already_live`) and any
run after a live payment exists (`live_payments_exist`). In this order:

1. `update public.app_settings set value = 'false' where key = 'payments_enabled';`
   (no card sheet or card step can open while the keys change: Profile hides
   the card section and the card step does not appear while payments are off).
2. Swap `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY` and `STRIPE_WEBHOOK_SECRET`
   to the live values, with the webhook endpoint made in live mode.
3. `select * from public.stripe_cutover_to_live();` It answers
   `accounts_cleared, payments_canceled, payments_marked_test, live_since`:
   every account's Stripe customer and card summary cleared (the card step
   then asks everyone), every ledger row still pending or processing canceled
   (`live_cutover`), every row whose mode was never recorded marked test mode,
   and `app_settings.stripe_live_since` written, after which the Money tab's
   card list hides test rows. The board report never counts them either way.
4. `update public.app_settings set value = 'true' where key = 'payments_enabled';`

The functions also heal on their own if step 3 is late: a customer the live key
cannot find is treated as none by `stripe-setup-intent` (a new one) and by
`stripe-charge` (the row fails as `no_card_on_file`, the stale card is
cleared). `tests/stripe/run.sh` section 13 runs the cutover end to end;
`tests/sql/stripe_live_cutover.sql` pins it rule by rule.

## Called from a browser: CORS

The web admin (`fxe-tennis-admin.vercel.app`) calls `review-submit`,
`stripe-charge` and `admin-reset-link` from the browser, a different origin
from `<project>.supabase.co`, so the browser sends a preflight first. Hosted's
gateway does not answer it for a function: the function must, or the browser
refuses the call. The local gateway does answer it, so a function without CORS
passes every local test and fails in production. `_shared/cors.ts` is the one
place for it; `scripts/hosted-smoke.sh` sends the preflight to each of the
three on every PR. Functions called only by the iOS app, Stripe or the
database need none.

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
supabase functions deploy admin-reset-link
```

## Testing without a Stripe account

`tests/stripe/run.sh` drives the whole pipeline against
[stripe-mock](https://github.com/stripe/stripe-mock), Stripe's own mock server:
SetupIntent → signed webhook writes the card summary → Tara's charge goes
pending → processing → succeeded and marks the registration paid → refund
unmarks it → a decline lands as failed with the reason and Stripe's decline code → unsigned or
wrongly signed webhooks change nothing. Since 2026-09-27 also: livemode on
every row and test money kept out of the Paid flag and the board report; the
early webhook; the stuck-row sweep; a dropped connection retried as the same
row (it stops and restarts the mock container, `STRIPE_MOCK_CONTAINER`,
default `stripe-mock`; set it empty to skip when the mock is the Homebrew
binary); a customer Stripe does not have; a deleted account; `delete-account`
and Stripe; the live cutover end to end. Its last check runs
`tests/stripe/errors.test.ts` with Deno, pinning the error rule with the
Stripe SDK's own error objects (declines, timeouts, 5xx, idempotency errors:
none of which stripe-mock can produce). Same PASS/FAIL lines as the probes.
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
STRIPE_MOCK_CONTAINER= bash tests/stripe/run.sh     # no container to stop: the retry check is skipped
```

A customer that Stripe "does not have" is played by an id with a `/` in it:
the SDK encodes it into the URL path, and stripe-mock answers 404 to a path
it does not know, the same status Stripe gives for "No such customer". The
functions treat any 404 on the customer (or `resource_missing`) as gone.

`make-env.sh` invents the secret key each run (stripe-mock takes any
`sk_test_` plus letters and digits) so no key-shaped string is ever in the
repo: GitHub's push protection refused the first draft, which carried Stripe's
public example key, and that refusal was the right call. `STRIPE_API_HOST`
is honoured by `_shared/stripe.ts` only when set; hosted never sets it. What the
mock cannot prove: Stripe's real decisions (3-D Secure, declines, real ids).
In particular `stripe-charge`'s synchronous decline branch has never seen a
real `decline_code`: stripe-mock's errors carry neither `code` nor
`decline_code`, so the harness proves the webhook's code path, and
`tests/stripe/errors.test.ts` proves only how the SDK's own error objects are
read (2026-09-27), not what Stripe really sends. That needs the test keys and
a test card, the same script with `stripe listen --forward-to` for the
webhooks.


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
