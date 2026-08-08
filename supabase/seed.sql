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
  ('55555555-5555-5555-5555-555555555555', 'Priya', 'Raman',      'priya@fxe.test', '704-555-0104', 'parent', 'member'),
  ('66666666-6666-6666-6666-666666666666', 'Dana',  'Okonkwo',    'dana@fxe.test',  '704-555-0105', 'adult',  'member')
on conflict (id) do nothing;

insert into public.players (id, account_id, kind, first_name, last_name, date_of_birth, adult_rating, is_member) values
  ('a0000000-0000-0000-0000-000000000001', '22222222-2222-2222-2222-222222222222', 'adult', 'Maria', 'Alvarez',   '1988-04-12', 3.5,  true),
  ('a0000000-0000-0000-0000-000000000002', '33333333-3333-3333-3333-333333333333', 'adult', 'Ken',   'Whitfield', '1979-09-30', 4.0,  true),
  ('a0000000-0000-0000-0000-000000000003', '44444444-4444-4444-4444-444444444444', 'adult', 'Rob',   'Delgado',   '1992-01-05', 3.0,  false),
  ('a0000000-0000-0000-0000-000000000004', '66666666-6666-6666-6666-666666666666', 'adult', 'Dana',  'Okonkwo',   '1985-06-22', 3.5,  true),
  ('a0000000-0000-0000-0000-000000000010', '55555555-5555-5555-5555-555555555555', 'junior', 'Jake', 'Raman',     '2015-03-08', null,  true),
  ('a0000000-0000-0000-0000-000000000011', '55555555-5555-5555-5555-555555555555', 'junior', 'Ana',  'Raman',     '2010-11-19', null,  true)
on conflict (id) do nothing;

insert into public.player_notes (player_id, body) values
  ('a0000000-0000-0000-0000-000000000001', 'Prefers doubles. Recovering from a wrist issue, keep serves light.')
on conflict (player_id) do nothing;

insert into public.clinic_templates (id, name, audience, category, description, price_cents, default_start_time, duration_minutes, internal_capacity) values
  ('b0000000-0000-0000-0000-000000000001', 'Ladies Drill',      'ladies',  'Drill',      'Live-ball drilling, 3.0 to 4.0.', 3000, '09:00', 90, 8),
  ('b0000000-0000-0000-0000-000000000002', 'Junior Development','juniors', 'Development','Ages 8 to 12, green ball.',        2500, '16:00', 60, 10)
on conflict (id) do nothing;
