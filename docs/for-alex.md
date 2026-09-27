# For Alex: everything only you can do, step by step

Living file. The model keeps it current; Alex reads it instead of chat.
Updated 2026-09-26. Newest asks first within each item. When a step is done,
tell the model "done with N" and it verifies and strikes it here.

Never paste a key, password or secret into chat. Every step below keeps the
value between you and the website.

---

## 1. Stripe test keys (about 20 minutes) — blocks all payments

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

## 2. Privacy policy (10 minutes) — blocks external TestFlight testers and the App Store

1. Open `docs/legal/privacy-policy.md` and read only the section at the
   bottom, **"What changed from Volee's text"**. Eight numbered changes.
   Number 3 is the one with legal weight (it names Stripe, Apple and the host).
2. Fill in the two blanks near the end: the contact email, and today's date.
   Tell the model the email, or edit the file.
3. Pick the URL: the admin site now
   (`https://fxe-tennis-admin.vercel.app/privacy.html`) or fersc.com later.
4. Tell the model "privacy approved, contact is X". Until then the page is
   kept out of every deploy by `web/.vercelignore`. It removes the Draft
   banner, deploys the page, links it from Profile, and gives you the URL to
   paste into App Store Connect.

## 3. Push notifications — blocked on Apple approving the LLC

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

## 4. Tara's review page — 2 minutes

1. Open https://fxe-tennis-admin.vercel.app, sign in as Tara's admin account.
2. Click the grey **Testing** tab (far right).
3. Under **Review links**, type a label (for example "Tara round 2"), click
   **Make link**, then **Copy**.
4. Text her the link. Her answers save as she types; they show under
   **Responses** on the same tab. Tell the model when she is done.

The page (version 3, 2026-09-27) now carries 17 questions: the six from
round two and eleven from the Final Updates (the board's 10%, Home with one
clinic, four about back-to-back 105s, the card box, the court photo and
logo), plus a "Try it" task to run the board report.

## 5. Kat — one message

Kat answered the header on 2026-09-26 ("straight line across"); it is built
straight. Three left:

- **The green line under the header.** Built straight, 4pt, because her
  guide had it and she asked for more colour. Keep it, or plain navy into
  the photo like Tara's mockup?

- **Tab bar colour.** iOS 26 will not paint the bottom tab bar solid navy.
  Is the light system bar with green and navy icons fine, or should we build
  our own navy bar (about a day)?
- **Green text contrast.** The guide's green is slightly too light for small
  text by the accessibility standard. OK to use a shade darker for text only?

## 5b. John: the next TestFlight build

After PR #58 merges (John's purpose strings, with the camera sentence
corrected), John archives **build 3** from `main` per `docs/testflight.md`.
It carries everything through 2026-09-27: the new front page, the card
step, the 105 rule. Build 2 was rejected-then-fixed on his branch only; any
archive from `main` before #58 would be rejected again by Apple for the
missing camera sentence.

## 6. From Tara (a text is enough)

- **The logo file.** She wrote "Need to get you the logo - not that one".
  Any format; the model swaps it in.
- **The court photo as the original file** (question 64). The one she sent
  is a screenshot and looks soft on a full screen.
- **Questions 58 to 65** in `docs/questions-for-tara.md` §M: the board's
  10%, Home with one clinic, four about the back-to-back 105 rule, the card
  box wording. They go on her review page next round.

## 7. Two GitHub settings (5 minutes)

Recommended in `docs/practice-ideas.md`, which also has the answer on Jev.

1. https://github.com/Volee-Team/FXE/settings/branches → edit the rule
   for `main`. It exists already (checked 2026-09-26 with `gh api
   .../branches/main/protection`) and requires "Build iOS app + unit tests"
   and "SQL probes + concurrency". Add "Hosted is closed to a signed-out
   caller" to the required checks, and tick "Do not allow bypassing the
   above settings" (today `enforce_admins` is off, so an admin, which the
   model's token is, can merge red).
2. https://github.com/Volee-Team/FXE/settings/security_analysis → turn on
   Dependabot alerts.

## 8. Business (no rush from the model's side)

- Apple LLC enrollment: chase if no email by 2026-10-01.
- Password-reset email: a free Resend account plus two DNS records on the
  club's domain; before members, not before testers.
