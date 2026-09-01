-- Registration closes 3 hours before a clinic starts.
--
-- Tara, 2026-08-27, answering open question 5:
--
--   "registration closes - gah, idk. This might be something we adjust. But
--    lets say 3 hours prior and if they try to register within 3 hours, they
--    have the option to send me a direct message to get into the clinic,
--    assuming there is space and it isn't full. I hate to say it but as much as
--    we want this to be done in one shot, there will be some things that will
--    need to be adjusted after trial and even during trial."
--
-- Two things in that answer. This migration does the first.
--
-- WHAT CHANGES
-- ------------
-- `closes_at` defaulted to the clinic's START, which was a placeholder chosen
-- because nothing had ever populated it at all: before 20260826000001 the
-- column was null on every row, so registration never closed and a clinic that
-- finished nine days ago was still bookable. Start-time was the smallest honest
-- default until she picked a real one. She has.
--
-- Deliberately a `-3 hours` on the DEFAULT only, not a constraint. She may set
-- any `closes_at` she likes per clinic through admin_upsert_clinic, and this is
-- what she gets when she does not think about it. Her own framing is that this
-- number will move, so it is a default, not a rule.
--
-- Existing rows are updated too. Every clinic currently in the database got
-- `closes_at = starts_at` from the placeholder, which is a value nobody chose;
-- leaving it would mean her first real week silently used the old behaviour.
-- Only future clinics are touched: a past clinic's window is a record of what
-- happened and hard rule 4 says do not rewrite history.
--
-- WHAT THIS DOES NOT DO
-- ---------------------
-- The second half of her answer is a FEATURE, not a default: inside the 3-hour
-- window a player should be able to message her to ask in, when the clinic is
-- not full. That needs a UI path and a notification to her, and it is tracked in
-- docs/backlog.md rather than smuggled in here. Closing registration without
-- that path is strictly better than today (where it never closed), and strictly
-- worse than the whole answer, which is why it is written down.

create or replace function public.default_closes_at(p_starts_at timestamptz)
returns timestamptz
language sql
immutable
set search_path = public, pg_temp
as $$ select p_starts_at - interval '3 hours' $$;

comment on function public.default_closes_at(timestamptz) is
  'When registration closes if Tara does not set it: 3 hours before the clinic '
  'starts (her answer, 2026-08-27). She expects to adjust this after trial, so '
  'it lives in one function rather than being spread across call sites.';

-- Rebuild admin_upsert_clinic with the new default. Only the two closes_at
-- expressions change; everything else is carried over unchanged so the diff
-- shows what actually moved.
create or replace function public.admin_upsert_clinic(
  p_id                uuid          default null,
  p_name              text          default null,
  p_audience          text          default null,
  p_starts_at         timestamptz   default null,
  p_duration_minutes  int           default null,
  p_internal_capacity int           default null,
  p_category          text          default null,
  p_description       text          default null,
  p_member_opens_at   timestamptz   default null,
  p_public_opens_at   timestamptz   default null,
  p_closes_at         timestamptz   default null
) returns public.clinics
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v public.clinics;
  v_ends timestamptz;
