# Launch checklist: the single source of truth for what is left

**Launch target: the launch party, Friday 2026-10-16.** Nineteen days from the
last full check (Sunday 2026-09-27).

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
   re-derivation: **2026-09-27**, each check named in the row.
4. **A machine keeps the format honest.** `scripts/check-launch-checklist.sh`
   runs in CI: it fails when a row has no owner or no status word, when a
   DONE has no date, or when `docs/for-alex.md` points at a row that does not
   exist.

---

## 0. The critical path to 2026-10-16

What must be true on the day, in the order it has to happen. Each item is a
row below; this list adds nothing of its own.

1. **Members can reset a forgotten password** (D1, D11). Today they cannot:
   the reset email never reaches anyone outside the Supabase team. [Alex]
2. **Build 3 is on the testers' phones** (C8). `main` is ready and verified.
   [John]
3. **The MVP call is made** (G1): payments in or out, push in or out. [Alex,
   Kat, Tara]
4. **If payments are in:** switch them on after build 3 is on phones (A9),
   then the end-to-end payment test (A2), then Stripe live mode in Tara's
   name (A7, A10). [Alex, me]
5. **Tara's real clinics are in the admin** (D5). [Tara]
6. **Members can install the app on the day** (C1, C11, C6): the LLC's App
   Store listing if Apple approves in time, otherwise external TestFlight on
   John's account, which needs the privacy policy URL and about a day of
   Apple's beta review. Decide by 2026-10-09. [Alex]
7. **Tara's open answers and Kat's style calls are in** (G2, G3). Every
   default is already built, so these improve the launch rather than block it.

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
| A9 | Switch payments on (`payments_enabled` true, by migration). From that moment nobody registers without a saved card | [me] | **DECIDE** [Alex]: say go once build 3 (C8) is on the testers' phones, since build 2 cannot save a card |
| A10 | Live keys: a restricted key with only the permissions our code uses, a live webhook, the three secrets swapped | [me]+[Alex] | **LATER**: with A7 |

## B. Stripe steps

One copy only: `docs/for-alex.md` §1 (done 2026-09-27; kept for live mode).
What Stripe takes: 2.9% + 30¢ per card charge. Apple takes nothing (decision
0009). Payouts to Tara's bank need live mode (A7).

## C. App Store and Apple

