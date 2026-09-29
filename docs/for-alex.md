# For Alex: how to do each thing only you can do

**What is left, and whose it is, lives in `docs/launch-checklist.md` and
nowhere else.** This file is only the how-to for Alex's rows, click by click.
Each section names its checklist row; the CI check fails if a section points
at a row that does not exist. Updated 2026-09-28.

Never paste a key, password or secret into the chat with the model. Everything
typed there is saved to `docs/prompt-log/`, which is committed to a public
repository. The logging hooks scrub key-shaped text and the secret scan fails
on it, but those are seatbelts, not permission.

---

## 0. Answers to your questions of 2026-09-27 night (checklist C8, C13, G3)

**Logo file and court photo.** Two things Tara mentioned herself on
2026-09-26 (decision 0015), not things we lost:
- In her marked-up front page she wrote *"Need to get you the logo - not that
  one…"*: she has a different or newer FXE logo than the gator the app uses.
  If she never sends one, the current logo stays; nothing breaks.
- The court photo behind every screen came from the picture she texted, which
  was a small screenshot (920 pixels wide), so it looks slightly soft on a
  full phone screen. If she has the original photo on her phone, a text of it
  makes it sharp. Again optional.

**Supabase Pro ($25 a month): can we upgrade later?** Yes. Two things it
buys: (1) the free plan pauses a project after about a week with no traffic
(it happened once, 2026-09-01), and (2) point-in-time recovery. With real
members opening the app every day it will not go quiet, and we already have
our own encrypted nightly backups. So: upgrade the week of the launch party,
or whenever the app is in real members' hands every day. Not needed tonight.

**Kat's questions, exactly** (section 7 below has the message to send her):
1. The bottom tab bar: iOS 26 draws it as frosted glass and will not take a
   solid navy fill. Keep the system bar (green active icon, navy inactive), or
   build our own navy bar (about a day)?
