# Launch checklist: the single source of truth for what is left

**Launch target: the launch party, Friday 2026-11-06** (moved from 2026-10-16 by Tara on 2026-09-28, decision 0024; she would go earlier if the app is ready).

How this file works, so it can be trusted:

1. **If something is left to do before launch, it is a row here, and only
   here.** Other files hold the detail a row links to: `docs/for-alex.md`
   (click-by-click steps for Alex's rows), `docs/questions-for-tara.md` (the
   questions' wording), `docs/mvp.md` (notes for the MVP call),
   `docs/backlog.md` (bugs that do not block launch). `docs/whats-next.md`
   describes the state of the app and holds no tasks. (Alex, 2026-09-27: *"i
   like having one thing to totally trust"*.)
2. **Every row has an owner and a status.** Owner in brackets: [Alex],
   [Tara], [Kat], [John], [me] for the model, [Apple], [Stripe]. Status starts
   with one word: **DONE** (with the date and the evidence), **OPEN**,
   **BLOCKED** (on what), **DECIDE** (whose call), or **LATER** (after launch).
3. **A status is re-derived by command, never copied forward.** Last full
   re-derivation: **2026-09-28**, each check named in the row.
4. **A machine keeps the format honest.** `scripts/check-launch-checklist.sh`
   runs in CI: it fails when a row has no owner or no status word, when a
   DONE has no date, or when `docs/for-alex.md` points at a row that does not
   exist.

---

## 0. The critical path to 2026-11-06

What must be true on the day, in the order it has to happen. Each item is a
row below; this list adds nothing of its own. Re-derived 2026-09-28.

1. **Build 7 is on the testers' phones** (C8): tag `v0.1.0-rc7`, everything
   below in section I plus the MVP-audit fixes. [John]
2. **Payments on, then tested, then live in Tara's name** (A9, A2, A7, A10,
   A12): on after build 7 is on phones; Tara's live activation by 2026-11-04
   is the gate (A11). [Alex, Tara, me]
3. **Push on the lock screen** (C3): John makes the key, Alex sets five
   secrets; the Accept and Decline buttons and her words are already built.
   [John, Alex]
4. **Members can install the app on the day** (C1, C11): the privacy URL is
   live (C6), so the external TestFlight review can be requested now; decide
   the path by 2026-10-09. [Alex]
5. **Tara's real clinics are in the admin** (D5). [Tara]
6. **One real "Forgot password?" email** to Alex's own address (D1). [Alex]
7. **Tara's open answers and Kat's style calls** (G2, G3). Every default is
   built, so these improve the launch rather than block it, except question
   75 (how members hear about the app).

---

## A. Payments

| ID | Item | Owner | Status |
|---|---|---|---|
| A1 | Stripe sandbox keys in Supabase's Edge Function secrets | [Alex] | **DONE 2026-09-27.** `supabase secrets list` shows `STRIPE_PUBLISHABLE_KEY`, `STRIPE_SECRET_KEY`, `STRIPE_WEBHOOK_SECRET`; a forged request to `stripe-webhook` answers `bad_signature`, so the signing secret is loaded |
| A2 | End-to-end payment test on the real app in Stripe's sandbox, Alex's own account (`docs/stripe-e2e-test.md`, eight rows) | [Alex]+[me] | **BLOCKED** on A9 |
| A3 | Tara's payment-policy answers | [Tara] | **DONE 2026-09-21** (decisions 0012, 0013) |
| A4 | Her policy in the code: no courtesy, 3 hours, no-shows, her one tap per clinic, card required, card permission | [me] | **DONE 2026-09-26** (20260916000001, 20260921000001, 20260926000001; probes `cancellation_policy`, `late_cancellation`, `card_consent`) |
| A5 | Refund when she cancels a clinic | [me] | **DONE 2026-09-16**, moot: nothing is charged before a clinic ends (her answer 7) |
| A6 | Payment history for players: the Past section of My Clinics; Stripe email receipts not decided | [me] | **LATER**: Past shipped 2026-09-21; receipts after launch |
| A7 | Stripe live mode: activate with Tara's business and bank details, typed into Stripe's own form only; move the account's ownership to Tara (Settings, Team, Transfer ownership) | [Alex]+[Tara] | **OPEN**: after A2 passes |
| A8 | Webhook destination for hosted, five events | [Alex] | **DONE 2026-09-27**, with A1 |
| A12 | Three more webhook events for chargebacks (`charge.dispute.created`, `.updated`, `.closed`), on the test endpoint now and the live one later (decision 0021) | [Alex] | **OPEN**: two minutes in Stripe, `docs/for-alex.md` §1; until then no dispute reaches Action Needed |
| A9 | Switch payments on (`payments_enabled` true **and `payments_enabled_at` = now(), in the same migration**, decision 0018: nothing ends-before that moment is ever owed or charged). From that moment nobody registers without a saved card | [me] | **DECIDE** [Alex]: say go once build 4 is on the testers' phones. **Not for everyone while the keys are sandbox**: a real card is declined in test mode (MVP audit 2026-09-27) |
| A10 | Live keys: a restricted key with only the permissions our code uses, a live webhook, the three secrets swapped, and at the same moment the cutover that forgets every sandbox card so everyone adds a real one (built on branch `stripe-robustness`, MVP audit 2026-09-27) | [me]+[Alex] | **OPEN if payments are in at the party**, after A7; otherwise LATER |
| A11 | **Real money at the party**: payments fully live at the party (2026-11-06; it was 2026-10-16 until Tara moved it) (Alex, 2026-09-27: *"yes we want it fully done"*; promo codes "prob not"). The fallback if Tara's live activation (A7) is not done by **2026-11-04**: payments stay off for the party | [Alex]+[Tara] | **OPEN**: decided 2026-09-27, target live; A7 by 11-04 is the gate (moved with the party from 10-14; Alex to confirm) |

## B. Stripe steps

One copy only: `docs/for-alex.md` §1 (done 2026-09-27; kept for live mode).
What Stripe takes: 2.9% + 30¢ per card charge. Apple takes nothing (decision
0009). Payouts to Tara's bank need live mode (A7).

## C. App Store and Apple

| ID | Item | Owner | Status |
|---|---|---|---|
| C1 | Apple Developer Program enrollment as FXE Tennis, LLC (Apple asked for the ID, employment verification and a business document on 2026-08-26; Tara sent them) | [Tara]/[Apple] | **BLOCKED** on Apple: still processing on 2026-09-27 |
| C2 | Bundle id, Team ID, App Store Connect record and APNs key under the LLC | [Alex] | **BLOCKED** on C1 |
| C3 | Push notifications on the lock screen: sender, trigger and audit columns built and deployed 2026-09-23 (#61); the app's half (banner while open, tap opens the clinic, badge clears) on branch `push-client` | [me] | **OPEN**: decided 2026-09-27, yes, push fully working for launch; steps for John in `docs/for-alex.md` §3. every tester build, and the launch build if C11 is used, is signed by John's team, so an APNs key from **John's** account works now (the LLC's key could never reach those phones). Ask John for one (Keys, +, Apple Push Notifications service), then five function secrets and two vault entries (`docs/for-alex.md` §3). Only if G1 says push is in |
| C4 | Privacy manifest | [me] | **DONE 2026-09-12** (#37) |
| C5 | Delete my account in the app, history kept (guideline 5.1.1(v)) | [me] | **DONE 2026-09-21**; `delete-account` deployed the same day |
| C6 | Privacy policy at a public URL | [Tara] | **DONE 2026-09-27**: Tara approved it ("looks good"), contact fersctennispro@gmail.com; published at `https://fxe-tennis-admin.vercel.app/privacy.html` (verified by `deploy-web.sh`) and linked from Profile in the app (build 4) |
| C7 | App Store listing: name, subtitle, description in Tara's words, screenshots, age rating, support URL, review notes with a test account | [Alex]+[me] | **BLOCKED** on C1, or on C11's path |
| C8 | TestFlight **build 7** from the tag `v0.1.0-rc7` (build 6 plus the navy banner and the logo sizes, decision 0033; it carries everything in builds 5 and 6, so those can be skipped) | [John] | **OPEN**: `v0.1.0-rc7` is made when this merges (2026-09-29); John archives it per `docs/testflight.md` (`docs/for-alex.md` §4) |
| C9 | Real-device pass: the two simulator flakes checked on an iPhone | [Alex]/[me] | **BLOCKED** on C8 |
| C10 | An annotated git tag at every TestFlight upload | [me]/[John] | **OPEN**: `v0.1.0-tf2`, `v0.1.0-rc6` and (on merge) `v0.1.0-rc7` exist (2026-09-29); tag `v0.1.0-tf7` when John's upload of build 7 is processed |
| C11 | External TestFlight on John's account with a public link, submitted to Apple's beta review **this week** with no testers invited, so the review is done before it matters (needs C6's URL) | [Alex]/[John] | **OPEN**: C6 is done (the URL is live), so nothing blocks the request; decided 2026-09-27 (Alex: *"yes prob"*) |
| C12 | Bundle id for the LLC's app. `com.fxetennis.app` is tied to John's account now: Apple transfers only apps with at least one App Store release, and a TestFlight upload locks the id to that account. The LLC's app will need a new id, and testers install it fresh (their accounts carry over; they live on our server) | [Alex] | **DECIDE** [Alex] before the first LLC build |
| C13 | How Apple's reviewer signs in: one real account called App Review, made through the app's own sign-up with an address Alex controls, left out of the board report; while keys are sandbox the review notes give Stripe's 4242 test card | [Alex] | **DECIDE** [Alex] before the first external or App Store submission |

## D. Backend and operations

| ID | Item | Owner | Status |
|---|---|---|---|
| D0 | "Confirm email" off on hosted (decision 0011) | [Alex] | **DONE**; verified 2026-09-27 through the management API (`mailer_autoconfirm` true). Re-check on any new project |
| D1 | **A real email sender, so "Forgot password?" reaches members** | [Alex] | **DONE 2026-09-27**: Gmail `fxetennis.app@gmail.com` with an app password as custom SMTP; read back through the management API (`smtp_host` smtp.gmail.com, port 465, sender "FXE Tennis", `rate_limit_email_sent` 30). One real reset by Alex still to confirm delivery |
| D2 | Reset page allow-listed as a redirect on hosted | [Alex] | **DONE 2026-09-01**; verified 2026-09-27 (`uri_allow_list` is `https://fxe-tennis-admin.vercel.app/reset.html`) |
| D3 | Supabase plan: the free tier pauses after a quiet week and has no point-in-time recovery; Pro is $25 a month | [Alex] | **DECIDE** [Alex] before real members |
| D4 | Restore drill (a backup nobody has restored is not a backup) | [me] | **DONE 2026-09-12**; next due 2026-10-12 |
| D5 | Tara's real templates and clinics in hosted, through the admin site | [Tara] | **OPEN**: asked 2026-09-01; only "Test Clinic" was seen on 2026-09-26 |
| D6 | Crash reporting and error alerts | [me]/[Alex] | **OPEN** (`docs/practice-ideas.md` idea 2) |
| D7 | Rate limits on the public functions and sign-up | [me] | **LATER**: low risk at club scale |
| D8 | Drop the dead `clinics.price_cents` column | [me] | **LATER** |
| D9 | Data export for Tara | [me] | **LATER** (v1.1) |
| D10 | Encrypted nightly backups | [Alex] then [me] | **DONE 2026-09-22** (age key; first encrypted run decrypted and checked) |
| D11 | Hosted "Site URL" and the reset email's link (decision 0017) | [me] | **DONE 2026-09-27**: Site URL `https://fxe-tennis-admin.vercel.app`; the reset email now links `{{ .SiteURL }}/reset.html#token_hash=…&type=recovery` (read back through the management API once custom SMTP made templates editable) |
| D12 | Nightly purge of card consents 90 days after an account is deleted | [me] | **DONE 2026-09-27**: the `retention` job ran on hosted, "Card consents purged ...: 0" |
| D13 | **Tara can reset any member by hand**: Players tab → Reset link → Copy → text it. One-time, within an hour, no email, every link audited (`admin-reset-link`, decision 0017) | [me] | **DONE 2026-09-27**: PR #73 merged; `supabase db push` applied 20260927000001; `admin-reset-link` deployed; `hosted-smoke.sh` 63 targets, 0 open; live page checked from outside |
| D14 | Sign-in rate limit on hosted: every phone at the party shares the club Wi-Fi's one address | [me] | **DONE 2026-09-27** through the management API, read back: `rate_limit_verify` 30 → 300, `rate_limit_token_refresh` 150 → 500 per 5 minutes per IP |
| D15 | How many courts the club has | [Tara] | **DONE 2026-09-27**: 5 (Alex), which is exactly what the app allows (1 to 5); no change needed |

## E. Testing

The rule (CLAUDE.md, verification asymmetry): the thing that builds a feature
cannot be the thing that certifies it, so every layer below is a different
observer.

| Layer | Runs where | Count 2026-09-28 | Gap |
|---|---|---|---|
| SQL probes (rules, privileges, attacks, concurrency) | every PR, and locally | 1240 checks, 43 probes, plus eleven race probes | none known |
| Stripe pipeline against stripe-mock | every PR | 94 checks | real Stripe behaviour waits on A2 |
| Push pipeline against a mock APNs | every PR | 57 checks | real APNs waits on C3 |
| Web admin browser tests (Playwright, real sign-in) | every PR | 45 | a cold-start flake after a local reset (backlog) |
| Swift unit tests (pure logic) | every PR | 232 | fine |
| Hosted signed-out smoke (`scripts/hosted-smoke.sh`) | every PR, read-only against production | 126 targets, including a browser preflight to each function the web admin calls | only the signed-out side |
| XCUITests, player and admin flows, and Apple's accessibility audit | **local only** (section F) | 22 | run on a laptop before every TestFlight build |
| Copy gate, secret scan (now Stripe keys too), migration immutability, icon gate, doc checks | every PR | – | none |
| Nightly backup and consent purge | nightly | – | restore drill due 2026-10-12 (D4) |

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


## G. People, decisions and content

| ID | Item | Owner | Status |
|---|---|---|---|
| G1 | The MVP call (`docs/mvp.md`): payments in or out, push in or out | [Alex]+[Kat]+[Tara] | **DONE 2026-09-27**: Alex: payments fully live for the party (A11) and push fully working (C3), *"we want everything 100% functional + even better"* |
| G2 | Tara's answers through the review page, **round four**: only what is new since her 2026-09-22 answers (15 words, questions 69 to 79, three tasks). Her 09-22 answers were read on 2026-09-27 (decision 0016); `review-watch.yml` now opens an issue whenever she saves | [Alex] sends, [Tara] answers | **OPEN**: send the link once round four is deployed (`docs/for-alex.md` §5). Question 75 (how members hear about the app) blocks launch |
| G3 | Kat's calls: the tab bar colour, the green text contrast, the green line under the header; and her earlier "tag spec" line (release tags, answered by C10, or analytics tags, not built; `docs/kat-due-diligence.md`) | [Kat] | **OPEN** (`docs/for-alex.md` §7) |
| G4 | Alex's ticks in `docs/copy-review.md` (sections G to J and the older open rows) | [Alex] | **OPEN** |
| G5 | Tara's logo file and the original court photo | [Tara] | **OPEN**: the logo is in (the gator in colour, decision 0032, 2026-09-29); the court photo is still to come |
| G6 | GitHub: require the hosted smoke check and stop admins bypassing `main`'s protection. Dependabot alerts are already on (verified 2026-09-27) | [Alex] | **OPEN** (`docs/for-alex.md` §8) |

## H. The MVP audit of 2026-09-27

Six reviewers (member, admin, money, store, ops, messages), a skeptic per
finding, then a synthesis: 58 findings kept, none refuted. The seventeen
"build now" items are being built on five branches in parallel, each verified
by a separate agent before it merges. The questions it raised are 75 to 79
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
| H8 | Walk on a real phone what the simulator could not: a push tapped with the app in the background, the Home spinner on a slow connection, Accept and Decline on the lock screen, a haptic | [Alex]/[me] | **OPEN**: with build 5 |

## I. Polish for the party (2026-09-28)

Alex, 2026-09-27: *"do as MUCH as you possibly can w building and testing
everything ... make the app as POLISHED as possibly and best feeatures"*.
Four branches, three of them built by separate agents from a written brief,
each checked by an independent reviewer or the sql-auditor, then merged on
`polish-0928` and verified there as one.

| ID | Item | Owner | Status |
|---|---|---|---|
| I1 | Tara's notification catalogue in her words, from the database (#1, #3, #5, #6, #13 to #15), one message per event under a double tap (decision 0022) | [me] | **DONE 2026-09-28.** `supabase migration list --linked` pairs `20260928000001`; `push` v5 ACTIVE. Her uninvite message (decision 0024) is `20260928500001`, local only until the next push |
| I2 | Accept and Decline on the invitation push; Add to Calendar (nothing about where); Remind me at the player's own opening; haptics and the chip's change (decision 0023) | [me] | **OPEN**: in build 5; the buttons appear once push is live (C3) |
| I3 | Text anyone can read: Larger Text followed live, Apple's accessibility audit as a UI test on every main screen, the clock readable on navy, Return through the forms, page titles in the guide's serif, outlined tab icons (decision 0023) | [me] | **OPEN**: in build 5 |
| I4 | Payouts and chargebacks on the Money tab (H7, decision 0021); the Action Needed crash on the first declined card fixed | [me] | **DONE 2026-09-28**, with H7 |
| I5 | Tara's questions from this round: 79 narrowed, 88 to 90 new | [Tara] | **DONE 2026-09-28**: answered in round four (decision 0024); 92 to 95 are the next round's |
| I6 | The QR code for members (question 75): it points at `/app` on the admin site, which forwards to the install link, so the printed card never changes; Tara's printable card under Players → QR code for the app | [me]/[Alex] | **OPEN**: live 2026-09-28 (`deploy-web.sh` matched byte for byte; `/app`, `qr.html` and `app-qr.png` answer 200, `/app` reads "Not available yet."). Waits only on the TestFlight public link: Alex sends it, the model sets `web/app/target.js` and redeploys |
| I7 | Build 6 for players: instant open (decision 0028), Siri and Spotlight, Subscribe in Calendar (0029), every held clinic on Home, clean titles, placeholders, a declined card that says why (0026) | [me] | **DONE 2026-09-29**: PR #81 merged on 27 green checks; locally `Executed 232 tests, with 0 failures` (unit) and all 22 UI tests (the declined-card one run with the local service key); tagged `v0.1.0-rc6` |
| I8 | Build 6 for Tara: pros and their Today screen (0025), Resolved (0026), saved messages (0030), a player's history, Copy to next week and the court sheet (0027); a clinic never published never reaches a player (20260929000001/2) | [me] | **DONE 2026-09-29**: `supabase db push` 60 of 60 paired, the six functions redeployed, `deploy-web.sh` matched byte for byte, `hosted-smoke.sh` 156 targets, 0 open |
| I9 | Tara's questions 92 to 100 and 73 on round five of her review page | [me]/[Alex] | **OPEN**: round five is live on the admin site (2026-09-29); Alex mints the link on the Testing tab and sends it (`docs/for-alex.md` §5) |

## F. The CI Supabase project (Alex asked 2026-09-12; corrected 2026-09-13; decided 2026-09-18)

**Decided 2026-09-18: option 3.** Alex: *"nahh unless we really need it no more money for now."* No CI project, no Pro plan. The 22 XCUITests run on a laptop before every TestFlight build and the run is pasted into the changelog entry for that build; the `ios-ui-tests` job stays green with its notice until the three settings exist, so switching later is a dashboard visit and two secrets, nothing in the repo. Revisit when the first paying member exists (D3 wants point-in-time recovery then anyway). The rest of this section is kept as the record of why.


Alex gave the go-ahead on 2026-09-13 ("exact steps for me or can you do it all?"); the create was attempted the same day and refused, see below. Would it help a lot? Yes: it is the only way to run the 22 XCUITests on every PR, which is the layer that walks the app like a member does. The macOS runner has no Docker, so it cannot host the local stack; a small hosted project it can reset to the seed is the practical answer. Everything on our side is built and waiting (2026-09-13): the Debug app accepts `FXE_SUPABASE_URL` / `FXE_SUPABASE_ANON_KEY`, the UI tests forward them, and the `ios-ui-tests` job resets the project with `supabase db reset --db-url` and runs the suite with one retry. The job stays green with a notice until the secrets exist.

**Does it use the Volee slot? Yes, and Alex was right.** The 2026-09-12 version of this section said the free plan is two projects per organization. It is two active free projects per *user* across every org they own: `supabase projects create fxe-ci` on 2026-09-13 was refused with "Alex-Epstein (2 project limit)", because Volee and `fxe-tennis` already fill it. Three ways out, cheapest first:

1. **Pro on the FXE org, $25/month.** Removes the pause-after-a-week risk and adds point-in-time recovery for production (row D3 wanted this before real members anyway). The extra `fxe-ci` micro project on a Pro org bills about $10/month on top. Roughly $35/month total.
2. **A second free owner.** A free org owned by someone else (Tara's own Supabase account, or an account Alex creates for the club) gets its own two free slots. Zero cost; one more login to keep track of, and Alex would need to be invited as an admin.
3. **No project: keep running the UI suite on a laptop before every TestFlight build**, and record the run in the changelog. Free, honest, and the weakest of the three.

What it needs from Alex once a project exists: its database password stays with him; set three things in GitHub, Settings → Secrets and variables → Actions: secret `CI_SUPABASE_DB_URL` (the session-pooler connection string, port 5432), secret `CI_SUPABASE_ANON_KEY` (the project's publishable key), and variable `CI_SUPABASE_URL` (`https://<ref>.supabase.co`). The next Swift change then runs the suite. Guardrail: the CI project holds seed data only, never Tara's.

---

## Done log

Rows stay in their tables with DONE; this is the short history.

- 2026-09-27: A1, A8 Stripe keys and webhook; D12 the consent purge's first run; D2 and D0 re-verified.
- 2026-09-22: D10 encrypted backups.
- 2026-09-21: C5 account deletion; A3 Tara's policy answers.
- 2026-09-12: C4 privacy manifest; E9 Stripe SDK pinned; D4 restore drill; the docs audit.
