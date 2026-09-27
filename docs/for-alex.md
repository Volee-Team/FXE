# For Alex: everything only you can do, step by step

Living file. The model keeps it current; Alex reads it instead of chat.
Updated 2026-09-26. Newest asks first within each item. When a step is done,
tell the model "done with N" and it verifies and strikes it here.

Never paste a key, password or secret into chat. Every step below keeps the
value between you and the website.

---

## 1. Stripe test keys (about 15 minutes) — blocks all payments

Status 2026-09-26: `supabase secrets list` on hosted shows no `STRIPE_*` secret.

1. Go to https://dashboard.stripe.com/register and sign up. Business name
   "FXE Tennis" is fine. Skip "Activate your account" for now.
2. Top right of the dashboard: make sure **Test mode** is on.
3. **Developers → API keys.** You will copy two values: the *Publishable key*
   (`pk_test_…`) and the *Secret key* (`sk_test_…`, click Reveal).
4. Open https://supabase.com/dashboard/project/amnaxvznkadkgzdxzegw/functions/secrets
   and add two secrets:
   - `STRIPE_SECRET_KEY` = the `sk_test_…` value
   - `STRIPE_PUBLISHABLE_KEY` = the `pk_test_…` value
5. Back in Stripe: **Developers → Webhooks → Add endpoint.**
   - Endpoint URL: `https://amnaxvznkadkgzdxzegw.supabase.co/functions/v1/stripe-webhook`
   - Events (search each and tick it): `setup_intent.succeeded`,
     `payment_intent.succeeded`, `payment_intent.payment_failed`,
     `refund.updated`, `charge.refunded`
   - Save. On the endpoint page click **Reveal** under *Signing secret* (`whsec_…`).
6. Supabase secrets page again: add `STRIPE_WEBHOOK_SECRET` = the `whsec_…` value.
7. Tell the model "Stripe keys are in". It checks the names exist (it never
   sees the values) and runs the end-to-end test in `docs/stripe-e2e-test.md`
   with you.

Later, for real money (live mode): Stripe → Activate account, Tara's business
and bank details typed **into Stripe's own form** by you or her, never into
chat or a doc. Then repeat steps 3 to 6 with the `pk_live_`/`sk_live_` keys and
a live-mode webhook.

## 2. Privacy policy (10 minutes) — blocks external TestFlight testers and the App Store

1. Open `docs/legal/privacy-policy.md` and read only the section at the
   bottom, **"What changed from Volee's text"**. Eight numbered changes.
   Number 3 is the one with legal weight (it names Stripe, Apple and the host).
2. Fill in the two blanks near the end: the contact email, and today's date.
   Tell the model the email, or edit the file.
3. Pick the URL: the admin site now
   (`https://fxe-tennis-admin.vercel.app/privacy.html`) or fersc.com later.
4. Tell the model "privacy approved, contact is X". It removes the Draft
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
