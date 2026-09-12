# FXE Tennis v1: Engineering Design

> **Historical (written 2026-07, before any code).** Kept as the record of what we intended. The live description is `docs/architecture.md`; decisions since are in `docs/decisions/`. Known-wrong sections are marked inline as `> **2026-09-12:** ...`.

Every engineering problem from the Developer Guide, with the solution we're building. Written before any code so the decisions are reviewable. Companion doc: `for-tara.md` (the questions only Tara can answer).

Stack: SwiftUI (iOS 26), Supabase (Postgres + Auth + Realtime + Edge Functions), APNs for push. Separate repo, separate Supabase project, separate bundle ID from Volee.

> **2026-09-12:** Realtime is not used anywhere in the app.

---

## 1. Information hiding is a database problem

**The problem.** The guide hides nine things from players: clinic capacity, number registered, spots remaining, Player Pool size, other players' names, court assignments, other players' payment status, private coaching notes, and clinic location. Hiding these in SwiftUI is not hiding them. Anyone with a network proxy reads the raw JSON and gets the whole roster plus Tara's private notes.

**The solution.** Three layers, all in Postgres.

**a) Players never read the `registrations` table directly.** RLS restricts SELECT to rows for players they own:

```sql
create policy registrations_select on public.registrations
for select using (public.is_admin() or public.owns_player(player_id));
```

> **2026-09-12:** Built as `registrations_own` on a table `authenticated` cannot select at all; players read the `my_registrations` view (hard rule 1).

`is_admin()` and `owns_player()` are `SECURITY DEFINER` helpers so the policy never queries the table it protects. (This is the `is_family_member()` lesson from Volee: a recursive `EXISTS` inside a table's own RLS policy explodes.)

**b) Players never read the `clinics` table directly.** `internal_capacity` and location live there. Revoke SELECT on the base table from `authenticated` and expose a view with only the allowed columns:

```sql
revoke select on public.clinics from authenticated;

create view public.clinics_public as
  select id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at, status
  from public.clinics
  where status in ('published', 'canceled');

grant select on public.clinics_public to authenticated;
```

> **2026-09-12:** The live view also carries `canceled_at`, `member_price_cents`, `nonmember_price_cents`, `duration_minutes` (2026-08-12) and filters `and ends_at > now()` (2026-08-28), so finished clinics drop off the players' list.

The view runs with the owner's rights, so it can read the locked base table while the client cannot. Admin reads the base table through `is_admin()` policies.

**c) No count is ever returned to a player.** Not `spots_left`, not a `count(*)`, not a header. A player's own registration row tells them their status and nothing else. Every player-facing read is either the public view or an RPC with a fixed, audited return shape.

**Private notes** live in a separate `player_notes` table, admin-only, so a careless `select *` on `players` can never leak them.

**Guarded by** `tests/sql/information_hiding.sql`: a probe that authenticates as an ordinary player and asserts it cannot read capacity, another player's registration, a court assignment, or a note. This gets the same hard-rule treatment as Volee's 18+/U18 isolation.

---

## 2. The Thursday 8:00 AM race

**The problem.** Member priority is the only place in the app where software decides capacity instead of Tara. Two members tapping Register in the same second must not both land in You're In! past capacity. A client that reads the count, decides, then inserts, is guaranteed to double-book eventually, on the busiest clinic.

**The solution.** One `SECURITY DEFINER` function that locks the clinic row, counts, and inserts inside a single transaction.

```sql
create or replace function public.register_for_clinic(p_clinic uuid, p_player uuid)
returns public.registrations
language plpgsql security definer set search_path = public as $$
declare c record; v_member boolean; v_taken int; v_status registration_status;
begin
  if not (public.owns_player(p_player) or public.is_admin()) then
    raise exception 'not_authorized';
  end if;

  select * into c from clinics where id = p_clinic and status = 'published' for update;
  if not found then raise exception 'clinic_not_found'; end if;
  if c.closes_at is not null and now() >= c.closes_at then raise exception 'registration_closed'; end if;

  select is_member into v_member from players where id = p_player;

  if now() < c.member_opens_at then
    raise exception 'registration_not_open';
  elsif v_member and now() < c.public_opens_at then
    select count(*) into v_taken from registrations
      where clinic_id = p_clinic and status = 'in';
    v_status := case when v_taken < c.internal_capacity then 'in' else 'pool' end;
  else
    v_status := 'pool';   -- non-member, or member past the priority window
  end if;

  insert into registrations (clinic_id, player_id, status, registered_at)
  values (p_clinic, p_player, v_status, now())
  returning * into c;
  return c;
end $$;
```

