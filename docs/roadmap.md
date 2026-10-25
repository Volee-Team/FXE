# FXE Tennis Roadmap

What is in each version, what is deliberately not, and where Tara's ideas go
when they arrive mid-build. **When she asks for something, it lands here first.**
Nothing gets built straight off a text message.

**This file carries no status.** Alex, 2026-10-12: *"we have tons of docs and
some are becoming outdated and we need a SOLID system and ASOT to stick to"*.
Status lives in four places only: `docs/launch-checklist.md` (work, LATER
included), `docs/backlog.md` (bugs), `docs/questions-for-tara.md` (questions)
and `docs/decisions/README.md` (decisions). A row here says one of three
things:

| Says | Means |
|---|---|
| **built** | On `main`. `docs/architecture.md` names every table, function, screen and test behind it, and CI fails if one is missing there |
| **checklist X** | Scheduled before launch. Row X of the launch checklist carries the status |
| nothing | An idea nobody has scheduled. Where it depends on something outside our hands, the row says what |

Re-check a "built" against the code whenever you touch a row. On 2026-08-13
this file said "not started" for an iOS app that eight commits had already
delivered: **a roadmap that lies in the optimistic direction wastes a day; one
that lies in the pessimistic direction hides finished work and gets it
rebuilt.**

---

## v1: the version that replaces the notebook

The bar: Tara stops running her program from texts, a spreadsheet, and a
handwritten court sheet. Nothing more.

### Backend

| Feature | |
|---|---|
| Accounts, players, clinics, templates, registrations | built (`20260728000001_core_schema.sql`) |
| Service-week registration windows (member Thursday 8 AM, public Friday 8 AM) | built (decision 0001, `registration_window_rule.sql`) |
| Member priority, capacity, Player Pool | built (`register_for_clinic`, `capacity_race.sh`) |
| Invitations: Tara invites by hand, player accepts or declines, never auto-promoted | built (`place_player`, `respond_to_invitation`) |
| Cancellations both sides, archive never delete | built (`cancel_registration`, `cancel_clinic`) |
| Information hiding enforced in Postgres, not the UI | built (`information_hiding.sql`) |
| Privilege-escalation fix and attack probe | built (`privilege_escalation.sql`) |
| Pricing by membership and length, snapshotted onto the registration | built (decision 0002) |
| `revenue_summary()`: the four numbers and the money | built |
| Court assignment 1 to 5, admin only | built (`assign_court`) |
| Clinic messages with audience targeting | built (`send_clinic_message`, `clinic_messaging.sql`) |
| News with audience and unread tracking | built on the server (`my_news`); no screen, by decision 0006 |
| The SQL probe suite plus the race probes, green in CI on every push | built (`bash tests/run-probes.sh` prints its own totals) |

### iOS app

| Feature | |
|---|---|
| Xcode project, brand tokens, the gator mark and the app icon (CI fails if the icon goes missing) | built |
| Sign in and sign up: profile screen with Tara's Screen-4 copy, `create_my_account` | built |
| Profile: NTRP "?" explainer, Edit details (name, phone, rating); membership stays Tara's to correct | built |
| Browse clinics: "Registration opens" state, finished clinics drop off, closed state with "Message Tara", week grouping, five-week horizon | built |
| Clinic details: name, day, time, price for *this* player, description, message board | built |
| Register, Cancel, Leave Player Pool | built |
| Accept or decline an invitation | built |
| The bell: notification center, unread badge, read state in the database | built |
| My Clinics, grouped by week, each with its status chip; Past under it | built |
| Manage tab for Tara: Action Needed, rosters, invite from the Player Pool, message audiences | built |
| Late requests: registration closes 3 hours before start; inside that a player can ask Tara | built (`request_late_spot`) |
| Confirmation dialogs on destructive taps | built |
| Push notifications on the lock screen | checklist C3 |
| News screen | Not in v1: decision 21 cut the tab (decision 0006). The model and repository stay |

### Test health

