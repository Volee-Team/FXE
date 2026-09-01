-- view_write_paths.sql
--
-- This probe ATTACKS, like privilege_escalation.sql. It writes through the
-- player-facing VIEWS instead of the base tables.
--
-- Origin: 2026-08-13. The lockdown in 20260728000002_helpers_views_rls.sql:90-96
-- revokes the base tables, and that half works: `authenticated` genuinely has no
-- INSERT/UPDATE/DELETE on clinics, registrations, clinic_messages. But Supabase
-- bootstraps `alter default privileges in schema public grant all on tables to
-- anon, authenticated`, so every view is BORN with all privileges, and lines
-- 170-175 only ever layer `grant select` on top. The inherited write grant was
-- never revoked.
--
-- Three properties then compose into a full RLS bypass:
--   1. The views are single-table selects, so Postgres makes them AUTO-UPDATABLE
--      (information_schema.views.is_updatable = YES).
--   2. They were created without `security_invoker`, so they execute as their
--      OWNER (postgres), not as the caller.
--   3. relforcerowsecurity = false on every base table, so the owner is exempt
--      from RLS.
-- A write through the view therefore runs as postgres with RLS switched off.
--
-- Why no existing probe caught it: this is hard rule 9 recurring for the third
-- time. information_hiding.sql asserts only what a player can READ through these
-- views. A probe that tests only the read surface cannot find a write path
-- through it. privilege_escalation.sql does attack, but only against `accounts`
-- and `players`, never against a view.
--
-- Expected: every row reads PASS, meaning every attack failed and every
-- legitimate read still works.
--
-- NOTE ON ONE NON-FINDING: an INSERT through clinics_public is also blocked by
-- clinics.internal_capacity being NOT NULL with no default and deliberately
-- absent from that view. That is a schema accident, NOT a privilege control, so
-- it is not asserted here. clinics_admin is `select *` and carries every column,
-- which is why the clinic-creation attack goes through that view instead.
--
-- ORDER MATTERS, AND IT IS NOT COSMETIC. The first draft of this probe ran the
-- `delete from clinics_public` attack first. It succeeded, cascaded through
-- registrations and clinic_messages, and every later attack then reported a
-- spurious PASS because its target row no longer existed: "cannot register
-- another player" passed only because the clinic was already gone. A probe whose
-- own first finding masks its later ones is the same family of defect as the
-- harness bugs in the 2026-08-10 changelog. The two CASCADE-inducing deletes
-- therefore run LAST, after every row-level attack and after the sanity reads.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  MARIA        constant uuid := 'a0000000-0000-0000-0000-000000000001';
  MARIA_ACC    constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN          constant uuid := 'a0000000-0000-0000-0000-000000000002';
  TARA_ACC     constant uuid := '11111111-1111-1111-1111-111111111111';
  CLINIC       constant uuid := 'd0000000-0000-0000-0000-000000000001';
  v_reg        uuid;
  v_msg        uuid;
  v_txt        text;
  v_bool       boolean;
  v_int        int;
  n            int;
  n_clinics    int;
