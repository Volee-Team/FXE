-- Deterministic seed for local development and the SQL probes.
-- Fixed UUIDs so probes can reference rows without lookups.
--
-- Cast of characters:
--   Tara      admin, does not play
--   Maria     adult MEMBER
--   Ken       adult MEMBER
--   Dana      adult MEMBER
--   Rob       adult NON-member
--   Priya     parent, does not play; kids Jake (11) and Ana (16)
--   Casey     a PRO (decision 0025): signed up like any member, then Tara
--             made her a pro through admin_set_pro, at the end of this file
--   Lena      adult MEMBER, You're In! in today's clinic (the pro's Today tab)
--   Theo      adult NON-member, You're In! in today's clinic

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tara@fxe.test',  crypt('password', gen_salt('bf')), now(), now(), now()),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'maria@fxe.test', crypt('password', gen_salt('bf')), now(), now(), now()),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ken@fxe.test',   crypt('password', gen_salt('bf')), now(), now(), now()),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rob@fxe.test',   crypt('password', gen_salt('bf')), now(), now(), now()),
  ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'priya@fxe.test', crypt('password', gen_salt('bf')), now(), now(), now()),
  ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dana@fxe.test',  crypt('password', gen_salt('bf')), now(), now(), now()),
  ('77777777-7777-7777-7777-777777777777', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'pro@fxe.test',   crypt('password', gen_salt('bf')), now(), now(), now()),
  ('88888888-8888-8888-8888-888888888888', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'lena@fxe.test',  crypt('password', gen_salt('bf')), now(), now(), now()),
  ('99999999-9999-9999-9999-999999999999', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'theo@fxe.test',  crypt('password', gen_salt('bf')), now(), now(), now())
on conflict (id) do nothing;

insert into public.accounts (id, first_name, last_name, email, phone, account_type, role) values
  ('11111111-1111-1111-1111-111111111111', 'Tara',  'Coach',      'tara@fxe.test',  '704-555-0100', 'adult',  'admin'),
  ('22222222-2222-2222-2222-222222222222', 'Maria', 'Alvarez',    'maria@fxe.test', '704-555-0101', 'adult',  'member'),
  ('33333333-3333-3333-3333-333333333333', 'Ken',   'Whitfield',  'ken@fxe.test',   '704-555-0102', 'adult',  'member'),
  ('44444444-4444-4444-4444-444444444444', 'Rob',   'Delgado',    'rob@fxe.test',   '704-555-0103', 'adult',  'member'),
  ('55555555-5555-5555-5555-555555555555', 'Priya', 'Raman',      'priya@fxe.test', '704-555-0104', 'adult',  'member'),
  ('66666666-6666-6666-6666-666666666666', 'Dana',  'Okonkwo',    'dana@fxe.test',  '704-555-0105', 'adult',  'member'),
  ('77777777-7777-7777-7777-777777777777', 'Casey', 'Park',       'pro@fxe.test',   '704-555-0106', 'adult',  'member'),
  ('88888888-8888-8888-8888-888888888888', 'Lena',  'Brooks',     'lena@fxe.test',  '704-555-0107', 'adult',  'member'),
  ('99999999-9999-9999-9999-999999999999', 'Theo',  'Grant',      'theo@fxe.test',  '704-555-0108', 'adult',  'member')
on conflict (id) do nothing;

