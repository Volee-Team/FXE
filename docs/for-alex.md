# For Alex: how to do each thing only you can do

**What is left, and whose it is, lives in `docs/launch-checklist.md` and
nowhere else.** This file is only the how-to for Alex's rows, click by click.
Each section names its checklist row; the CI check fails if a section points
at a row that does not exist. Updated 2026-10-12.

Never paste a key, password or secret into the chat with the model.
Everything typed there is saved to `docs/prompt-log/` on this Mac (gitignored
since 2026-10-04, and the repository is public). The logging hooks scrub
key-shaped text and the secret scan fails on it, but those are seatbelts, not
permission.

The order is the checklist's critical path (its section 0). In this file:
the review account and John's build 10 upload (§4a), the Stripe rehearsal and
live keys alongside them (§1a, §1b), the public link once Apple approves
(§4b).

---

## 1. Stripe sandbox keys and webhook (checklist A1, A8, A12)

These steps were followed on 2026-09-27 (A1, A8) and the dispute events were
added on 2026-10-01 (A12). They stay here because the rehearsal (§1a) and the
live keys (§1b) repeat parts of them. Stripe calls test mode a **sandbox**
and keeps webhooks in **Workbench** as "event destinations" (checked against
Stripe's and Supabase's docs on 2026-09-27).

Keep two tabs open: Stripe, and the Supabase secrets page (step 7).

If a key ever lands somewhere it should not, rotate it: API keys page, the ⋯
menu beside the key, **Rotate key**.

**A. The account**

1. Go to https://dashboard.stripe.com/register and sign up: email, name,
   country United States, password. Confirm the email Stripe sends.
2. Skip every "activate your account" or "tell us about your business"
   screen. Testing needs none of it. (The account later went to Tara: §2b.)

**B. Get into the sandbox**

3. In the account menu at the top left, pick the sandbox (it may say
   **Sandbox** or **Test mode**). A banner tells you you are looking at test
   data. If no sandbox exists, the same menu offers to create one.
   Everything below happens inside the sandbox. Keys there start with
   `pk_test_` and `sk_test_`; if you see `pk_live_`, you are in live mode.

**C. Copy the two keys**

