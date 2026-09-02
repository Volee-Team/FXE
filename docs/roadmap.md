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
| ✅ | Automated SQL probe suite + a concurrency probe (the suite prints its own total; 299 checks across 12 probes as of 2026-09-01), green in CI on every push |

### iOS app 🔨

Status corrected 2026-08-13. This section read "not started" for every row while
`docs/architecture.md` in the same repo said "Built" and eight commits on
2026-08-12 had delivered a walkable player flow. **A roadmap that lies in the
optimistic direction wastes a day; one that lies in the pessimistic direction
hides finished work and gets it rebuilt.** Re-check this table against the code
whenever you touch it.

| | |
|---|---|
| ✅ | Xcode project, brand tokens from Tara's palette, the gator mark, **and the app icon** (real crossed-racquets mark on navy, 2026-08-16; CI fails if it ever goes missing) |
| ✅ | Sign in AND sign up (2026-08-15): profile screen with Tara's Screen-4 copy, `create_my_account`, `.needsProfile` routing, sign-up regression UI test |
| ✅ | Profile: populated after sign-up, NTRP "?" explainer, and **Edit details** (2026-09-02): name, phone, rating. Membership stays Tara's to correct |
| 🔨 | Browse clinics: "Registration opens" state ✅, date floor ✅ (2026-08-28, finished clinics vanish), **closed state with "Message Tara"** ✅, **week grouping** ✅ (2026-09-01, This week / Next week / Week of …). **five-week horizon** ✅ (2026-09-02) |
| ✅ | Clinic details: name, day, time, price for *this* player, description, Zelle/Venmo line, message board |
| ✅ | Register / Cancel / Leave Player Pool |
| ✅ | Accept or decline an invitation |
| ✅ | **The bell** (2026-09-02): notification center behind the Home bell, badge from unread count, per-row and mark-all read, state in the database |
| ✅ | **My Clinics** (2026-09-02): "View All Clinics" opens a screen of the player's own clinics, grouped by week, each with its status chip; the empty state hands off to the open list |
| ✅ | **Admin tab** (2026-08-15): Action Needed, rosters, invite from Player Pool, mark paid, message audiences |
| ✅ | **Late requests** (2026-08-28): registration closes 3h before start; inside the window a player can Message Tara to ask in |
| ✅ | Confirmation dialogs on all destructive taps (2026-08-28) |
| 🔨 | **Push, the client half** (2026-09-02, decision 0008): permission sheet with Tara's Screen-3 line, `aps-environment` entitlement, APNs registration on every signed-in launch, `register_device` / `unregister_device` RPCs (11-check probe), unregister on sign out. **Not built:** the sender (edge function + webhook) and the APNs key, which only the Apple Developer account can issue. Token delivery was not observable on the simulator (apsd held no sandbox token); the RPC path is probe-tested |
| ⏸ | News. Model and repository exist, no screen. **Deferred**: decision 21 cut the tab (see `docs/decisions/0006`) |

### Test health 🔨

Tracked here because it was red for days without anyone noticing, which is
itself the finding.

| | |
|---|---|
| ✅ | SQL probe suite: 13 probes (313 checks as of 2026-09-02 — the suite prints its own total), plus the concurrency probe. Green in CI on every push |
| ✅ | **Web admin browser tests** (2026-09-02): 8 Playwright tests walk Tara's side against a fresh seed (sign-in and the non-admin door, prices, walk-up, courts, unpaid reminder, directory note round-trip, cancel clinic). Run in CI on every push |
| ✅ | SQL probe suite: 12 probes (299 checks as of 2026-09-01 — the suite prints its own total), plus the concurrency probe. Green in CI on every push |
| ✅ | **Admin XCUITests** (2026-09-02): four flows on Tara's side of the phone: register → court → unpaid reminder → paid; Player Pool → invite → the player's own Accept (hard rule 2 end to end); directory note round-trip; cancel clinic with confirmation. The phone's UI suite is now 12 tests, 8 player + 4 admin |
| ✅ | Unit tests: 13, covering the pure logic the probes cannot see (price formatting, member rate selection, NTRP bucketing) |
| ✅ | XCUITests: **5 of 5 green** as of 2026-08-15, including a sign-up regression test |

The XCUITest suite was 0 of 4, not the "2 of 4" claimed in `ed88c1f`. Three
causes, all worth remembering because two are the same mistake:

