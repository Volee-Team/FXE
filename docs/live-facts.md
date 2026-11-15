# Live facts no script can read

`scripts/live-status.sh` re-derives everything it can from the live systems
(hosted database, Supabase secrets, migrations, GitHub). These are the facts
it cannot see: settings in Stripe's dashboard, Apple, and what people said.
Each row says how it was verified and when. A row older than a few days is
re-checked (by browser, read-only) before it is repeated as true.

Why this file exists (2026-10-16): the model's status list said Tara's bank
was not linked and no real charge had happened, both done in the same
session. A recalled status is not a status (hard rule 12).

| Fact | Value | How verified | When |
|---|---|---|---|
| Stripe payout bank | PNC, account ending 7473, default for the payments balance, ACH routing | Stripe dashboard, Settings, Linked accounts (browser, read-only) | 2026-10-16 |
| Stripe payout destination | Transfer all revenue to the payout bank account | Stripe dashboard, Settlement and transfer rules (browser, read-only) | 2026-10-16 |
| Stripe payout schedule | Automatic, daily | Same page | 2026-10-16 |
| Stripe live webhook | "FXE app", 9 events, API version 2026-08-26.dahlia, signature accepted (a real `setup_intent.succeeded` wrote a card at 19:37 on 10-14) | Live database row written only by a signed event | 2026-10-14 |
| First real money | Alex charged $23 and refunded it in live mode, 2026-10-14 20:11 and 20:12 | `scripts/live-status.sh` (money on hosted) | 2026-10-16 |
| Stripe customer receipts setting | Off: successful-payment and refund emails both off, as Tara asked (question 86, "No receipts") | Alex, 2026-10-21: "both off alr" | 2026-10-21 |
| Apple: FXE Tennis, LLC developer account | Never approved, and no longer needed: the app moved to Volee LLC's account instead (checklist C1, C12) | Checklist C1, C12 | 2026-11-14 |
| Members' site domain | `fxeclinics.com` and `www` (bought by John on Namecheap) on Vercel project `fxe-tennis-admin`: A @ 216.198.79.1 and 64.29.17.1, CNAME www to Vercel; certificate forced with `vercel certs issue` after 30 min without one; both answer 307 to `/play/` then 200 | `dig @8.8.8.8`, `curl -sL`, the built-in browser | 2026-10-27 |
| Supabase Auth redirect allow-list | `reset.html` on `fxe-tennis-admin.vercel.app`, `fxeclinics.com` and `www.fxeclinics.com` (management API, 2026-10-26) | `GET /v1/projects/.../config/auth` | 2026-10-26 |
| APNs key on hosted | Volee LLC's key `42D24JXB54` (team `FBJXDTHTN4`) since 2026-11-11 19:21 UTC, replacing John's `94698TDPGY` after the App Transfer (C2). Topic unchanged since 2026-10-03 | `supabase secrets list -o json` (APNS_KEY_ID, APNS_PRIVATE_KEY, APNS_TEAM_ID all updated 2026-11-11T19:21:44Z); push 976 of 1062 delivered in 14 days (`scripts/live-status.sh`) | 2026-11-14 |
| Apple: App Store release | FXE Tennis **1.0.3** (build 18) live since 2026-11-13, seller **Volee LLC**, 5 ratings, `https://apps.apple.com/us/app/fxe-tennis/id6814658300`. 1.0.0 was first released 2026-10-28 on John's account; App Transfer to Volee LLC 2026-11-11 (C12) | `curl "https://itunes.apple.com/lookup?bundleId=com.fxetennis.app"` (version 1.0.3, sellerName Volee LLC) | 2026-11-14 |
| Apple: Volee LLC developer account | **Approved**; FXE and Volee will both live on it (Alex, 2026-10-25) | Alex | 2026-10-25 |
| Apple: App Privacy rows | Product Interaction added by John; Purchase History not found by him yet (John's text, relayed 2026-10-25) | John via Alex | 2026-10-25 |
| Testers' installed build | Not a thing any more: players install from the App Store (C14); TestFlight is checklist C8 (LATER) | Git tags | 2026-11-14 |
| The 10-22 refunds (three on hosted) | On purpose: Tara charged two testers $22 each to try live payments, then they were refunded ("FXE testers" group text, 2026-10-22: Angie refunded, Jennifer "will refund you now too"), plus Alex's own $23 of 10-14 | Group text, read 2026-11-03 | 2026-11-03 |
| Emily B's "charge" (Tara, 2026-10-19: charged, money shown to Tara, not taken from her bank) | No charge to Emily exists: Stripe's Payments list has exactly three (Jennifer R and Angie K, $22 each, Oct 17 9:00 PM; Alex's $23, reversed). Emily never accepted Tara's invitation to Ladies 4.0+ on 10-15 (still Response Needed) and sat in the Player Pool for 10-07, so the app had nothing to charge her for | Stripe dashboard, Transactions (browser, read-only) and hosted `payments` / `registrations` (read-only query) | 2026-10-19 |
