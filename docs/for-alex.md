# For Alex: how to do each thing only you can do

**What is left, and whose it is, lives in `docs/launch-checklist.md` and
nowhere else.** This file is only the how-to for Alex's rows, click by click.
Each section names its checklist row; the CI check fails if a section points
at a row that does not exist. Updated 2026-09-27.

Never paste a key, password or secret into the chat with the model. Everything
typed there is saved to `docs/prompt-log/`, which is committed to a public
repository. The logging hooks scrub key-shaped text and the secret scan fails
on it, but those are seatbelts, not permission.

---

## 1. Stripe keys (checklist A1, A8): DONE 2026-09-27

Verified 2026-09-27: all three secret names exist on hosted, and a forged
webhook call is rejected with `bad_signature`. The steps stay here for live
mode (checklist A7, A10).

Status 2026-09-27: `supabase secrets list` on hosted shows no `STRIPE_*`
secret. Wording below checked against Stripe's and Supabase's docs on
2026-09-27; Stripe now calls test mode a **sandbox** and keeps webhooks in
**Workbench** as "event destinations".

Keep two tabs open: Stripe, and the Supabase secrets page (step 7).

**Do not paste any key into the chat with the model.** Everything typed there
is saved to `docs/prompt-log/`, which is committed to a public repository.
The logging hooks now scrub Stripe keys (2026-09-27), but that is a seatbelt,
not permission. If a key ever lands somewhere it should not, rotate it: API
keys page, the ⋯ menu beside the key, **Rotate key**.

**A. The account**

1. Go to https://dashboard.stripe.com/register and sign up: email, name,
   country United States, password. Confirm the email Stripe sends.
