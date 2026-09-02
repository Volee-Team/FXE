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

insert into auth.users (id, instance_id, aud, role, email, encrypted_password,
                        email_confirmed_at, created_at, updated_at)
values
  ('11111111-1111-1111-1111-111111111111', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'tara@fxe.test',  crypt('password', gen_salt('bf')), now(), now(), now()),
  ('22222222-2222-2222-2222-222222222222', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'maria@fxe.test', crypt('password', gen_salt('bf')), now(), now(), now()),
  ('33333333-3333-3333-3333-333333333333', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ken@fxe.test',   crypt('password', gen_salt('bf')), now(), now(), now()),
  ('44444444-4444-4444-4444-444444444444', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'rob@fxe.test',   crypt('password', gen_salt('bf')), now(), now(), now()),
  ('55555555-5555-5555-5555-555555555555', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'priya@fxe.test', crypt('password', gen_salt('bf')), now(), now(), now()),
  ('66666666-6666-6666-6666-666666666666', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'dana@fxe.test',  crypt('password', gen_salt('bf')), now(), now(), now())
on conflict (id) do nothing;

insert into public.accounts (id, first_name, last_name, email, phone, account_type, role) values
  ('11111111-1111-1111-1111-111111111111', 'Tara',  'Coach',      'tara@fxe.test',  '704-555-0100', 'adult',  'admin'),
  ('22222222-2222-2222-2222-222222222222', 'Maria', 'Alvarez',    'maria@fxe.test', '704-555-0101', 'adult',  'member'),
  ('33333333-3333-3333-3333-333333333333', 'Ken',   'Whitfield',  'ken@fxe.test',   '704-555-0102', 'adult',  'member'),
  ('44444444-4444-4444-4444-444444444444', 'Rob',   'Delgado',    'rob@fxe.test',   '704-555-0103', 'adult',  'member'),
  ('55555555-5555-5555-5555-555555555555', 'Priya', 'Raman',      'priya@fxe.test', '704-555-0104', 'adult',  'member'),
  ('66666666-6666-6666-6666-666666666666', 'Dana',  'Okonkwo',    'dana@fxe.test',  '704-555-0105', 'adult',  'member')
on conflict (id) do nothing;

insert into public.players (id, account_id, kind, first_name, last_name, date_of_birth, adult_rating, is_member) values
  ('a0000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'adult', 'Maria', 'Alvarez',   '1988-04-12', 3.5,  true),
  ('a0000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 'adult', 'Ken',   'Whitfield', '1979-09-30', 4.0,  true),
  ('a0000000-0000-0000-0000-000000000003', '44444444-4444-4444-4444-444444444444', 'adult', 'Rob',   'Delgado',   '1992-01-05', 3.0,  false),
  ('a0000000-0000-0000-0000-000000000004', '66666666-6666-6666-6666-666666666666', 'adult', 'Dana',  'Okonkwo',   '1985-06-22', 3.5,  true),
  -- Priya plays too. v1 is adults only (Tara, 2026-08-02): no junior players,
  -- no parent-managed children. The 'junior' enum value and the junior columns
  -- stay in the schema so the fall re-enable is UI work, not a migration.
  ('a0000000-0000-0000-0000-000000000005', '55555555-5555-5555-5555-555555555555', 'adult', 'Priya', 'Raman',     '1983-07-14', 3.0,  false)
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
-- reset (the notification-center XCUITest reads these). Bodies are the shape
-- the RPCs write; they are not shown to Tara and carry nothing hidden.
insert into public.notifications (account_id, type, entity_type, entity_id, body, created_at) values
  ('22222222-2222-2222-2222-222222222222', 'invitation_received', 'clinic', 'd0000000-0000-0000-0000-000000000002',
   'A spot opened up in Thursday Morning Cardio and it''s yours if you want it. Open the app to say yes or no.', now() - interval '2 hours'),
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
