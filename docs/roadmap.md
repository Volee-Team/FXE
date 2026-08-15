# FXE Tennis Roadmap

What is in each version, what is deliberately not, and where Tara's ideas go
when they arrive mid-build. **When she asks for something, it lands here first.**
Nothing gets built straight off a text message.

Statuses: ✅ done · 🔨 in progress · ⬜ not started · ❓ needs a decision

---

## v1 — the version that replaces the notebook

The bar: Tara stops running her program from texts, a spreadsheet, and a
handwritten court sheet. Nothing more.

### Backend ✅

| | |
|---|---|
| ✅ | Accounts, players, clinics, templates, registrations |
| ✅ | Service-week registration windows (member Thursday 8 AM, public Friday 8 AM) |
| ✅ | Member priority, capacity, Player Pool |
| ✅ | Invitations: Tara invites by hand, player accepts or declines, never auto-promoted |
| ✅ | Cancellations both sides, archive never delete |
| ✅ | Information hiding enforced in Postgres, not the UI |
| ✅ | Privilege-escalation fix and attack probe |
| ✅ | Pricing by membership × length, snapshotted onto the registration |
| ✅ | `revenue_summary()` — the four numbers and the money |
| ✅ | Court assignment 1–5, admin only |
| ✅ | Clinic messages with audience targeting |
| ✅ | News with audience and unread tracking |
| ✅ | 142 automated checks + a concurrency probe, green in CI on every push |

### iOS app 🔨

Status corrected 2026-08-13. This section read "not started" for every row while
`docs/architecture.md` in the same repo said "Built" and eight commits on
2026-08-12 had delivered a walkable player flow. **A roadmap that lies in the
optimistic direction wastes a day; one that lies in the pessimistic direction
hides finished work and gets it rebuilt.** Re-check this table against the code
whenever you touch it.

| | |
|---|---|
| ✅ | Xcode project, brand tokens from Tara's palette, the gator mark. **Except the app icon**: the asset slot is empty, which is a hard TestFlight blocker (backlog) |
| 🔨 | Sign **in** works. Sign **up** is broken: nothing creates the `accounts` row, so a new user gets an orphan auth record and a Register button that silently does nothing |
| 🔨 | Profile: the NTRP "?" explainer is done and correct. Everything else is read-only and unpopulated, because there is no write path to `accounts` or `players` anywhere in the client |
| 🔨 | Browse clinics: the "Registration opens" state is built and handles member vs non-member correctly. Week grouping, the one-month horizon, and a date floor are not, so past clinics live in the list forever and sort to the top |
| ✅ | Clinic details: name, day, time, price for *this* player, description, Zelle/Venmo line, message board |
| ✅ | Register / Cancel / Leave Player Pool |
| ✅ | Accept or decline an invitation |
| 🔨 | My Clinics: a three-row section on Home, no dedicated surface, and "View All Clinics" does not go there |
| ⬜ | Notification permission with the warning Tara asked for. Zero code: no permission request, no APNs entitlement, no device registration, and no sender in `supabase/functions/` |
| ⏸ | News. Model and repository exist, no screen. **Deferred**: decision 21 cut the tab (see `docs/decisions/0006`) |

### Test health 🔨

Tracked here because it was red for days without anyone noticing, which is
itself the finding.

| | |
|---|---|
| ✅ | SQL probe suite: 7 probes, 164 checks, plus the concurrency probe. Green in CI on every push |
| ⬜ | `FXETennisTests/` is **empty**, so `xcodebuild test` cannot load the bundle and exits 65 regardless of anything else. Also breaks `xcodegen` on a fresh clone |
| ⬜ | XCUITests are **0 of 4 green**, not the 2 of 4 claimed in `ed88c1f` |

### Web admin ⬜

Tara's weekly setup, on a laptop (her call, 2026-08-02: *"yes, please move
forward with suggestion"*).

| | |
|---|---|
| ⬜ | Create a week from templates in one pass |
| ⬜ | Clinic management: You're In! / Player Pool / Response Needed, invite, message |
| ⬜ | **Quick-add a player to any clinic**, dropdowns and a calendar, no typing sentences |
| ⬜ | **Court dropdown on every roster row**, re-arrangeable any time |
| ⬜ | Paid checkbox and the unpaid reminder |
| ⬜ | Revenue screen: the four numbers, the total, what is outstanding |
| ⬜ | Player directory with forgiving search, private notes |

