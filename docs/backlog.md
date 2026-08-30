# Backlog

Bugs, chores, and small things that are not worth a roadmap entry. **Anything
noticed and not fixed goes here in the same breath**, or it is forgotten.

Priority: 🔴 blocks a person · 🟡 should fix · 🟢 whenever

## Open

| | Item | Found | Note |
|---|---|---|---|
| 🔴 | **No app icon.** `AppIcon.appiconset` has a slot with no `filename` and no PNG, so the bundle has no `CFBundleIconName` | 2026-08-13 | Hard TestFlight blocker: ITMS-90713 fails at upload processing, before Beta App Review. Needs a 1024x1024 opaque PNG of the crossed-racquets mark (decision 22), and the loose `Brand/gator-x.pdf` should stop shipping as a bundle file |
| 🔴 | **Sign-up cannot create a usable account** | 2026-08-13 | `authenticated` has no INSERT on `accounts`, no trigger on `auth.users`, no RPC, and the Swift client has zero table writes. A new user gets an orphan auth row, no `players` row, and Register silently no-ops at `ClinicDetailView.swift:213`. `players` INSERT is already correctly wired, so the gap is exactly one table plus a name-collecting screen |
| 🔴 | **`FXETennisTests/` is empty**, so the whole test action fails to load | 2026-08-13 | `xcodebuild test` exits 65 with "bundle couldn't be loaded" regardless of the UI tests, and `xcodegen` fails on a fresh clone for the same reason. `build-for-testing` alone still succeeds, which is why it went unnoticed |
| 🔴 | **XCUITests are 0 of 4 green**, not the 2 of 4 claimed in `ed88c1f` | 2026-08-13 | Two independent causes: `8357fb9` moved `clinic.price` and `clinic.card` off Home, and the empty test target above. Should have been logged here when it went red, per this file's own rule |
| 🟡 | `clinics_admin` is stale and Tara cannot see real prices | 2026-08-13 | Created as `select *` before the 2026-08-10 pricing migration. A `select *` view snapshots its column list at creation, so it still lacks `duration_minutes`, `member_price_cents`, `nonmember_price_cents`. Found while writing `view_write_paths.sql`, where naming those columns made an attack fail with 42703 and report a false pass |
| 🟡 | **Tara's real clinic descriptions are not in the database** | 2026-08-16 | She sent verbatim copy for 105, Ladies 3.0+, All-Level Ladies, All-Level Men's and a new Queen City team practice. All transcribed in `docs/copy.md`; none of it is in `clinic_templates` or `clinics` yet. This is the content that makes a TestFlight build feel real to her instead of a demo |
| 🟡 | **The "?" description affordance does not exist** | 2026-08-16 | Tara's own idea: *"Should you put a '?' w the description by each clinic?"* Every clinic name is club shorthand ("105", "3.0+", "All-Level") a new member does not know. Same affordance as the NTRP "?" on Profile, so the pattern is already learned. Description reaches clinic detail; the "?" on the list does not exist |
| 🟡 | **Queen City team eligibility is not enforced, by decision** | 2026-08-16 | Her clinic is "only Queen city team players". There is no team concept in the schema and inventing one is a schema decision, not a copy one. Her words: *"I'll just need to manually figure that one out."* v1: the description says who it is for, anyone may register, Tara selects from the Player Pool. Needs a decision record if it ever becomes a real rule |
| 🟡 | **Late-request path is not built** | 2026-08-27 | Half of Tara's own answer on close times: *"if they try to register within 3 hours, they have the option to send me a direct message to get into the clinic, assuming there is space and it isn't full."* Registration now closes 3h before start (decision 0007) with no way to ask in. Needs a UI path, a notification to her, and a not-full check |
| ✅ | ~~`closes_at` is never populated~~ | 2026-08-13 | No migration, seed, or `create_clinic_from_template` sets it, so registration never closes and finished clinics stay bookable. Combined with the missing date floor, registering for a clinic that ended nine days ago succeeds and lands in Tara's queue. Open question 5 for Tara: at clinic start, some hours before, or only when full? |
| 🟡 | Clinic list has no date bounds in either direction | 2026-08-13 | `clinics_public` has no date clause, `clinic_status` has no terminal state, and `ClinicRepository.upcoming()` only orders. Past clinics accumulate forever and sort to the TOP, so Home's `prefix(3)` shows the three oldest |
| 🟢 | `anon` holds EXECUTE on 22 SECURITY DEFINER RPCs | 2026-08-13 | Not a live hole: `place_player` and `cancel_clinic` both return `not_authorized` to anon, verified. Revoke anyway as defence in depth, same reasoning as hard rule 11 |
| 🟢 | `web/tokens.css` is palette A while `Brand.swift` is palette B | 2026-08-13 | Each file's header declares itself a mirror of the other. Palette B was chosen by Tara on 2026-08-12 |
| 🟢 | `docs/roadmap.md` iOS section says NOT STARTED; most of it is built | 2026-08-13 | 4 of 8 rows done, 3 partly done. `docs/architecture.md:29` in the same repo says "Built". Also `docs/copy.md` is referenced by CLAUDE.md and has never existed |
| 🟡 | Notification triggers with no producer | 2026-08-02 | `REGISTRATION IS OPEN` needs a scheduler that does not exist. Copy is written, nothing fires it |
| 🟡 | Four "high" findings from the completeness review | 2026-08-02 | Docs drifted from code; probes asserting less than their comments claim |
| 🟢 | Six "medium" / seven "low" findings from the same review | 2026-08-02 | Not security. Worth one focused pass |
| 🟢 | `clinics.price_cents` is dead | 2026-08-10 | Superseded by the two price columns. Drop once the Swift client and web admin are both off it |
| 🟢 | Supabase CLI is v2.90, current is v2.113 | 2026-08-10 | Works fine, just stale |

## Fixed

| | Item | Found | Fix |
|---|---|---|---|
| 🔴 | **Any player could make themselves admin** with one UPDATE, then read every roster, court and payment, demote Tara, and reassign other players to their own account | 2026-08-02 | Column grants + `WITH CHECK` + trigger. `tests/sql/privilege_escalation.sql` attacks it, verified red first |
| 🔴 | Registration window rule was wrong on Fridays and Saturdays | 2026-08-02 | See decision 0001 |
| 🔴 | **Probe harness reported SQL errors as passes.** It matched `^ERROR`, psql writes `psql:<stdin>:138: ERROR:`. Five probes were aborting and the suite said green | 2026-08-10 | Match `ERROR:` anywhere |
| 🔴 | **A probe running zero assertions reported as a pass** | 2026-08-10 | Zero checks is now red |
| 🟡 | Probe pass condition used substring matching, so an actual of `105` passed an expected of `0` | 2026-08-02 | Substring only when the expected value contains a letter |
