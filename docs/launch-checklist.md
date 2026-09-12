# Launch checklist: everything between today and a real member using the app

Living file. Written 2026-09-12 after Alex asked "what else to get it 99% to
prod, and make sure you are not forgetting any kind of testing". One row per
thing. Owner in brackets. When a row is done, move it to the bottom with the
date. Numbers here are re-derived, not copied: the commands are in
`docs/dev-practices-for-john.md` and `tests/run-probes.sh` prints its own.

Owners: **[me]** built by the model, **[Alex]** needs his hands or his accounts,
**[Tara]** her answer or her details, **[Apple]** waiting on Apple,
**[Stripe]** waiting on Stripe.

---

## A. Payments (target October 1)

| | Item | Owner | Status 2026-09-12 |
|---|---|---|---|
| 1 | Stripe test-mode account and the three keys in Supabase secrets (steps in section B) | [Alex] | not started |
| 2 | Run `tests/stripe/run.sh` against real Stripe with test cards, `stripe listen` for webhooks, fix what the mock could not show | [me] | blocked on 1 |
| 3 | Tara's answers to questions 28–42 (`docs/for-tara-2026-09-12.md`), recorded as decision 0011 | [Tara] | sent 2026-09-12 |
| 4 | Flip `payments_enabled`, set the fee policy settings, add her two sentences (card entry, inside 4 hours) | [me] | blocked on 3 |
| 5 | Refund on her clinic cancel (question 31) and no-show charge (question 29), if she says yes | [me] | blocked on 3 |
| 6 | Player-side payment history and receipts on Profile (Stripe sends email receipts if we pass `receipt_email`; decide whether to) | [me] | policy-independent, not built |
| 7 | Live-mode activation: business details, bank account, SSN or EIN, on stripe.com | [Tara] | not started; the only step nobody else can do |
| 8 | Stripe webhook endpoint for hosted (`https://amnaxvznkadkgzdxzegw.supabase.co/functions/v1/stripe-webhook`, five events, section B) | [Alex] | with 1 |

## B. Stripe, exact steps for Alex

Test mode needs no bank details; live mode does and is Tara's.

1. **Create the account.** stripe.com → Sign up with your email. Business name "FXE Tennis" is fine for now; it can change. Skip "activate your account" (that is live mode).
2. **Stay in test mode.** The toggle top-right of the dashboard. Everything below is test mode; test keys start with `sk_test_` and `pk_test_`.
3. **Copy the two API keys.** Developers → API keys: *Publishable key* and *Secret key* (click Reveal). Do not paste either into chat, the repo, or a text message.
4. **Set them as Edge Function secrets.** Supabase dashboard → project `fxe-tennis` → Edge Functions → Secrets → Add: `STRIPE_SECRET_KEY` = the secret key, `STRIPE_PUBLISHABLE_KEY` = the publishable key. (Alternative from your terminal, which never shows the value in the repo: `supabase secrets set STRIPE_SECRET_KEY=... STRIPE_PUBLISHABLE_KEY=...` from the repo root.)
5. **Create the webhook.** Stripe → Developers → Webhooks → Add endpoint. URL: `https://amnaxvznkadkgzdxzegw.supabase.co/functions/v1/stripe-webhook`. Events: `setup_intent.succeeded`, `payment_intent.succeeded`, `payment_intent.payment_failed`, `refund.updated`, `charge.refunded`. Save, then Reveal the *Signing secret* (`whsec_...`).
6. **Set it too.** Same Secrets page: `STRIPE_WEBHOOK_SECRET` = the signing secret.
7. **Tell me it is done.** I do not need the values. I will hit the hosted function with a test card (`4242 4242 4242 4242`, any future date, any CVC) and read the ledger.
8. **Optional, for local end-to-end:** `brew install stripe/stripe-cli/stripe`, `stripe login`, then `stripe listen --forward-to http://127.0.0.1:54321/functions/v1/stripe-webhook`. It prints a local `whsec_` which goes in a local env file only.

What Stripe takes: 2.9% + 30¢ per card charge. Apple takes nothing (decision 0009). Payouts to Tara's bank need live mode (row A7).

## C. App Store and Apple

