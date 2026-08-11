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

### iOS app ⬜

| | |
|---|---|
| ⬜ | Xcode project, brand tokens from Tara's palette, the gator mark |
| ⬜ | Sign up / sign in. **Everyone makes an account** (Tara, 2026-08-02) |
| ⬜ | Profile: name, contact, member yes/no, NTRP rating with the "?" explainer |
| ⬜ | Browse clinics by week, **one month ahead**, showing "Registration opens Aug 8" on ones not yet open |
| ⬜ | Clinic details: name, day, time, price for *this* player, description, Zelle/Venmo line, message board |
| ⬜ | Register / Cancel / Leave Player Pool |
| ⬜ | Accept or decline an invitation |
| ⬜ | My Clinics, News, notification permission with the warning Tara asked for |

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

| | |
|---|---|
| ❓ | FXE Tennis, LLC — does it exist? D-U-N-S number needed either way |
| ⬜ | Privacy policy live on a URL, FXE waiver wording |
| ⬜ | App Store listing, TestFlight round with real members |

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
