# 0059. Remove the dead code, keep what an app on a phone still calls (2026-11-17)

**Status:** accepted by John, 2026-11-17 (*"clean up all of that for
1.0.5"*). Built in `supabase/migrations/20261117000001_drop_dead_code.sql`
and the app, branch `cleanup-dead-code`. Ships with 1.0.5.

## What was asked

John asked *"how much dead code is there?"*. A read-only survey of the repo
answered that very little was dead, about 2% of the Swift app plus a few
database objects; the web, the edge functions and the scripts had none. Every
candidate was grepped across the whole repo before it counted. He then asked
for all of it to go in 1.0.5.

## Removed

**App** (no caller anywhere in `FXETennis/`):

- `NotificationCopy.swift`:
  - `NotificationAudience` and the `audience`, `typeKey`, `trigger` and
    `title` members;
  - the lock-screen measuring (`sentenceCount`, `characterCount`,
    `fitsLockScreen`);
  - `catalogueSamples`.

  The catalogue itself, its bodies and the formatters stay: they are the
  record of Tara's wording, and the app reads `registrationIsOpen.body` and
  the day, date and time formatters.
- The Charge whole clinic chain: `AdminRepository.chargeClinic`,
  `LedgerOutcomeRow`, `ChargeSummary`, `ChargeOutcome` and
  `ChargeSummaryTests`. The button left both screens with decision 0037.
- The News client: `NewsRepository` and `NewsPost`.
- `NavyHeaderBar`, unused since the bell moved into the header.
- Unused `Brand` tokens:
  - colours: `navyPressed`, `courtShade`, `aceYellow`, `surfaceInverted`,
    `textOnCourt`, `textOnAccent`, `focusRing`;
  - type: `Typography.displayDesign`, `bodyDesign`;
  - radii: `Radius.xs`, `Radius.pill`.

  `web/tokens.css` keeps its own copies.
- `AdminRepository.place`, `PlacePlayerParams` and `setPlayerRating`. The
  laptop calls `place_player` and `admin_set_player_rating` directly, so
  those functions stay.
- `Repositories.myCourtesyAvailable`.
- `gator-x.pdf` in the app's Brand resources folder, bundled but never loaded:
  `Image("gator-x")` reads the asset catalog's PNG.

**Database:**

- News, deferred by decision 0006 and never switched on: `my_news`,
  `mark_news_read`, `publish_news`, `news_posts`, `news_reads` and the two
  news enum types. Hosted held 0 rows in each table.
- `create_clinic_from_template`, replaced by `admin_upsert_clinic` and
  `admin_copy_week`.
- `admin_delete_template`: templates are archived instead.
- `my_courtesy_available`: decision 0013 left no courtesy, and its only
  caller was the app wrapper above.
- `admin_app_diagnostics`: no screen reads crash reports; they are read on
  hosted with SQL.
- `revenue_by_clinic` and `revenue_by_segment`: the Money tab reads
  `revenue_summary()`.

## Kept, and why

- **`admin_charge_clinic`.** TestFlight builds 2 to 8 call it from Tara's
  Charge clinic button, and builds 7 and 8 were seen on hosted as late as
  2026-11-05 (`waiver_acceptances.app_version` and
  `card_consents.app_version`). Drop it once those builds have expired.
- **The `FXENotification` catalogue.** Its 14 server-sent cases are Tara's
  wording, kept on purpose.
- **`stripe_cutover_to_live`.** A one-time step of the go-live procedure
  (launch checklist A10).
- **`clinics.price_cents`.** Already its own backlog row; dropping it touches
  `clinics_public` and `clinics_admin`.
- **`scripts/backfill-prompt-log.py`.** Uncertain, not proven dead.

## How old apps were protected

Every object dropped was looked for at every release tag and release branch,
from build 2 to 1.0.4 (19), in `FXETennis/`, `web/` and
`supabase/functions/`. Where the Swift named one, it was inside a wrapper
nothing called, except `admin_charge_clinic`, which stays. The migration
uses no `CASCADE`. Dependents were listed with `pg_depend` first:

- `my_news` was the only reader of the two news tables;
- the revenue views had no dependents;
- `revenue_summary()` never read them.

## Pinned by

- **Probes:** the existing probes, rewritten where they read a dropped object.
  - `pricing_and_revenue.sql` and `account_deletion.sql` read the same
    numbers from `revenue_summary()` and from `registrations`.
  - `registration_window_rule.sql` creates its clinic through
    `admin_upsert_clinic`.
  - `admin_clinic_crud.sql` attacks archiving.
  - `app_diagnostics.sql` now asserts that no client can call any
    diagnostics function except the phone's one write.
- **Smoke lists:** `scripts/hosted-smoke.sh` and
  `scripts/hosted-smoke-functions.txt` (regenerated) no longer name the
  dropped objects.
