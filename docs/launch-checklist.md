# Launch checklist: the single source of truth for what is left

**Launch target: the launch party, Friday 2026-11-06** (moved from 2026-10-16 by Tara on 2026-09-28, decision 0024; she would go earlier if the app is ready). Passed: members book and pay in the app every day (State today).

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
   re-derivation: **2026-11-12**, by the model, each check named in the row
   (`scripts/live-status.sh`, read-only queries, the management API, `gh`,
   `git`, Apple's public lookup). Before that 2026-10-21 (four read-only
   reviewers in parallel) and 2026-09-28. Re-derived
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

## State today (re-derived 2026-11-12)

- **Code:** `main` is `081d1ce` (PR #141 merged 2026-11-11), version 1.0.3;
  build 18's number is PR #143. Green on iOS 26.0 and 18.6 on 2026-11-11 for
  fingerprint `6ada1b648d7e55d7` (`docs/ui-test-runs.log`), the code build 18
  was archived from. The pros' rounds (decision 0056) wait in PR #142 for
  1.0.4.
- **At Apple:** FXE Tennis is on **Volee LLC's** account (team `FBJXDTHTN4`)
  since the App Transfer of 2026-11-11 (C12). The App Store has 1.0.2,
  released 2026-11-07, seller Volee LLC
  (`curl "https://itunes.apple.com/lookup?bundleId=com.fxetennis.app"`,
  2026-11-12). 1.0.3 build 17 went up under John's team minutes before the
  transfer and did not carry over; build 18, the same code signed by the LLC
  (tag `v1.0.3-18`), was uploaded and submitted for review by John on
  2026-11-12.
- **Hosted:** 86 of 87 migrations applied, newest `20261111000001`
  (read-only query of `supabase_migrations.schema_migrations`, 2026-11-12);
  `20261111000002` (the pros' rounds) is pushed when PR #142 merges;
  the project is ACTIVE_HEALTHY (management API). **Payments live** since
  2026-10-14: 166 charges succeeded, 3 refunds, 0 failed; 338 member
  accounts, 218 with a saved card. Push: 631 of 719 delivered in 14 days, 302
  devices (`scripts/live-status.sh`, 2026-11-12). 14 clinics published
  through 2026-11-20 (read-only query).
- **Tests:** 59 SQL probes plus 19 shell probes, 330 unit tests, 29
  XCUITests, 87 browser tests (`scripts/check-doc-claims.sh`, 2026-11-12).
- **Waiting on others:** Apple's review of 1.0.3 (18); Tara: the juniors
  decisions and the open questions (`docs/questions-for-tara.md`).

---

## 0. The critical path to 2026-11-06

What had to be true on the day, in the order it had to happen. Each item is
a row below; this list adds nothing of its own. The party has passed; kept as
the record. Re-derived 2026-11-12.

1. **Apple approves 1.0.0** (C14): done 2026-10-27.
2. **Release** (C14): done 2026-10-28, tagged `v1.0.0` 2026-10-30. Testers
   move to it from the App Store. 1.0.1 (build 13) uploaded 2026-10-30 without
   the Waitlist wording (PR #116), which needs the build after it. 1.0.2 on
   the App Store since 2026-11-07; 1.0.3 (18) in review since 2026-11-12.
   [John]
3. **Real payments**: live since 2026-10-14 (A9, A10); receipts off
   (2026-10-21); dispute emails in Tara's own login still to check (A14).
   [Tara]
4. **Decision 0041's server side**: held 2026-11-05. Decision 0047 moves a
   Waitlist player straight in unless it is the same day, and 0045 covers
   members, so what is left of 1-hour offers waits on question 141. [Tara]
5. **Tara's email to members** with the QR code and the App Store link (G8,
   I6). [Tara]
6. **Push seen on a real lock screen** (C3): done 2026-11-05.
7. **The move to the LLC** (C1, C12): done 2026-11-11: App Transfer
   accepted, the LLC's APNs key on hosted the same day (C2), build 18 signed
   by the LLC. [John]
8. **Supabase Pro** (D3): deferred by Alex on 2026-10-21; the keep-warm job
   and our own nightly backup cover it until then. [Alex]

---
## A. Payments

| ID | Item | Owner | Status |
|---|---|---|---|
| A1 | Stripe sandbox keys in Supabase's Edge Function secrets | [Alex] | **DONE 2026-09-27** (sandbox). Replaced by live keys 2026-10-14 (A10): the secrets API shows `STRIPE_SECRET_KEY`, `STRIPE_PUBLISHABLE_KEY` and `STRIPE_WEBHOOK_SECRET` updated 2026-10-14T23:20 UTC (read 2026-10-21) Unchanged 2026-11-12 (`scripts/live-status.sh`) |
| A2 | End-to-end payment test on the real app in Stripe's sandbox, Alex's own account (`docs/stripe-e2e-test.md`, eight rows) | [Alex]+[me] | **LATER**: overtaken on 2026-10-14 by the real thing (A10: a live card saved, a $23 charge and its refund on Alex's account); it returns with A13 if the Stripe code changes |
| A3 | Tara's payment-policy answers | [Tara] | **DONE 2026-09-21** (decisions 0012, 0013) |
| A4 | Her policy in the code: no courtesy, 3 hours, no-shows, her one tap per clinic, card required, card permission | [me] | **DONE 2026-09-26** (20260916000001, 20260921000001, 20260926000001; probes `cancellation_policy`, `late_cancellation`, `card_consent`) |
| A5 | Refund when she cancels a clinic | [me] | **DONE 2026-09-16**, moot: nothing is charged before a clinic ends (her answer 7) |
| A6 | Payment history for players: the Past section of My Clinics; Stripe email receipts not decided | [me] | **DONE 2026-10-21**: Past shipped 2026-09-21; no Stripe receipts by Tara's choice (question 86, "No receipts"); Stripe's successful-payment and refund emails both off (Alex 2026-10-21, `docs/live-facts.md`) |
| A7 | Stripe live mode: activate with Tara's business and bank details, typed into Stripe's own form only; move the account's ownership to Tara | [Alex]+[Tara] | **DONE 2026-10-04**: Tara owns the account (transferred 2026-10-03); the LLC's EIN replaced the SSN in Stripe's business details; Payments and Payouts both Active (Alex, 2026-10-04). Tara has no accountant, so the SSN-or-EIN question is closed (Alex, 2026-10-05). Single-member LLC, statement descriptor FXE TENNIS, Radar Lite, tax off. Watch her email for Stripe's follow-ups |
| A8 | Webhook destination for hosted, five events | [Alex] | **DONE 2026-09-27**, with A1 (sandbox). Live endpoint "FXE app" with nine events since 2026-10-14 (A10, `docs/live-facts.md`) |
| A12 | Three more webhook events for chargebacks (`charge.dispute.created`, `.updated`, `.closed`), on the test endpoint now and the live one later (decision 0021) | [Alex] | **DONE 2026-10-01** on the test endpoint, and on the live endpoint "FXE app" since 2026-10-14 (nine events, A10). Not yet seen working: no dispute on hosted (`payments` kinds are `clinic_fee` and `refund` only, read 2026-10-21) Still no dispute 2026-11-12 (read-only query) |
| A9 | Switch payments on (`payments_enabled` true **and `payments_enabled_at` = now(), in the same migration**, decision 0018: nothing that ends before that moment is ever owed or charged). From that moment nobody registers or accepts an invitation without a saved card (decision 0040) | [me] | **DONE** 2026-10-14: `20261014000005_payments_on` pushed to hosted after the cutover. `scripts/live-status.sh` 2026-10-21: `payments_enabled` and `payments_enabled_at` set, live charges succeeded 3 and refunds 1 (Alex's $23 test, refunded; two members at $22 on Oct 17), 0 failed, 0 waiting. Alex said go before Apple's review because build 7 already reads the publishable key from the server Re-read 2026-11-12 (`scripts/live-status.sh`): 166 charges succeeded, 3 refunds, 0 failed, 0 waiting |
| A10 | Live keys: a restricted key with only the permissions our code uses, a live webhook with the nine events (the ninth, `payment_method.detached`, since 2026-10-13), the three secrets swapped, and at the same moment the cutover that forgets every sandbox card so everyone adds a real one (`stripe_cutover_to_live`, `20260927200001`, built in PR #75, H2) | [me]+[Alex] | **DONE** 2026-10-14: restricted key "FXE app server", live webhook "FXE app" with nine events, three secrets set on hosted 2026-10-14 23:20 UTC, cutover `20261014000004` pushed (`stripe_live_since` set); a live `setup_intent.succeeded` wrote a card the same evening (`scripts/live-status.sh`, `docs/live-facts.md`) |
| A11 | **Real money at the party**: payments fully live at the party (2026-11-06; it was 2026-10-16 until Tara moved it) (Alex, 2026-09-27: *"yes we want it fully done"*; promo codes "prob not"). The fallback if the live switch (A13, A10, A9) is not done by **2026-11-04**: payments stay off for the party | [Alex]+[Tara] | **DONE** 2026-10-14: payments live three weeks before the 11-04 gate (A9, A10; `scripts/live-status.sh` 2026-10-17) |
| A13 | Rehearsal before the live switch: a restricted key in Stripe's **sandbox** carrying exactly the live key's permissions, and the model runs save a card, a charge after a clinic, a refund, a declined card and a 3-D Secure card against real Stripe test mode (a restricted key missing one permission makes saving a card fail silently; nothing has talked to real Stripe yet, only the mock). The gate for A10 | [Alex]+[me] | **LATER**: Alex skipped it on 2026-10-14 ("we dont rlly need to rehearse"); the real charge and refund on his own card stood in for it. `tests/stripe/rehearsal.sh` stays ready for a change to the Stripe code |
| A14 | Three Stripe settings on the live account: customer receipts off (Tara: "No receipts", question 86), payouts to her bank on a Daily schedule, dispute emails on in Tara's own login | [Alex]+[Tara] | **OPEN**: receipts off (successful-payment and refund emails, Alex 2026-10-21) and daily payouts to her bank (2026-10-16) both verified (`docs/live-facts.md`); dispute emails in Tara's own login not yet checked; steps in `docs/for-alex.md` Not readable by command; unchanged as of 2026-11-12 |
## B. Stripe steps

One copy only: `docs/for-alex.md` §1 (done 2026-09-27; kept for live mode).
What Stripe takes: 2.9% + 30¢ per card charge. Apple takes nothing (decision
0009). Payouts to Tara's bank need live mode (A7).

## C. App Store and Apple

| ID | Item | Owner | Status |
|---|---|---|---|
| C1 | Apple Developer Program enrollment as FXE Tennis, LLC (Apple asked for the ID, employment verification and a business document on 2026-08-26; Tara sent them) | [Tara]/[Apple] | **DONE 2026-11-11**, by another road: Apple never approved the FXE Tennis, LLC enrollment (case 102990597020, enrollment L6R8KDC88Y). Since 2026-10-25 (Alex: *"volee just got an LLC acct approved, and for now were gonna have both volee and LLC under Volee's llc acct!"*) the plan was Volee's LLC account, and FXE moved there by App Transfer on 2026-11-11 (C12). The FXE Tennis, LLC enrollment is no longer needed |
| C2 | Bundle id, Team ID, App Store Connect record and APNs key under the LLC | [John] | **DONE 2026-11-11**: the App Transfer moved `com.fxetennis.app` and its App Store Connect record to Volee LLC (team `FBJXDTHTN4`); the LLC's APNs key `42D24JXB54` set on hosted the same day; in the last 2 days hosted delivered 110 of 123 notifications (12 `no_device`, 1 `TopicDisallowed` at the moment of the transfer; read-only query 2026-11-12). Build 18 is signed by the LLC (archive's application identifier `FBJXDTHTN4.com.fxetennis.app`) |
| C3 | Push notifications on the lock screen: sender, trigger and audit columns deployed 2026-09-23 (#61); the app's half (banner while open, tap opens the clinic, badge clears, Accept and Decline on the lock screen) merged in PR #75 (H5) | [me] | **DONE** 2026-11-05: Alex saw a test push on his iPhone ("Yes, got it"), sent straight through Apple with the new key `94698TDPGY` (HTTP 200 on both his devices; set on hosted 2026-11-06 01:14 UTC). Separately, the server's own path delivered its first two notifications after the key (`scripts/live-status.sh`: sent 50, delivered 2, failed 48, all 48 from before the key). Before it no push had ever been delivered: key `75U93U9VS6` of 2026-10-03 was not valid for production push (`BadEnvironmentKeyInToken`). A push from the server seen on a phone is still part of H8 Re-read 2026-11-12: 631 of 719 delivered in 14 days, 302 devices (`scripts/live-status.sh`) |
| C4 | Privacy manifest | [me] | **OPEN**: `FXETennis/Resources/PrivacyInfo.xcprivacy` unchanged since 2026-09-12 (`git log`, 2026-11-12) declares Name, Email, Phone, User ID and Payment Info; build 10 added the note to Tara (Other User Content) and build 12 crash reports (Crash Data, Performance Data), and Purchase History is declared in App Store Connect. Builds 13 to 18 did not change it. Fix in the next build [me] |
| C5 | Delete my account in the app, history kept (guideline 5.1.1(v)) | [me] | **DONE 2026-09-21**; `delete-account` deployed the same day |
| C6 | Privacy policy at a public URL | [Tara] | **DONE 2026-09-27**: Tara approved it ("looks good"), contact fersctennispro@gmail.com; published at `https://fxe-tennis-admin.vercel.app/privacy.html` (verified by `deploy-web.sh`) and linked from Profile in the app (build 4) |
| C7 | App Store listing: name, subtitle, description in Tara's words, screenshots, age rating, support URL, review notes with a test account | [Alex]+[me] | **DONE** 2026-10-21 (Alex: "he submitted before i saw this"): John filled the listing from `docs/for-alex.md` §4c and submitted. The description went as drafted; its approval tick and the support page's are still open in `docs/copy-review.md` (G4); a change is an edit in App Store Connect |
| C8 | TestFlight for testers: the group and the build it gets (the row was build 11, which was never uploaded) | [John] | **LATER** [John]: players install from the App Store now (1.0.2, C14), not TestFlight. The App Transfer of 2026-11-11 likely emptied the testers' list, as Volee's own transfer did; set the group up again under the LLC only if TestFlight is wanted |
| C9 | Real-device pass: the two simulator flakes checked on an iPhone | [John]/[me] | **LATER** [John]: 302 real phones run the app (`scripts/live-status.sh`, 2026-11-12) and no one has reported either flake; check on a real iPhone if one is |
| C10 | An annotated git tag at every TestFlight build and upload | [me]/[John] | **DONE 2026-11-12**: every App Store upload since 1.0.2 has an annotated tag: `v1.0.2`, `v1.0.3` (build 16), `v1.0.3-17`, `v1.0.3-18` (`git cat-file -t` reads `tag` for each, 2026-11-12), and `v1.0.0` on `2f5888d`. 1.0.1's builds 13 and 14 have none. Earlier: `v0.1.0-rc4` to `rc12`, upload tags for builds 2, 5, 7 and 12; `v0.1.0-tf2` is lightweight |
| C11 | External TestFlight on John's account with a public link, through Apple's beta review, with no testers invited until the soft launch (G7) | [Alex]/[John] | **LATER**: not needed: the QR link and the website send people to the App Store listing (I6; `web/app/target.js` and the live `/app/target.js`, 2026-11-12) |
| C12 | Move the app to Volee's LLC developer account (approved 2026-10-25; was the FXE Tennis LLC, C1): App Transfer of `com.fxetennis.app` from John's account (possible once it has an App Store release, C14), then the LLC's APNs key on hosted | [John] | **DONE 2026-11-11**: John transferred FXE to Volee LLC's developer account (team `FBJXDTHTN4`); push moved to the LLC's key the same day (C2); build 18 is the first LLC-signed build. Left: TestFlight testers, if wanted (C8) |
| C13 | How Apple's reviewer signs in: one real account called App Review, made through the app's own sign-up with an address Alex controls, left out of the board report; while keys are sandbox the review notes give Stripe's 4242 test card | [John] | **DONE 2026-11-12**: John signed in with the login in App Store Connect's App Review Information while 1.0.3 was in review ("it worked"). The first reviewer account, made 2026-10-20 through the TestFlight app, was deleted 2026-10-21 18:30 UTC (read-only query, 2026-11-12); the review notes hold a working one |
| C14 | **App Store release, build 12, on John's account** (decision 0042): PR #97 merged green, tag `v0.1.0-rc12`, John uploads and submits version 1.0.0 with the review account (C13) and the listing (C7); Tara has the next week's clinics published so the reviewer sees some | [me]+[John]+[Alex] | **DONE** 2026-10-28: Apple approved 1.0.0 on 2026-10-27 (its email, forwarded by Kat to the group text) and it was released 2026-10-28 (`curl "https://itunes.apple.com/lookup?bundleId=com.fxetennis.app"`: version 1.0.0, releaseDate 2026-10-28, 2026-10-30); Tara found it in App Store search on 2026-10-29 (group text). Left from this row: the `v1.0.0` tag (C10) Since then: 1.0.2 released 2026-11-07 (Apple's lookup, seller Volee LLC, 2026-11-12); 1.0.3 build 18 submitted 2026-11-12 |
## D. Backend and operations

| ID | Item | Owner | Status |
|---|---|---|---|
| D0 | "Confirm email" off on hosted (decision 0011) | [Alex] | **DONE**; verified 2026-09-27 through the management API (`mailer_autoconfirm` true). Re-check on any new project Re-read 2026-11-12 (management API): `mailer_autoconfirm` true |
| D1 | **A real email sender, so "Forgot password?" reaches members** | [Alex] | **DONE 2026-09-27**: Gmail `fxetennis.app@gmail.com` with an app password as custom SMTP; read back through the management API (`smtp_host` smtp.gmail.com, port 465, sender "FXE Tennis"). Delivery confirmed by Alex 2026-10-01: *"the reset emails came in just took a while"* Re-read 2026-11-12 (management API): smtp.gmail.com, port 465, sender "FXE Tennis" |
| D2 | Reset page allow-listed as a redirect on hosted | [Alex] | **DONE 2026-09-01**; verified 2026-09-27 (`uri_allow_list` is `https://fxe-tennis-admin.vercel.app/reset.html`) Re-read 2026-11-12 (management API): `reset.html` on `fxe-tennis-admin.vercel.app`, `fxeclinics.com` and `www.fxeclinics.com` |
| D3 | Supabase plan: the free tier pauses after a quiet week and has no point-in-time recovery; Pro is $25 a month | [Alex] | **LATER**: Alex, 2026-10-21: *"ig were fine for now, we dont rlly need it yet"*. What covers the gap meanwhile: real members use it daily now, the nightly keep-warm job pings it, and the nightly encrypted backup (restore drill passed 2026-10-12, D4). Revisit if the project pauses or before a busy season Re-read 2026-11-12: the project is ACTIVE_HEALTHY (management API) |
| D4 | Restore drill (a backup nobody has restored is not a backup) | [me] | **DONE 2026-11-03**: the 2026-11-02 nightly backup (run 41483885958) decrypted with Alex's key and restored into a throwaway `supabase/postgres:17.6` container after `drop schema auth cascade`; one harmless error ("schema public already exists"). Restored: 26 sign-ins, every migration through `20261101000001`, 24 accounts, 24 players, 37 clinics, 31 registrations, 6 payments. Hosted at the same moment: 28, 73, 24, 24, 37, 32, 6, and exactly 2 sign-ins and 1 registration on hosted postdate the backup (read-only query), so every row the backup should hold came back. Container and decrypted dump deleted. Monthly; next due 2026-12-03 The nightly backup succeeded 2026-11-12 (run 43250303851); 2026-11-11's failed on the runner's DNS (apt could not resolve its mirror) and the next night's passed |
| D5 | Tara's real templates and clinics in hosted, through the admin site | [Tara] | **DONE 2026-10-11**: her real clinics are on hosted from 2026-10-04 (read-only query 2026-10-21). Re-read 2026-11-12: 14 published clinics ahead, through 2026-11-20 (read-only query) |
| D6 | Crash reporting and error alerts: MetricKit crash and hang reports into `app_diagnostics` through `report_app_diagnostic` (decision 0035) | [me]/[Alex] | **OPEN**: shipped in build 12 (PR #97 merged 2026-10-19; hosted has `20261014000001` and `20261014000002`, 69 of 69 paired; the live privacy page carries the MetricKit sentence; the nightly retention job runs `purge_app_diagnostics()`). Not yet seen end to end: `app_diagnostics` has 0 rows on hosted (2026-10-21), expected until a build-12 phone reports Re-read 2026-11-12: still 0 rows, with 302 devices on hosted; either no phone has crashed or reports are not arriving |
| D7 | Rate limits on the public functions and sign-up | [me] | **LATER**: low risk at club scale |
| D8 | Drop the dead `clinics.price_cents` column | [me] | **LATER** |
| D9 | Data export for Tara | [me] | **LATER** (v1.1) |
| D10 | Encrypted nightly backups | [Alex] then [me] | **DONE 2026-09-22** (age key; first encrypted run decrypted and checked) |
| D11 | Hosted "Site URL" and the reset email's link (decision 0017) | [me] | **DONE 2026-09-27**: Site URL `https://fxe-tennis-admin.vercel.app`; the reset email now links `{{ .SiteURL }}/reset.html#token_hash=…&type=recovery` (read back through the management API once custom SMTP made templates editable) Re-read 2026-11-12 (management API): Site URL unchanged |
| D12 | Nightly purge of card consents 90 days after an account is deleted | [me] | **DONE 2026-09-27**: the `retention` job ran on hosted, "Card consents purged ...: 0" |
| D13 | **Tara can reset any member by hand**: Players tab → Reset link → Copy → text it. One-time, within an hour, no email, every link audited (`admin-reset-link`, decision 0017) | [me] | **DONE 2026-09-27**: PR #73 merged; `supabase db push` applied 20260927000001; `admin-reset-link` deployed; `hosted-smoke.sh` 63 targets, 0 open; live page checked from outside |
| D14 | Sign-in and sign-up rate limits on hosted: every phone at the party shares the club Wi-Fi's one address | [me] | **DONE 2026-10-05** through the management API, read back: sign-ups 300 per 5 minutes per address, auth emails 100 an hour (earlier, 2026-09-27: `rate_limit_verify` 30 → 300, `rate_limit_token_refresh` 150 → 500 per 5 minutes per IP) Re-read 2026-11-12 (management API): emails 100 an hour, verify 300, token refresh 500, OTP 300 |
| D15 | How many courts the club has | [Tara] | **DONE 2026-09-27**: 5 (Alex), which is exactly what the app allows (1 to 5); no change needed |
| D16 | The website deploys itself from GitHub on every merge to `main` that touches `web/` (`deploy-web.yml`), verified byte for byte, so John can ship without Alex's laptop | [Alex] | **DONE 2026-10-25**: all three secrets set (`gh secret list`); the first run on the merge of PR #106 deployed and matched the live site byte for byte on attempt 1 (`gh run view 40162237668`). Any merge to `main` touching `web/` now ships itself Last run 2026-11-11 succeeded (`gh run list`, 2026-11-12) |
## E. Testing

The rule (CLAUDE.md, verification asymmetry): the thing that builds a feature
cannot be the thing that certifies it, so every layer below is a different
observer.

| Layer | Runs where | Count (derived 2026-11-12 unless dated) | Gap |
|---|---|---|---|
| SQL probes (rules, privileges, attacks, concurrency) | every PR, and locally | 59 probes plus 19 shell probes (the races and the 200-request rush); the suite prints its own check total | none known |
| Stripe pipeline against stripe-mock | every PR | 94 checks as of 2026-09-28 | real Stripe behaviour: one live charge and refund, 2026-10-14 (A10) |
| Push pipeline against a mock APNs | every PR | 57 checks as of 2026-09-28 | real APNs delivering since 2026-11-05 (C3) |
| Web admin browser tests (Playwright, real sign-in) | every PR | 87 | a cold-start flake after a local reset (backlog) |
| Swift unit tests (pure logic) | every PR | 330 | fine |
| Hosted signed-out smoke (`scripts/hosted-smoke.sh`) | every PR, read-only against production | 162 targets as of 2026-10-11, including a browser preflight to each function the web admin calls | only the signed-out side |
| XCUITests, player and admin flows, and Apple's accessibility audit | **local only** (section F) | 29 | run on a laptop before every TestFlight build, on iOS 17, 18 and 26 (`docs/ui-test-runs.log`) |
| Copy gate, secret scan (now Stripe keys too), migration immutability, icon gate, doc checks | every PR | – | none |
| Nightly backup and consent purge | nightly | – | restored by hand monthly (D4, last 2026-11-03) |

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
| G2 | Tara's review page, **round six**: only her 14 unseen words and 5 laptop tasks, no Questions tab (page version 6, `scripts/build-tara-review.py`). Round four was answered 2026-09-28 (decision 0024) and round five's questions 2026-10-12 (decision 0040); `review-watch.yml` opens an issue whenever she saves | [John] sends, [Tara] answers | **LATER**: Tara answers by text now (decisions 0051 to 0056). Re-read 2026-11-12: no round-six link minted (hosted `review_links` newest 2026-09-28; `review_responses` page versions 2 and 4 only). Mint one from the admin site's Testing tab only if wanted (`docs/for-alex.md` §5) |
| G3 | Kat's calls: the tab bar colour, the green text contrast, the green line under the header; and her earlier "tag spec" line (release tags, answered by C10, or analytics tags, not built; `docs/kat-due-diligence.md`) | [Kat] | **DONE 2026-10-01**: keep the system tab bar, the darker green for text, keep the green line (decision 0036); her "tag spec" line is answered by the release tags (C10) |
| G4 | Alex's ticks in `docs/copy-review.md` (sections G to J and the older open rows) | [John] | **OPEN** (Alex stepped back 2026-10-30; John approves) |
| G5 | Tara's logo file and the original court photo | [Tara] | **DONE 2026-10-01**: the logo (the gator in colour, decision 0032, 2026-09-29) and the court photo, which is the one from her 2026-09-26 mockup, in the app since then (Alex, 2026-10-01: *"its legit in the app alr"*); a full-size original would only make it sharper |
| G6 | GitHub: require the hosted smoke check and stop admins bypassing `main`'s protection. Dependabot alerts are already on (verified 2026-09-27) | [Alex] | **DONE 2026-10-12**: `gh api repos/Volee-Team/FXE/branches/main/protection` (2026-10-21): `enforce_admins: true`, 15 required checks including the hosted smoke check. Dependabot alerts on (2026-09-27) Re-read 2026-11-12: `enforce_admins` true, 15 required checks |
| G7 | The soft launch: the date, and the first 20 to 30 testers who get the public link | [Alex]+[Tara] | **DONE 2026-11-06**: no separate soft launch; members install from the App Store (C14), 338 member accounts on hosted (`scripts/live-status.sh`, 2026-11-12) |
| G8 | Tara's email to members with the QR code and the public link (question 75, I6); we check her steps before it goes | [Tara] | **OPEN**: her words (question 75 answered 2026-09-28, decision 0024). The QR link (`/app`) gets its target when 1.0.0 is released (C14), or C11's public link if that path is used Not visible to the model; 338 member accounts on hosted (2026-11-12) say members found the app |
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
| H7 | **Payouts on the Money tab** (the balance, the next deposit and its date; Tara's "when will $ be in my account") and dispute alerts in Action Needed, so Tara never needs the Stripe dashboard day to day | [me] | **DONE 2026-09-28.** On hosted: `supabase migration list --linked` pairs `20260928200001`; `supabase functions list` shows `stripe-payouts` v1 and `stripe-webhook` v8 ACTIVE; the live `index.html` carries the Payouts card (`curl ... | **DONE 2026-09-28.** On hosted, `20260928200001` is applied (69 of 69 paired, 2026-10-21) and the functions API shows `stripe-payouts` v7 and `stripe-webhook` v18 ACTIVE; the live `index.html` carries the Payouts card (curl, 2026-10-21) |
| H8 | Walk on a real phone what the simulator could not: a push tapped with the app in the background, the Home spinner on a slow connection, Accept and Decline on the lock screen, a haptic | [John]/[me] | **OPEN**: walk it on the newest build (1.0.3 build 18, in review 2026-11-12). Push now reaches phones: 631 of 719 delivered in 14 days (C3, `scripts/live-status.sh` 2026-11-12) |
## I. Polish for the party (2026-09-28)

Alex, 2026-09-27: *"do as MUCH as you possibly can w building and testing
everything ... make the app as POLISHED as possibly and best feeatures"*.
Four branches, three of them built by separate agents from a written brief,
each checked by an independent reviewer or the sql-auditor, then merged on
`polish-0928` and verified there as one.

| ID | Item | Owner | Status |
|---|---|---|---|
| I1 | Tara's notification catalogue in her words, from the database (#1, #3, #5, #6, #13 to #15), one message per event under a double tap (decision 0022) | [me] | **DONE 2026-09-28.** On hosted, `20260928000001` and the uninvite message `20260928500001` (decision 0024) are applied, 69 of 69 paired (2026-10-21) |
| I2 | Accept and Decline on the invitation push; Add to Calendar (nothing about where); Remind me at the player's own opening; haptics and the chip's change (decision 0023) | [me] | **DONE 2026-09-28**: merged with `polish-0928` and in every build since (`v0.1.0-rc5` onwards). Seeing the lock-screen buttons on a real phone is H8 |
| I3 | Text anyone can read: Larger Text followed live, Apple's accessibility audit as a UI test on every main screen, the clock readable on navy, Return through the forms, page titles in the guide's serif, outlined tab icons (decision 0023) | [me] | **DONE 2026-09-28**: `FXETennisUITests/AccessibilityAuditUITests.swift` on `main`; the suite passed on iOS 26.2, 18.6 and 17.5 on 2026-10-19 UTC, fingerprint `96d01ac99a1a364c`, 288 unit and 27 UI (`docs/ui-test-runs.log`) |
| I4 | Payouts and chargebacks on the Money tab (H7, decision 0021); the Action Needed crash on the first declined card fixed | [me] | **DONE 2026-09-28**, with H7 |
| I5 | Tara's questions from this round: 79 narrowed, 88 to 90 new | [Tara] | **DONE 2026-09-28**: answered in round four (decision 0024); 92 to 95 are the next round's |
| I6 | The QR code for members (question 75): it points at `/app` on the admin site, which forwards to the install link, so the printed card never changes; Tara's printable card under Players → QR code for the app | [me]/[Alex] | **DONE** 2026-11-03: `INSTALL_URL` is the App Store listing `https://apps.apple.com/app/fxe-tennis/id6814658300` (Apple's lookup for `com.fxetennis.app`, 1.0.0 released 2026-10-28, C14); the browser test "the committed link is FXE Tennis on the App Store" pins it. Live `/app/target.js` carries it (curl, 2026-11-12) |
| I7 | Build 6 for players: instant open (decision 0028), Siri and Spotlight, Subscribe in Calendar (0029), every held clinic on Home, clean titles, placeholders, a declined card that says why (0026) | [me] | **DONE 2026-09-29**: PR #81 merged on 27 green checks; locally `Executed 232 tests, with 0 failures` (unit) and all 22 UI tests at the time (the declined-card one run with the local service key); tagged `v0.1.0-rc6` |
| I8 | Build 6 for Tara: pros and their Today screen (0025), Resolved (0026), saved messages (0030), a player's history, Copy to next week and the court sheet (0027); a clinic never published never reaches a player (20260929000001/2) | [me] | **DONE 2026-09-29**: `supabase db push` 60 of 60 paired, the six functions redeployed, `deploy-web.sh` matched byte for byte, `hosted-smoke.sh` 156 targets, 0 open |
| I9 | Tara's questions 92 to 100 and 73 on round five of her review page | [me]/[Alex] | **DONE 2026-10-12**: answered by text (decision 0040), all but 101 (Foxcroft's share, her meeting) |

## F. The CI Supabase project (Alex asked 2026-09-12; corrected 2026-09-13; decided 2026-09-18)

**Decided 2026-09-18: option 3.** Alex: *"nahh unless we really need it no more money for now."* No CI project, no Pro plan. The 29 XCUITests run on a laptop before every TestFlight build and the run is pasted into the changelog entry for that build; the `ios-ui-tests` job stays green with its notice until the three settings exist, so switching later is a dashboard visit and two secrets, nothing in the repo. Revisit when the first paying member exists (D3 wants point-in-time recovery then anyway). The rest of this section is kept as the record of why.


Alex gave the go-ahead on 2026-09-13 ("exact steps for me or can you do it all?"); the create was attempted the same day and refused, see below. Would it help a lot? Yes: it is the only way to run the 29 XCUITests on every PR, which is the layer that walks the app like a member does. The macOS runner has no Docker, so it cannot host the local stack; a small hosted project it can reset to the seed is the practical answer. Everything on our side is built and waiting (2026-09-13): the Debug app accepts `FXE_SUPABASE_URL` / `FXE_SUPABASE_ANON_KEY`, the UI tests forward them, and the `ios-ui-tests` job resets the project with `supabase db reset --db-url` and runs the suite with one retry. The job stays green with a notice until the secrets exist.

**Does it use the Volee slot? Yes, and Alex was right.** The 2026-09-12 version of this section said the free plan is two projects per organization. It is two active free projects per *user* across every org they own: `supabase projects create fxe-ci` on 2026-09-13 was refused with "Alex-Epstein (2 project limit)", because Volee and `fxe-tennis` already fill it. Three ways out, cheapest first:

1. **Pro on the FXE org, $25/month.** Removes the pause-after-a-week risk and adds point-in-time recovery for production (row D3 wanted this before real members anyway). The extra `fxe-ci` micro project on a Pro org bills about $10/month on top. Roughly $35/month total.
2. **A second free owner.** A free org owned by someone else (Tara's own Supabase account, or an account Alex creates for the club) gets its own two free slots. Zero cost; one more login to keep track of, and Alex would need to be invited as an admin.
3. **No project: keep running the UI suite on a laptop before every TestFlight build**, and record the run in the changelog. Free, honest, and the weakest of the three.

What it needs from Alex once a project exists: its database password stays with him; set three things in GitHub, Settings → Secrets and variables → Actions: secret `CI_SUPABASE_DB_URL` (the session-pooler connection string, port 5432), secret `CI_SUPABASE_ANON_KEY` (the project's publishable key), and variable `CI_SUPABASE_URL` (`https://<ref>.supabase.co`). The next Swift change then runs the suite. Guardrail: the CI project holds seed data only, never Tara's.

---

## Done log

Rows stay in their tables with DONE; this is the short history.

- 2026-11-11: C1, C2, C12 FXE on Volee LLC's account, push on the LLC's key.
- 2026-11-06: G7 launched at the party.
- 2026-10-12: I9 round five answered (decision 0040).
- 2026-10-05: D14 sign-up and email limits raised.
- 2026-10-04: A7 Tara's live Stripe account active.
- 2026-09-28: I2, I3 the polish round merged.
- 2026-09-27: A1, A8 Stripe keys and webhook; D12 the consent purge's first run; D2 and D0 re-verified.
- 2026-09-22: D10 encrypted backups.
- 2026-09-21: C5 account deletion; A3 Tara's policy answers.
- 2026-09-12: C4 privacy manifest; E9 Stripe SDK pinned; D4 restore drill; the docs audit.
