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
| Stripe customer receipts setting | Not checked | Alex to report whether his inbox got a receipt | never |
| Apple: FXE Tennis, LLC developer account | Pending as far as known (authority letter, case 102990597020); no Apple email in Alex's inbox | Gmail search of Alex's inbox | 2026-10-16 |
| Testers' installed build | Build 7 (`v0.1.0-tf7`) was the last upload reported | Git tags; John has not reported builds 8 to 11 | 2026-10-16 |