insert into public.players (id, account_id, kind, first_name, last_name, date_of_birth, adult_rating, is_member) values
  ('a0000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'adult', 'Maria', 'Alvarez',   '1988-04-12', 3.5,  true),
  ('a0000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 'adult', 'Ken',   'Whitfield', '1979-09-30', 4.0,  true),
  ('a0000000-0000-0000-0000-000000000003', '44444444-4444-4444-4444-444444444444', 'adult', 'Rob',   'Delgado',   '1992-01-05', 3.0,  false),
  ('a0000000-0000-0000-0000-000000000004', '66666666-6666-6666-6666-666666666666', 'adult', 'Dana',  'Okonkwo',   '1985-06-22', 3.5,  true),
  -- Priya plays too. v1 is adults only (Tara, 2026-08-02): no junior players,
  -- no parent-managed children. The 'junior' enum value and the junior columns
  -- stay in the schema so the fall re-enable is UI work, not a migration.
  ('a0000000-0000-0000-0000-000000000005', '55555555-5555-5555-5555-555555555555', 'adult', 'Priya', 'Raman',     '1983-07-14', 3.0,  false),
  ('a0000000-0000-0000-0000-000000000006', '77777777-7777-7777-7777-777777777777', 'adult', 'Casey', 'Park',      '1990-03-18', 4.5,  true),
  ('a0000000-0000-0000-0000-000000000007', '88888888-8888-8888-8888-888888888888', 'adult', 'Lena',  'Brooks',    '1986-11-02', 3.5,  true),
  ('a0000000-0000-0000-0000-000000000008', '99999999-9999-9999-9999-999999999999', 'adult', 'Theo',  'Grant',     '1981-05-27', 3.0,  false)
on conflict (id) do nothing;

insert into public.player_notes (player_id, body) values
  ('a0000000-0000-0000-0000-000000000001', 'Prefers doubles. Recovering from a wrist issue, keep serves light.')
on conflict (player_id) do nothing;

-- Templates carry Tara's locked prices (2026-08-02): a 60-minute clinic is $18
-- for members and $23 for everyone else; a 90-minute clinic is $22 and $28.
-- Adults only in v1, so both templates are adult audiences.
insert into public.clinic_templates (id, name, audience, category, description,
    price_cents, member_price_cents, nonmember_price_cents,
    default_start_time, duration_minutes, internal_capacity) values
  ('b0000000-0000-0000-0000-000000000001', 'Ladies Drill', 'ladies', 'Clinic',
   'Live-ball drilling, 3.0 to 4.0.', 2200, 2200, 2800, '09:00', 90, 8),
  ('b0000000-0000-0000-0000-000000000002', 'Coed Cardio',  'coed',   'Clinic',
   'Fast-paced hour, all levels.',     1800, 1800, 2300, '18:00', 60, 10)
on conflict (id) do nothing;

-- ── Dev-only walkable clinics (local app verification + XCUITest) ────────────
-- Published clinics in the current service week so a signed-in seed user sees a
-- browsable list. NO registrations seeded on purpose: an 'in' registration would
-- change revenue_summary() and break the pricing probe. Register live through the
-- app instead — that exercises the core loop. Prices are left null so the
-- default-pricing trigger fills them from duration.
insert into public.clinics (id, name, audience, category, description, starts_at, ends_at,
    member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
values
  -- Description is Tara's verbatim copy for her real "Ladies 3.0+" clinic
  -- (docs/copy.md, 2026-08-15), replacing an invented placeholder. The NAME and
  -- the UUID are deliberately unchanged: probes reference this clinic by both.
  ('d0000000-0000-0000-0000-000000000001', 'Tuesday Ladies 3.0+', 'coed', 'Clinic',
   'A fast-paced clinic for 3.0+ players focused on live-ball doubles play. Pros feed plenty of points while players rotate through courts, work with different pros, and focus on doubles strategy, positioning, and movement. Lots of balls, constant action, and great preparation for match play',
   now() + interval '3 days', now() + interval '3 days 1 hour',
   now() - interval '1 day', now() - interval '12 hours', 8, 'published', 60),
  ('d0000000-0000-0000-0000-000000000002', 'Thursday Morning Cardio', 'coed', 'Clinic',
   'High-energy cardio tennis, all levels welcome.',
   now() + interval '5 days', now() + interval '5 days 90 minutes',
   now() - interval '1 day', now() - interval '12 hours', 10, 'published', 90),
  ('d0000000-0000-0000-0000-000000000003', 'Saturday Members Only', 'coed', 'Clinic',
   'Members priority window is open; public opens Friday.',
   now() + interval '6 days', now() + interval '6 days 1 hour',
   now() - interval '2 hours', now() + interval '12 hours', 6, 'published', 60),
  ('d0000000-0000-0000-0000-000000000004', 'Sunday Social (next week)', 'coed', '105',
   'Opens later so you can see the "registration opens" state.',
   now() + interval '10 days', now() + interval '10 days 90 minutes',
   now() + interval '3 days', now() + interval '4 days', 12, 'published', 90)
on conflict (id) do nothing;

-- Two notifications for Maria so the bell has something to show on a fresh
-- reset (the notification-center XCUITest reads these): this clinic message,
-- and an invitation written at the end of this file by invite_from_pool
-- itself. They are not shown to Tara and carry nothing hidden.
insert into public.notifications (account_id, type, entity_type, entity_id, body, created_at) values
  ('22222222-2222-2222-2222-222222222222', 'clinic_message', 'clinic', 'd0000000-0000-0000-0000-000000000001',
   'Courts are wet, we start 15 minutes late tonight.', now() - interval '1 day');

-- GoTrue login reads these token columns and cannot scan NULLs — a manual
-- auth.users INSERT leaves them null, which fails real sign-in with "Database
-- error querying schema" (the probes never hit GoTrue, so this stayed hidden
-- until the app first signed in for real). Set them to '' for every seeded user.
update auth.users set
  confirmation_token = coalesce(confirmation_token, ''),
  recovery_token = coalesce(recovery_token, ''),
  email_change = coalesce(email_change, ''),
  email_change_token_new = coalesce(email_change_token_new, ''),
  email_change_token_current = coalesce(email_change_token_current, ''),
  phone_change = coalesce(phone_change, ''),
  phone_change_token = coalesce(phone_change_token, ''),
  reauthentication_token = coalesce(reauthentication_token, '')
where email like '%@fxe.test';

-- Decision 0013 (2026-09-21): the waiver is signed before the first spot is
-- held. Every seeded player has signed the current version; the waiver probe
-- creates its own unsigned account so the refusal is tested without making a
-- seeded person the odd one out.
insert into public.waiver_acceptances (account_id, version, legal_name, email, app_version) values
  ('22222222-2222-2222-2222-222222222222', '2026-09', 'Maria Alvarez',  'maria@fxe.test', 'seed'),
  ('33333333-3333-3333-3333-333333333333', '2026-09', 'Ken Whitfield',  'ken@fxe.test',   'seed'),
  ('44444444-4444-4444-4444-444444444444', '2026-09', 'Rob Delgado',    'rob@fxe.test',   'seed'),
  ('55555555-5555-5555-5555-555555555555', '2026-09', 'Priya Raman',    'priya@fxe.test', 'seed'),
  ('66666666-6666-6666-6666-666666666666', '2026-09', 'Dana Okonkwo',   'dana@fxe.test',  'seed'),
  ('77777777-7777-7777-7777-777777777777', '2026-09', 'Casey Park',     'pro@fxe.test',   'seed'),
  ('88888888-8888-8888-8888-888888888888', '2026-09', 'Lena Brooks',    'lena@fxe.test',  'seed'),
  ('99999999-9999-9999-9999-999999999999', '2026-09', 'Theo Grant',    'theo@fxe.test',  'seed')
on conflict (account_id, version) do nothing;

-- ── The invitation in Maria's bell, written by the producer ─────────────────
-- (2026-09-27, MVP audit item 12.) This row used to be typed here as
-- entity_type 'clinic' with a clinic id and wording nobody sends. The real
-- producer, invite_from_pool, writes entity_type 'registration' with the
-- registration id, and the bell only opened 'clinic', so tapping a real
-- invitation did nothing while the one invitation a test could see opened a
-- clinic. The seed hid the bug. Now the producer writes the row itself, as
-- Tara, so the fixture cannot drift from it again;
-- tests/sql/notification_targets.sql pins the producer.
--
-- The clinic starts 40 days out, past the app's 35-day list horizon
-- (ClinicRepository.upcoming), so Maria's Home, Clinics and My Clinics look
-- exactly as they did before (the XCUITests read them, and Home's layout
-- depends on how many clinics are hers). The bell and a push still open it:
-- clinics_public has no horizon. Fixed ids so tests/push/simctl-invitation.apns
-- can name this row and its registration.
insert into public.clinics (id, name, audience, category, description, starts_at, ends_at,
    member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
values
  ('d0000000-0000-0000-0000-000000000005', 'Evening Coed', 'coed', 'Clinic',
   'Holds the invitation example in Maria''s bell.',
   now() + interval '40 days', now() + interval '40 days 1 hour',
   now() - interval '1 day', now() - interval '12 hours', 8, 'published', 60)
on conflict (id) do nothing;

insert into public.registrations (id, clinic_id, player_id, status, source,
    price_cents_charged, was_member, duration_minutes, registered_at)
values
  ('e0000000-0000-0000-0000-000000000001', 'd0000000-0000-0000-0000-000000000005',
   'a0000000-0000-0000-0000-000000000001', 'pool', 'self', 1800, true, 60, now() - interval '3 hours')
on conflict (id) do nothing;

do $$
begin
  -- Tara presses Invite. require_admin() reads auth.uid() from these claims;
  -- they are cleared again so nothing after this runs as her.
  perform set_config('request.jwt.claims',
    json_build_object('sub', '11111111-1111-1111-1111-111111111111')::text, true);
  if exists (select 1 from public.registrations
              where id = 'e0000000-0000-0000-0000-000000000001' and status = 'pool') then
    perform public.invite_from_pool('e0000000-0000-0000-0000-000000000001');
    -- The one thing changed after the producer: the row's own id, so the
    -- simctl payload file can mark exactly this row read.
    update public.notifications set id = 'f0000000-0000-0000-0000-000000000001'
     where account_id = '22222222-2222-2222-2222-222222222222'
       and type = 'invitation_received'
       and entity_id = 'e0000000-0000-0000-0000-000000000001';
  end if;
  perform set_config('request.jwt.claims', '', true);
end $$;

-- ── The pro's Today tab (decision 0025, 2026-09-28) ─────────────────────────
-- One published clinic on TODAY's New York date, with two You're In! players,
-- so the pro has something to see whenever the suite runs (tests/sql/
-- pro_role.sql's seed checks and FXETennisUITests/ProFlowUITests.swift).
--
-- 00:30 to 01:30 New York, not noon, on purpose. A clinic is on every
-- player's Clinics list until it ENDS (clinics_public: ends_at > now()), so a
-- noon clinic would sit first on that list from midnight to 13:00: open to
-- register before 09:00 (and PlayerFlowUITests' first test would register
-- Maria into it), closed but listed from 09:00 to 13:00 (and that test,
-- which opens the FIRST card and expects Register, would fail). Any clinic
-- dated today is unfinished for part of today; at 00:30 that part is the
-- smallest: from midnight to 01:30 New York (closed and listed until 00:30,
-- in progress until 01:30) it is the first card on every player's list, and
-- the UI tests should not be run in those ninety minutes. Outside them players
-- never see it, every money probe meets it in one state ("ended"), and it is
-- still today for the whole New York day of the reset (tests/sql/pro_role.sql
-- moves it to today itself, so the probe does not care which day that was).
-- Lena and Theo exist only for this clinic, so no probe that counts Maria's,
-- Ken's or Dana's rows sees them. Snapshots as register_for_clinic would
-- write them.
insert into public.clinics (id, name, audience, category, description, starts_at, ends_at,
    member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
values
  ('d0000000-0000-0000-0000-000000000006', 'Today Drill', 'coed', 'Clinic',
   'Holds the example on the pro''s Today tab.',
   ((now() at time zone 'America/New_York')::date + time '00:30') at time zone 'America/New_York',
   ((now() at time zone 'America/New_York')::date + time '01:30') at time zone 'America/New_York',
   now() - interval '4 days', now() - interval '3 days', 8, 'published', 60)
on conflict (id) do nothing;

insert into public.registrations (id, clinic_id, player_id, status, source,
    price_cents_charged, was_member, duration_minutes, registered_at, court_number)
values
  ('e0000000-0000-0000-0000-000000000002', 'd0000000-0000-0000-0000-000000000006',
   'a0000000-0000-0000-0000-000000000007', 'in', 'self', 1800, true, 60, now() - interval '3 days', 1),
  ('e0000000-0000-0000-0000-000000000003', 'd0000000-0000-0000-0000-000000000006',
   'a0000000-0000-0000-0000-000000000008', 'in', 'self', 2300, false, 60, now() - interval '2 days', null)
on conflict (id) do nothing;

-- Casey becomes a pro the only way anyone can: Tara's admin_set_pro, as Tara
-- (the same claims dance as the invitation above), so the fixture exercises
-- the production path on every reset and cannot drift from it.
do $$
begin
  perform set_config('request.jwt.claims',
    json_build_object('sub', '11111111-1111-1111-1111-111111111111')::text, true);
  if exists (select 1 from public.accounts
              where id = '77777777-7777-7777-7777-777777777777' and role::text = 'member') then
    perform public.admin_set_pro('77777777-7777-7777-7777-777777777777', true);
  end if;
  perform set_config('request.jwt.claims', '', true);
end $$;
