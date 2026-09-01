-- templates_floor_bootstrap.sql — pins 20260828000001, and attacks it.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA_ACC  constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA_ACC constant uuid := '22222222-2222-2222-2222-222222222222';
  n int; v_role text; v_past uuid;
begin
  -- ---------------------------------------------------------- templates_admin
  perform set_config('request.jwt.claims', json_build_object('sub', TARA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.templates_admin;
  insert into _probe_result values ('admin_can_list_templates', 'true', (n >= 1)::text);

  -- A member gets zero rows, not an error (matches clinics_admin behaviour).
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  select count(*) into n from public.templates_admin;
  insert into _probe_result values ('member_sees_zero_templates', '0', n::text);

  -- The view must never grow write grants (the 2026-08-13 lesson).
  select count(*) into n from information_schema.role_table_grants
   where table_schema='public' and table_name='templates_admin'
     and grantee in ('anon','authenticated')
     and privilege_type in ('INSERT','UPDATE','DELETE','TRUNCATE');
  insert into _probe_result values ('templates_view_is_read_only', '0', n::text);

  -- ------------------------------------------------------------- date floor
  perform set_config('role', 'postgres', true);
  insert into public.clinics (name, audience, starts_at, ends_at, duration_minutes,
      member_opens_at, public_opens_at, closes_at, internal_capacity, status)
  values ('Probe FINISHED', 'ladies', now() - interval '9 days', now() - interval '9 days' + interval '1 hour',
          60, now() - interval '20 days', now() - interval '19 days', now() - interval '10 days', 8, 'published')
  returning id into v_past;

  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.clinics_public where id = v_past;
  insert into _probe_result values ('finished_clinic_hidden_from_players', '0', n::text);

  -- Tara still sees history: her Past section is real (hard rule 4 in spirit).
  perform set_config('request.jwt.claims', json_build_object('sub', TARA_ACC)::text, true);
  select count(*) into n from public.clinics_admin where id = v_past;
  insert into _probe_result values ('finished_clinic_still_visible_to_admin', '1', n::text);

  -- Future clinics still show (the floor must not eat the schedule).
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  select count(*) into n from public.clinics_public where starts_at > now();
  insert into _probe_result values ('future_clinics_still_listed', 'true', (n >= 1)::text);

  -- ------------------------------------------------------------- bootstrap
  perform set_config('role', 'postgres', true);
  -- accounts.id FKs to auth.users, so mint the auth rows first (same pattern
  -- as create_my_account.sql). Capitalised email on purpose: the trigger must
  -- match case-insensitively, because that is how people type their own email.
  insert into auth.users (id, email, instance_id, aud, role)
  values ('99999999-0000-0000-0000-000000000001', 'FerscTennisPro@gmail.com',
          '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated'),
         ('99999999-0000-0000-0000-000000000002', 'nottara@gmail.com',
          '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
  insert into public.accounts (id, first_name, last_name, email)
  values ('99999999-0000-0000-0000-000000000001', 'Tara', 'Marcel', 'FerscTennisPro@gmail.com');
  select role::text into v_role from public.accounts where id = '99999999-0000-0000-0000-000000000001';
  insert into _probe_result values ('taras_email_arrives_as_admin', 'admin', v_role);

  insert into public.accounts (id, first_name, last_name, email)
  values ('99999999-0000-0000-0000-000000000002', 'Not', 'Tara', 'nottara@gmail.com');
  select role::text into v_role from public.accounts where id = '99999999-0000-0000-0000-000000000002';
  insert into _probe_result values ('anyone_else_arrives_as_member', 'member', v_role);

  -- The trigger must not create an UPDATE path to admin (hard rule 8 intact).
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    update public.accounts set role = 'admin' where id = MARIA_ACC;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select role::text into v_role from public.accounts where id = MARIA_ACC;
  insert into _probe_result values ('self_promotion_still_blocked', 'member', v_role);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;
rollback;