2. Skip every "activate your account" or "tell us about your business"
   screen. Testing needs none of it. The account can be handed to Tara
   before it takes real money: Settings, Team, invite her as Administrator,
   then **Transfer ownership** to her (Stripe's own flow).

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
   Use this standard secret key. Stripe may suggest a restricted key; for
   live mode the model will set one up with only the permissions our code
   uses (least privilege), but for testing the standard one is right.

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
    switched **off** until you say go, because switching them on means
    nobody can register without a saved card, and that should wait for the
    TestFlight build with the card step (build 3). Then the eight-row
    test in `docs/stripe-e2e-test.md`, with your own account.

**The terminal command you may have seen** (`supabase secrets set
STRIPE_SECRET_KEY=...`) is not needed. It does exactly what steps 8, 9 and
16 do, and typing a key into the terminal leaves it in your shell history
file in plain text. Use the web page.

**Later, for real money (live mode):** Stripe, **Activate account**, with
Tara's business and bank details typed **into Stripe's own form** by you or
her, never into chat or a doc. Then the same steps C to E in live mode
(`pk_live_`, a restricted key instead of `sk_live_`, a live webhook with the
same five events), and the model swaps the three secrets.

## 2. Privacy policy (checklist C6), about 10 minutes

Apple needs a public privacy policy URL before external TestFlight testers or
the App Store. Tara said reuse Volee's (decision 16).

1. Open the draft on GitHub:
   https://github.com/Volee-Team/FXE/blob/main/docs/legal/privacy-policy.md
   and scroll to the last section, **"What changed from Volee's text, for
   approval"**. Eight numbered changes.
2. Number 3 is the one with legal weight. Volee's policy says it shares data
   with no third parties. Ours cannot say that: Stripe handles the cards,
   Apple delivers notifications, and Supabase hosts the data, so the draft
   names all three as service providers. The other seven swap Volee's facts
   for ours (what we collect, adults only, what deleting an account does, no
   tracking cookies).
3. Pick the contact email the policy will show, the address members write to
   about their data (a club address Tara reads is best).
4. Tell the model: **"privacy approved, contact is \_\_\_"**, or which change
   you want different.
5. The model then removes the Draft banner, dates it, publishes it at
   `https://fxe-tennis-admin.vercel.app/privacy.html`, adds a Privacy policy
   link on Profile (listed for your tick), and checks the live page from
   outside.
6. Paste that URL into App Store Connect: the app, **App Information**,
   **Privacy Policy URL**. On John's account for now, so John or whoever has
   access there does this. Moving the page to fersc.com later changes only
   the URL.

## 3. Push notifications (checklist C3): blocked on Apple approving the LLC

Nothing to do until Apple's email arrives. Then:

1. https://developer.apple.com/account → **Certificates, Identifiers & Profiles → Keys → +**.
   Name it "FXE Push", tick **Apple Push Notifications service (APNs)**, Continue, Register.
2. **Download** the `.p8` file. Apple lets you download it once. Put it in
   LastPass. Note the **Key ID** on that page and the **Team ID** (top right of
   the developer site).
3. In Terminal, from the repo folder:
   ```bash
   supabase secrets set APNS_KEY_ID=<key id> APNS_TEAM_ID=<team id> APNS_TOPIC=<final bundle id> PUSH_WEBHOOK_SECRET=$(openssl rand -hex 32)
   ```
   ```bash
   supabase secrets set APNS_PRIVATE_KEY="$(cat ~/Downloads/AuthKey_<key id>.p8)"
   ```
4. The model then creates the two Vault entries (the URL and the same
   webhook secret) and sends one real invitation to your phone.

The final bundle id is decided when the LLC account exists; today's
`com.fxetennis.app` is a placeholder.

## 4. John: TestFlight build 3 (checklist C8, C10)

`main` is ready: a Release build on 2026-09-27 carried build number 3, the
camera sentence Apple asked for, the encryption flag, and the real backend.
The build number is already 3 in `project.yml` (his PR #58), so no bump is
needed. Text John something like this:

> John, build 3 is ready on `main`. `git pull`, `xcodegen generate`, open
> the project, scheme FXETennis, destination Any iOS Device, Product →
> Archive, then Distribute App → TestFlight Internal Only → Upload. The
> camera sentence and the encryption flag are in this build, so Apple should
> not bounce it and App Store Connect should not ask the export question.
> After it processes, add it to the internal group, then tag it:
> `git tag -a v0.1.0-tf3 -m "TestFlight build 3, uploaded by John"` and
> `git push origin v0.1.0-tf3`. Full steps are in `docs/testflight.md`.

What testers get in build 3: the new front page with Tara's court photo, the
card step with the permission box, the back-to-back 105 rule, the board
report on Tara's web admin, and every fix since build 2. Payments stay off
until you say go (checklist A9).

## 5. Tara's review page, round four (checklist G2), about 5 minutes

**Do not send the round-three link.** Tara answered round two on 2026-09-22
and nobody had read it (decision 0016); round three would have asked her the
same things again. Round four is only what is new since then: 15 words to
Keep or Change, nine questions (who the pros are and what they may do, guests
without the app, the board's 10%, the 105 rule, how members hear about the
app, how they reach her, the waiver after deletion, a declined card, telling
a player when she moves them), and three things to try.

1. Wait for the model to say round four is live (it deploys it and checks the
   live page says version 4).
2. On a laptop, open https://fxe-tennis-admin.vercel.app and sign in with the
   admin login.
3. Click the small grey **Testing** link at the very bottom right of the page.
4. Under **Review links**, type a label such as `Tara round 4`, click **Make
   link**, then **Copy**.
5. Text her the link, with something like: *"Your changes from last week are
   in the app. This is only what's new: 15 words and 9 short questions. One
   line each is plenty, and it saves as you type."*
6. Nothing else to do: when she saves answers, GitHub opens an issue labelled
   `tara-answers` and the next session with the model starts with it.

## 6. Email that reaches members (checklist D1), about 10 minutes, free

Today a member who taps Forgot password gets nothing: Supabase's built-in
sender delivers only to the Supabase project's own team, 2 an hour (verified
2026-09-27 through the management API). Two things are already done so this
is the only step left:

- **Tara can already reset anyone by hand**: Players tab → the member →
  **Reset link** → Copy → text it to them. It works once, within an hour, and
  needs no email at all (decision 0017).
- **The reset page and the Site URL are handled** by the model (D11).

The simplest free sender is a Gmail account made for the app. Gmail allows
about 500 emails a day, far more than a club needs. Use a NEW account, not
Tara's: its app password goes into Supabase, so it should be an account whose
only job is sending the app's email.

1. Make a new Gmail account for the app, for example `fxetennis.app@gmail.com`
   (any free name). Use your phone number for its recovery. Save the password
   in LastPass.
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
   management API (it never sees the password), switches the reset email to
   the scanner-proof link, and asks you for one real test: Forgot password
   with your own email, the email arrives from FXE Tennis, the link opens the
   reset page, the new password signs you in.

Later, if the club wants email from its own domain (`noreply@fersc.com`
rather than a Gmail address): Resend's free plan, host `smtp.resend.com`,
port 465, username `resend`, password a Resend API key, after adding the DNS
records Resend shows to the domain. Not needed for launch.

The reset email's wording is Supabase's default. Tara may want her own words
later; that is a question for her, not a blocker.

## 7. Kat's three style calls (checklist G3), one message

Text Kat something like this:

> Three quick style calls on the app:
> 1. **Bottom tab bar.** iOS 26 draws it as frosted glass and won't take a
>    solid navy fill. Today it's the system bar with a green active icon and
>    navy inactive ones. Keep it, or build our own navy bar (about a day)?
> 2. **Green text.** Your gator green (#4F7A38) on the porcelain background
>    measures 4.42:1 contrast, just under the 4.5:1 accessibility minimum for
>    small text. OK to use a slightly darker green (#446A30, 5.51:1) for text
>    only, and your green everywhere else?
> 3. **The header.** Now straight across as you asked, with the guide's thin
>    green line along the bottom. Keep the green line, or plain navy like
>    Tara's mockup?

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

## 9. From Tara (checklist G5, D5), a text is enough

- **How many courts the club has** (checklist D15): one number; the app
  allows 1 to 5 today.
- **The logo file** she mentioned ("not that one"), any format, the largest
  she has.
- **The original court photo** from her phone (the one in the message is a
  small screenshot and looks soft full screen).
- **Her real templates and clinics** in the admin site. The review page's
  "Try it" tab walks her through it.

## 10. Decisions only you can make

| Checklist | Decision | When | The model's recommendation |
|---|---|---|---|
| A9 | Switch payments on | After the next build is on testers' phones | Go for testers as soon as the build is out, then run the payment test the same day; not for everyone until live keys (A11) |
| G1 | Payments and push in the MVP or not (with Kat and Tara) | This week | Payments in; push in only if Apple approves the LLC in time, otherwise launch with in-app notifications |
| C11 | Fallback if the LLC is not approved in time: external TestFlight on John's account with a public link | This week (was 10-09; see below) | Yes: prepare it (needs the privacy URL), use it only if needed |
| C12 | The LLC app's bundle id (the current one is locked to John's account) | Before the first LLC build | Accept a new id such as `com.fxetennis.club`; testers reinstall once |
| D3 | Supabase Pro ($25 a month): no pause after a quiet week, point-in-time recovery | Before real members | Yes, from launch week |
| A11 | Cut-off for real money at the party: if Tara's Stripe live activation (A7) is not done by 2026-10-14, payments stay off on 10-16 | With G1 | Yes, 10-14. And never switch "card required" on for everyone while the keys are sandbox: a real card is declined in test mode |
| C3 | Push with **John's** APNs key now: every tester build is signed by his team, so the LLC's key could never reach those phones | With G1 | Yes if push is in: ask John for a key (developer account, Keys, +, Apple Push Notifications service) |
| C11 (again) | Upload one build to external beta review **this week**, no testers invited, so Apple's review is done before it matters | This week | Yes |
| C13 | Apple's reviewer account: one real account called App Review, made through the app's sign-up with an address you control | Before the first external or App Store submission | Yes; the review notes give Stripe's 4242 test card while keys are sandbox |
| D14 | Raise the sign-in rate limit from 30 to about 300 per 5 minutes per IP: the party shares one Wi-Fi address | Before the party | Say go and the model sets it through the management API |

## 11. Business

- **Apple LLC enrollment (checklist C1).** Still processing on 2026-09-27. If
  there is no email by 2026-10-01, contact Apple Developer Support
  (https://developer.apple.com/contact, Membership and Account, Program
  Enrollment) and ask what is outstanding.
- **Stripe live mode (checklist A7)** after the payment test passes: Tara's
  business and bank details typed into Stripe's own form by you or her, then
  move the account's ownership to her.
