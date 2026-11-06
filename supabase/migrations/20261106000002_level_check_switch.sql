-- 20261106000002_level_check_switch.sql — decision 0048, amended.
--
-- Tara, by text, 2026-11-06, as non-member registration opened at noon:
--   "A lot of people won't get in then right now" ... "Turn off now!"
--
-- The 1.0.1 app in the store has no Request Approval button and reads
-- level_approval_required as "Sorry, someone beat you to the punch", so about
-- 60 players rated below a clinic's level were being refused with the wrong
-- words and no way to ask from the app. Until 1.0.2 (which has the button) is
-- out, the level check is off.
--
-- A switch, not a removal: app_settings.level_check_enabled. While it is
-- 'false':
--   * guard_clinic_level lets every registration and late request through;
--   * clinics_public and clinics_admin show min_rating as null, so the
--     members' site and 1.0.2 offer Register, not the request, to everyone.
-- Approvals Tara has already given are kept and count again when it is back on.
-- Turning it back on is one migration: update app_settings set value = 'true'
-- where key = 'level_check_enabled'.

insert into public.app_settings (key, value)
values ('level_check_enabled', 'false')
on conflict (key) do update set value = excluded.value;

create or replace function public.level_check_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select value = 'true' from public.app_settings where key = 'level_check_enabled'), true);
$$;
comment on function public.level_check_enabled() is
  'Decision 0048: the level check on or off (app_settings.level_check_enabled). Off from 2026-11-06 until the 1.0.2 app is out.';

create or replace function public.guard_clinic_level()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_min numeric;
begin
  if auth.uid() is null or public.is_admin() or not public.level_check_enabled() then
    return new;
  end if;
  select min_rating into v_min from public.clinics where id = new.clinic_id;
  if not public.level_ok(new.player_id, v_min) then
    raise exception 'level_approval_required' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_clinic_level() from public, anon, authenticated;

-- Same column lists as 20261105000002; only min_rating changes.
create or replace view public.clinics_admin as
  select id, template_id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         internal_capacity, status, canceled_at, created_at,
         member_price_cents, nonmember_price_cents, duration_minutes,
         (case when public.level_check_enabled() then min_rating end)::numeric(2,1) as min_rating
    from public.clinics
   where public.is_admin();

create or replace view public.clinics_public as
  select id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         status, canceled_at, member_price_cents, nonmember_price_cents,
         duration_minutes,
         (case when public.level_check_enabled() then min_rating end)::numeric(2,1) as min_rating
    from public.clinics c
   where (c.status = 'published'
          or (c.status = 'canceled' and c.published_at is not null))
     and c.ends_at > now()
     and (
       c.audience not in ('ladies', 'men')
       or not exists (select 1 from public.players p where p.account_id = auth.uid())
       or exists (select 1 from public.players p
                   where p.account_id = auth.uid()
                     and public.audience_open_to(c.audience, p.gender))
       or exists (select 1 from public.registrations r
                    join public.players p on p.id = r.player_id
                   where r.clinic_id = c.id and p.account_id = auth.uid())
     );

revoke all on public.clinics_admin from public, anon, authenticated;
grant select on public.clinics_admin to authenticated;
revoke all on public.clinics_public from public, anon, authenticated;
grant select on public.clinics_public to authenticated;

revoke all on function public.level_check_enabled() from public, anon;
grant execute on function public.level_check_enabled() to authenticated;
