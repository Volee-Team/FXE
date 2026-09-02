# Feature review, 2026-09-02

Every screen on both surfaces, walked as Tara and as a player, after the day's
merges (PRs #4 through #18). One finding per line, each with the concrete
change I would make. Severity: **fix now** (a player or Tara will hit it in
week one), **soon** (before real members), **later** (v1.1 material).

What was verified by hand today, so it is not repeated below: sign-in, sign-up
and profile completion, password reset, browse, register / cancel / leave pool,
late request, the bell, profile edit, My Clinics; and on Tara's side rosters,
invite, courts, paid, unpaid reminder, message audiences, late requests,
Action Needed, Money, directory with notes, cancel clinic, templates.

## Player app

| Sev | Finding | Suggested change |
|---|---|---|
| fix now | A notification row does not open the clinic it is about. `entity_id` is on every row. | Make rows with `entity_type = 'clinic'` a NavigationLink to that clinic's detail; mark read on tap as now. |
| fix now | After registering, the detail screen flips the button but says nothing about what happens next. A Player Pool member does not know Tara picks by hand. | One line under the status, in Tara's words (needs her sentence; the developer guide's "Tara picks from here" was hers to approve and was pulled). |
| soon | Home's "Available Clinics" shows three rows with no "and 4 more". | Add the count to the button: "View Open Clinics (7)". Chrome, not copy. |
| soon | The clinic list has no way to see last week (finished clinics vanish by design). A player checking what they paid for has nowhere to look. | A "Past" section at the bottom of My Clinics, from `my_registrations` joined to ended clinics, read-only. Needs a view change: `clinics_public` drops ended rows. |
| soon | Forgot password on the phone succeeds silently apart from one inline line; the sheet-style confirmation the web page has would match. | Reuse the permission-sheet pattern: one sentence, one button. |
| later | No app version anywhere on Profile. Tara cannot tell which build a player has. | Footer line "Version 0.1.0 (1)" from the bundle. |
| later | The rating pills on profile edit allow clearing to "no rating" with no confirmation; harmless but surprising. | Leave. |

## Admin, phone

| Sev | Finding | Suggested change |
|---|---|---|
| fix now | The Players toolbar button renders icon-only on iOS 26 despite `.titleAndIcon` (screenshots 16:40, 17:40). Violates the icon-plus-text rule. | Replace the Label with `Text("Players")` in the toolbar. |
| fix now | Canceled clinics still show a green "You're In! 0/6" chip beneath the Canceled badge. | Hide the count chips when `status == canceled`. |
| soon | Roster rows carry court menu + paid toggle on one line; at 4.7" this wraps. | Two-line row: name and subtitle on the first, controls on the second. |
| soon | No way to remove a walk-up placed by mistake. Only the player can cancel from their side. | "Remove" in a swipe action on You're In! calling `cancel_registration` (admin is already allowed). Confirmation, because it notifies. |
| soon | Action Needed rows are not tappable through to the thing needing action. | Each row a NavigationLink: late requests to that clinic, notices to the bell-equivalent list for Tara. |
| later | Message Players has no character count against the push limit (`docs/notifications.md` measured 133 as the edge). | A live count under the editor once push delivery exists. |

## Admin, web

| Sev | Finding | Suggested change |
|---|---|---|
| fix now | Money sits at the bottom of a page that grows with every clinic. Tara's first question each Monday is money. | Tabs across the top: This week · Players · Money. Same page, three panels. |
| soon | Canceled clinics stay in the list forever with their Canceled chip. | "Show canceled" toggle, off by default; the date floor already hides finished ones. |
| soon | Templates cannot be reordered or archived; the picker will grow with the season. | `archived_at` on templates and an "Archived" filter. One migration, one probe. |
| soon | Directory note has no "last edited". `updated_at` exists. | Show it under the textarea. |
| later | No search on the clinic list. Fine at four, not at forty. | Filter box above the list once Tara's season is in. |
| later | The two-click cancel disarms after five seconds with no visible countdown. | Fine as is; note only. |

## Both surfaces

| Sev | Finding | Suggested change |
|---|---|---|
| fix now | ~45 strings await Alex's tick in `docs/copy-review.md`. The reminder body and the permission sheet are the two that speak in Tara's name. | One sitting, tick or reword, then delete the review rows. |
| soon | The walkthrough artifact for Tara is two weeks behind the app. | Regenerate after the copy review so it shows her words. |
| soon | Court numbers are 1–5 in the schema; nobody has confirmed the club has five. | Ask Tara once; a check constraint is a one-line migration either way. |

## Test coverage after today

| Layer | Count | Gap |
|---|---|---|
| SQL probes | 14 files, 324 checks | none known; every migration has one |
| Swift unit | 18 | none of the view models are testable without the network; fine for now |
| XCUITest (player) | 8 | no admin flows at all |
| XCUITest (admin) | 0 | invite, courts, paid, reminder, late request, directory, cancel |
| Playwright (web admin) | 8 | templates: create from template, save-as-template, edit; Action Needed approve / decline |

The UI-testing pass that follows this review targets the two empty rows.
