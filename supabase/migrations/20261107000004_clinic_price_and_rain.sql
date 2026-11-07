-- 20261107000004_clinic_price_and_rain.sql — decision 0053.
--
-- Tara, by text, 2026-11-07, answering question 143 ("Next update" item 3):
--   "Nobody will be charged ahead of time, so if it were to rain halfway
--    through the clinic, I would just be able to manually change the clinic
--    rate. It might just be easiest if I have the option to change the clinic
--    rate always, even though I hardly will ever do that unless it rains"
--   "But yes, if I could have the option to charge half, then that means
--    everybody would be charged half if it were to rain"
-- John: "build this".
--
-- What a person is charged is their registration's price_cents_charged
-- (money_rows, admin_charge_registration, the revenue and board reports all
-- read it), snapshotted at sign-up. So both of her asks reprice the clinic's
-- registrations that nobody has paid or been charged for:
--
--   admin_set_clinic_prices(clinic, member, non-member): her rate, any time.
--     The clinic's two prices change, and so does every such registration on
--     it (You're In!, Waitlist, Response Needed, and a late cancel's fee).
--   admin_set_rain_half(clinic, on): "everybody would be charged half". The
--     clinic's prices stay what they are; everyone You're In! who came owes
--     half (rounded to the cent), and turning it off puts the full price back.
--     A no-show and a late cancel still owe the full fee: her answer to
--     question 103 (2026-10-04, decision 0053). A rate change while it is on
--     keeps it half. While it is on, a trigger keeps each row right as it
--     changes: marked a no-show (full), unmarked (half), or added after (half).
--
-- Never a registration marked Paid or holding a live fee (a charge pending,
-- processing or taken; registration_has_live_fee): money already taken is
-- a refund, not a reprice. Nobody is told; she did not ask for a message.

alter table public.clinics add column rain_half boolean not null default false;
comment on column public.clinics.rain_half is
  'Decision 0053: rained out, everybody pays half. Set only by admin_set_rain_half.';

-- What one registration owes on its clinic now: the clinic's price for its
-- member status, halved while rain_half is on for someone You're In! who came
-- (a no-show and a late cancel pay in full, question 103). Internal.
create or replace function public.clinic_price_for(
  p_clinic public.clinics, p_was_member boolean, p_status public.registration_status, p_no_show boolean)
returns integer
language sql
immutable
set search_path = public, pg_temp
as $$
  select round(
           (case when p_was_member then p_clinic.member_price_cents else p_clinic.nonmember_price_cents end)
           * (case when p_clinic.rain_half and p_status = 'in' and not coalesce(p_no_show, false)
                   then 0.5 else 1 end))::integer;
$$;
revoke all on function public.clinic_price_for(public.clinics, boolean, public.registration_status, boolean)
  from public, anon, authenticated;

-- Every registration on the clinic not marked Paid and holding no charge, to
-- what it owes now. Internal.
create or replace function public.reprice_clinic(p_clinic uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.clinics;
  n integer;
begin
  select * into c from public.clinics where id = p_clinic;
  -- Every row of the clinic, not only those about to change: a no-show
  -- unmarked while rain is turned on would otherwise read the old flag and
  -- keep the old price (the sql-auditor, 2026-11-07). Clinic then rows, the
  -- order admin_charge_clinic takes, so no deadlock.
  perform 1 from public.registrations where clinic_id = p_clinic order by id for update;
  update public.registrations r
     set price_cents_charged = public.clinic_price_for(c, r.was_member, r.status, r.no_show)
   where r.clinic_id = p_clinic
     and not r.paid
     and not public.registration_has_live_fee(r.id)
     and r.price_cents_charged is distinct from public.clinic_price_for(c, r.was_member, r.status, r.no_show);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.reprice_clinic(uuid) from public, anon, authenticated;

-- While a clinic is rained out, each row is kept right as it changes. Does
-- nothing on any other clinic, so a sign-up's snapshot is untouched there.
create or replace function public.keep_rain_price()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.clinics;
begin
  select * into c from public.clinics where id = new.clinic_id;
  if c.rain_half and not new.paid
     and (tg_op = 'INSERT' or not public.registration_has_live_fee(new.id)) then
    new.price_cents_charged := public.clinic_price_for(c, new.was_member, new.status, new.no_show);
  end if;
  return new;
end;
$$;
revoke all on function public.keep_rain_price() from public, anon, authenticated;
create trigger keep_rain_price
  before insert or update of status, no_show, late_cancel, paid on public.registrations
  for each row execute function public.keep_rain_price();

create or replace function public.admin_set_clinic_prices(
  p_clinic uuid, p_member_cents integer, p_nonmember_cents integer)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  -- Above zero (a charge of nothing is refused by admin_charge_registration)
  -- and at most $1,000, which no clinic is.
  if p_member_cents is null or p_nonmember_cents is null
     or p_member_cents not between 1 and 100000 or p_nonmember_cents not between 1 and 100000 then
    raise exception 'invalid_price' using errcode = 'P0001';
  end if;
  -- The clinic's lock, as a registration takes it, so a sign-up lands either
  -- before (and is repriced) or after (and snapshots the new price).
  perform 1 from public.clinics where id = p_clinic for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  update public.clinics
     set member_price_cents = p_member_cents, nonmember_price_cents = p_nonmember_cents
   where id = p_clinic;
  return public.reprice_clinic(p_clinic);
end;
$$;

create or replace function public.admin_set_rain_half(p_clinic uuid, p_on boolean)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  if p_on is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  perform 1 from public.clinics where id = p_clinic for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  update public.clinics set rain_half = p_on where id = p_clinic;
  return public.reprice_clinic(p_clinic);
end;
$$;

-- A clinic's length resets its prices to her table (admin_upsert_clinic,
-- question 113 open) without repricing anyone; while it is rained out that
-- would leave one clinic holding two rates. Refused until rain is off.
create or replace function public.guard_rain_length()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if old.rain_half and new.duration_minutes is distinct from old.duration_minutes then
    raise exception 'rain_half_on' using errcode = 'P0001';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_rain_length() from public, anon, authenticated;
create trigger guard_rain_length
  before update of duration_minutes on public.clinics
  for each row execute function public.guard_rain_length();

-- Tara reads the flag with the clinic. Same columns as 20261106000002, one
-- appended.
create or replace view public.clinics_admin as
  select id, template_id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         internal_capacity, status, canceled_at, created_at,
         member_price_cents, nonmember_price_cents, duration_minutes,
         (case when public.level_check_enabled() then min_rating end)::numeric(2,1) as min_rating,
         rain_half
    from public.clinics
   where public.is_admin();
revoke all on public.clinics_admin from public, anon, authenticated;
grant select on public.clinics_admin to authenticated;

revoke all on function public.admin_set_clinic_prices(uuid, integer, integer) from public, anon;
grant execute on function public.admin_set_clinic_prices(uuid, integer, integer) to authenticated;
revoke all on function public.admin_set_rain_half(uuid, boolean) from public, anon;
grant execute on function public.admin_set_rain_half(uuid, boolean) to authenticated;
