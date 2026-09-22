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
| 1 | Stripe test-mode account and the three keys in Supabase secrets (steps in section B) | [Alex] | deferred by Alex 2026-09-13 ("figure that stuff out then I'll do the stripe stuff later"): after the CI project and the doc mechanisms |
| 2 | Run `tests/stripe/run.sh` against real Stripe with test cards, `stripe listen` for webhooks, fix what the mock could not show | [me] | blocked on 1 |
| 3 | Tara's answers to questions 28–42 | [Tara] | **answered 2026-09-16**, decision 0012; follow-ups 43–47 **answered 2026-09-21**, decision 0013; questions 52–57 open |
| 4 | Her policy in the code: no courtesy (switched off at 0 days, 2026-09-21), no-shows, one tap per clinic after it ends, card required to register, her two sentences | [me] | **built 2026-09-16** (20260916000001), **amended 2026-09-21** (20260921000001, decision 0013); `payments_enabled` still off until Stripe keys and question 43 |
| 5 | Refund on her clinic cancel | [me] | **moot 2026-09-16**: nothing is charged before a clinic ends (her answer 7) |
| 6 | Player-side payment history: **the Past section of My Clinics** shipped 2026-09-21 (`my_past_clinics`: what I played and what it cost). Still not built: Stripe email receipts (decide whether to pass `receipt_email`) | [me] | Past built; receipts open |
| 7 | Live-mode activation on stripe.com. Tara sent Alex her business details on 2026-09-16; **they go into Stripe's own form and nowhere else** (not the repo, not chat, not the prompt log, which now redacts them) | [Alex] with Tara's details | ready to do with the test account |
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
| 1 | Apple Developer Program enrollment as FXE Tennis, LLC. Apple asked (2026-08-26) for the applicant's government photo ID, employment verification, and one business document (Articles of Incorporation, business license, Certificate of Formation, charter, or notarized partnership papers); Tara is sending them. Alex's own Apple ID has no developer account; he holds John's Volee login and it will not be used (an Individual account would show John as the seller; decided 2026-08-16 and 08-19: the LLC from the start) | [Tara]/[Apple] | in review (docs/whats-next.md) |
| 2 | Bundle id (replaces `com.fxetennis.app` placeholder), Team ID, App Store Connect record, APNs key | [Alex] | blocked on 1 |
| 3 | Push delivery: the `push` edge function on the notifications webhook, audit columns (decision 0008) | [me] | blocked on the APNs key |
| 4 | **Privacy manifest** (`PrivacyInfo.xcprivacy`): Apple rejects builds that use required-reason APIs without it | [me] | **done 2026-09-12** (PR #37) |
| 5 | **Account deletion in the app**: App Store guideline 5.1.1(v). Tara, 2026-09-21: "Keep their history." Built: `delete_my_account()` scrubs the person and keeps registrations, ledger and her notes; the `delete-account` edge function removes the sign-in through Supabase's admin API (soft delete). Profile → Delete my account, two taps. Probe `account_deletion` (18) | [me] | **built 2026-09-21**; edge function to deploy with the PR |
| 6 | Privacy policy at a URL, terms (Tara said Volee's privacy policy can be reused, decision 16). **Waiver: done 2026-09-21**, her Adult Tennis Participation Waiver signed in the app before the first spot (decision 0013 §4) | [Alex]/[Tara] | privacy policy still needs a place to host it (fersc.com, she said) |
| 7 | App Store listing: name, subtitle, description (Tara's words), screenshots on the required sizes, age rating, support URL, review notes with a test account | [Alex]+[me] | not started |
| 8 | TestFlight internal build to Tara's phone, then external testers (external needs the privacy URL) | [John] then [Alex] | **stopgap 2026-09-21 (decision 0014):** John uploads internal builds from his own account per `docs/testflight.md`; external testers and the listing wait on 1 |
| 10 | **An annotated git tag and a changelog line at every TestFlight upload** (`git tag -a v0.1.0-tf1 -m ...`), so a build on a phone can always be matched to a commit. Alex asked for tags and patch notes on 2026-08-13; Volee once shipped a build no commit matched. No tags exist yet | [me] | at the first upload |
| 9 | Real-device pass: the two simulator flakes (Profile tab first tap, sign-in timing) checked on an iPhone | [Alex]/[me] | blocked on 8 |

## D. Backend and operations

| | Item | Owner | Status |
|---|---|---|---|
| 0 | **Hosted Auth has "Confirm email" switched OFF**, set by hand in the dashboard on 2026-08-16 (Alex: "I'd rather just have no verification right now"; Tara's Screen 2 says no email verification in v1; decision 0011). Local `config.toml` has `enable_confirmations = false`. **Any new project (the CI one, a restore into a fresh project, a plan change) comes with it ON**, and sign-up then hangs exactly as it did on 2026-08-13; it is the first thing to check on any new project | [Alex] | done on production; re-check on every new project |
| 1 | **Auth email delivery.** Hosted uses Supabase's built-in email, which is rate-limited to a handful per hour and lands in spam. Password resets and any sign-up confirmation need custom SMTP (Resend or Postmark, free tiers cover a club) with DNS records on the club's domain | [Alex] | not done; blocks a real password reset |
| 2 | Password reset redirect URL allow-listed in the hosted dashboard | [Alex] | done 2026-09-01 per whats-next; re-verify with one real reset |
| 3 | Supabase plan: free tier pauses after 7 idle days and has no point-in-time recovery. Nightly `pg_dump` exists and the keep-warm job runs. Pro ($25/mo) removes both risks; decide before members are on it | [Alex] | decide |
| 4 | **Restore drill**: a backup nobody has restored is not a backup | [me] | **done 2026-09-12**: the 11:22 UTC artifact (26 KB) restored into a scratch `supabase/postgres:17.6.1.155` container with one benign error (`schema public already exists`); 15 tables, 51 functions, 10 views, `auth.users` present (Tara's login survives), 1 account, 1 clinic, 1 template. Found and fixed: the dump omitted `supabase_migrations`, so a restore into a fresh project would have re-run every migration on the next push. Repeat monthly; next 2026-10-12 |
| 5 | Tara's real templates and clinics in hosted through the web admin (no hand INSERTs, CLAUDE.md) | [Tara] | asked 2026-09-01 |
| 6 | Crash reporting and error visibility (Sentry or Supabase logs + an alert on edge-function errors) | [me]/[Alex] | none |
| 7 | Rate limits on the public functions (`stripe-setup-intent`) and on sign-up | [me] | none; low risk at club scale, note it |
| 8 | Drop dead `clinics.price_cents` (blast radius in backlog) | [me] | whenever |
| 9 | Data retention and export: what Tara gets if she leaves the app (CSV of players and payments) | [me] | v1.1 |
| 10 | **Backup artifacts are readable by any signed-in GitHub user** because the repo is public and the dump carries `auth.users` (emails, bcrypt password hashes). Found 2026-09-12 by the docs audit. Fix in the same PR: the job now encrypts with `age` to a public key in `.github/backup-recipient.txt` and refuses to upload without one. Alex generated the key on 2026-09-13 and keeps the private half in LastPass; the public `age1...` line still has to go into that file. The repo stays public (Alex, 2026-09-13: it was made public for free CI minutes). The eleven existing unencrypted artifacts were deleted on 2026-09-18 (`gh api -X DELETE`, remaining count verified 0; Alex: "whatever you think") | [Alex] | **public line needed; job fails until then** |

## E. Testing: what exists, what is missing, what to build

The rule (CLAUDE.md, verification asymmetry): the thing that builds a feature cannot be the thing that certifies it, so every layer below is a different observer.

| Layer | Runs where | Count 2026-09-12 | Gap |
|---|---|---|---|
| SQL probes (rules, privileges, attacks, concurrency) | every PR, and locally | 513 checks, 24 probes | none known |
| Stripe pipeline against stripe-mock | every PR | 27 checks | real Stripe behaviour (3DS, declines) waits on keys |
| Web admin browser tests (Playwright, real sign-in) | every PR | 14 | not idempotent (backlog); no test of the charge path with the switch on |
| Swift unit tests (pure logic) | every PR | 23 | fine |
| Hosted signed-out smoke (`scripts/hosted-smoke.sh`) | every PR, read-only against production | 48 targets | only the anon side; a signed-in run needs a real person's session |
| XCUITests, player and admin flows on the simulator | **local only** | 13 | **not in CI** by decision (§F, 2026-09-18): run on a laptop before every TestFlight build and pasted into that build's changelog entry |
| Hand-driven simulator and browser passes with screenshots | every feature, by me | – | not repeatable; that is what the two layers above are for |
| Copy gate, secret scan, migration immutability, icon gate | every PR | – | none |
| Nightly backup | nightly | – | never restored (D4) |

Missing kinds of testing, in the order they matter:

1. **UI tests in CI**: deliberately deferred 2026-09-18 (section F); until then the laptop run before each TestFlight build is the control.
2. **A restore drill** (D4).
3. **Real-device pass** (C9).
4. **Accessibility pass**: VoiceOver on every screen, Dynamic Type at the largest size, colour never the only signal (the design system promises this; nothing checks it). Build: an XCUITest that reads every button's accessibility label on each screen and fails on an empty one.
5. **Offline and bad network**: airplane mode on every action; the app should say "Couldn't…" and keep state. Build: a UI test with a stubbed network is expensive; a manual checklist first.
6. **Time-zone and DST**: the window rule has probes across DST; the app's week grouping has unit tests. Missing: a probe on the 3-hour cutoff across a DST change (add to `late_cancellation.sql`).
7. **Load at club scale**: the capacity race runs 24-way; a season publish of 60 clinics has never been listed on a phone. Build: seed 60 clinics locally once and screenshot Home and Clinics.
8. **Security review of the edge functions** with the `sql-auditor` agent (rewritten for FXE 2026-09-12) and an adversarial pass: call every function as anon, as a player, as a player with a forged body.
9. **Dependency audit**: `npm audit` for the web tests. Swift packages: Stripe SDK pinned exactly 2026-09-12 (PR #37); supabase-swift was already exact.
10. **Copy review with Tara**: done 2026-09-21 (decision 0013, her Words tab applied verbatim); round two sent the same day, questions 52–57 outstanding.

## F. The CI Supabase project (Alex asked 2026-09-12; corrected 2026-09-13; decided 2026-09-18)

**Decided 2026-09-18: option 3.** Alex: *"nahh unless we really need it no more money for now."* No CI project, no Pro plan. The 13 XCUITests run on a laptop before every TestFlight build and the run is pasted into the changelog entry for that build; the `ios-ui-tests` job stays green with its notice until the three settings exist, so switching later is a dashboard visit and two secrets, nothing in the repo. Revisit when the first paying member exists (D3 wants point-in-time recovery then anyway). The rest of this section is kept as the record of why.


Alex gave the go-ahead on 2026-09-13 ("exact steps for me or can you do it all?"); the create was attempted the same day and refused, see below. Would it help a lot? Yes: it is the only way to run the 13 XCUITests on every PR, which is the layer that walks the app like a member does. The macOS runner has no Docker, so it cannot host the local stack; a small hosted project it can reset to the seed is the practical answer. Everything on our side is built and waiting (2026-09-13): the Debug app accepts `FXE_SUPABASE_URL` / `FXE_SUPABASE_ANON_KEY`, the UI tests forward them, and the `ios-ui-tests` job resets the project with `supabase db reset --db-url` and runs the suite with one retry. The job stays green with a notice until the secrets exist.

**Does it use the Volee slot? Yes, and Alex was right.** The 2026-09-12 version of this section said the free plan is two projects per organization. It is two active free projects per *user* across every org they own: `supabase projects create fxe-ci` on 2026-09-13 was refused with "Alex-Epstein (2 project limit)", because Volee and `fxe-tennis` already fill it. Three ways out, cheapest first:

1. **Pro on the FXE org, $25/month.** Removes the pause-after-a-week risk and adds point-in-time recovery for production (row D3 wanted this before real members anyway). The extra `fxe-ci` micro project on a Pro org bills about $10/month on top. Roughly $35/month total.
2. **A second free owner.** A free org owned by someone else (Tara's own Supabase account, or an account Alex creates for the club) gets its own two free slots. Zero cost; one more login to keep track of, and Alex would need to be invited as an admin.
3. **No project: keep running the UI suite on a laptop before every TestFlight build**, and record the run in the changelog. Free, honest, and the weakest of the three.

What it needs from Alex once a project exists: its database password stays with him; set three things in GitHub, Settings → Secrets and variables → Actions: secret `CI_SUPABASE_DB_URL` (the session-pooler connection string, port 5432), secret `CI_SUPABASE_ANON_KEY` (the project's publishable key), and variable `CI_SUPABASE_URL` (`https://<ref>.supabase.co`). The next Swift change then runs the suite. Guardrail: the CI project holds seed data only, never Tara's.

---

## Done

- C4 Privacy manifest, 2026-09-12 (PR #37).
- E9 Stripe SDK pinned exactly, 2026-09-12 (PR #37).
- D4 Restore drill, 2026-09-12 (kept in the table above because it recurs monthly).
- Docs audit, 2026-09-12: four read-only agents, about 150 drifts fixed, `scripts/check-doc-paths.sh` in CI so a doc can no longer name a file that is not there.