1. `FXETennisTests/` was empty, so the target built an `.xctest` with no
   executable and **every** `xcodebuild test` exited 65 regardless of the UI
   tests' own result. `build-for-testing` still succeeded, which is why it went
   unnoticed.
2. `clinic.card` on Home and `profile.signOut` on Profile were set on the view
   *inside* the button rather than on the button, so `app.buttons[...]` matched
   nothing. `ClinicsView:84` had it right; Home drifted in `8357fb9`.
3. The status assertion compared against visible chip text, but `StatusChip`
   collapses to one accessibility element publishing its **VoiceOver** label. It
   now asserts the documented strings from `docs/design-system.md`, which pins
   the accessibility contract too.

### Web admin 🔨 — LIVE at `fxe-tennis-admin.vercel.app` (2026-08-28)

Tara's weekly setup, on a laptop (her call, 2026-08-02). Sign-up self-promotes
her email to admin, so the bootstrap is entirely hers.

| | |
|---|---|
| ✅ | Sign in / first-time sign up; create + edit + publish clinics; windows and prices derived automatically |
| ✅ | Templates: "Start from a template" picker and save-as-template — a clinic in ~3 clicks |
| ✅ | Rosters: You're In! / Player Pool / Response Needed, invite, cancel invite, paid toggle |
| ✅ | Message players by audience (Everyone / You're In! / Player Pool / Response Needed / Unpaid) |
| ✅ | **Walk-up "Add player"**: forgiving search, one tap to You're In! |
| ✅ | **Cancel clinic** (2026-09-02), web (two clicks, five seconds apart) and iOS (More menu with a confirmation). `cancel_clinic` had waited since July for a caller; it notifies everyone live |
| ✅ | **Court dropdown on every roster row** (2026-09-01), web and iOS, re-arrangeable any time. You're In! reads in court order, so the list is the court sheet. `assign_court` had waited since July for a caller |
| ✅ | **One-tap unpaid reminder** (2026-09-01), web and iOS. Body is the clinic name, its date and Tara's own payment line; the audience is resolved server-side. The connective words await Alex's tick in `docs/copy-review.md` |
| ✅ | **Money** (2026-09-01): the four numbers, expected / collected / still owed, and a per-clinic line. Web only; `revenue_summary()` + `revenue_by_clinic()` |
| ✅ | **Player directory** (2026-09-01), web and iOS: forgiving search, private notes, membership correction, deactivate/reactivate. Notes travel only through admin-only RPCs (20260902000002, 14-check probe, red first) |
| ✅ | **Action Needed** (2026-09-01): late requests with Put them in / No room, and unread cancellations and invitation replies with Seen. Web and iOS (iOS shows late requests on the roster) |
| ✅ | **Forgot password?** (2026-09-01) on both sign-in screens, landing on `web/reset.html`. Works on hosted only once the reset URL is in Supabase Auth → URL Configuration (Alex, dashboard) |

### Ship ⬜

Split by what actually gates what. An **internal** TestFlight round (Tara added
as an App Store Connect user on our own team) needs far less than an external
one, and conflating the two is what made this section look like a wall.

**Gates an internal TestFlight build:**

| | |
|---|---|
| ✅ | ~~App icon~~ Done 2026-08-16; CI gate keeps it |
| ⬜ | **`DEVELOPMENT_TEAM`** in `project.yml` — waiting on the Apple LLC enrollment (in review; docs submitted) |
| ⬜ | Distribution certificate and provisioning profile on the build machine |
| ⬜ | App Store Connect app record; the bundle id is still the placeholder `com.fxetennis.app` |
| ✅ | ~~Sign-up that produces a usable account~~ Done 2026-08-15, regression-tested |
| 🔨 | Tara's real clinics in hosted — the path is open (live web admin + her self-promoting sign-up, 2026-09-01); the step is hers |

**Gates an external round and App Store release, but NOT an internal one:**

| | |
|---|---|
| ✅ | FXE Tennis, LLC exists. **D-U-N-S 11-654-7195**, registered, address on file with D&B |
| 🔨 | Apple Developer Program enrollment as the LLC — **in review**: fersc.com email accepted, ID + business docs submitted |
| ✅ | ~~A website at the entity's domain~~ fersc.com accepted by Apple |
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