Counts are not written here; the suites print their own and
`bash scripts/check-doc-claims.sh` derives them. What exists: the SQL probe
suite, the Playwright browser suite, the Stripe pipeline against stripe-mock
(`tests/stripe/run.sh`), the push harness (`tests/push/`), Swift unit tests,
and XCUITests for player, admin and pro flows. The XCUITests run on a laptop
through `scripts/run-ui-tests.sh` before each TestFlight build, not in CI
(decided 2026-09-18, launch checklist §F option 3); the `ui-test-record` CI
job checks that a green run is recorded.

**History worth keeping.** The XCUITest suite was 0 of 4 on 2026-08-14, not the
"2 of 4" claimed in `ed88c1f`. Three causes, two of them the same mistake:

1. `FXETennisTests/` was empty, so the target built an `.xctest` with no
   executable and **every** `xcodebuild test` exited 65 regardless of the UI
   tests' own result. `build-for-testing` still succeeded, which is why it went
   unnoticed.
2. `clinic.card` on Home and `profile.signOut` on Profile were set on the view
   *inside* the button rather than on the button, so `app.buttons[...]` matched
   nothing. `ClinicsView:84` had it right; Home drifted in `8357fb9`.
3. The status assertion compared against visible chip text, but `StatusChip`
   collapses to one accessibility element publishing its **VoiceOver** label. It
   now asserts the documented strings from `docs/archive/design-system.md`, which pins
   the accessibility contract too.

### Web admin, at `fxe-tennis-admin.vercel.app`

Tara's weekly setup, on a laptop (her call, 2026-08-02). Sign-up self-promotes
her email to admin, so the bootstrap is entirely hers.

| Feature | |
|---|---|
| Sign in and first-time sign up; create, edit and publish clinics; windows and prices derived automatically | built |
| Templates: "Start from a template" and save-as-template; archive and restore | built (`admin_set_template_archived`) |
| Rosters: You're In!, Player Pool, Response Needed; invite, cancel invite | built |
| Message players by audience. **Five audiences, not the three of decision 0005**; the enum's extra two are kept, Unpaid hidden while `zelle_allowed` is false | built |
| Walk-up "Add player": forgiving search, one tap to You're In! | built |
| Cancel clinic, web (two clicks) and phone (More menu with a confirmation); everyone live is told | built |
| Court dropdown on every roster row, web and phone; You're In! reads in court order | built |
| One-tap unpaid reminder, web and phone. Not rendered while `zelle_allowed` is false (decision 0013) | built |
| Money: the four numbers, per-clinic lines, the card-payments ledger, payouts and disputes (decision 0021), the board report (question 73, decision 0040) | built |
| Player directory, web and phone: search, private notes with "Edited <date>", membership correction, deactivate | built |
| Action Needed: late requests, cancellations and invitation replies | built |
| Forgot password on both sign-in screens, landing on `web/reset.html`; Tara's own reset link (decision 0017) | built |
| Three tabs: This week, Players, Money; canceled clinics behind Show canceled | built |
| Tara's cancellation policy as decision 0013 left it: no courtesy, 3-hour cutoff, no-shows marked, card required, the waiver before the first spot, Delete my account keeping history | built (decisions 0012, 0013) |
| Past under My Clinics, the notifications-off line on Home | built (`my_past_clinics`) |

### Ship

The dates and the critical path are in `docs/launch-checklist.md`: the launch
party is 2026-11-06 (decision 0024). Internal TestFlight goes through John's
account (decision 0014).

Alex, 2026-08-19: *"we're not in a big rush, I can do it as an org from the start"*: the LLC account from day one, no personal-account TestFlight shortcut, and John's Volee login (which Alex holds) is not used for FXE.