4. Open the **API keys** page (Workbench, or https://dashboard.stripe.com/test/apikeys).
5. **Publishable key** (`pk_test_…`) is shown already. Click it to copy.
6. **Secret key** (`sk_test_…`): click **Reveal**, then click it to copy.
   For testing the standard secret key is right; live mode uses a restricted
   key with only the permissions our code uses (§1b).

**D. Put them into Supabase**

7. Open https://supabase.com/dashboard/project/amnaxvznkadkgzdxzegw/functions/secrets
8. Add a secret. **Key** `STRIPE_PUBLISHABLE_KEY`, **Value** the `pk_test_…`
   you copied. **Save**.
9. Add another. **Key** `STRIPE_SECRET_KEY`, **Value** the `sk_test_…`.
   **Save**. The names must be exactly these: capitals and underscores.
   Nothing needs redeploying; the functions see secrets immediately.

**E. The webhook** (Stripe telling our server a card was saved or charged)

10. Stripe: Workbench, **Webhooks** tab (https://dashboard.stripe.com/test/webhooks),
    **Create an event destination**.
11. Events from: **Your account**. API version: leave the default.
12. Select these five events (search each name and tick it):
    - `setup_intent.succeeded`
    - `payment_intent.succeeded`
    - `payment_intent.payment_failed`
    - `charge.refunded`
    - `refund.updated`
13. **Continue**, choose **Webhook endpoint**, **Continue**.
14. **Endpoint URL**, exactly:
    `https://amnaxvznkadkgzdxzegw.supabase.co/functions/v1/stripe-webhook`
    Description is optional ("FXE app"). Create it.
15. On the endpoint's page, find **Signing secret**, click **Reveal secret**,
    copy the `whsec_…`.
16. Back on the Supabase secrets page: **Key** `STRIPE_WEBHOOK_SECRET`,
    **Value** the `whsec_…`. **Save**.

**F. Tell the model "Stripe keys are in"**

17. The model checks the three names exist on hosted (`supabase secrets
    list` shows names and fingerprints, never values). Payments stay
    switched off (checklist A9).

**G. Three more events, for chargebacks (checklist A12)**

When a player's bank takes back a clinic fee, Stripe sends one of three
events; without them the app never hears about it and nothing reaches
Tara's Action Needed (decision 0021).

18. Stripe dashboard (sandbox), **Developers** → **Webhooks** → the endpoint
    ending in `/stripe-webhook`.
19. **⋯** (or **Edit destination**) → **Select events** → search `dispute`
    and tick `charge.dispute.created`, `charge.dispute.updated` and
    `charge.dispute.closed`. Keep the five already ticked. **Save** / **Update
    destination**. Eight events in all.
20. Nothing to copy: the signing secret does not change.

**The terminal command you may have seen** (`supabase secrets set
STRIPE_SECRET_KEY=...`) is not needed. It does exactly what steps 8, 9 and
16 do, and typing a key into the terminal leaves it in your shell history
file in plain text. Use the web page.

## 1a. The rehearsal: a restricted sandbox key (checklist A13)

Why: nothing has talked to real Stripe yet, only Stripe's mock server in CI.
A restricted key missing one permission does not show as an error (the app
retries it as pending, decision 0019), so saving a card would just quietly
never finish. The rehearsal runs the whole flow against Stripe's real test
mode with a key carrying exactly the live key's permissions. About 45
minutes, with the model.

1. Stripe dashboard, inside the **sandbox** (the test-data banner is showing;
   §1 step 3).
2. **Developers** → **API keys** → **Create restricted key**. Name it
   `FXE rehearsal`.
3. Set the permissions, exactly these and nothing more:
   - **Write**: Customers, SetupIntents, PaymentIntents, Refunds,
     Ephemeral keys.
   - **Read**: PaymentMethods, Charges, Balance, Payouts.
   - **Everything else: None.**
   Why each one is needed is in `supabase/functions/README.md` (re-derived
   from every Stripe call in our functions).
4. **Create key**. Stripe shows an `rk_test_…` key. Copy it.
5. Paste it into the file the model names when you start, save, and close
   it. Never paste it into the chat. The file is never one git tracks.
6. Once only: install the Stripe CLI (`brew install stripe/stripe-cli/stripe`)
   and run `stripe login`, which opens the browser to approve. It lets
   Stripe's sandbox send webhooks to the model's local copy.
7. Tell the model **"rehearsal key saved"**. It runs `docs/stripe-e2e-test.md`
   on its local copy against real Stripe test mode: save a card, a charge
   after a clinic, a refund, a declined card and a 3-D Secure card.
8. When it passes, the live keys are next (§1b).

## 1b. Live keys (checklist A10)

After the rehearsal (§1a) passes. In the **live** account: no sandbox
banner, and keys start `pk_live_` and `rk_live_`. Keys go only into
Supabase's secrets page, never into a chat or a file. Set all three in one
sitting: the card screen refuses while the secret and publishable keys are
in different modes (`keyModesAgree` in `stripe-setup-intent`).

1. **Developers** → **API keys** → **Create restricted key**. Name it
   `FXE app server`. The same permissions as §1a step 3: **Write** =
   Customers, SetupIntents, PaymentIntents, Refunds, Ephemeral keys;
   **Read** = PaymentMethods, Charges, Balance, Payouts; everything else
   **None**. **Create key** and copy the `rk_live_…`.
2. Supabase secrets page
   (https://supabase.com/dashboard/project/amnaxvznkadkgzdxzegw/functions/secrets):
   set `STRIPE_SECRET_KEY` to the `rk_live_…`. **Save**.
3. Stripe, **API keys**: copy the **Publishable key** (`pk_live_…`). Set
   `STRIPE_PUBLISHABLE_KEY` to it. **Save**.
4. Stripe, Workbench → **Webhooks** → **Create an event destination**.
   Events from **Your account**, API version the default. Tick these nine:
   - `setup_intent.succeeded`
   - `payment_intent.succeeded`
   - `payment_intent.payment_failed`
   - `charge.refunded`
   - `refund.updated`
   - `charge.dispute.created`
   - `charge.dispute.updated`
   - `charge.dispute.closed`
   - `payment_method.detached` (a card removed in Stripe's dashboard; without it the app keeps showing the removed card)
   **Continue** → **Webhook endpoint** → **Continue**. Endpoint URL, exactly:
   `https://amnaxvznkadkgzdxzegw.supabase.co/functions/v1/stripe-webhook`.
   Create it.
5. On the endpoint's page, **Reveal secret**, copy the `whsec_…`, and set
   `STRIPE_WEBHOOK_SECRET` to it. **Save**.
6. On the same endpoint page, **Send test event** → `setup_intent.succeeded`.
   Stripe shows the response code. Expect **200**: a dashboard test event is
   not a card the app started, so the function records nothing and answers
   `received`. A **400** with `bad_signature` means the `whsec_…` in step 5
   is not this endpoint's.
7. Tell the model **"live keys in"** and the response code. The model checks
   the three names (`supabase secrets list`), runs the cutover that forgets
   every sandbox card (`stripe_cutover_to_live`, so everyone adds a real
   one; no new build), then one real charge and refund on your own card on
   hosted. Payments go on only after that and after Apple approves the
   external build (checklist A9).

The nine events match the `case` lines in
`supabase/functions/stripe-webhook/index.ts`; an event not ticked never
reaches the app.

## 1c. Three Stripe settings (checklist A14), about 5 minutes

In the live account, any time.

1. **Settings** → **Business** → **Customer emails**: turn **Successful
   payments** and **Refunds** off (Tara: "No receipts", question 86).
2. **Settings** → **Payouts**: check Tara's bank is the payout account and
   set the schedule to **Daily**, automatic. A new account's first payout
   takes longer while Stripe reviews it (`docs/stripe-e2e-test.md`).
3. **Tara**, signed in to her own Stripe login: her name (top right) →
   **Profile** → **Communication preferences** → **Disputes** on. A dispute
   has a deadline of 7 to 21 days; the app also lists disputes in her Action
   Needed (decision 0021).

## 2. Privacy policy (checklist C6)

Published 2026-09-27 at https://fxe-tennis-admin.vercel.app/privacy.html
after Tara approved it, and linked from Profile in the app. Nothing left for
you here. When the LLC's App Store record exists (checklist C7), paste the
same URL into App Store Connect: the app, **App Information**, **Privacy
Policy URL**. Moving the page to fersc.com later changes only the URL.

## 2b. Stripe to Tara (checklist A7)

The account was transferred to Tara on 2026-10-03 and activated: the LLC's
EIN replaced the SSN, and Payments and Payouts were both Active on
2026-10-04. Tara has no accountant (2026-10-05). Nothing left for you here
except to watch her email for Stripe's follow-ups with her.

## 3. Push notifications (checklist C3, H8)

John's APNs key went into hosted on 2026-10-03. What is left is seeing one
real push on a lock screen:

1. On your phone, the TestFlight build, signed in as yourself, with
   notifications allowed.
2. Lock the phone, then from the model's prompt (or Tara's admin site)
   trigger a notification to you: registering for a clinic sends You're In!
   or Player Pool (`docs/notifications.md`, #1 and #5).
3. Tell the model whether a banner arrived on the lock screen. Then the
   real-phone walk (checklist H8).

**When the LLC's app ships** (checklist C2), it gets its own key the same
way, on the LLC's account:

1. https://developer.apple.com/account → **Certificates, IDs & Profiles** →
   **Keys** → the **+** button.
2. Key name `FXE Push`. Tick **Apple Push Notifications service (APNs)**.
   Continue → Register.
3. **Download** the `.p8` file (the private key our server uses to prove to
   Apple it may send notifications). Apple allows one download only, so save
   it straight into LastPass as an attachment. Copy the **Key ID**.
4. Copy the **Team ID**: Membership details on the same site (10 characters).
5. **Identifiers** → the app's bundle id → **Push Notifications** is ticked.

Then, in Terminal from the repo folder (the values go straight to Supabase,
never into a chat or a file in the repo):

```bash
supabase secrets set APNS_KEY_ID=<key id> APNS_TEAM_ID=<team id> APNS_TOPIC=<bundle id>
```

```bash
supabase secrets set APNS_PRIVATE_KEY="$(cat ~/Downloads/AuthKey_<key id>.p8)"
```

Delete the `.p8` from Downloads (LastPass has it) and tell the model **"push
key is in"**. No `APNS_HOST` is needed: TestFlight and App Store builds use
Apple's production server, which is the default.

## 4. TestFlight builds so far (checklist C8, C10)

Build 7 was uploaded by John on 2026-09-29 (tag `v0.1.0-tf7`). Builds 8 and
9 were tagged (`v0.1.0-rc8`, `v0.1.0-rc9`), but no `tf8` or `tf9` tag
exists, so neither was recorded as uploaded. Build 10 replaces them (§4a).
The full runbook is `docs/testflight.md`.

## 4a. The review account, then build 10 to External Testing (checklist C8, C11, C13)

**Build 10 is the tag `v0.1.0-rc10`** on `main` (`88a1871`, PR #94, merged
2026-10-12): Tara's note box at Register (decision 0039) and her 2026-10-12
answers (decision 0040). It was tagged after the UI suite was green on
iOS 17, 18 and 26 for that code.

**A. The App Review account (you, about 3 minutes; checklist C13).** Apple's
beta reviewer is a person who installs the build, and the app shows nothing
until sign-in, so App Store Connect asks for a working email and password.
The account must be made in the **TestFlight app**, which talks to hosted;
the one made on 2026-10-01 was made on a local build and never reached
hosted.

1. TestFlight app on your phone → Profile → **Sign out**.
2. **Create an account** with an address you control and a new password
   used nowhere else. Save both in LastPass; Apple will see them.
3. Profile: name `App Review`, your own phone, any rating, Member: **No**.
4. Waiver: tick, type your own name, **Agree and sign**.
5. Notifications: your choice.
6. Sign out, and sign back in to your own account.
7. Send John the email and password, with the review notes below.
8. Tell Tara that "App Review" is Apple's tester, and to Remove it from any
   clinic it joins. Payments are off, so nothing is charged. The model keeps
   it out of the board report.

Also check a clinic is open to non-members during the review days, or the
reviewer sees only "Registration opens". Payments must still be **off** when
John submits, or the reviewer stops at Add a card.

**B. John (about 30 minutes, then Apple's 1 to 2 days; checklist C8, C11).**
Text John something like this:

> John, build 10 is ready. `git fetch --tags && git checkout v0.1.0-rc10`,
> `xcodegen generate`, open the project, scheme FXETennis, destination Any
> iOS Device, Product → Archive. Then Distribute App → **App Store Connect →
> Upload** (not TestFlight Internal Only: that kind can never go to External
> Testing). Once it has processed, tag it:
> `git tag -a v0.1.0-tf10 -m "TestFlight build 10, uploaded by John"` and
> `git push origin v0.1.0-tf10`. Full steps are in `docs/testflight.md`.

Then, in App Store Connect:

1. appstoreconnect.apple.com → Apps → FXE Tennis → **TestFlight**.
2. External Testing → **+** → a group named `FXE Members`.
3. Add build 10 to the group. Fill in **Test Information** (below), the
   feedback email, the contact (name, phone, email) and the sign-in for
   Apple's reviewer from A.
4. **Submit for Review**. Apple usually answers in 1 to 2 days.
5. Once approved: the group → **Public Link** → **Enable**. Send Alex the
   link; it becomes the QR code's target (§4b). Nobody gets it until the
   soft launch (checklist G7).

**Test Information** (testers read the first two; words for Alex to approve):

> What to test: Sign in or create an account, then look through the Clinics
> tab. Register for a clinic, or join the Player Pool when it is full. Check
> that your clinics show under Profile, My Clinics. Tell us anything that
> looks wrong or is hard to find.

> Beta App Description: FXE Tennis is the clinic sign-up app for the FXE
> tennis program. Players see the week's clinics, register, get updates from
> their coach, and manage their spot. This is a test version for club players
> before the full release.

**Beta App Review notes** (only Apple reads these):

> This app is for a private tennis club's clinic program. Players register
> for in-person group tennis clinics run by the club's coach.
>
> Sign-in: email [REVIEW ACCOUNT EMAIL] / password [REVIEW ACCOUNT PASSWORD].
> This is a real member account with the waiver already signed.
>
> Home shows your clinics and what is open to you. The Clinics tab lists the
> week's clinics; tap one for its details and Register. Profile has My
> Clinics, Subscribe in Calendar, Contact, Privacy Policy and Delete my
> account (please use a new account from Create an account to try deletion).
>
> Registration for each week opens Thursday 8:00 AM Eastern for club members
> and Friday 8:00 AM Eastern for everyone else.
>
> Payments: players save a card through Stripe's form and are charged only
> after an in-person clinic they attended, or for a late cancellation or
> no-show. These are real-world services used outside the app, so in-app
> purchase does not apply (guideline 3.1.3(e)). Card entry is not active in
> this build. Notifications are optional. Clinic locations are deliberately
> not shown because this is a members' club.

## 4b. The QR code's link (checklist I6), one message

The QR code Tara prints and emails points at
https://fxe-tennis-admin.vercel.app/app, which shows "Not available yet." until
it knows where the app installs from. When the external TestFlight beta is
approved, App Store Connect → the app → TestFlight → the external group →
**Public Link** → copy it (it looks like `https://testflight.apple.com/join/…`)
and send it to the model. It sets one line (`web/app/target.js`) and deploys;
the printed code never changes, even when the App Store link replaces it later.
Tara's card: web admin → Players → **QR code for the app** → Print, or
Download for email (her email to members is checklist G8, §9).

## 5. Tara's review page, round six (checklist G2), about 5 minutes

Round six is only what she has not seen: 14 words to Keep or Change and 5
things to try on her laptop. There is no Questions tab: she answered every
round-five question on 2026-10-12 (decision 0040). Questions 109 to 112 are
not on the page.

1. Wait for the model to say round six is live (it deploys with
   `scripts/deploy-web.sh`, which checks the live page byte for byte).
2. On a laptop, open https://fxe-tennis-admin.vercel.app and sign in with the
   admin login.
3. Click the small grey **Testing** link at the very bottom right of the page.
4. Under **Review links**, type a label such as `Tara round 6`, click **Make
   link**, then **Copy**.
5. Text her the link, with something like: *"Your answers are in the app.
   This is only the words still waiting on you, plus a few things to try on
   your laptop. One line each is plenty, and it saves as you type."*
6. Nothing else to do: when she saves answers, GitHub opens an issue labelled
   `tara-answers` and the next session with the model starts with it.

## 6. Email that reaches members (checklist D1)

Set up on 2026-09-27, and you confirmed delivery on 2026-10-01. The steps
stay for the record, and for a club-domain sender later.

Before this, a member who tapped Forgot password got nothing: Supabase's
built-in sender delivers only to the Supabase project's own team, 2 an hour
(verified 2026-09-27 through the management API).

- **Tara can reset anyone by hand**: Players tab → the member → **Reset
  link** → Copy → text it to them. It works once, within an hour, and needs
  no email at all (decision 0017).
- **The reset page and the Site URL** are the model's (checklist D11).

The simplest free sender is a Gmail account made for the app. Gmail allows
about 500 emails a day, far more than a club needs. Use a NEW account, not
Tara's: its app password goes into Supabase, so it should be an account whose
only job is sending the app's email.

1. Make a new Gmail account for the app (any free name). Use your phone
   number for its recovery. Save the password in LastPass.
2. Signed in to that account, open https://myaccount.google.com/security and
   turn on **2-Step Verification** (Google requires it for app passwords).
3. Open https://myaccount.google.com/apppasswords, type the name
   `FXE Supabase`, click **Create**. Google shows a 16-letter password once.
   Copy it. It is a password: it goes only into step 4, never into a chat.
4. Supabase: https://supabase.com/dashboard/project/amnaxvznkadkgzdxzegw →
   **Authentication** → **Emails** → **SMTP Settings** → turn on
   **Enable custom SMTP**:
   - Sender email: the new Gmail address
   - Sender name: `FXE Tennis`
   - Host: `smtp.gmail.com`
   - Port: `465`
   - Username: the new Gmail address
   - Password: the 16-letter app password (paste it without the spaces)
   Save.
5. Same dashboard → **Authentication** → **Rate Limits** → "Rate limit for
   sending emails": change 2 to `30`. Save.
6. Tell the model **"email is set up"**. It re-reads the settings through the
   management API (it never sees the password) and asks you for one real
   test: Forgot password with your own email, the email arrives from FXE
   Tennis, the link opens the reset page, the new password signs you in.

Later, if the club wants email from its own domain (`noreply@fersc.com`
rather than a Gmail address): Resend's free plan, host `smtp.resend.com`,
port 465, username `resend`, password a Resend API key, after adding the DNS
records Resend shows to the domain. Not needed for launch.

The reset email's wording is Supabase's default. Tara may want her own words
later; that is a question for her, not a blocker.

## 7. Kat's three style calls (checklist G3)

Kat answered all three on 2026-10-01 (decision 0036): keep the system tab
bar, use the darker green (#446A30) for text, keep the green line under the
header. Nothing left here.

## 8. GitHub: make CI a real gate (checklist G6), about 5 minutes

Today `main` requires two checks, and admins may merge past them. The model's
GitHub access is admin, so today only its own scripts stop it merging a red
PR. This makes GitHub itself refuse.

1. Open https://github.com/Volee-Team/FXE/settings/branches
2. Next to the rule for `main`, click **Edit**.
3. Under **Require status checks to pass before merging**, use the search box
   to add each of these (two are there already):
   - `Hosted is closed to a signed-out caller`
   - `Secret scan`
   - `Docs are consistent`
   - `No unapproved copy`
   - `Stripe pipeline (mocked)`
   - `Push pipeline (mocked)`
   - `Web admin browser tests`
   Do not add `iOS UI tests on a CI project`; it only prints a notice until a
   CI database exists.
4. Tick **Do not allow bypassing the above settings**.
5. **Save changes**.

Dependabot alerts are already on (checked 2026-09-27), so nothing to do there.

## 9. With Tara (checklist G7, G8)

- **The soft launch** (checklist G7): once Apple approves the external build
  (C11), pick the date and the first 20 to 30 testers with her. They get the
  public link (§4b); nobody else does yet.
- **Her email to members** (checklist G8): in her words, with the QR code
  (web admin → Players → **QR code for the app** → Download) or the public
  link. Send the model her steps before it goes out, so the steps match the
  app.

Her earlier asks have their own rows: the logo and court photo (G5), her
real clinics on hosted (D5), the number of courts (D15).

## 10. Decisions only you can make

| Checklist | Decision | When | The model's recommendation |
|---|---|---|---|
| Backlog, 2026-09-28 | **Should the app refuse to put someone in, or message, a clinic Tara has not published yet?** Today it allows both (a draft looks like any card on her laptop) | Any time; nothing waits on it | Keep allowing: it is her tool, and nothing reaches a player about a never-published clinic that gets canceled (20260929000002). Refuse if she ever sets up next week and forgets to publish |
| A9 | Switch payments on | After Apple approves the external build (C11) and the live keys and their rehearsal are done (A10, A13) | Go then, once the one real charge and refund on your card has passed. Never while the keys are sandbox: a real card is declined in test mode |
| C12 | The LLC app's bundle id (the current one is locked to John's account) | Before the first LLC build | Accept a new id such as `com.fxetennis.club`; testers reinstall once, and their accounts and cards carry over (they live on our server) |
| D3 | Supabase Pro ($25 a month): the free plan pauses a project after about a week with no traffic (it happened once, 2026-09-01) and has no point-in-time recovery; we already have our own encrypted nightly backups (D10) | Before real members | Yes, from the week the first members get the link (G7) |
| I1 (decision 0022 §5) | **A behaviour change you can veto:** nobody can accept an invitation into a clinic Tara canceled or that has already ended, and Tara's Invite and "Put them in" are gone on a canceled clinic | Built 2026-09-28 | Keep: a stale invitation tapped days later landed a player in a finished clinic and got them charged. Where the Accept cut-off sits (start or end) is Tara's question 91 |

## 11. Business

- **Apple LLC enrollment (checklist C1).** Apple asked on 2026-10-11 for a
  letter on the LLC's letterhead giving you authority to bind the LLC; you
  and Tara signed it and you reported it sent on 2026-10-12. Answer Apple in
  the same email thread if they ask for more. If Apple goes quiet, Apple
  Developer Support (https://developer.apple.com/contact, Membership and
  Account, Program Enrollment) can say what is outstanding.