`FOR UPDATE` on the clinic row is what serializes the concurrent registers. The three branches encode the whole registration table from the guide: member in window → You're In! if room, otherwise Pool; member late → Pool; non-member → Pool.

> **2026-09-12:** Built with one extra branch: a non-member inside the member-only window is rejected (`registration_not_open`), not pooled (CLAUDE.md, "Blocking non-members"). The insert also snapshots `price_cents_charged`, `was_member` and `duration_minutes` per decision 0002.

**Guarded by** `tests/sql/registration_windows.sql` (one case per row of the guide's table) and `tests/sql/capacity_race.sh` (N concurrent sessions against a capacity-1 clinic, assert exactly one `in`).

---

## 3. Registration state machine and idempotency

**The problem.** Four statuses with real collisions. Tara taps Cancel Invitation at the same moment the player taps Accept. A player taps Register twice on a bad connection. A retry after a timeout. The guide's own edge-case table is a spec for this.

**The solution.**

**One live registration per player per clinic**, enforced by a partial unique index so a canceled registration can be replaced but a live one can't be duplicated:

```sql
create unique index registrations_one_live
  on registrations (clinic_id, player_id)
  where status in ('in', 'pool', 'response_needed');
```

A duplicate insert raises `23505`, which the app renders as the guide's copy: "You're already registered for this clinic." A retried request after a timeout hits the same index, so retries are safe.

**Every transition is a conditional update that reports whether it did anything:**

```sql
update registrations set status = 'response_needed', invited_at = now()
where id = p_registration and status = 'pool'
returning *;
```

Zero rows returned means someone else got there first. The Tara-cancels vs player-accepts race resolves to whoever's UPDATE lands first; the loser gets a friendly message instead of a silent overwrite. Same pattern for accept, decline, cancel-invitation, and player-cancel.

Legal transitions, everything else rejected:

```
(none) → in | pool          register
pool   → response_needed    Tara invites
response_needed → in        player accepts
response_needed → pool      player declines, or Tara cancels the invitation
in | pool | response_needed → canceled   player cancels, or Tara removes
pool   → (deleted)          player leaves the Pool
```

> **2026-09-12:** Since: late requests (`20260827000002`, `request_late_spot` / `resolve_late_request` → `in` after close) and the late-cancel note (decision 0010: `cancel_registration(p_registration, p_note)` refuses a You're In! cancel inside the 4-hour cutoff without a note). Tara removes a player through the same `cancel_registration` (2026-09-10).

Canceled rows are never deleted. Tara sees them with the cancellation timestamp.

---

## 4. Push is the only channel, with no fallback

**The problem.** No email by design. A player who denies notification permission receives nothing: no invitation, no cancellation. Combined with "invitations never expire," an invite can sit dead forever while Tara waits for an answer that will never come.

**The solution.**

- **In-app is the real source of truth.** Response Needed shows on Home and in My Clinics regardless of push. Push is an accelerator, not the channel.
- **Track permission state.** The app writes the notification authorization status to `accounts.push_enabled` on every launch. Tara sees a "notifications off" marker on the player's profile so she can text them.
  > **Overruled 2026-08-02 (Tara, decision 13):** no column, no marker. The app tells the player instead (at sign-up, and persistently while permission is denied).
- **Every push carries a deep link payload** (`{type, id}`) so tapping it opens the exact clinic, invitation, or news post. Routed by a single `DeepLink` enum parsed at the app root. Cheap now, painful to retrofit.
  > **2026-09-12:** Not built; waits on the push sender (decision 0008).
- **Delivery is an edge function**, not the client: `POST /notify` takes recipients and a payload, signs an APNs JWT, and records a row in `notifications` regardless of whether APNs accepted it. The in-app notification list is therefore complete even when push fails.
  > **2026-09-12:** Superseded by decision 0008: the RPCs write the `notifications` row; a `push` edge function on a `notifications` INSERT webhook delivers. Not yet deployed.

---

## 5. The active-player context

**The problem.** A parent switching between themselves and three kids means every read and write is parameterized by which player is active. This is exactly where Volee's family picker bit us: a value captured in one place and read in another, across a SwiftUI render boundary, silently becomes the wrong value. The failure mode here is "registered the wrong kid," which Tara will hear about.

**The solution.** One app-level `@Observable ActivePlayer` holding a `Player`, and a hard rule: **no repository function ever infers the subject.** Every call takes an explicit `playerId`. There is no `registerMe()`, only `register(clinicId:playerId:)`. The player id travels as a value type in one stack frame from the button to the RPC.

The active player's name appears at the top of Home and Clinics at all times, and every confirmation names them: "Jake has joined the Player Pool."

**Guarded by** a unit test that asserts every repository method with a player-scoped effect requires a `playerId` argument, and a UI test that switches players mid-flow and asserts the registration landed on the right one.

> **2026-09-12:** §5 is deferred with juniors (decision 0004); `activePlayer` is simply `players.first`. The explicit-`playerId` rule is followed (`register(clinicId:playerId:)`); neither guard test exists.

---

## 6. Admin authorization: designed for many, built for one

**The problem.** One admin in v1, "multiple administrators or coaches" is a stated v2 candidate. If Tara's UUID gets hardcoded anywhere, v2 is an RLS rewrite.

**The solution.** `accounts.role` (`'member' | 'admin'`), plus:

```sql
create function public.is_admin() returns boolean
language sql security definer stable set search_path = public as $$
  select exists (select 1 from accounts where id = auth.uid() and role = 'admin')
$$;
```

Every admin policy and every admin RPC calls `is_admin()`. v2 becomes an UPDATE statement instead of a migration. Costs nothing now.

---

## 7. Templates snapshot, they don't reference

**The problem.** If a clinic points at its template instead of copying from it, Tara editing the template in October silently rewrites every clinic she published in September, including their prices.

**The solution.** `create_clinic_from_template(template_id, starts_at, ends_at)` copies every value into the new `clinics` row. `clinics.template_id` is kept for reporting only and is never read at render time. Editing a template affects nothing that already exists.

This also delivers the guide's one-to-two-minutes-per-clinic goal: the only required inputs are the date and an optional time adjustment.

---

## 8. Time zone and daylight saving

> **Wrong, corrected 2026-08-02 (decision 0001).** The per-clinic rule below opens Friday and Saturday clinics a week late. Built rule: per service week, `service_week_start()` − 3 / − 2 days at 08:00 America/New_York (`STABLE`, not `immutable`). Pinned by `tests/sql/registration_window_rule.sql`; `registration_window_dates.sql` never existed.

**The problem.** Clinic times are wall-clock local events. Registration windows are absolute instants. Get the storage wrong and March and November both break.

**The solution.** Everything is `timestamptz`. Registration windows are derived, not typed, using the most recent Thursday strictly before the clinic date:

```sql
create function public.member_opens_at(p_starts_at timestamptz)
returns timestamptz language sql immutable as $$
  select (
    ((p_starts_at at time zone 'America/New_York')::date
      - (((extract(isodow from p_starts_at at time zone 'America/New_York')::int - 4 + 6) % 7) + 1)
    ) + time '08:00'
  ) at time zone 'America/New_York'
$$;
```

Verified against every weekday: a Saturday clinic gets the Thursday two days before, a Monday clinic gets the previous week's Thursday, a Thursday clinic gets the Thursday a week earlier (strictly before, never same-day). `public_opens_at` is that plus one day. Both are stored on the clinic at creation so Tara can override either.

Naming it `America/New_York` rather than a fixed offset is what makes DST a non-issue.

**Guarded by** tests/sql/registration_window_dates.sql (never created; see the 2026-09-12 note): one assertion per weekday, plus a clinic on each side of both DST transitions.

**Client clocks are never trusted.** The countdown ("Opens in 14 hours") is display only; the gate is `now()` inside `register_for_clinic`. A device with a wrong clock cannot register early.

---

## 9. Offline and retry

The guide: "Do not assume success. Show a clear retry message."

The partial unique index from §3 makes registration naturally idempotent, so a retry after a timeout either succeeds or returns the already-registered error, never a double booking. The client shows the retry prompt on any network error and does not optimistically flip the UI to You're In!.

---

## 10. Unread state

`news_reads (news_id, account_id, read_at)`. The badge counts published posts matching the account's audience with no read row. Keyed to the account, not the player, because a parent reads once even when they manage three kids.

> **2026-09-12:** Deferred with News (decision 0006); the Home badge counts `notifications.read_at` instead (2026-09-02).

---

## 11. Children's data and the App Store

**The problem.** Two risks, neither a blocker, both needing deliberate handling.

- The app stores children's first name, last name, and birthday under a parent account. That is kids' data. It needs an accurate App Privacy declaration, a real privacy policy URL, and no third-party analytics SDKs touching those records.
- A single-club app can draw Guideline 4.2 (minimum functionality) scrutiny.

**The solution.** No third-party SDKs in v1 (no analytics vendor, no ad network, no crash reporter that ships PII). Children have no login, no email, no phone, no password: the parent enters the data and controls it, which is the defensible standard pattern. A demo account with realistic seeded data is ready before the first submission, and the reviewer notes explain that the app serves a specific club's members.

> **2026-09-12:** Children's data is out of v1 (decision 0004). The Stripe iOS SDK (PaymentSheet only) was added 2026-09-12, so "no third-party SDKs" no longer holds. The demo account conflicts with CLAUDE.md's "No test fixtures in hosted, ever"; how App Review gets a login needs a decision.

No money moves through the app, so there is no IAP obligation and none of Volee's subscription review pain. Tennis clinics are a real-world service, which is exempt from Apple's in-app-purchase requirement, so linking out to Venmo is fine as long as it is not dressed up as a purchase flow.

> **2026-09-12:** Superseded by decision 0009: money moves via Stripe (real-world service, still no IAP). Zelle stays as text.

---

## 12. Scale

A club program is hundreds of players and dozens of clinics per week. Supabase is roughly a hundred times oversized for this. There is no scaling problem, and the honest answer to anyone who asks is that we deliberately did not build for one. The indexes that matter are `registrations(clinic_id, status)` and `players(last_name, first_name)` for the forgiving search.

---

## Data model

```
accounts          id (= auth.users.id), first_name, last_name, email, phone,
                  account_type ('adult'|'parent'|'both'), role ('member'|'admin'),
                  push_enabled, created_at

players           id, account_id, kind ('adult'|'junior'),
                  first_name, last_name,
                  date_of_birth (juniors),          -- birthday, not age; see below
                  adult_rating (adults),
                  is_member, is_active, created_at

player_notes      player_id, body, updated_at              -- ADMIN ONLY, separate table

clinic_templates  id, name, audience, category, description, price_cents,
                  default_start_time, default_duration_minutes,
                  internal_capacity, archived_at

clinics           id, template_id (provenance only), name, audience, category,
                  description, price_cents, starts_at, ends_at,
                  member_opens_at, public_opens_at, closes_at,
                  internal_capacity, status ('draft'|'published'|'canceled'),
                  canceled_at, created_at

registrations     id, clinic_id, player_id,
                  status ('in'|'pool'|'response_needed'|'canceled'),
                  paid, court_number (1-5, admin-only),
                  registered_at, invited_at, responded_at, canceled_at, canceled_by,
                  source ('self'|'admin')

clinic_messages   id, clinic_id, body,
                  audience ('everyone'|'in'|'pool'|'response_needed'|'unpaid'),
                  sent_at

news_posts        id, title, body, audience ('adults'|'juniors'|'everyone'),
                  status ('draft'|'published'), published_at, archived_at

news_reads        news_id, account_id, read_at

notifications     id, account_id, type, entity_type, entity_id, body, created_at, read_at

devices           account_id, apns_token, platform, updated_at
```

> **2026-09-12:** Drift from the live schema: `accounts` has no `push_enabled` (decision 13) and gained `stripe_customer_id, card_brand, card_last4, card_added_at` (0009). `clinic_templates` uses `duration_minutes` (not `default_duration_minutes`) and adds `member_price_cents, nonmember_price_cents, created_at` (legacy `price_cents` remains). `clinics` adds `duration_minutes, member_price_cents, nonmember_price_cents`. `registrations` adds `price_cents_charged, was_member, duration_minutes` (0002) and `late_cancel, cancel_note` (0010). Four tables are missing from the list entirely: `app_settings`, `clinic_message_recipients`, `late_requests`, `payments`.

Two deliberate departures from the guide's entity list:

- **Court assignment is a column on `registrations`, not its own table.** The guide describes it as (clinic, player, court 1-5), which is exactly a column on the row that already joins clinic and player. A separate table would add a join and a consistency problem for zero benefit.
- **Child profiles store `date_of_birth`, not `age`.** A stored age is silently wrong within a year. This is the same mistake Volee made with `age_group` and had to derive on read instead. Flagged for Tara, since it changes the form label from "Age" to "Birthday."

Everything archives, nothing deletes: `players.is_active`, `clinics.status = 'canceled'`, `registrations.status = 'canceled'`, `clinic_templates.archived_at`, `news_posts.archived_at`.

---

## RPC surface

Player-facing:

| Function | Notes |
|---|---|
| `register_for_clinic(clinic, player)` | §2, atomic, the only capacity decision in the app |
| `respond_to_invitation(registration, accept)` | conditional on `status = 'response_needed'` |
| `cancel_registration(registration, note)` | conditional, preserves history, notifies Tara; since 0010 the note is required inside the 4-hour cutoff (old one-argument signature dropped) |
| `leave_pool(registration)` | conditional on `status = 'pool'` |
| `mark_news_read(news_post)` | upsert into `news_reads` |

Admin-only (each guarded by `is_admin()`):

| Function | Notes |
|---|---|
| `create_clinic_from_template(template, starts_at, ends_at)` | snapshot copy, §7 |
| `publish_clinic(clinic)` / `cancel_clinic(clinic)` | cancel notifies all three live statuses |
| `invite_from_pool(registration)` | → `response_needed` |
| `cancel_invitation(registration)` | → `pool` |
| `place_player(clinic, player, status)` | the walk-up path (Tara decision 3, 2026-08-02) |
| `set_paid(registration, paid)` | |
| `assign_court(registration, court)` | |
| `send_clinic_message(clinic, audience, body)` | resolves recipients server-side |
| `publish_news(post)` | |
| `set_player_active(player, active)` | deactivate, never delete |

Player-facing reads go through `clinics_public` (§1) and an RLS-filtered `registrations` select. There is no player-facing endpoint that returns a count of anything.

> **2026-09-12:** Players read the `my_registrations` view; the table is not selectable by clients (hard rule 1). The two tables above are the July surface; there are 20+ more functions now (`admin_upsert_clinic`, `admin_upsert_template`, `admin_set_template_archived`, `admin_set_player_note`, `admin_set_membership`, `admin_charge_registration`, `admin_refund_payment`, `request_late_spot`, `resolve_late_request`, `create_my_account`, `register_device`, `search_players`, `revenue_summary`, ...). The surface as of 2026-09-12 is in `docs/architecture.md`.

---

## Test plan

The guide's own QA list (its line 583 onward) is the test suite. Fourteen scenarios, each mapped to the layer that can actually prove it:

| Scenario | Layer |
|---|---|
| Member registers Thursday after opening → You're In! | SQL probe |
| Member registers after priority → Player Pool | SQL probe |
| Non-member registers Friday → Player Pool | SQL probe |
| Full clinic → still joins Pool, no leak of fullness | SQL probe |
| Two members register simultaneously at capacity 1 | SQL probe (concurrent) |
| Tara invites, player accepts | SQL probe + XCUITest |
| Tara invites, player declines, returns to Pool | SQL probe |
| Tara cancels invitation while player accepts | SQL probe (race) |
| Player cancels, Action Needed updates | SQL probe + XCUITest |
| Parent adds multiple children, registers each | XCUITest (deferred: juniors out of v1, decision 0004) |
| Adult sees no junior clinics or junior news | SQL probe (RLS) (deferred: 0004, 0006) |
| Player never sees capacity, spots, location, others, courts, notes | SQL probe (the §1 probe) |
| Clinic from template in about one minute | XCUITest, timed |
| Unpaid reminder reaches only unchecked players | SQL probe |
| Cancellation notice reaches all three live statuses | SQL probe |
| News stays until manually removed | SQL probe (deferred: News, decision 0006) |
| Push opens the related screen | XCUITest with launch argument (deferred: push sender pending, decision 0008) |
| Duplicate registration prevented | SQL probe (unique index) |
| DST boundary clinics get correct windows | SQL probe |

Written before or alongside the feature, not after. The repo ships with the starter kit (slash commands, hooks, CI) installed on day one rather than retrofitted.

> **2026-09-12:** CI arrived 2026-08-10 and hooks 2026-08-14, not day one.

---

## Open items waiting on Tara

Numbered to match `for-tara.md`: the admin surface (1), registration timing rule (2), manual placement (3), capacity vs invites (4), member self-report (5), rating scale and guide copy (6, 7), clinic categories (8), junior age split (9), why location is hidden (10), payment copy (11), targeted-message visibility (12), notification copy (14), brand assets (15), Apple account and privacy policy (16).

None of these block starting on §1 through §10, which are the foundation and the parts that are expensive to change later.

> **2026-09-12:** All answered by 2026-08-27; see the header of `docs/for-tara.md` and `docs/decisions/`.