| Step | |
|---|---|
| App icon, sign-up that makes a usable account | built |
| Privacy manifest | checklist C4 |
| Account deletion in the app | checklist C5 |
| Tara's real clinics in hosted, through the admin site | checklist D5 |
| Apple Developer Program enrollment as FXE Tennis, LLC (D-U-N-S 11-654-7195; website fersc.com) | checklist C1 |
| `DEVELOPMENT_TEAM`, certificates, the App Store Connect record, the LLC's bundle id | checklist C2, C12 |
| Privacy policy on a URL | checklist C6 |
| External TestFlight, Beta App Review, the App Store listing, Apple's review account | checklist C11, C7, C13 |
| The soft launch and Tara's email to members | checklist G7, G8 |

---

## v1.1: the next one

| Feature | |
|---|---|
| **Stripe, card on file** (decision 0009): schema, ledger, edge functions, the card screen, Tara's per-person Charge (decision 0037), refunds on the laptop, the stripe-mock harness in CI | built. Turning it on and going live: checklist A2, A9, A10, A11, A13, A14 |
| **Juniors.** Deferred by Tara to November or the spring session (decision 0007 §6). The enum value is already in the schema, so this is UI work, not a migration | |
| Parent accounts managing children, junior age groups | |
| Duplicate a week: Copy to next week, as drafts she checks and publishes | built (`admin_copy_week`, decision 0027) |
| Add to Calendar (nothing about where goes into the entry) | built (decision 0023) |
| Attendance check-in | built as Came and No-show on the roster (`admin_set_no_show`) and the pros' Today screen (decision 0025) |
| Data export for Tara | checklist D9 |
| **A members' website with the app's full functionality**, for the club's few Android users (call of 2026-10-19 with Tara, Kat, John and Wayne; Alex: *"not urgent this second"*, a new domain to come). Same Supabase project, same views and RPCs, so the information hiding holds by construction (hard rule 1); the web admin's sign-in and `supabase-js` are the starting point | built (decision 0043): `web/play/`, merged 2026-10-25 (PR #104), live at `/play/` once `scripts/deploy-web.sh` runs; no push yet |

---

## Player-facing polish: the wow list (Alex, 2026-09-27)

Alex: *"wow things need to be very user facing, not for tara and kat"*, and
*"WE WANT EXTRA FEATURES NOT JUST MVP"*. Ideas are not scheduled until Alex
picks them.

| Feature | |
|---|---|
| Accept and Decline right on an invitation's notification | built (decision 0023) |
| Tara's own words on every notification the club sends, the same on the lock screen and in the bell | built (decision 0022) |
| Add to Calendar on a clinic you're in | built (decision 0023) |
| Remind me: a notification at the moment registration opens to you | built (decision 0023) |
| A tap you can feel when you land a spot; the status changes smoothly | built (decision 0023) |
| Text that grows with Larger Text, live; Apple's accessibility audit on every main screen | built |
| A readable clock over the navy screens; page titles in the club's serif; outlined icons | built |
| Return moves through sign-in and the profile form | built |
| "Hey Siri, when's my next clinic?", and your next clinic in Spotlight (App Intents) | built (`NextClinicIntent.swift`) |
| Instant open: the last load shown at once and refreshed behind it, so the app also works with no signal at the courts | built (decision 0028) |
| Placeholders shaped like the list while it loads, instead of a spinner | built |
| Your clinics in your calendar automatically (a subscribed feed; times only, never where) | built (decision 0029, `calendar-feed`) |

Found while walking the app for the build 5 demo, which was sent to Alex on
2026-09-28, and fixed the same day: a clinic you hold more than five weeks out
was on no screen at all; titles scrolled under ghosted content on iOS 26 (a
solid edge now, `scripts/check-title-edge.sh`); Delete my account moved to the
foot of Profile.

**Ideas, not scheduled:**

| Idea | Depends on |
|---|---|
| A Home Screen widget: your next clinic and its time | The LLC's bundle id (checklist C12): a widget needs an App Group, tied to the id |
| Sign in with Apple: one tap, no password to forget | The LLC's Apple account (a Services ID) and Supabase's Apple provider |
| Saved passwords offered for the club's site and app together | The LLC's team id in a file on the admin site (associated domains) |
| Clinic day on the Lock Screen (a Live Activity: "Tonight 7:00, You're In!") | Push live (checklist C3); after launch |
| Your season on Profile: clinics played, from the Past list | The words are Tara's |
| The forecast for the hour you play | Tara first: it names the club's town |
| Share a clinic with a friend | Tara: she hides FXE from non-members, so this is her call first |

## Tara's tools: the laptop list (2026-09-28)

The app organizes; she decides. Each of these saves her time without making
a decision for her.

| Feature | |
|---|---|
| **Pros** (question 71, decisions 0024 and 0025): her pros see that day's clinics and who is in them, mark Came, No-show and late cancels; never anything financial, never an invitation. Only she makes someone a pro. Pros skip the waiver and the card step (question 96, decision 0040) | built (`pro_role.sql`, `ProTodayView.swift`) |
| **A declined card blocks sign-up until a new card is saved** (question 78), and **Resolved** on a declined card she won't chase (question 83) | built (decision 0026) |
| **A court sheet to print**, in place of the handwritten one | built (`web/sheet.html`, decision 0027) |
| **A player's history at a glance** on her directory and beside each name in the Player Pool; every cancel counted, "12 played, 5 canceled (2 late), 1 no-show" (question 105) | built (`admin_player_history`, decisions 0027 and 0040) |
| **Copy this week to next week**, as drafts | built (`admin_copy_week`, decision 0027) |
| Her saved messages: sentences she sends often, kept in her words, sent in one tap | built (decision 0030) |
| **Charge each person on their own tap** (2026-10-02): a green Charge $18 beside every name once a clinic ends, phone and laptop; Remove means not charged; Charge clinic retired from both screens | built (decision 0037) |
| **Waive** a late-cancel fee, with Undo, and the red "Late cancellation" flag that keeps the name on her list (questions 81 and 106) | built (decision 0040) |
| **Accept needs a saved card** while cards are required, as Register does (question 107) | built (decision 0040) |
| **A private note for Tara at Register** (Tara, 2026-10-11): a box above Register with her example ("please put me on court with my friend Jane") and "Only Tara sees this"; she reads it beside the name on her roster, phone and laptop. Only she and the writer can read it, enforced in the database. Not on the printed court sheet unless she says so (question 110) | built (decision 0039, `tests/sql/registration_note.sql`) |

**Asked for, not scheduled:**

| Idea | Note |
|---|---|
| **Refunds from her phone** (Alex, 2026-10-06) | A refund today is the laptop's Money tab (whole amount, once, two clicks) or Stripe's own dashboard, which the webhook records. The phone has no Refund, yet tells her "Already charged: refund it first" when she removes a charged player, which is a dead end on the phone. `admin_refund_payment` exists; the phone needs a Refund beside Charged on the roster. Refunds stay whole (question 108, decision 0040) |
| **Charge half for a clinic cut short** (Tara, 2026-10-03, "maybe three times a year") | Her rule (questions 102 to 104): one switch on the clinic, everyone half, no-shows and late cancels full. The server already takes an amount (`admin_charge_registration`'s `p_amount_cents`), so this is a switch on the clinic plus the button's price |
| **Everything from her phone** (Tara, 2026-10-02, via Alex: *"EVERYTHING she possibly can from her phone ... in a perfect world get rid of the dashboard"*; Alex: not top priority) | Laptop-only today: new and edit clinic and publish, templates and Copy to next week, add a walk-up, the Money tab (ledger, refunds, payouts, disputes), a player's reset link, the board report and the court sheet (a share sheet on the phone, not a printer). Every one is a screen over a server function that already exists; about three or four sessions. The laptop stays as her backup |
| A Sunday-night email: next week's sign-ups, cards to chase, requests waiting on her | The club's mail sender |
| More for two of her pros, when she asks ("Eventually", question 71) | |

Settled in round four and built: a Contact Tara link (question 76), no Stripe
receipts (question 86: "No receipts"; the Stripe setting is checklist A14).

---

## v2 and beyond

### The dream, in Tara's words (2026-09-12, relayed by Alex)

Logged exactly as Alex wrote it, so the direction is never paraphrased away:

> rn they use 500/yr for reservemycourt.com to reserve courts, and for now they
> use that but we'd LOVE to someday integrate that into the app, then we could
> white label sell this to many other clubs ... - she said we can sign up and
> tara will approve me as an FXE member so I can play around with it
> ^she said the DREAM is having everything on the app: pay for treats, barcode
> to scan when you enter the pool to scan it, buy merch on the app, reserve
> pool cabana for $150 for a bday, etc etc like truly comprehensive - then this
> would TRULY be amazing to go to other clubs

What that means for how we build now: keep the club, not the tennis program,
as the unit the schema can grow into (accounts and payments already are
club-level; clinics are one product line). Court reservations stay on
reservemycourt.com ($500/yr) until v2; Alex can get an FXE member account
there to study it. White-labelling later means nothing FXE-specific hard-coded
where a setting would do (the payment instructions, the club name, the logo).

### Tara's ask: FXE and Volee together (2026-10-16, group text, relayed by Alex)

Alex: *"shes talking about now integrating volee with the FXE app, like having
a tab or smth in FXE that will take you to volee, we want them to be
together"*. Not started; the shape is not decided. Volee is John's released
app on its own Supabase project (CLAUDE.md: FXE is not Volee); both store
NTRP as `numeric(2,1)` on purpose, so a rating already crosses untranslated.
Three depths, cheapest first:

1. **A door (days):** a Volee tab or Home row that opens the Volee app if it
   is installed and its App Store page if not. No shared data, no new
   account. Works under any developer account. Needs Volee's App Store link
   and URL scheme from John, and Tara's words for the label.
2. **One sign-in (weeks):** one account for both. Needs both apps on the
   same Apple team (App Groups / shared keychain) and an auth bridge between
   the two Supabase projects, so it depends on the Volee-transfer decision.
3. **One app (a rebuild):** Volee's features inside FXE. Not before the
   2026-11-06 launch.

Decision 21 (three tabs, no Community tab) is hers and this would revise it;
her most recent word wins, recorded in a decision when she picks a depth.

### Kat's ask: white label, multi-tenant (2026-10-12, group text)

> What would it take to make FXE a white label multi tenant app? Meaning- I
> want pros to be able to download, set up and manage clinics/lessons and give
> me canned reporting. Also, allow payment integrator of choice.

Tara: *"This is the breakthrough"*. Not started; nothing below is decided.
Engineering sketch, so the conversation starts from the real cost:

1. **A `clubs` table and `club_id` on every row** (25 tables today). Every RLS
   policy, owner-rights view and RPC (125 functions) gains "and it is my club";
   `is_admin()` becomes "admin *of this club*". This is the whole job, and the
   probe suite is what makes it safe: `information_hiding.sql` and the attack
   probes get a second club and assert nothing crosses.
2. **One app, a club code to join**, not one App Store build per club (Apple's
   guideline 4.3 rejects template clones). Branding (name, logo, colours,
   Tara-style copy) moves from `Brand.swift` and `app_settings` into a per-club
   row.
3. **Self-serve setup for a pro**: create a club, become its admin, invite
   players. Today the first admin is made by hand.
4. **Payments: Stripe Connect first**, each club its own connected account, so
   money never passes through us. "Integrator of choice" means an adapter
   layer behind `stripe-charge`; worth building only when a second provider is
   actually asked for.
5. **Canned reporting**: the board report and Money tab per club, plus a
   cross-club view for whoever runs the platform.
6. **Lessons** are a new product line (private 1:1 booking), not a clinic
   setting.

Rough size: items 1 to 3 are a few weeks of focused work after launch, and
should start with a decision record and the second-club probes, not code.
Do not start before 2026-11-06.


Also for v2: multiple admins, reminders for unanswered invitations, schedule
conflict warnings, advanced player search, multiple locations.

---

## Parked: raised but not scheduled

Parked is not rejected; it means nobody has decided when.

| Idea | Raised | Note |
|---|---|---|
| **Guests: a member brings a friend** | 2026-09-22 (question 72) | Parked by Tara, 2026-10-12 (question 95, decision 0040): *"Until this becomes an issue, none of the above. If someone brings a guest, I hope the guest gets the app and this isn't ongoing."* A guest gets the app like anyone. When it comes back, the design is in `docs/archive/guests.md` (rows below) |
| Guests, path 1: Invite a friend sends the app | 2026-09-28 (question 72) | The friend signs up as a non-member with their own card and waiver. Needs the install link (checklist I6) |
| Guests, path 2: Tara writes the friend in, billed to the member at the non-member price | 2026-09-28 (question 72) | A guest is a `players` row owned by the member's account with an `is_guest` flag; a `guest_requests` row like a late request; Tara's approval places them with `place_player`. Her sentence for the member is recorded (question 93): "Your card will be charged for your guests clinic rate". Open design point: a guest who never installs the app never signs the waiver |
| Analytics: an `events` table, no third-party SDK | 2026-08-15 (Kat's list) | Whether her "tagged / tag spec / what tool" meant release tags or analytics tagging is unresolved (`docs/kat-due-diligence.md` row 8). If analytics, it is a Tara question first (what she wants to know) and a privacy line in the policy second |
| UTR / USTA APIs | Kat's list | Never explored; the NTRP scale is self-reported. A Tara question before any integration |
| Recording Tara's calls and FaceTimes so the transcript reaches the model | 2026-08-15 (Alex) | A consent and storage question before it is a feature |
| The model texting Tara directly during the day | 2026-08-15 (Alex) | The answer is the relay through Alex (hard rule 14) until she asks for it |
| Holiday mornings: does registration still open at 8:00 on Christmas Eve and Christmas Day? | 2026-08-10 | Short weeks are settled (question 50, decision 0013); the holiday morning is not yet a numbered question in `docs/questions-for-tara.md` |
| Category field | 2026-08-02 | She was unsure what it meant and said no filtering is needed. Column exists, deliberately unindexed, no UI |
| Saturday clinics | 2026-08-02 | Settled by decision 0013 (question 49): "Yes. But no Saturday clinics." The Sunday-to-Saturday week stands; Saturday is theoretical |

### Practices and tools (from `docs/archive/practice-ideas.md`, 2026-09-26)

Alex: *"can we use jev?? + other ideas to be catching up w all the new
tools/workflows/be best SWE as possible??"*

| Idea | Note |
|---|---|
| Jev, a small model for yes/no decisions (copy gate chrome-or-voice, "does this diff touch a hard rule?") | Not now. Every rule here is enforced by a deterministic check, and a model's yes/no is weaker evidence than those (hard rule 12); it would also send code to another vendor. Revisit after launch if the copy gate's false alarms become a chore |
| A screenshot tour as a UI test: one XCUITest that walks every screen and keeps a PNG of each | Kat and Tara would review every screen from one folder after each build. Only the pro flow keeps screenshots today (`FXETennisUITests/ProFlowUITests.swift`) |
| Crash and error reporting | Checklist D6. MetricKit reports into `app_diagnostics` (decision 0035), merged in build 12 (PR #97) |
| Tighter branch protection on `main` (no admin bypass, hosted smoke required) | Checklist G6 |
| A git tag per TestFlight build | built: every upload since the second has a `v0.1.0-*` tag (`git tag --list 'v0.1.0*'`). The rule is checklist C10 |
| Supabase Pro (no pause, point-in-time recovery, $25 a month) | Checklist D3 |
| Dependabot | built: `.github/dependabot.yml`, and security alerts on (checklist G6) |
| Post-compaction replay of Alex's last prompts | built (`.claude/hooks/session-start.sh`, 2026-09-23) |
| The hosted signed-out smoke test in CI | built (`scripts/hosted-smoke.sh`, 2026-09-22) |
| Doc claims, paths, inventory and status checked in CI | built (`scripts/check-doc-claims.sh` and its siblings, from 2026-09-13) |

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
