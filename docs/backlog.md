# Backlog

Bugs, chores, and small things that are not worth a roadmap entry. **Anything
noticed and not fixed goes here in the same breath**, or it is forgotten.

Priority: 🔴 blocks a person · 🟡 should fix · 🟢 whenever

## Open

| | Item | Found | Note |
|---|---|---|---|
| 🟢 | `extract-copy.py` captures a Swift interpolation (`“\(m)”`) as a string | 2026-09-01 | Harmless, but it is not copy. Teach the extractor to skip strings that are only an interpolation |
| 🟡 | **Tara's real clinic descriptions are not in the database** | 2026-08-16 | She sent verbatim copy for 105, Ladies 3.0+, All-Level Ladies, All-Level Men's and a new Queen City team practice. All transcribed in `docs/copy.md`; none of it is in `clinic_templates` or `clinics` yet. This is the content that makes a TestFlight build feel real to her instead of a demo |
| 🟡 | **UI tests are order-dependent on the probe suite** | 2026-08-27 | `capacity_race.sh` is the one probe that writes real rows and is not transactional, so running `run-probes.sh` immediately before `xcodebuild test` leaves the database dirty and a UI test fails. Both are green independently from a clean seed. Fix: have the concurrency probe clean up after itself, or make the UI suite reset first |
| 🟡 | Notification triggers with no producer | 2026-08-02 | `REGISTRATION IS OPEN` needs a scheduler that does not exist. Copy is written, nothing fires it |
| 🟡 | Four "high" findings from the completeness review | 2026-08-02 | Docs drifted from code; probes asserting less than their comments claim |
| 🟢 | Six "medium" / seven "low" findings from the same review | 2026-08-02 | Not security. Worth one focused pass |
| 🟢 | `clinics.price_cents` is dead | 2026-08-10 | Superseded by the two price columns. Drop once the Swift client and web admin are both off it |

## Fixed

| | Item | Fixed | Fix |
|---|---|---|---|
| 🟢 | ~~`anon` holds EXECUTE on 22 SECURITY DEFINER RPCs~~ | 2026-09-01 | It was 30 of 41 by then. 20260902000001 revokes from PUBLIC and anon on every function; `grants_are_explicit.sql` enumerates `pg_proc` so it cannot regress silently |
| 🟡 | ~~Clinic list has no date bounds in either direction~~ | 2026-09-02 | Floor: `clinics_public` drops ended clinics (08-28). Ceiling: the client stops five weeks out (09-02) |
| 🟡 | ~~20 unmerged commits: `main` is a pre-security-lockdown codebase~~ | 2026-09-01 | PRs #1–#3 merged by Alex; everything since merges on green under branch protection (21 PRs by 2026-09-02) |
| 🟡 | ~~Hosted password reset needs one dashboard setting~~ | 2026-09-01 | Alex added `https://fxe-tennis-admin.vercel.app/reset.html` to Supabase Auth redirect URLs the same evening; verified in the audit of 2026-09-10 |
| 🟢 | ~~`docs/architecture.md` needs a rewrite~~ | 2026-09-01 | Regenerated from the live schema (`pg_class`, `pg_proc`), the file tree and the probe list. The 2026-08 version had six sections that were no longer true |
| 🟡 | ~~**Late-request path is not built**~~ | 2026-08-28 | Built whole: `late_requests` table + `request_late_spot`/`resolve_late_request` (24-check probe, red-first), and the closed-clinic screen offers "Message Tara" instead of a dead end |
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
