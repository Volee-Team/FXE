# Launch checklist: the single source of truth for what is left

**Launch target: the launch party, Friday 2026-11-06** (moved from 2026-10-16 by Tara on 2026-09-28, decision 0024; she would go earlier if the app is ready).

How this file works, so it can be trusted:

1. **If something is left to do before launch, it is a row here, and only
   here.** Other files hold the detail a row links to: `docs/for-alex.md`
   (click-by-click steps for Alex's rows), `docs/questions-for-tara.md` (the
   questions' wording), `docs/backlog.md` (bugs that do not block launch).
   The "State today" block below replaced `docs/archive/whats-next.md` on
   2026-10-12. (Alex, 2026-09-27: *"i like having one thing to totally
   trust"*.)
2. **Status words live in four files only** (Alex, 2026-10-12: *"we have
   tons of docs and some are becoming outdated and we need a SOLID system
   and ASOT to stick to"*): this file for work (LATER included),
   `docs/backlog.md` for bugs, `docs/questions-for-tara.md` for questions,
   `docs/decisions/README.md` for decisions. Every other doc points at a row
   ID ("see C3") instead of saying DONE, OPEN, built or pending itself.
   Retired snapshots live in `docs/archive/` with a banner naming the live
   source.
3. **Every row has an owner and a status.** Owner in brackets: [Alex],
   [Tara], [Kat], [John], [me] for the model, [Apple], [Stripe]. Status starts
   with one word: **DONE** (with the date and the evidence), **OPEN**,
   **BLOCKED** (on what), **DECIDE** (whose call), or **LATER** (after launch).
4. **A status is re-derived by command, never copied forward.** Last full
   re-derivation: **2026-09-28**, each check named in the row. Re-derived
   again on 2026-10-12 (by `git`, the code and Alex's reports, each named in
   the row): the State today block, A7, A9, A10, A13, A14, C3, C8, C10, C11,
   C13, D1, D4, D6, D14, G2, G7, G8, H8, I2, I3, I9 and section E.
5. **Machines keep it honest.** In CI: `scripts/check-launch-checklist.sh`
   (an owner and a status word on every row, a date on every DONE, no row
   past its due date, `docs/for-alex.md` points only at real rows);
   `scripts/check-doc-status.sh` (no old build, merged branch or forbidden
   instruction in a live doc); `scripts/check-doc-registry.sh` (every doc is
   registered in `CLAUDE.md` or archived with its banner);
   `scripts/check-doc-claims.sh` (counts, and no question a decision answered
   still open).

---

## State today (re-derived 2026-10-13)

- **Code:** `main` carries build 11, tag `v0.1.0-rc11` (PR #96, `355f546`:
  the 2026-10-12 audit fixes on top of build 10's note at Register and
  Tara's 2026-10-12 answers). Branch `prelive-1013` is the next PR (crash
  reports, the card-removed webhook, the secret scan, the clinic page for
  staff) and becomes build 12.
- **On testers' phones:** the last upload tagged in git is `v0.1.0-tf7`; no
  upload of build 8 or 9 was reported (C8).
- **Hosted:** every migration through `20261013000001`, 64 of 64 paired on
  2026-10-13 (`supabase migration list --linked` after the push); the two
  crash-report migrations on `prelive-1013` go with that PR. **Payments are off**: no migration sets `payments_enabled`
  to true (A9).
- **Tests:** 48 SQL probes plus 15 shell probes (races and the 200-request
  rush), 283 unit tests, 26 XCUITests (green on iOS 26.2, 18.6 and 17.5 on
  2026-10-13 UTC, `docs/ui-test-runs.log`), 49 browser tests.
- **Waiting on others:** Apple's answer on the LLC (C1), John's upload of
  build 11 and Apple's beta review (C8, C11), the live Stripe keys (A10),
  Tara's question 101 (Foxcroft's share) and 109 to 112 (the note).

---

## 0. The critical path to 2026-11-06

What must be true on the day, in the order it has to happen. Each item is a
row below; this list adds nothing of its own. Re-derived 2026-10-12 (Tara:
"when can we put it on the app store and have people testing ... with actual
payments", decision 0040).

Testers come first, on John's account, without waiting for the LLC: TestFlight
needs only Apple's beta review, and payments go through Stripe, not Apple.

1. **The review account exists** (C13): Alex signs up "App Review" in the
   TestFlight app, so it lands on hosted, and gives John the login. [Alex]
2. **Build 10 to External Testing on John's account** (C8, C11): the tag
   `v0.1.0-rc10` exists (merged 2026-10-12); John archives it,
   uploads as App Store Connect (not Internal Only) and submits External
   Testing. Apple's beta review takes about 1 to 2 days. [me, John, Apple]
3. **Real payments on** (A13, A10, A14, then A9), after Apple approves 2: a
   rehearsal against Stripe's sandbox with a restricted key carrying exactly
   the live permissions, the live keys, the cutover that forgets sandbox
   cards, one real charge and refund on Alex's card, the three Stripe
   settings, then payments on. Tara's live account is active (A7). [Alex, me]
4. **The soft launch** (G7): the date and the first testers, picked by Alex
   and Tara; the public link goes to them once Apple approves (C11). [Alex,
   Tara, John]
5. **Tara's email to members** with the QR code and the public link (G8, I6).
   [Tara]
6. **Push seen on a real lock screen** (C3). [Alex]
7. **The LLC's own app** (C1, C2, C12, C7): Apple's answer on the authority
   letter, then a new bundle id under the LLC, testers reinstall (accounts
   and cards carry over; they live on our server), and the App Store
   submission before the party. [Apple, Alex, me]
8. **Supabase Pro before real members** (D3): backups held by Supabase and
   no pause after a quiet week. [Alex]

---
## A. Payments

| ID | Item | Owner | Status |
|---|---|---|---|
| A1 | Stripe sandbox keys in Supabase's Edge Function secrets | [Alex] | **DONE 2026-09-27.** `supabase secrets list` shows `STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`; a forged request to `stripe-webhook` answers `bad_signature`, so the signing secret is loaded |
| A2 | End-to-end payment test on the real app in Stripe's sandbox, Alex's own account (`docs/stripe-e2e-test.md`, eight rows) | [Alex]+[me] | **BLOCKED** on A13: the rehearsal with a restricted sandbox key is this test, run against real Stripe test mode |
| A3 | Tara's payment-policy answers | [Tara] | **DONE 2026-09-21** (decisions 0012, 0013) |
| A4 | Her policy in the code: no courtesy, 3 hours, no-shows, her one tap per clinic, card required, card permission | [me] | **DONE 2026-09-26** (20260916000001, 20260921000001, 20260926000001; probes `cancellation_policy`, `late_cancellation`, `card_consent`) |
| A5 | Refund when she cancels a clinic | [me] | **DONE 2026-09-16**, moot: nothing is charged before a clinic ends (her answer 7) |
| A6 | Payment history for players: the Past section of My Clinics; Stripe email receipts not decided | [me] | **LATER**: Past shipped 2026-09-21; receipts after launch |
| A7 | Stripe live mode: activate with Tara's business and bank details, typed into Stripe's own form only; move the account's ownership to Tara | [Alex]+[Tara] | **DONE 2026-10-04**: Tara owns the account (transferred 2026-10-03); the LLC's EIN replaced the SSN in Stripe's business details; Payments and Payouts both Active (Alex, 2026-10-04). Tara has no accountant, so the SSN-or-EIN question is closed (Alex, 2026-10-05). Single-member LLC, statement descriptor FXE TENNIS, Radar Lite, tax off. Watch her email for Stripe's follow-ups |
| A8 | Webhook destination for hosted, five events | [Alex] | **DONE 2026-09-27**, with A1 |
| A12 | Three more webhook events for chargebacks (`charge.dispute.created`, `.updated`, `.closed`), on the test endpoint now and the live one later (decision 0021) | [Alex] | **DONE 2026-10-01** (Alex: "dispute events added", in the prompt log). Not yet seen working: the first test dispute in the sandbox is the check |
| A9 | Switch payments on (`payments_enabled` true **and `payments_enabled_at` = now(), in the same migration**, decision 0018: nothing that ends before that moment is ever owed or charged). From that moment nobody registers or accepts an invitation without a saved card (decision 0040) | [me] | **BLOCKED** on C11 (Apple approves the external build), A10 (live keys and the cutover) and A13 (the rehearsal); then Alex says go. No migration sets it true today (`grep payments_enabled supabase/migrations/*.sql`, 2026-10-12). **Never while the keys are sandbox**: a real card is declined in test mode (MVP audit 2026-09-27) |
| A10 | Live keys: a restricted key with only the permissions our code uses, a live webhook with the nine events (the ninth, `payment_method.detached`, since 2026-10-13), the three secrets swapped, and at the same moment the cutover that forgets every sandbox card so everyone adds a real one (`stripe_cutover_to_live`, `20260927200001`, built in PR #75, H2) | [me]+[Alex] | **OPEN**, after A13; steps in `docs/for-alex.md` |
| A11 | **Real money at the party**: payments fully live at the party (2026-11-06; it was 2026-10-16 until Tara moved it) (Alex, 2026-09-27: *"yes we want it fully done"*; promo codes "prob not"). The fallback if the live switch (A13, A10, A9) is not done by **2026-11-04**: payments stay off for the party | [Alex]+[Tara] | **OPEN**: decided 2026-09-27, target live; Tara's activation is done (A7, 2026-10-04), so the 11-04 gate is now A13, A10 and A9 (Alex to confirm the date) |
| A13 | Rehearsal before the live switch: a restricted key in Stripe's **sandbox** carrying exactly the live key's permissions, and the model runs save a card, a charge after a clinic, a refund, a declined card and a 3-D Secure card against real Stripe test mode (a restricted key missing one permission makes saving a card fail silently; nothing has talked to real Stripe yet, only the mock). The gate for A10 | [Alex]+[me] | **OPEN**: steps in `docs/for-alex.md` |
| A14 | Three Stripe settings on the live account: customer receipts off (Tara: "No receipts", question 86), payouts to her bank on a Daily schedule, dispute emails on in Tara's own login | [Alex]+[Tara] | **OPEN**: steps in `docs/for-alex.md` |

## B. Stripe steps

One copy only: `docs/for-alex.md` §1 (done 2026-09-27; kept for live mode).
What Stripe takes: 2.9% + 30¢ per card charge. Apple takes nothing (decision
0009). Payouts to Tara's bank need live mode (A7).

## C. App Store and Apple

| ID | Item | Owner | Status |
|---|---|---|---|
| C1 | Apple Developer Program enrollment as FXE Tennis, LLC (Apple asked for the ID, employment verification and a business document on 2026-08-26; Tara sent them) | [Tara]/[Apple] | **BLOCKED** on Apple: on 2026-10-11 Apple (case 102990597020, enrollment L6R8KDC88Y) asked for a letter giving Alex authority to bind the LLC; signed by Alex and Tara, and Alex reported it sent on 2026-10-12. Waiting on Apple |
| C2 | Bundle id, Team ID, App Store Connect record and APNs key under the LLC | [Alex] | **BLOCKED** on C1 |
| C3 | Push notifications on the lock screen: sender, trigger and audit columns deployed 2026-09-23 (#61); the app's half (banner while open, tap opens the clinic, badge clears, Accept and Decline on the lock screen) merged in PR #75 (H5) | [me] | **OPEN**: key in 2026-10-03. John's key `75U93U9VS6` (team `Q7NA43M86G`); `APNS_KEY_ID`, `APNS_TEAM_ID`, `APNS_TOPIC`, `APNS_PRIVATE_KEY` and `PUSH_WEBHOOK_SECRET` set on hosted, and Vault `push_function_url` (58 chars) and `push_webhook_secret` (64) written through the management API, both names read back. Alex's phone is registered (1 device on his account). **Open: the first real push seen on a lock screen** [Alex] |
| C4 | Privacy manifest | [me] | **DONE 2026-09-12** (#37) |
| C5 | Delete my account in the app, history kept (guideline 5.1.1(v)) | [me] | **DONE 2026-09-21**; `delete-account` deployed the same day |
| C6 | Privacy policy at a public URL | [Tara] | **DONE 2026-09-27**: Tara approved it ("looks good"), contact fersctennispro@gmail.com; published at `https://fxe-tennis-admin.vercel.app/privacy.html` (verified by `deploy-web.sh`) and linked from Profile in the app (build 4) |
| C7 | App Store listing: name, subtitle, description in Tara's words, screenshots, age rating, support URL, review notes with a test account | [Alex]+[me] | **BLOCKED** on C1, or on C11's path |
| C8 | TestFlight **build 11** from the tag `v0.1.0-rc11` (build 10's note at Register and Tara's 2026-10-12 answers, plus the 2026-10-12 audit fixes; green on iOS 17, 18 and 26 before the tag) | [John] | **OPEN**: tagged 2026-10-13 on `355f546` (`git ls-remote --tags origin v0.1.0-rc11`); John uploads it as App Store Connect, not Internal Only (`docs/testflight.md`). Builds 9 and 10 were never reported uploaded; 11 replaces both |
| C9 | Real-device pass: the two simulator flakes checked on an iPhone | [Alex]/[me] | **BLOCKED** on C8 |
| C10 | An annotated git tag at every TestFlight build and upload | [me]/[John] | **OPEN**: `v0.1.0-rc4` to `rc11` exist, and upload tags were made for builds 2, 5 and 7 only (`git tag`, 2026-10-13). Next: `v0.1.0-tf11` when John's upload of build 11 is processed |
| C11 | External TestFlight on John's account with a public link, through Apple's beta review, with no testers invited until the soft launch (G7) | [Alex]/[John] | **OPEN**: not yet submitted; John uploads build 11 as App Store Connect and submits External Testing (`docs/testflight.md`, `docs/for-alex.md`). The privacy URL it needs is live (C6) |
| C12 | Bundle id for the LLC's app. `com.fxetennis.app` is tied to John's account now: Apple transfers only apps with at least one App Store release, and a TestFlight upload locks the id to that account. The LLC's app will need a new id, and testers install it fresh (their accounts carry over; they live on our server) | [Alex] | **DECIDE** [Alex] before the first LLC build |
| C13 | How Apple's reviewer signs in: one real account called App Review, made through the app's own sign-up with an address Alex controls, left out of the board report; while keys are sandbox the review notes give Stripe's 4242 test card | [Alex] | **OPEN** [Alex]: decided 2026-10-06. The account Alex made on 2026-10-01 was made on a local build and never reached hosted (not there when checked 2026-10-06); it must be made in the TestFlight app, which talks to hosted |

## D. Backend and operations

| ID | Item | Owner | Status |
|---|---|---|---|
| D0 | "Confirm email" off on hosted (decision 0011) | [Alex] | **DONE**; verified 2026-09-27 through the management API (`mailer_autoconfirm` true). Re-check on any new project |
| D1 | **A real email sender, so "Forgot password?" reaches members** | [Alex] | **DONE 2026-09-27**: Gmail `fxetennis.app@gmail.com` with an app password as custom SMTP; read back through the management API (`smtp_host` smtp.gmail.com, port 465, sender "FXE Tennis"). Delivery confirmed by Alex 2026-10-01: *"the reset emails came in just took a while"* |
| D2 | Reset page allow-listed as a redirect on hosted | [Alex] | **DONE 2026-09-01**; verified 2026-09-27 (`uri_allow_list` is `https://fxe-tennis-admin.vercel.app/reset.html`) |
| D3 | Supabase plan: the free tier pauses after a quiet week and has no point-in-time recovery; Pro is $25 a month | [Alex] | **DECIDE** [Alex] before real members |
| D4 | Restore drill (a backup nobody has restored is not a backup) | [me] | **DONE 2026-10-12**: last night's encrypted backup restored into a bare Postgres, the whole migration ledger and all 9 sign-ins back, after dropping the image's own `auth` schema first (restoring onto it gave 0 users). Monthly; next due 2026-11-02, the week before the party (runbook row 12) |
| D5 | Tara's real templates and clinics in hosted, through the admin site | [Tara] | **DONE 2026-10-11**: her real clinics are on hosted (Coed "105", Ladies All Level, Ladies 3.0+, Queen City, Ladies Beginner 2.5, Men's 3.0+, 2026-10-04 to 2026-10-07, read through the management API); none after 2026-10-07 yet |
| D6 | Crash reporting and error alerts: MetricKit crash and hang reports into `app_diagnostics` through `report_app_diagnostic` (decision 0035) | [me]/[Alex] | **OPEN**: merged into branch `prelive-1013` on 2026-10-13 for build 12, its migrations renumbered past hosted's newest (`20261014000001`, `20261014000002`; neither redefines a function changed since 10-01), and the privacy sentence Alex approved on 2026-10-03 ("crash report looks great") added to the policy. Not yet seen end to end on a device: MetricKit does not deliver on the simulator |
| D7 | Rate limits on the public functions and sign-up | [me] | **LATER**: low risk at club scale |
| D8 | Drop the dead `clinics.price_cents` column | [me] | **LATER** |
| D9 | Data export for Tara | [me] | **LATER** (v1.1) |
| D10 | Encrypted nightly backups | [Alex] then [me] | **DONE 2026-09-22** (age key; first encrypted run decrypted and checked) |
| D11 | Hosted "Site URL" and the reset email's link (decision 0017) | [me] | **DONE 2026-09-27**: Site URL `https://fxe-tennis-admin.vercel.app`; the reset email now links `{{ .SiteURL }}/reset.html#token_hash=…&type=recovery` (read back through the management API once custom SMTP made templates editable) |
| D12 | Nightly purge of card consents 90 days after an account is deleted | [me] | **DONE 2026-09-27**: the `retention` job ran on hosted, "Card consents purged ...: 0" |
| D13 | **Tara can reset any member by hand**: Players tab → Reset link → Copy → text it. One-time, within an hour, no email, every link audited (`admin-reset-link`, decision 0017) | [me] | **DONE 2026-09-27**: PR #73 merged; `supabase db push` applied 20260927000001; `admin-reset-link` deployed; `hosted-smoke.sh` 63 targets, 0 open; live page checked from outside |
| D14 | Sign-in and sign-up rate limits on hosted: every phone at the party shares the club Wi-Fi's one address | [me] | **DONE 2026-10-05** through the management API, read back: sign-ups 300 per 5 minutes per address, auth emails 100 an hour (earlier, 2026-09-27: `rate_limit_verify` 30 → 300, `rate_limit_token_refresh` 150 → 500 per 5 minutes per IP) |
| D15 | How many courts the club has | [Tara] | **DONE 2026-09-27**: 5 (Alex), which is exactly what the app allows (1 to 5); no change needed |

## E. Testing

The rule (CLAUDE.md, verification asymmetry): the thing that builds a feature
cannot be the thing that certifies it, so every layer below is a different
observer.

| Layer | Runs where | Count (derived 2026-10-12 unless dated) | Gap |
|---|---|---|---|
| SQL probes (rules, privileges, attacks, concurrency) | every PR, and locally | 48 probes plus 15 shell probes (the races and the 200-request rush); the suite prints its own check total | none known |
| Stripe pipeline against stripe-mock | every PR | 94 checks as of 2026-09-28 | real Stripe behaviour waits on A13 |
| Push pipeline against a mock APNs | every PR | 57 checks as of 2026-09-28 | real APNs waits on C3 |
| Web admin browser tests (Playwright, real sign-in) | every PR | 49 | a cold-start flake after a local reset (backlog) |
| Swift unit tests (pure logic) | every PR | 283 | fine |
| Hosted signed-out smoke (`scripts/hosted-smoke.sh`) | every PR, read-only against production | 162 targets as of 2026-10-11, including a browser preflight to each function the web admin calls | only the signed-out side |
| XCUITests, player and admin flows, and Apple's accessibility audit | **local only** (section F) | 26 | run on a laptop before every TestFlight build, on iOS 17, 18 and 26 (`docs/ui-test-runs.log`) |
| Copy gate, secret scan (now Stripe keys too), migration immutability, icon gate, doc checks | every PR | – | none |
| Nightly backup and consent purge | nightly | – | restored by hand monthly (D4, last 2026-10-12) |

Missing kinds of testing, in the order they matter:

1. **UI tests in CI**: deliberately deferred 2026-09-18 (section F); until then the laptop run before each TestFlight build is the control.
2. **Real-device pass** (C9).
3. **Accessibility pass**: Apple's accessibility audit runs as a UI test on the player's, Tara's and the pro's main screens (decision 0023); still missing, VoiceOver walked by a person on every screen and Larger Text at the largest size on a real phone.
4. **Offline and bad network**: airplane mode on every action; the app should say "Couldn't…" and keep state. Build: a UI test with a stubbed network is expensive; a manual checklist first.
5. **Time-zone and DST**: the window rule has probes across DST; the app's week grouping has unit tests. Missing: a probe on the 3-hour cutoff across a DST change (add to `late_cancellation.sql`).
6. **Load at club scale**: 200 signed-in requests through the API at once (`tests/sql/rush_via_api.sh`, 2026-10-01); a season publish of 60 clinics has never been listed on a phone. Build: seed 60 clinics locally once and screenshot Home and Clinics.
7. **Security review of the edge functions** with the `sql-auditor` agent and an adversarial pass: call every function as anon, as a player, as a player with a forged body.
8. **Dependency audit**: `npm audit` for the web tests. Swift packages: Stripe SDK pinned exactly 2026-09-12 (PR #37); supabase-swift was already exact.
9. **Copy review with Tara**: rounds one to five answered (decisions 0013, 0016, 0024, 0040); round six is G2.


## G. People, decisions and content

| ID | Item | Owner | Status |
|---|---|---|---|
| G1 | The MVP call (`docs/archive/mvp.md`): payments in or out, push in or out | [Alex]+[Kat]+[Tara] | **DONE 2026-09-27**: Alex: payments fully live for the party (A11) and push fully working (C3), *"we want everything 100% functional + even better"* |
| G2 | Tara's review page, **round six**: only her 14 unseen words and 5 laptop tasks, no Questions tab (page version 6, `scripts/build-tara-review.py`). Round four was answered 2026-09-28 (decision 0024) and round five's questions 2026-10-12 (decision 0040); `review-watch.yml` opens an issue whenever she saves | [Alex] sends, [Tara] answers | **OPEN**: Alex mints the round-six link (admin site, Testing tab) and texts it (`docs/for-alex.md`). Questions 109 to 112 are not on the page |
| G3 | Kat's calls: the tab bar colour, the green text contrast, the green line under the header; and her earlier "tag spec" line (release tags, answered by C10, or analytics tags, not built; `docs/kat-due-diligence.md`) | [Kat] | **DONE 2026-10-01**: keep the system tab bar, the darker green for text, keep the green line (decision 0036); her "tag spec" line is answered by the release tags (C10) |
| G4 | Alex's ticks in `docs/copy-review.md` (sections G to J and the older open rows) | [Alex] | **OPEN** |
| G5 | Tara's logo file and the original court photo | [Tara] | **DONE 2026-10-01**: the logo (the gator in colour, decision 0032, 2026-09-29) and the court photo, which is the one from her 2026-09-26 mockup, in the app since then (Alex, 2026-10-01: *"its legit in the app alr"*); a full-size original would only make it sharper |
| G6 | GitHub: require the hosted smoke check and stop admins bypassing `main`'s protection. Dependabot alerts are already on (verified 2026-09-27) | [Alex] | **OPEN** (`docs/for-alex.md` §8) |
| G7 | The soft launch: the date, and the first 20 to 30 testers who get the public link | [Alex]+[Tara] | **DECIDE** [Alex]+[Tara]: after Apple approves the external build (C11) |
| G8 | Tara's email to members with the QR code and the public link (question 75, I6); we check her steps before it goes | [Tara] | **OPEN**: her words; the link exists once C11 is approved |

## H. The MVP audit of 2026-09-27

Six reviewers (member, admin, money, store, ops, messages), a skeptic per
finding, then a synthesis: 58 findings kept, none refuted. The seventeen
"build now" items were built on five branches in parallel, each verified
by a separate agent, and all merged in PR #75. The questions it raised are 75 to 79
for Tara and A11, C3, C11, C13, D14 and D15 for Alex. The fourteen "after
launch" items are in `docs/backlog.md`.

| ID | Item | Owner | Status |
|---|---|---|---|
| H1 | Money integrity: one fee per player per clinic; Tara records a late cancellation; Money shows what was charged, declined and not charged yet; her own removal no longer shows as the player canceling (branch `money-integrity`) | [me] | **DONE 2026-09-27** (PR #75, `997cc65`) |
| H2 | Stripe robustness: livemode on every payment and sandbox money kept out of the reports; the cutover for A10; a late or lost webhook no longer strands a charge or a new member; deleting an account deletes the Stripe customer; the waiver survives a hard delete (branch `stripe-robustness`) | [me] | **DONE 2026-09-27** (PR #75, `997cc65`) |
| H3 | The app when things go wrong: a way out of the waiver sheet; reload on return from the background and Register at 8:00 without a pull; bad signal shown as bad signal; the rate-limit line; Larger Text honoured (branch `ios-resilience`) | [me] | **DONE 2026-09-27** (PR #75, `997cc65`) |
| H4 | Web admin: This week bounded to this week (plus ended, uncharged clinics), no silent loss past 1000 rows, supabase-js vendored at an exact version (branch `web-admin-bounds`) | [me] | **DONE 2026-09-27** (PR #75, `997cc65`) |
| H5 | Push, the app's half: banner while open, a tap opens the clinic, the badge clears (branch `push-client`) | [me] | **DONE 2026-09-27** (PR #75, `997cc65`) |
| H6 | Password reset without email (D13) and the scanner-proof reset page (branch `admin-reset-link`) | [me] | **DONE 2026-09-27** (PR #73) |
| H7 | **Payouts on the Money tab** (the balance, the next deposit and its date; Tara's "when will $ be in my account") and dispute alerts in Action Needed, so Tara never needs the Stripe dashboard day to day | [me] | **DONE 2026-09-28.** On hosted: `supabase migration list --linked` pairs `20260928200001`; `supabase functions list` shows `stripe-payouts` v1 and `stripe-webhook` v8 ACTIVE; the live `index.html` carries the Payouts card (`curl ... | grep -c Payouts`: 5) |
| H8 | Walk on a real phone what the simulator could not: a push tapped with the app in the background, the Home spinner on a slow connection, Accept and Decline on the lock screen, a haptic | [Alex]/[me] | **OPEN**: on build 11 (C8), once push is seen (C3) |

## I. Polish for the party (2026-09-28)

Alex, 2026-09-27: *"do as MUCH as you possibly can w building and testing
everything ... make the app as POLISHED as possibly and best feeatures"*.
Four branches, three of them built by separate agents from a written brief,
each checked by an independent reviewer or the sql-auditor, then merged on
`polish-0928` and verified there as one.

| ID | Item | Owner | Status |
|---|---|---|---|
| I1 | Tara's notification catalogue in her words, from the database (#1, #3, #5, #6, #13 to #15), one message per event under a double tap (decision 0022) | [me] | **DONE 2026-09-28.** `supabase migration list --linked` pairs `20260928000001`; `push` v5 ACTIVE. Her uninvite message (decision 0024) is `20260928500001`, local only until the next push |
| I2 | Accept and Decline on the invitation push; Add to Calendar (nothing about where); Remind me at the player's own opening; haptics and the chip's change (decision 0023) | [me] | **DONE 2026-09-28**: merged with `polish-0928` and in every build since (`v0.1.0-rc5` onwards). Seeing the lock-screen buttons on a real phone is H8 |
| I3 | Text anyone can read: Larger Text followed live, Apple's accessibility audit as a UI test on every main screen, the clock readable on navy, Return through the forms, page titles in the guide's serif, outlined tab icons (decision 0023) | [me] | **DONE 2026-09-28**: merged with `polish-0928`; the audit tests pass on iOS 26.2, 18.6 and 17.5 (`docs/ui-test-runs.log`, 2026-10-13 UTC) |
| I4 | Payouts and chargebacks on the Money tab (H7, decision 0021); the Action Needed crash on the first declined card fixed | [me] | **DONE 2026-09-28**, with H7 |
| I5 | Tara's questions from this round: 79 narrowed, 88 to 90 new | [Tara] | **DONE 2026-09-28**: answered in round four (decision 0024); 92 to 95 are the next round's |
| I6 | The QR code for members (question 75): it points at `/app` on the admin site, which forwards to the install link, so the printed card never changes; Tara's printable card under Players → QR code for the app | [me]/[Alex] | **OPEN**: live 2026-09-28 (`deploy-web.sh` matched byte for byte; `/app`, `qr.html` and `app-qr.png` answer 200, `/app` reads "Not available yet."). Waits only on the TestFlight public link: Alex sends it, the model sets `web/app/target.js` and redeploys |
| I7 | Build 6 for players: instant open (decision 0028), Siri and Spotlight, Subscribe in Calendar (0029), every held clinic on Home, clean titles, placeholders, a declined card that says why (0026) | [me] | **DONE 2026-09-29**: PR #81 merged on 27 green checks; locally `Executed 232 tests, with 0 failures` (unit) and all 22 UI tests at the time (the declined-card one run with the local service key); tagged `v0.1.0-rc6` |
| I8 | Build 6 for Tara: pros and their Today screen (0025), Resolved (0026), saved messages (0030), a player's history, Copy to next week and the court sheet (0027); a clinic never published never reaches a player (20260929000001/2) | [me] | **DONE 2026-09-29**: `supabase db push` 60 of 60 paired, the six functions redeployed, `deploy-web.sh` matched byte for byte, `hosted-smoke.sh` 156 targets, 0 open |
| I9 | Tara's questions 92 to 100 and 73 on round five of her review page | [me]/[Alex] | **DONE 2026-10-12**: answered by text (decision 0040), all but 101 (Foxcroft's share, her meeting) |

## F. The CI Supabase project (Alex asked 2026-09-12; corrected 2026-09-13; decided 2026-09-18)

**Decided 2026-09-18: option 3.** Alex: *"nahh unless we really need it no more money for now."* No CI project, no Pro plan. The 26 XCUITests run on a laptop before every TestFlight build and the run is pasted into the changelog entry for that build; the `ios-ui-tests` job stays green with its notice until the three settings exist, so switching later is a dashboard visit and two secrets, nothing in the repo. Revisit when the first paying member exists (D3 wants point-in-time recovery then anyway). The rest of this section is kept as the record of why.


Alex gave the go-ahead on 2026-09-13 ("exact steps for me or can you do it all?"); the create was attempted the same day and refused, see below. Would it help a lot? Yes: it is the only way to run the 26 XCUITests on every PR, which is the layer that walks the app like a member does. The macOS runner has no Docker, so it cannot host the local stack; a small hosted project it can reset to the seed is the practical answer. Everything on our side is built and waiting (2026-09-13): the Debug app accepts `FXE_SUPABASE_URL` / `FXE_SUPABASE_ANON_KEY`, the UI tests forward them, and the `ios-ui-tests` job resets the project with `supabase db reset --db-url` and runs the suite with one retry. The job stays green with a notice until the secrets exist.

**Does it use the Volee slot? Yes, and Alex was right.** The 2026-09-12 version of this section said the free plan is two projects per organization. It is two active free projects per *user* across every org they own: `supabase projects create fxe-ci` on 2026-09-13 was refused with "Alex-Epstein (2 project limit)", because Volee and `fxe-tennis` already fill it. Three ways out, cheapest first:

1. **Pro on the FXE org, $25/month.** Removes the pause-after-a-week risk and adds point-in-time recovery for production (row D3 wanted this before real members anyway). The extra `fxe-ci` micro project on a Pro org bills about $10/month on top. Roughly $35/month total.
2. **A second free owner.** A free org owned by someone else (Tara's own Supabase account, or an account Alex creates for the club) gets its own two free slots. Zero cost; one more login to keep track of, and Alex would need to be invited as an admin.
3. **No project: keep running the UI suite on a laptop before every TestFlight build**, and record the run in the changelog. Free, honest, and the weakest of the three.

What it needs from Alex once a project exists: its database password stays with him; set three things in GitHub, Settings → Secrets and variables → Actions: secret `CI_SUPABASE_DB_URL` (the session-pooler connection string, port 5432), secret `CI_SUPABASE_ANON_KEY` (the project's publishable key), and variable `CI_SUPABASE_URL` (`https://<ref>.supabase.co`). The next Swift change then runs the suite. Guardrail: the CI project holds seed data only, never Tara's.

---

## Done log

Rows stay in their tables with DONE; this is the short history.

- 2026-10-12: I9 round five answered (decision 0040).
- 2026-10-05: D14 sign-up and email limits raised.
- 2026-10-04: A7 Tara's live Stripe account active.
- 2026-09-28: I2, I3 the polish round merged.
- 2026-09-27: A1, A8 Stripe keys and webhook; D12 the consent purge's first run; D2 and D0 re-verified.
- 2026-09-22: D10 encrypted backups.
- 2026-09-21: C5 account deletion; A3 Tara's policy answers.
- 2026-09-12: C4 privacy manifest; E9 Stripe SDK pinned; D4 restore drill; the docs audit.