| ID | Item | Owner | Status |
|---|---|---|---|
| C1 | Apple Developer Program enrollment as FXE Tennis, LLC (Apple asked for the ID, employment verification and a business document on 2026-08-26; Tara sent them) | [Tara]/[Apple] | **BLOCKED** on Apple: still processing on 2026-09-27 |
| C2 | Bundle id, Team ID, App Store Connect record and APNs key under the LLC | [Alex] | **BLOCKED** on C1 |
| C3 | Push notifications on the lock screen: sender, trigger and audit columns built and deployed 2026-09-23 (#61) | [me] | **BLOCKED** on C2's APNs key; then five function secrets and two vault entries (`docs/for-alex.md` §3) |
| C4 | Privacy manifest | [me] | **DONE 2026-09-12** (#37) |
| C5 | Delete my account in the app, history kept (guideline 5.1.1(v)) | [me] | **DONE 2026-09-21**; `delete-account` deployed the same day |
| C6 | Privacy policy at a public URL | [Alex] | **OPEN**: the draft is Volee's with eight listed changes to approve and a contact email to fill (`docs/for-alex.md` §2); the model then publishes it and links it from Profile |
| C7 | App Store listing: name, subtitle, description in Tara's words, screenshots, age rating, support URL, review notes with a test account | [Alex]+[me] | **BLOCKED** on C1, or on C11's path |
| C8 | TestFlight build 3 from `main` | [John] | **OPEN**: `main` verified 2026-09-27 by a Release build (build number 3, the camera sentence, the encryption flag, the hosted backend and no local address in the binary); John archives per `docs/testflight.md` (`docs/for-alex.md` §4) |
| C9 | Real-device pass: the two simulator flakes checked on an iPhone | [Alex]/[me] | **BLOCKED** on C8 |
| C10 | An annotated git tag at every TestFlight upload | [me]/[John] | **OPEN**: `v0.1.0-tf2` exists; tag `v0.1.0-tf3` when build 3 uploads |
| C11 | If C1 is late for 2026-10-16: external TestFlight on John's account with a public link (needs C6 and Apple's beta review, about a day) | [Alex] | **DECIDE** [Alex] by 2026-10-09 |
| C12 | Bundle id for the LLC's app. `com.fxetennis.app` is tied to John's account now: Apple transfers only apps with at least one App Store release, and a TestFlight upload locks the id to that account. The LLC's app will need a new id, and testers install it fresh (their accounts carry over; they live on our server) | [Alex] | **DECIDE** [Alex] before the first LLC build |

## D. Backend and operations

| ID | Item | Owner | Status |
|---|---|---|---|
| D0 | "Confirm email" off on hosted (decision 0011) | [Alex] | **DONE**; verified 2026-09-27 through the management API (`mailer_autoconfirm` true). Re-check on any new project |
| D1 | **A real email sender, so password resets reach members.** Verified 2026-09-27: hosted has no custom SMTP, and Supabase's built-in sender "will refuse to deliver messages to addresses that are not part of the project's team", 2 per hour | [Alex] | **OPEN, launch blocker**: Resend's free plan plus a domain whose DNS Alex or Tara controls (`docs/for-alex.md` §6) |
| D2 | Reset page allow-listed as a redirect on hosted | [Alex] | **DONE 2026-09-01**; verified 2026-09-27 (`uri_allow_list` is `https://fxe-tennis-admin.vercel.app/reset.html`) |
| D3 | Supabase plan: the free tier pauses after a quiet week and has no point-in-time recovery; Pro is $25 a month | [Alex] | **DECIDE** [Alex] before real members |
| D4 | Restore drill (a backup nobody has restored is not a backup) | [me] | **DONE 2026-09-12**; next due 2026-10-12 |
| D5 | Tara's real templates and clinics in hosted, through the admin site | [Tara] | **OPEN**: asked 2026-09-01; only "Test Clinic" was seen on 2026-09-26 |
| D6 | Crash reporting and error alerts | [me]/[Alex] | **OPEN** (`docs/practice-ideas.md` idea 2) |
| D7 | Rate limits on the public functions and sign-up | [me] | **LATER**: low risk at club scale |
| D8 | Drop the dead `clinics.price_cents` column | [me] | **LATER** |
| D9 | Data export for Tara | [me] | **LATER** (v1.1) |
| D10 | Encrypted nightly backups | [Alex] then [me] | **DONE 2026-09-22** (age key; first encrypted run decrypted and checked) |
| D11 | Hosted "Site URL" is `http://localhost:3000`; Supabase uses it as the default link in its emails | [Alex] | **OPEN**: one field in the dashboard (`docs/for-alex.md` §6), verified 2026-09-27 through the management API |
| D12 | Nightly purge of card consents 90 days after an account is deleted | [me] | **DONE 2026-09-27**: the `retention` job ran on hosted, "Card consents purged ...: 0" |

## E. Testing

The rule (CLAUDE.md, verification asymmetry): the thing that builds a feature
cannot be the thing that certifies it, so every layer below is a different
observer.

| Layer | Runs where | Count 2026-09-27 | Gap |
|---|---|---|---|
| SQL probes (rules, privileges, attacks, concurrency) | every PR, and locally | 644 checks, 28 probes | none known |
| Stripe pipeline against stripe-mock | every PR | 34 checks | real Stripe behaviour waits on A2 |
| Push pipeline against a mock APNs | every PR | 48 checks | real APNs waits on C3 |
| Web admin browser tests (Playwright, real sign-in) | every PR | 15 | a cold-start flake after a local reset (backlog) |
| Swift unit tests (pure logic) | every PR | 31 | fine |
| Hosted signed-out smoke (`scripts/hosted-smoke.sh`) | every PR, read-only against production | 58 targets | only the signed-out side |
| XCUITests, player and admin flows | **local only** (section F) | 13 | run on a laptop before every TestFlight build |
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
| G1 | The MVP call (`docs/mvp.md`): payments in or out, push in or out | [Alex]+[Kat]+[Tara] | **DECIDE** |
| G2 | Tara's answers to questions 52 to 68 through the review page, round three (17 questions and a board-report task, live 2026-09-27) | [Alex] sends, [Tara] answers | **OPEN** (`docs/for-alex.md` §5) |
| G3 | Kat's calls: the tab bar colour, the green text contrast, the green line under the header; and her earlier "tag spec" line (release tags, answered by C10, or analytics tags, not built; `docs/kat-due-diligence.md`) | [Kat] | **OPEN** (`docs/for-alex.md` §7) |
| G4 | Alex's ticks in `docs/copy-review.md` (sections G to J and the older open rows) | [Alex] | **OPEN** |
| G5 | Tara's logo file and the original court photo | [Tara] | **OPEN** (question 64) |
| G6 | GitHub: require the hosted smoke check and stop admins bypassing `main`'s protection. Dependabot alerts are already on (verified 2026-09-27) | [Alex] | **OPEN** (`docs/for-alex.md` §8) |

## F. The CI Supabase project (Alex asked 2026-09-12; corrected 2026-09-13; decided 2026-09-18)

**Decided 2026-09-18: option 3.** Alex: *"nahh unless we really need it no more money for now."* No CI project, no Pro plan. The 13 XCUITests run on a laptop before every TestFlight build and the run is pasted into the changelog entry for that build; the `ios-ui-tests` job stays green with its notice until the three settings exist, so switching later is a dashboard visit and two secrets, nothing in the repo. Revisit when the first paying member exists (D3 wants point-in-time recovery then anyway). The rest of this section is kept as the record of why.


Alex gave the go-ahead on 2026-09-13 ("exact steps for me or can you do it all?"); the create was attempted the same day and refused, see below. Would it help a lot? Yes: it is the only way to run the 13 XCUITests on every PR, which is the layer that walks the app like a member does. The macOS runner has no Docker, so it cannot host the local stack; a small hosted project it can reset to the seed is the practical answer. Everything on our side is built and waiting (2026-09-13): the Debug app accepts `FXE_SUPABASE_URL` / `FXE_SUPABASE_ANON_KEY`, the UI tests forward them, and the `ios-ui-tests` job resets the project with `supabase db reset --db-url` and runs the suite with one retry. The job stays green with a notice until the secrets exist.

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