2. Green text: her gator green (#4F7A38) on the porcelain background is 4.42:1
   contrast, just under the 4.5:1 accessibility minimum for small text. OK to
   use a slightly darker green (#446A30, 5.51:1) for text only?
3. The header: straight across as she asked, with the style guide's thin green
   line along the bottom. Keep the line, or plain navy like Tara's mockup?

**The .p8 file.** It is the file Apple gives you when you create a push
notification key: a small text file named like `AuthKey_ABC123DEFG.p8`. It is
the private key our server uses to prove to Apple that it is allowed to send
notifications to the FXE Tennis app. Apple lets you download it exactly once,
so it goes straight into LastPass. Steps, redone: section 3 below.

**The App Review test account.** Before Apple lets strangers install the app
(external TestFlight, and later the App Store), a person at Apple opens it and
tries it. They cannot sign up with a club membership or a real card, so App
Store Connect asks for a working email and password for them to sign in with.
We make one real account for them:
1. On build 5 (TestFlight on your phone), sign up with
   `fxetennis.app+review@gmail.com` (Gmail delivers "+review" to the inbox you
   just made) and a password you save in LastPass.
2. Finish the profile (name "App Review", any rating, member: No) and sign the
   waiver.
3. In App Store Connect → the app → TestFlight → **Test Information** (and
   later App Review Information), fill in that email and password, and in the
   notes: "Tennis clinic registration for a private club. Card payments are
   for a real-world service (clinic fees), so no in-app purchase applies."
Checklist C13. The model keeps this account out of the board report.

**What to tell John.** Archive the commit tagged `v0.1.0-rc5` (build 5):
`git fetch --tags && git checkout v0.1.0-rc5`, then the usual steps in
section 4. Build 4 was never archived; 5 has everything from 4 plus the
night's polish (section I of the checklist). The tag means he gets exactly the
build that was tested, whatever lands on `main` afterwards.

**Your "wow" direction.** Recorded as a standing rule: player-facing features
that impress on first open, not just the minimum. Tara-facing items (pro
logins, guests billed to a member, her Contact link) are in
`docs/roadmap.md` and wait on her answers (questions 71, 72, 76).

---

## 1. Stripe keys (checklist A1, A8, A12): A1 and A8 DONE 2026-09-27; step G (A12) is new

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
    TestFlight build with the card step (build 4). Then the eight-row
    test in `docs/stripe-e2e-test.md`, with your own account.

**G. Three more events, for chargebacks (checklist A12), two minutes**

When a player's bank takes back a clinic fee, Stripe sends one of three
events; without them the app never hears about it and nothing reaches
Tara's Action Needed (decision 0021).

18. Stripe dashboard (sandbox), **Developers** → **Webhooks** → the endpoint
    ending in `/stripe-webhook`.
19. **⋯** (or **Edit destination**) → **Select events** → search `dispute`
    and tick `charge.dispute.created`, `charge.dispute.updated` and
    `charge.dispute.closed`. Keep the five already ticked. **Save** / **Update
    destination**. Eight events in all.
20. Nothing to copy: the signing secret does not change. Tell the model
    "dispute events added" and it checks the next test dispute lands.

**The terminal command you may have seen** (`supabase secrets set
STRIPE_SECRET_KEY=...`) is not needed. It does exactly what steps 8, 9 and
16 do, and typing a key into the terminal leaves it in your shell history
file in plain text. Use the web page.

**Later, for real money (live mode):** Stripe, **Activate account**, with
Tara's business and bank details typed **into Stripe's own form** by you or
her, never into chat or a doc. Then the same steps C to E in live mode
(`pk_live_`, a restricted key instead of `sk_live_`, a live webhook with the
same eight events), and the model swaps the three secrets.

## 2. Privacy policy (checklist C6): DONE 2026-09-27

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

## 2b. Stripe to Tara (checklist A7), about 10 minutes of yours, 20 of hers

Real money at the party is the goal (A11). The Stripe account you made has to
become Tara's before it can take real payments: Stripe's live activation asks
for the business owner's own details and bank account, typed by her into
Stripe's own form, never into anything of ours.

**You, today:**

1. https://dashboard.stripe.com → the gear (Settings) → **Team and
   security** → **Team** → **+ Add member**.
2. Her email (fersctennispro@gmail.com, or whichever she uses), role
   **Administrator** → **Send invite**.

**Tara, from the invite email:** she creates her Stripe login (or signs in)
and accepts.

**You again, once she shows on the Team page:**

3. On her row → the **⋯** menu → **Transfer ownership** → confirm. Only the
   owner can do this, which is you today.
4. You can stay on the team as Administrator (useful for helping her) or
   remove yourself later.

**Tara, as the owner: activate the account** (checklist A7). Stripe shows an
**Activate payments** / **Complete your profile** banner. She fills in:
FXE Tennis, LLC as the business, its EIN, her own details as the
representative, and the bank account payouts go to. Stripe may take a day or
two to verify. This is the step with the 2026-11-04 deadline (A11; it was 10-14 until the party moved to 11-06).

**Then the model** (checklist A10): builds the live key swap, the live webhook
and the cutover migration that clears everyone's test cards, and runs the
payment test (A2) with you. Nothing about the test keys changes before then.

## 3. Push notifications (checklist C3): John's key, about 10 minutes

Decided 2026-09-27: push works for launch, on **John's** Apple account, because
every tester build (and the launch build, if C11 is used) is signed by his
team. A key from the LLC could never reach those phones. When the LLC's app
ships later, it gets its own key the same way.

**John (or you, signed in to his account with his OK):**

1. https://developer.apple.com/account → **Certificates, IDs & Profiles** →
   **Keys** → the **+** button.
2. Key name `FXE Push`. Tick **Apple Push Notifications service (APNs)**.
   Continue → Register.
3. **Download** the `.p8` file. Apple allows one download only, so save it
   straight into LastPass as an attachment. Copy the **Key ID** shown on that
   page.
4. Copy the **Team ID**: Membership details on the same site (10 characters).
5. Check the app has push switched on: **Identifiers** → `com.fxetennis.app`
   → **Push Notifications** is ticked. Xcode ticks it on its own when he
   archives, since the project asks for push; if it is not there, tick it and
   Save.

**You, in Terminal from the repo folder** (the values go straight to Supabase,
never into a chat or a file in the repo):

```bash
supabase secrets set APNS_KEY_ID=<key id> APNS_TEAM_ID=<team id> APNS_TOPIC=com.fxetennis.app
```

```bash
supabase secrets set APNS_PRIVATE_KEY="$(cat ~/Downloads/AuthKey_<key id>.p8)"
```

Then delete the `.p8` from Downloads (LastPass has it) and tell the model
**"push key is in"**. It does the rest in one step nobody sees: generates the
webhook secret in a shell variable and puts it both in the function's secrets
and in the database's Vault (with the function's address), so the two match
without the value ever being printed. Then it sends one real invitation to
your phone running build 4 to prove it, and reads back whether Apple took it.
No `APNS_HOST` is needed: TestFlight builds use Apple's production server,
which is the default.

## 4. John: TestFlight build 5 (checklist C8, C10)

**Build 5 is the tag `v0.1.0-rc5`.** The build number is already 5 in
`project.yml`. Build 4 was never archived, so nothing is lost. Text John
something like this:

> John, build 5 is ready. `git fetch --tags && git checkout v0.1.0-rc5`,
> `xcodegen generate`, open the project, scheme FXETennis, destination Any
> iOS Device, Product → Archive, then Distribute App → TestFlight Internal
> Only → Upload. After it processes, add it to the internal group, then tag
> it: `git tag -a v0.1.0-tf5 -m "TestFlight build 5, uploaded by John"` and
> `git push origin v0.1.0-tf5`. Full steps are in `docs/testflight.md`.

What testers get in build 5: everything from the MVP audit (bad signal read
as bad signal, not "no account"; screens that refresh when you come back;
Register at 8:00 on its own; a way out of every sign-up step), plus the
night's polish: Accept and Decline right on an invitation's notification (once
push is live), Add to Calendar on a clinic you're in, Remind me when
registration opens, text that grows with the iPhone's Larger Text setting,
a readable clock on the navy screens, Return moving through the sign-in form,
and on Tara's side a Payouts card and chargeback alerts on the laptop's Money
tab. Payments stay off until you say go (checklist A9).

## 4b. The QR code's link (checklist I6), one message

The QR code Tara prints and emails points at
https://fxe-tennis-admin.vercel.app/app, which shows "Not available yet." until
it knows where the app installs from. When the external TestFlight beta is
approved, App Store Connect → the app → TestFlight → the external group →
**Public Link** → copy it (it looks like `https://testflight.apple.com/join/…`)
and send it to the model. It sets one line (`web/app/target.js`) and deploys;
the printed code never changes, even when the App Store link replaces it later.
Tara's card: web admin → Players → **QR code for the app** → Print, or
Download for email.

## 5. Tara's review page, round four (checklist G2), about 5 minutes

**Do not send the round-three link.** Tara answered round two on 2026-09-22
and nobody had read it (decision 0016); round three would have asked her the
same things again. Round four is only what is new since then: 15 words to
Keep or Change, 17 short questions (who the pros are and what they may do,
guests without the app, the board's 10%, the 105 rule, how members hear about
the app, how they reach her, the waiver after deletion, declined cards,
telling a player when she moves them, and three from 2026-09-28: the day or
the date in "You're all set", a bank taking back a fee, the late-request
message), and three things to try.

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

## 6. Email that reaches members (checklist D1): DONE 2026-09-27, one test left

**Done:** the Gmail account, 2-Step Verification, the app password in
Supabase, the rate limit, and the scanner-proof reset link (read back through
the management API). **Left:** one real test, step 6 below, with your own
email. The steps stay here for the record.

Before this, a member who tapped Forgot password got nothing: Supabase's
built-in sender delivers only to the Supabase project's own team, 2 an hour
(verified 2026-09-27 through the management API). Two things were already
done before the email step:

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
| Backlog, 2026-09-28 | **Should the app refuse to put someone in, or message, a clinic Tara has not published yet?** Today it allows both (a draft looks like any card on her laptop) | Any time; nothing waits on it | Keep allowing: it is her tool, and nothing reaches a player about a never-published clinic that gets canceled (20260929000002). Refuse if she ever sets up next week and forgets to publish |
| A9 | Switch payments on | After the next build is on testers' phones | Go for testers as soon as the build is out, then run the payment test the same day; not for everyone until live keys (A11) |
| G1 | Payments and push in the MVP or not (with Kat and Tara) | Decided 2026-09-27 | Both in: payments fully live for the party (A11), push fully working (C3) |
| C11 | Fallback if the LLC is not approved in time: external TestFlight on John's account with a public link | This week (was 10-09; see below) | Yes: prepare it (needs the privacy URL), use it only if needed |
| C12 | The LLC app's bundle id (the current one is locked to John's account) | Before the first LLC build | Accept a new id such as `com.fxetennis.club`; testers reinstall once |
| D3 | Supabase Pro ($25 a month): no pause after a quiet week, point-in-time recovery | Before real members | Yes, from launch week |
| A11 | Cut-off for real money at the party: if Tara's Stripe live activation (A7) is not done by 2026-11-04 (it was 10-14; the party moved to 11-06), payments stay off on 10-16 | Decided 2026-09-27 | Yes, 10-14 (your answer). Never "card required" for everyone while the keys are sandbox: a real card is declined in test mode |
| C3 | Push with **John's** APNs key now: every tester build is signed by his team, so the LLC's key could never reach those phones | Decided 2026-09-27 | Yes: John makes the key (section 3), you set the secrets |
| C11 (again) | Upload one build to external beta review **this week**, no testers invited, so Apple's review is done before it matters | Decided 2026-09-27 ("yes prob") | The privacy URL is live now, so build 5 can go to beta review as soon as John uploads it |
| C13 | Apple's reviewer account: one real account called App Review, made through the app's sign-up with an address you control | Before the first external or App Store submission | Yes; the review notes give Stripe's 4242 test card while keys are sandbox |
| D14 | Raise the sign-in rate limit for the party's one Wi-Fi address | Done 2026-09-27 | 30 → 300 per 5 minutes, set and read back through the management API |
| I1 (decision 0022 §5) | **A behaviour change you can veto:** nobody can accept an invitation into a clinic Tara canceled or that has already ended, and Tara's Invite and "Put them in" are gone on a canceled clinic | Built 2026-09-28 | Keep: a stale invitation tapped days later landed a player in a finished clinic and got them charged. Where the Accept cut-off sits (start or end) is Tara's question 91 |

## 11. Business

- **Apple LLC enrollment (checklist C1).** Still processing on 2026-09-27. If
  there is no email by 2026-10-01, contact Apple Developer Support
  (https://developer.apple.com/contact, Membership and Account, Program
  Enrollment) and ask what is outstanding.
- **Stripe live mode (checklist A7)** after the payment test passes: Tara's
  business and bank details typed into Stripe's own form by you or her, then
  move the account's ownership to her.