| | Item | Owner | Status |
|---|---|---|---|
| 1 | Apple Developer Program enrollment as FXE Tennis, LLC | [Tara]/[Apple] | in review (docs/whats-next.md) |
| 2 | Bundle id (replaces `com.fxetennis.app` placeholder), Team ID, App Store Connect record, APNs key | [Alex] | blocked on 1 |
| 3 | Push delivery: the `push` edge function on the notifications webhook, audit columns (decision 0008) | [me] | blocked on the APNs key |
| 4 | **Privacy manifest** (`PrivacyInfo.xcprivacy`): Apple rejects builds that use required-reason APIs without it | [me] | **done 2026-09-12** (PR #37) |
| 5 | **Account deletion in the app**: App Store guideline 5.1.1(v) requires it for any app with account creation. What it deletes is a Tara question (a player's history and ledger rows vs. their name and contact), so: question for Tara, then build | [Tara] then [me] | not built |
| 6 | Privacy policy at a URL, terms, waiver wording (Tara said Volee's privacy policy can be reused, decision 16) | [Alex]/[Tara] | needs a place to host it (fersc.com?) |
| 7 | App Store listing: name, subtitle, description (Tara's words), screenshots on the required sizes, age rating, support URL, review notes with a test account | [Alex]+[me] | not started |
| 8 | TestFlight internal build to Tara's phone, then external testers (external needs the privacy URL) | [Alex] | blocked on 1 |
| 9 | Real-device pass: the two simulator flakes (Profile tab first tap, sign-in timing) checked on an iPhone | [Alex]/[me] | blocked on 8 |

## D. Backend and operations

| | Item | Owner | Status |
|---|---|---|---|
| 1 | **Auth email delivery.** Hosted uses Supabase's built-in email, which is rate-limited to a handful per hour and lands in spam. Password resets and any sign-up confirmation need custom SMTP (Resend or Postmark, free tiers cover a club) with DNS records on the club's domain | [Alex] | not done; blocks a real password reset |
| 2 | Password reset redirect URL allow-listed in the hosted dashboard | [Alex] | done 2026-09-01 per whats-next; re-verify with one real reset |
| 3 | Supabase plan: free tier pauses after 7 idle days and has no point-in-time recovery. Nightly `pg_dump` exists and the keep-warm job runs. Pro ($25/mo) removes both risks; decide before members are on it | [Alex] | decide |
| 4 | **Restore drill**: a backup nobody has restored is not a backup | [me] | **done 2026-09-12**: the 11:22 UTC artifact (26 KB) restored into a scratch `supabase/postgres:17.6.1.155` container with one benign error (`schema public already exists`); 15 tables, 51 functions, 10 views, `auth.users` present (Tara's login survives), 1 account, 1 clinic, 1 template. Found and fixed: the dump omitted `supabase_migrations`, so a restore into a fresh project would have re-run every migration on the next push. Repeat monthly; next 2026-10-12 |
| 5 | Tara's real templates and clinics in hosted through the web admin (no hand INSERTs, CLAUDE.md) | [Tara] | asked 2026-09-01 |
| 6 | Crash reporting and error visibility (Sentry or Supabase logs + an alert on edge-function errors) | [me]/[Alex] | none |
| 7 | Rate limits on the public functions (`stripe-setup-intent`) and on sign-up | [me] | none; low risk at club scale, note it |
| 8 | Drop dead `clinics.price_cents` (blast radius in backlog) | [me] | whenever |
| 9 | Data retention and export: what Tara gets if she leaves the app (CSV of players and payments) | [me] | v1.1 |
| 10 | **Backup artifacts are readable by any signed-in GitHub user** because the repo is public and the dump carries `auth.users` (emails, bcrypt password hashes). Found 2026-09-12 by the docs audit. Fix in the same PR: the job now encrypts with `age` to a public key in `.github/backup-recipient.txt` and refuses to upload without one. Needs Alex: run `age-keygen`, keep the private key in his password manager, paste the public line into that file. Then decide on the ten existing unencrypted artifacts (delete via `gh api -X DELETE`, or accept until they expire in December) and whether the repo goes private | [Alex] | **key needed; job fails until then** |

## E. Testing: what exists, what is missing, what to build

The rule (CLAUDE.md, verification asymmetry): the thing that builds a feature cannot be the thing that certifies it, so every layer below is a different observer.

| Layer | Runs where | Count 2026-09-12 | Gap |
|---|---|---|---|
| SQL probes (rules, privileges, attacks, concurrency) | every PR, and locally | 386 checks, 18 probes | none known |
| Stripe pipeline against stripe-mock | every PR | 27 checks | real Stripe behaviour (3DS, declines) waits on keys |
| Web admin browser tests (Playwright, real sign-in) | every PR | 12 | not idempotent (backlog); no test of the charge path with the switch on |
| Swift unit tests (pure logic) | every PR | 23 | fine |
| XCUITests, player and admin flows on the simulator | **local only** | 13 | **not in CI**: the macOS runner cannot host the local database. Fix: a CI Supabase project (section F) |
| Hand-driven simulator and browser passes with screenshots | every feature, by me | – | not repeatable; that is what the two layers above are for |
| Copy gate, secret scan, migration immutability, icon gate | every PR | – | none |
| Nightly backup | nightly | – | never restored (D4) |

Missing kinds of testing, in the order they matter:

1. **UI tests in CI** (section F). The largest gap: today a Swift change is proven only on my machine.
2. **A restore drill** (D4).
3. **Real-device pass** (C9).
4. **Accessibility pass**: VoiceOver on every screen, Dynamic Type at the largest size, colour never the only signal (the design system promises this; nothing checks it). Build: an XCUITest that reads every button's accessibility label on each screen and fails on an empty one.
5. **Offline and bad network**: airplane mode on every action; the app should say "Couldn't…" and keep state. Build: a UI test with a stubbed network is expensive; a manual checklist first.
6. **Time-zone and DST**: the window rule has probes across DST; the app's week grouping has unit tests. Missing: a probe on the 4-hour cutoff across a DST change (add to `late_cancellation.sql`).
7. **Load at club scale**: the capacity race runs 24-way; a season publish of 60 clinics has never been listed on a phone. Build: seed 60 clinics locally once and screenshot Home and Clinics.
8. **Security review of the edge functions** with the `sql-auditor` agent (rewritten for FXE 2026-09-12) and an adversarial pass: call every function as anon, as a player, as a player with a forged body.
9. **Dependency audit**: `npm audit` for the web tests. Swift packages: Stripe SDK pinned exactly 2026-09-12 (PR #37); supabase-swift was already exact.
10. **Copy review with Tara**: the 60-odd chrome strings in `docs/copy-review.md` and every sentence marked hers.

## F. The CI Supabase project (Alex asked 2026-09-12)

Would it help a lot? Yes: it is the only way to run the 13 XCUITests on every PR, which is the layer that walks the app like a member does. The macOS runner has no Docker, so it cannot host the local stack; a small hosted project it can reset to the seed is the practical answer.

Does it use the Volee slot? No. Supabase's free plan is per organization, two active projects each. `supabase orgs list` shows two orgs: Volee (one project) and FXE (one project, `fxe-tennis`). A `fxe-ci` project goes in the FXE org, next to production, and Volee is untouched.

What it costs: nothing. Free projects pause after a week idle; CI resetting it nightly keeps it awake.

What it needs from Alex: create the project in the FXE org (dashboard, two minutes, choose us-east-1, any database password: the password is a credential and stays with Alex), then set two GitHub secrets: `CI_SUPABASE_DB_URL` (the connection string) and `CI_SUPABASE_ANON_KEY`. I do the rest: a workflow job that runs `supabase db reset --linked` against it, points the UI tests at it through the existing `AppEnv`, and serializes runs with a concurrency group so two PRs never share a seed. Guardrail: the CI project holds seed data only, never Tara's (CLAUDE.md, "no test fixtures in hosted" applies to production, not to a throwaway).

---

## Done

- C4 Privacy manifest, 2026-09-12 (PR #37).
- E9 Stripe SDK pinned exactly, 2026-09-12 (PR #37).
- D4 Restore drill, 2026-09-12 (kept in the table above because it recurs monthly).
- Docs audit, 2026-09-12: four read-only agents, about 150 drifts fixed, `scripts/check-doc-paths.sh` in CI so a doc can no longer name a file that is not there.