begin
  -- ---------------------------------------------------------------- fixtures --
  -- Seed has clinics and players but no registrations, so build the rows the
  -- attacks operate on. All of this rolls back.
  insert into public.registrations (clinic_id, player_id, status, paid)
    values (CLINIC, MARIA, 'pool', false)
    returning id into v_reg;

  insert into public.clinic_messages (clinic_id, body, audience)
    values (CLINIC, 'Fixture message.', 'everyone')
    returning id into v_msg;

  select count(*) into n_clinics from public.clinics;

  -- ================================================================== ANON ====
  -- No JWT at all. This is the publishable key that ships inside the iOS binary.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);

  -- ATTACK 2: cancel a clinic.
  begin
    update public.clinics_public set status = 'canceled' where id = CLINIC;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select status::text into v_txt from public.clinics where id = CLINIC;
  insert into _probe_result values ('anon_cannot_cancel_clinic_via_view', 'published', coalesce(v_txt, 'ROW GONE'));
  perform set_config('role', 'anon', true);

  -- ATTACK 3: rewrite the price. Revenue is snapshotted onto the registration
  -- (decision 0002), but the published rate is what the next player is charged.
  begin
    update public.clinics_public set member_price_cents = 0 where id = CLINIC;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select member_price_cents into v_int from public.clinics where id = CLINIC;
  insert into _probe_result values ('anon_cannot_rewrite_price_via_view', '1800', coalesce(v_int::text, 'ROW GONE'));
  perform set_config('role', 'anon', true);

  -- ATTACK 4: move the registration window, which decides who gets a seat.
  begin
    update public.clinics_public set member_opens_at = now() - interval '30 days' where id = CLINIC;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select (member_opens_at < now() - interval '20 days') into v_bool from public.clinics where id = CLINIC;
  insert into _probe_result values ('anon_cannot_move_window_via_view', 'false', coalesce(v_bool::text, 'ROW GONE'));
  perform set_config('role', 'anon', true);

  -- ATTACK 5: create a clinic. An INSERT through an auto-updatable view without
  -- WITH CHECK OPTION never evaluates the view's WHERE, so `where is_admin()`
  -- filters reads and constrains nothing on write.
  --
  -- The column list here is clinics_admin's, NOT clinics'. clinics_admin was
  -- created as `select *` before the 2026-08-10 pricing migration, and a
  -- `select *` view snapshots its column list at creation time rather than
  -- tracking later ADD COLUMNs. It therefore has no duration_minutes,
  -- member_price_cents or nonmember_price_cents. Naming those made the first
  -- draft of this attack fail with 42703 "column does not exist" and report a
  -- false PASS. Blocked-by-a-typo is not blocked-by-a-privilege.
  begin
    insert into public.clinics_admin
      (name, audience, starts_at, ends_at, member_opens_at, public_opens_at,
       internal_capacity, status)
    values ('ATTACKER CLINIC', 'coed', now(), now() + interval '1 hour', now(), now(),
            99, 'published');
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinics;
  insert into _probe_result values ('anon_cannot_insert_clinic_via_admin_view', n_clinics::text, n::text);
  delete from public.clinics where name = 'ATTACKER CLINIC';
  perform set_config('role', 'anon', true);

  -- ATTACK 6: register somebody. my_registrations' WHERE is owns_player(), which
  -- again does not apply to an INSERT.
  begin
    insert into public.my_registrations (clinic_id, player_id, status, paid)
      values (CLINIC, KEN, 'in', true);
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where player_id = KEN;
  insert into _probe_result values ('anon_cannot_insert_registration_via_view', '0', n::text);
  perform set_config('role', 'anon', true);

  -- ================================== AUTHENTICATED, NON-ADMIN (Maria) ========
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);

  insert into _probe_result values ('baseline_maria_not_admin', 'false', public.is_admin()::text);

  -- ATTACK 8: self-promote out of the Player Pool into a spot. This is hard rule
  -- 2 (nothing is ever auto-promoted) and it also skips register_for_clinic's
  -- FOR UPDATE capacity serialisation and the price snapshot entirely.
  begin
    update public.my_registrations set status = 'in' where id = v_reg;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select status::text into v_txt from public.registrations where id = v_reg;
  insert into _probe_result values ('maria_cannot_self_promote_via_view', 'pool', coalesce(v_txt, 'ROW GONE'));
  perform set_config('role', 'authenticated', true);

  -- ATTACK 9: mark herself paid.
  begin
    update public.my_registrations set paid = true where id = v_reg;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select paid into v_bool from public.registrations where id = v_reg;
  insert into _probe_result values ('maria_cannot_mark_self_paid_via_view', 'false', coalesce(v_bool::text, 'ROW GONE'));
  perform set_config('role', 'authenticated', true);

  -- ATTACK 10: hard-delete her own registration. Hard rule 4 is archive, never
  -- delete: Tara must keep seeing the cancellation and its timestamp.
  begin
    delete from public.my_registrations where id = v_reg;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where id = v_reg;
  insert into _probe_result values ('maria_cannot_hard_delete_own_registration', '1', n::text);
  perform set_config('role', 'authenticated', true);

  -- ATTACK 11: register a different player.
  begin
    insert into public.my_registrations (clinic_id, player_id, status, paid)
      values (CLINIC, KEN, 'in', true);
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.registrations where player_id = KEN;
  insert into _probe_result values ('maria_cannot_register_another_player', '0', n::text);
  perform set_config('role', 'authenticated', true);

  -- ATTACK 12: cancel a clinic she merely attends.
  begin
    update public.clinics_public set status = 'canceled' where id = CLINIC;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select status::text into v_txt from public.clinics where id = CLINIC;
  insert into _probe_result values ('maria_cannot_cancel_clinic_via_view', 'published', coalesce(v_txt, 'ROW GONE'));
  perform set_config('role', 'authenticated', true);

  -- ================================================================ SANITY ====
  -- The hole must not be closed by breaking the product. Same discipline as
  -- privilege_escalation.sql's legitimate_contact_edit_still_works.

  select count(*) into n from public.clinics_public;
  insert into _probe_result values ('sanity_maria_can_still_read_clinics', 'true', (n > 0)::text);

  select count(*) into n from public.my_registrations where id = v_reg;
  insert into _probe_result values ('sanity_maria_can_still_read_own_registration', '1', n::text);

  select count(*) into n from public.my_clinic_messages where id = v_msg;
  insert into _probe_result values ('sanity_maria_can_still_read_clinic_message', '1', n::text);

  -- Tara's admin reads rely on the views executing with owner rights, because
  -- `authenticated` has no SELECT on the locked base tables. This is why the fix
  -- is a grant change and NOT security_invoker: turning that on would break
  -- exactly these two rows.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA_ACC)::text, true);
  insert into _probe_result values ('baseline_tara_is_admin', 'true', public.is_admin()::text);

  select count(*) into n from public.clinics_admin;
  insert into _probe_result values ('sanity_tara_can_still_read_clinics_admin', 'true', (n > 0)::text);

  select count(*) into n from public.registrations_admin where id = v_reg;
  insert into _probe_result values ('sanity_tara_can_still_read_registrations_admin', '1', n::text);

  -- =========================================== DESTRUCTIVE ATTACKS, LAST ======
  -- These two CASCADE. They run after every row-level attack and after the
  -- sanity reads, because on an unfixed schema they succeed and would otherwise
  -- delete the fixtures out from under every assertion above. See the ORDER
  -- MATTERS note in the header.
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'anon', true);

  -- ATTACK 13: delete the clinic message history.
  begin
    delete from public.my_clinic_messages;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinic_messages where id = v_msg;
  insert into _probe_result values ('anon_cannot_delete_messages_via_view', '1', n::text);
  perform set_config('role', 'anon', true);

  -- ATTACK 14: wipe the entire schedule. clinics_public's WHERE is `status in
  -- ('published','canceled')`, which is not user-scoped, so every published
  -- clinic is in range. registrations and clinic_messages both FK to clinics
  -- ON DELETE CASCADE, so this takes every roster and all message history with
  -- it. This is the worst single statement available to an unauthenticated
  -- caller holding the key that ships inside the iOS binary.
  begin
    delete from public.clinics_public;
  exception when others then null;
  end;
  perform set_config('role', 'postgres', true);
  select count(*) into n from public.clinics;
  insert into _probe_result values ('anon_cannot_delete_clinics_via_view', n_clinics::text, n::text);
  select count(*) into n from public.registrations where id = v_reg;
  insert into _probe_result values ('anon_delete_did_not_cascade_registrations', '1', n::text);
end $$;

-- Belt and braces: assert the grants themselves, so a future migration that
-- re-creates a view (and silently re-inherits the default ALL) fails here even
-- if the behavioural attacks above are somehow satisfied.
insert into _probe_result
select 'no_write_grant__' || table_name || '__' || grantee, 'none',
       string_agg(distinct privilege_type, ',' order by privilege_type)
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated')
  and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
  and table_name in ('clinics_public', 'clinics_admin', 'my_registrations',
                     'registrations_admin', 'my_clinic_messages', 'my_news',
                     'revenue_by_clinic', 'revenue_by_segment')
group by table_name, grantee;

-- The aggregate above emits a row only when a write grant EXISTS, so a clean
-- schema produces none of them. Emit one positive assertion so this section can
-- never be the "zero checks ran" case the harness now treats as red.
insert into _probe_result
select 'no_write_grants_on_any_player_view', '0', count(*)::text
from information_schema.role_table_grants
where table_schema = 'public'
  and grantee in ('anon', 'authenticated')
  and privilege_type in ('INSERT', 'UPDATE', 'DELETE', 'TRUNCATE')
  and table_name in ('clinics_public', 'clinics_admin', 'my_registrations',
                     'registrations_admin', 'my_clinic_messages', 'my_news',
                     'revenue_by_clinic', 'revenue_by_segment');

-- ------------------------------------------------- view column completeness --
--
-- A `select *` view snapshots its column list at creation, so a later
-- `alter table ... add column` leaves the view silently behind. That is how
-- `clinics_admin` lost the pricing columns for five weeks: players saw both
-- published rates and the person who SETS the rates could not.
--
-- It is also how an attack in this very probe reported a false pass, by naming
-- a column the view did not have and failing with 42703 instead of a privilege
-- error. Blocked-by-a-typo is not blocked-by-a-privilege.
--
-- This asserts the shape rather than any one bug: every pricing column on
-- `clinics` must be visible on the admin view. Adding a column to `clinics`
-- without deciding about `clinics_admin` now goes red here.
do $$
declare
  missing text;
begin
  select string_agg(c.column_name, ', ' order by c.column_name)
    into missing
  from information_schema.columns c
  where c.table_schema = 'public' and c.table_name = 'clinics'
    and c.column_name like '%price%'
    and not exists (
      select 1 from information_schema.columns v
      where v.table_schema = 'public' and v.table_name = 'clinics_admin'
        and v.column_name = c.column_name
    );

  insert into _probe_result
  values ('clinics_admin_has_every_price_column', 'none missing', coalesce(missing, 'none missing'));

  -- duration_minutes drives the "60 min · $18" line and went missing the same way.
  insert into _probe_result
  select 'clinics_admin_has_duration_minutes', '1', count(*)::text
  from information_schema.columns
  where table_schema = 'public' and table_name = 'clinics_admin'
    and column_name = 'duration_minutes';
end $$;

select
  check_name,
  expected,
  actual,
  case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result
order by check_name;

rollback;