### Ship ⬜

Split by what actually gates what. An **internal** TestFlight round (Tara added
as an App Store Connect user on our own team) needs far less than an external
one, and conflating the two is what made this section look like a wall.

**Gates an internal TestFlight build:**

| | |
|---|---|
| ⬜ | **App icon.** The `AppIcon.appiconset` slot is empty, so the bundle has no `CFBundleIconName` and the upload fails validation (ITMS-90713) before Beta App Review ever runs |
| ⬜ | **`DEVELOPMENT_TEAM`.** Not set anywhere, so a device build fails outright. Must go in `project.yml`, not the Xcode UI, because `.gitignore` excludes the `.xcodeproj` and `xcodegen` regenerates it |
| ⬜ | Distribution certificate and provisioning profile on the build machine |
| ⬜ | App Store Connect app record; the bundle id is still the placeholder `com.fxetennis.app` |
| ⬜ | **Sign-up that produces a usable account.** Without it a tester installs the app and cannot get past the first screen |
| ⬜ | Tara's real clinics in hosted, which needs an admin path to create them |

**Gates an external round and App Store release, but NOT an internal one:**

| | |
|---|---|
| ✅ | FXE Tennis, LLC exists. **D-U-N-S 11-654-7195**, registered, address on file with D&B |
| ⬜ | Apple Developer Program enrollment as the LLC (Tara decision 16). Alex has authority as her developer |
| ⬜ | A website at the entity's domain. Apple wants one at enrollment. Cheap: a static page on Vercel, as done for Volee |
| ⬜ | Privacy policy live on a URL, FXE waiver wording |
| ⬜ | Beta App Review, then the App Store listing |

---

## v1.1 — the next one

| | |
|---|---|
| ⬜ | **Stripe.** Tara wants card-on-file so she can charge it. Allowed by Apple: tennis clinics are a real-world service, so no IAP required. Real work: Customers, SetupIntents, off-session charges, declines on cards charged days later. See `docs/decisions/0003-payments.md` |
| ⬜ | **Juniors.** Deferred by Tara "before winter time". Enum values already in the schema so this is UI work, not a migration |
| ⬜ | Parent accounts managing children, junior age groups |
| ⬜ | Duplicate an entire week and adjust dates |
| ⬜ | Add to Calendar |
| ⬜ | Attendance check-in |

---

## v2 and beyond

Multiple admins or coaches. Reminder for unanswered invitations. Schedule
conflict warnings. Advanced player search. Multiple locations.

---

## Parked — raised but not scheduled

Things Tara has mentioned that are real but have no version yet. Parked is not
rejected; it means nobody has decided when.

| Idea | Raised | Note |
|---|---|---|
| Saturday clinics | 2026-08-02 | Her example ran Sunday–Friday. The service week is Sunday–Saturday so a Saturday clinic works, but she has never confirmed she runs them. **Open question** |
| Short holiday weeks | 2026-08-10 | Does the Thursday still anchor to that week's Sunday when there are only clinics Mon–Wed? **Open question** |
| Category field | 2026-08-02 | She was unsure what it meant and said no filtering is needed. Column exists, deliberately unindexed, no UI |
| What the club actually needs | 2026-08-10 | Report gives counts by membership × length plus the total. Not confirmed that this is what she hands them |

---

## Deliberately not doing

Saying no is a decision too, and these keep coming back if they are not written
down.

| Not doing | Why |
|---|---|
| In-app purchase for clinic fees | Apple does not require IAP for real-world services. Stripe direct is allowed and keeps Apple's cut off the top |
| A CMS | There is no managed content. Clinic descriptions live on the clinic |
| Auto-promoting from the Player Pool | Tara picks every player. This is the product, not a limitation |
| Auto-expiring invitations | Same reason. She cancels one by hand if she wants it back |
| Showing players anything about capacity or other players | The hard rule the whole schema is built around |
| Roster-only players with no account | Considered 2026-08-02, rejected: *"everyone should make an account"* |
