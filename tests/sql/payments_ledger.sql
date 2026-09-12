-- payments_ledger.sql
--
-- The admin's read of card payments (20260912000003). The view runs as its
-- owner and joins tables a player cannot read, so the thing to prove is the
-- gate: Tara sees the row with the names on it, Maria sees nothing at all, and
-- nobody can write through it.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  CLINIC  constant uuid := 'd0000000-0000-0000-0000-000000000002';
  reg_m uuid; pay uuid; n int; v text; cname text;
begin
  -- Fixture (as postgres): Maria is in, has a card, payments are on, Tara
  -- charged her. The webhook is what records a card; simulate it.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (CLINIC, MARIA_P, 'in', 'admin', 2200, true, 90) returning id into reg_m;
  update public.app_settings set value = 'true' where key = 'payments_enabled';
  update public.accounts set stripe_customer_id = 'cus_test_maria', card_brand = 'visa', card_last4 = '4242', card_added_at = now() where id = MARIA;
  select name into cname from public.clinics where id = CLINIC;

  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select id into pay from public.admin_charge_registration(reg_m, 'clinic_fee');

  -- 1. Tara reads the row, and it names the player and the clinic.
  select first_name || ' ' || last_name || ' | ' || clinic_name || ' | ' || amount_cents || ' ' || status || ' ' || kind
    into v from public.payments_ledger where id = pay;
  insert into _probe_result values ('admin_sees_named_row', 'Maria Alvarez | ' || cname || ' | 2200 pending clinic_fee', coalesce(v, 'NO ROW'));

  -- 2. Newest first is the page's order; the view must not hide created_at.
  select count(*) into n from public.payments_ledger where created_at is not null and clinic_starts_at is not null;
  insert into _probe_result values ('admin_row_carries_dates', '1', n::text);
  perform set_config('role', 'postgres', true);

  -- 3. Maria, the payer herself, sees nothing through the admin view. Her own
  --    ledger is `payments` under RLS (payments_own); this view is Tara's.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.payments_ledger;
  insert into _probe_result values ('player_sees_nothing_in_admin_ledger', '0', n::text);
  perform set_config('role', 'postgres', true);

  -- 4. Anon has no select at all, before RLS or is_admin() even run.
  insert into _probe_result values ('anon_cannot_select_ledger', 'false',
    has_table_privilege('anon', 'public.payments_ledger', 'SELECT')::text);
  insert into _probe_result values ('public_cannot_select_ledger', 'false',
    (select coalesce(bool_or(privilege_type = 'SELECT'), false) from information_schema.role_table_grants
      where table_schema = 'public' and table_name = 'payments_ledger' and grantee = 'PUBLIC')::text);

  -- 5. No write path through the view for anyone the app signs in as.
  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'payments_ledger'
     and grantee in ('anon', 'authenticated')
     and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE');
  insert into _probe_result values ('no_write_grants_on_ledger', '0', n::text);

  -- 6. The gate is in the definition, not in a policy someone can drop later
  --    without noticing. (A four-table join is never auto-updatable, so the
  --    2026-08-13 write-through hole cannot reopen here.)
  select count(*) into n from pg_views where schemaname = 'public' and viewname = 'payments_ledger'
    and definition like '%is_admin()%';
  insert into _probe_result values ('gate_is_in_the_view_definition', '1', n::text);
  select is_updatable into v from information_schema.views where table_schema = 'public' and table_name = 'payments_ledger';
  insert into _probe_result values ('ledger_view_is_not_updatable', 'NO', v);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