begin
  perform public.require_admin();

  if p_id is null then
    if p_name is null or btrim(p_name) = '' then
      raise exception 'name_required' using errcode = '22023';
    end if;
    if p_audience is null or p_starts_at is null
       or p_duration_minutes is null or p_internal_capacity is null then
      raise exception 'missing_required_field' using errcode = '22023';
    end if;
    if p_duration_minutes <= 0 then
      raise exception 'duration_must_be_positive' using errcode = '22023';
    end if;
    if p_internal_capacity <= 0 then
      raise exception 'capacity_must_be_positive' using errcode = '22023';
    end if;

    v_ends := p_starts_at + make_interval(mins => p_duration_minutes);

    insert into public.clinics (
      name, audience, category, description,
      starts_at, ends_at, duration_minutes,
      member_opens_at, public_opens_at, closes_at,
      internal_capacity, status)
    values (
      btrim(p_name), p_audience::public.clinic_audience,
      nullif(btrim(coalesce(p_category, '')), ''),
      nullif(btrim(coalesce(p_description, '')), ''),
      p_starts_at, v_ends, p_duration_minutes,
      coalesce(p_member_opens_at, public.member_opens_at(p_starts_at)),
      coalesce(p_public_opens_at, public.public_opens_at(p_starts_at)),
      coalesce(p_closes_at, public.default_closes_at(p_starts_at)),
      p_internal_capacity, 'draft')
    returning * into v;

    return v;
  end if;

  select * into v from public.clinics where id = p_id;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;

  if p_duration_minutes is not null and p_duration_minutes <= 0 then
    raise exception 'duration_must_be_positive' using errcode = '22023';
  end if;
  if p_internal_capacity is not null and p_internal_capacity <= 0 then
    raise exception 'capacity_must_be_positive' using errcode = '22023';
  end if;

  update public.clinics set
    name              = coalesce(nullif(btrim(coalesce(p_name, '')), ''), name),
    audience          = coalesce(p_audience::public.clinic_audience, audience),
    category          = case when p_category is null then category
                             else nullif(btrim(p_category), '') end,
    description       = case when p_description is null then description
                             else nullif(btrim(p_description), '') end,
    starts_at         = coalesce(p_starts_at, starts_at),
    duration_minutes  = coalesce(p_duration_minutes, duration_minutes),
    ends_at           = coalesce(p_starts_at, starts_at)
                        + make_interval(mins => coalesce(p_duration_minutes, duration_minutes)),
    member_opens_at   = coalesce(p_member_opens_at,
                                 case when p_starts_at is null then member_opens_at
                                      else public.member_opens_at(p_starts_at) end),
    public_opens_at   = coalesce(p_public_opens_at,
                                 case when p_starts_at is null then public_opens_at
                                      else public.public_opens_at(p_starts_at) end),
    -- Rescheduling moves the close with the clinic, same as the open windows.
    closes_at         = coalesce(p_closes_at,
                                 case when p_starts_at is null then closes_at
                                      else public.default_closes_at(p_starts_at) end),
    internal_capacity = coalesce(p_internal_capacity, internal_capacity)
  where id = p_id
  returning * into v;

  return v;
end;
$$;

revoke all on function public.admin_upsert_clinic(uuid, text, text, timestamptz, int, int, text, text, timestamptz, timestamptz, timestamptz) from public, anon, authenticated;
grant execute on function public.admin_upsert_clinic(uuid, text, text, timestamptz, int, int, text, text, timestamptz, timestamptz, timestamptz) to authenticated;

-- Future clinics only. A finished clinic's window is a record of what happened.
update public.clinics
   set closes_at = public.default_closes_at(starts_at)
 where starts_at > now()
   and (closes_at is null or closes_at = starts_at);

-- ------------------------------------------------------------- the trigger --
--
-- The UPDATE above is not enough, and finding out why is the useful part.
--
-- `supabase db reset` applies migrations and THEN seeds, so that UPDATE ran
-- against an empty table and every seeded clinic still came out with
-- closes_at = null. Worse, it would have been null for any future insert that
-- did not go through admin_upsert_clinic: the seed, a manual fix, an import.
--
-- Putting the default in one RPC makes it a property of that CODE PATH. Putting
-- it in a trigger makes it a property of the TABLE, which is what it actually
-- is. `clinics` already does exactly this for prices and duration via
-- apply_default_clinic_pricing; a clinic with no close time is the same class
-- of half-built row.
--
-- BEFORE INSERT only. Updates are handled by admin_upsert_clinic, which moves
-- the close when a clinic is rescheduled; a trigger firing on UPDATE would
-- silently overwrite a close time Tara had deliberately set by hand.

create or replace function public.apply_default_clinic_close()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.closes_at is null then
    new.closes_at := public.default_closes_at(new.starts_at);
  end if;
  return new;
end;
$$;

drop trigger if exists apply_default_clinic_close on public.clinics;
create trigger apply_default_clinic_close
  before insert on public.clinics
  for each row execute function public.apply_default_clinic_close();

-- Re-run for anything already in the table. Harmless on a fresh reset (the
-- trigger got there first), and it is what fixes an existing hosted database.
update public.clinics
   set closes_at = public.default_closes_at(starts_at)
 where starts_at > now()
   and (closes_at is null or closes_at = starts_at);
