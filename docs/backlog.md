# Backlog

Bugs, chores, and small things that are not worth a roadmap entry. **Anything
noticed and not fixed goes here in the same breath**, or it is forgotten.

Priority: 🔴 blocks a person · 🟡 should fix · 🟢 whenever

## Open

| | Item | Found | Note |
|---|---|---|---|
| 🟡 | **Tara's real clinic descriptions are not in the database** | 2026-08-16 | She sent verbatim copy for 105, Ladies 3.0+, All-Level Ladies, All-Level Men's and a new Queen City team practice. All transcribed in `docs/copy.md`; none of it is in `clinic_templates` or `clinics` yet. This is the content that makes a TestFlight build feel real to her instead of a demo |
| 🟡 | **Late-request path is not built** | 2026-08-27 | Half of Tara's own answer on close times: *"if they try to register within 3 hours, they have the option to send me a direct message to get into the clinic, assuming there is space and it isn't full."* Registration now closes 3h before start (decision 0007) with no way to ask in. Needs a UI path, a notification to her, and a not-full check |
| 🟡 | Clinic list has no date bounds in either direction | 2026-08-13 | `clinics_public` has no date clause, `clinic_status` has no terminal state, and `ClinicRepository.upcoming()` only orders. Past clinics accumulate forever and sort to the TOP, so Home's `prefix(3)` shows the three oldest |
| 🟢 | `anon` holds EXECUTE on 22 SECURITY DEFINER RPCs | 2026-08-13 | Not a live hole: `place_player` and `cancel_clinic` both return `not_authorized` to anon, verified. Revoke anyway as defence in depth, same reasoning as hard rule 11 |
| 🟡 | Notification triggers with no producer | 2026-08-02 | `REGISTRATION IS OPEN` needs a scheduler that does not exist. Copy is written, nothing fires it |
| 🟡 | Four "high" findings from the completeness review | 2026-08-02 | Docs drifted from code; probes asserting less than their comments claim |
| 🟢 | Six "medium" / seven "low" findings from the same review | 2026-08-02 | Not security. Worth one focused pass |
| 🟢 | `clinics.price_cents` is dead | 2026-08-10 | Superseded by the two price columns. Drop once the Swift client and web admin are both off it |

## Fixed

| | Item | Fixed | Fix |
|---|---|---|---|
| 🔴 | ~~**No app icon.** `AppIcon.appiconset` has a slot with no `filename` and no PNG, so the bundle has no `CFBundleIconName`~~ | 2026-08-16 | 1024x1024 opaque PNG of the crossed-racquets mark on Brand.navy. Verified `CFBundleIconName` in the built Info.plist, and CI now fails the build if it is ever missing again |
| 🔴 | ~~**Sign-up cannot create a usable account**~~ | 2026-08-15 | `create_my_account` (SECURITY DEFINER; id is auth.uid(), email from auth.users, role hard-coded) plus a profile screen and a `.needsProfile` phase. 22-check probe, red first |
| 🔴 | ~~**`FXETennisTests/` is empty**, so the whole test action fails to load~~ | 2026-08-14 | 13 unit tests covering price formatting, member-rate selection and NTRP bucketing. `xcodebuild test` can exit 0 for the first time |
| 🔴 | ~~**XCUITests are 0 of 4 green**, not the 2 of 4 claimed in `ed88c1f`~~ | 2026-08-14 | 5 of 5 green. Three causes: the empty test target, identifiers set on the view inside the button rather than the button, and an assertion comparing visible text when StatusChip publishes its VoiceOver label |
| 🟡 | ~~`clinics_admin` is stale and Tara cannot see real prices~~ | 2026-08-16 | Recreated with columns listed explicitly instead of `select *`. Two probe assertions pin it, verified red first |
| 🟡 | ~~**The "?" description affordance does not exist**~~ | 2026-08-16 | Built on the clinic list, opening a sheet with the description and, for a 105 clinic, Tara's definition of the format |
| 🟡 | ~~**Queen City team eligibility is not enforced, by decision**~~ | 2026-08-27 | Tara: *"Too complicated to filter this, so let it go and I'll see who signs up."* Confirmed as a non-feature. See decision 0007 |
| ✅ | ~~~~`closes_at` is never populated~~~~ | 2026-08-27 | Closes 3 hours before the clinic starts (Tara's call). A BEFORE INSERT trigger makes it a property of the table, not of one RPC |
| 🟢 | ~~`web/tokens.css` is palette A while `Brand.swift` is palette B~~ | 2026-08-26 | Transcribed from Brand.swift. Brand.swift is the source of truth; change it there first |
| 🟢 | ~~`docs/roadmap.md` iOS section says NOT STARTED; most of it is built~~ | 2026-08-13 | Corrected per row, and `docs/copy.md` now exists |
| 🟢 | ~~Supabase CLI is v2.90, current is v2.113~~ | 2026-08-26 | Upgraded to 2.115.0, and CI is pinned to the SAME version. The skew had been hiding a real bug for three days |
| 🔴 | **Any player could make themselves admin** with one UPDATE, then read every roster, court and payment, demote Tara, and reassign other players to their own account | 2026-08-02 | Column grants + `WITH CHECK` + trigger. `tests/sql/privilege_escalation.sql` attacks it, verified red first |
| 🔴 | Registration window rule was wrong on Fridays and Saturdays | 2026-08-02 | See decision 0001 |
| 🔴 | **Probe harness reported SQL errors as passes.** It matched `^ERROR`, psql writes `psql:<stdin>:138: ERROR:`. Five probes were aborting and the suite said green | 2026-08-10 | Match `ERROR:` anywhere |
| 🔴 | **A probe running zero assertions reported as a pass** | 2026-08-10 | Zero checks is now red |
| 🟡 | Probe pass condition used substring matching, so an actual of `105` passed an expected of `0` | 2026-08-02 | Substring only when the expected value contains a letter |
