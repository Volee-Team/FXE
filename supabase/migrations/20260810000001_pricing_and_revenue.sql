-- Pricing: member vs non-member, by clinic length. Plus the revenue report
-- Tara reconciles her Zelle payments against.
--
-- Tara, 2026-08-02 (evening call), prices "locked in, only time they will
-- change is w inflation":
--
--                 60 min    90 min
--   Member         $18       $22
--   Non-member     $23       $28
--
-- WHY THE PRICE IS COPIED ONTO THE REGISTRATION
--
-- The obvious design is to read the price off the clinic whenever you need it.
-- That is wrong here, and it is the kind of wrong that is invisible for months.
--
-- Tara's whole reason for wanting this is reconciliation: at the end of a
-- period she needs to know what *should* have been Zelled to her, so she can
-- settle up with the club. If the registration only points at the clinic, then
-- editing a clinic's price in September silently rewrites what August says it
-- earned. Her books would disagree with the club's and neither of them would
-- know why.
--
-- So `register_for_clinic` and `place_player` copy three facts onto the
-- registration at the moment it is created: the price charged, whether the
-- player was a member *then*, and how long the clinic was *then*. Those are
-- historical facts. Nothing that happens later may change them. A player who
-- joins the club in October still owes the non-member rate for September.
--
-- Same reasoning for `was_member`: `players.is_member` is self-reported and
-- Tara corrects it when she notices. A correction must not retroactively
-- change what somebody owed.

-- ── clinic length and the two prices ────────────────────────────────────────

alter table public.clinics
  add column if not exists duration_minutes      integer,
  add column if not exists member_price_cents    integer,
  add column if not exists nonmember_price_cents integer;

alter table public.clinic_templates
  add column if not exists member_price_cents    integer,
  add column if not exists nonmember_price_cents integer;

-- Backfill from the single price that used to exist, then make them required.
-- (No production data yet; this keeps local and any existing rows coherent.)
update public.clinics set
  duration_minutes      = coalesce(duration_minutes,
                            greatest(30, (extract(epoch from (ends_at - starts_at)) / 60)::int)),
  member_price_cents    = coalesce(member_price_cents, price_cents),
  nonmember_price_cents = coalesce(nonmember_price_cents, price_cents);

update public.clinic_templates set
  member_price_cents    = coalesce(member_price_cents, price_cents),
  nonmember_price_cents = coalesce(nonmember_price_cents, price_cents);

alter table public.clinics
  alter column duration_minutes      set not null,
  alter column member_price_cents    set not null,
  alter column nonmember_price_cents set not null;

alter table public.clinic_templates
  alter column member_price_cents    set not null,
  alter column nonmember_price_cents set not null;

alter table public.clinics
  add constraint clinic_duration_positive check (duration_minutes > 0),
  add constraint clinic_member_price_nonneg check (member_price_cents >= 0),
  add constraint clinic_nonmember_price_nonneg check (nonmember_price_cents >= 0);

comment on column public.clinics.duration_minutes is
  'Clinic length in minutes. Tara runs 60 and 90 as of 2026-08-02, but this is '
  'a number rather than an enum so a 120-minute Saturday session does not need '
  'a migration.';
comment on column public.clinics.member_price_cents is
  'What a member pays. Snapshotted onto the registration at register time; '
  'editing this never changes what past registrations owed.';

-- price_cents is superseded. Left in place rather than dropped so nothing that
-- still reads it breaks silently mid-change; remove once the Swift client and
-- web admin both use the two-price columns.
comment on column public.clinics.price_cents is
  'DEPRECATED 2026-08-10, superseded by member_price_cents / nonmember_price_cents. '
  'Do not read this in new code. Scheduled for removal once no caller remains.';

-- ── the locked price table ──────────────────────────────────────────────────

create or replace function public.default_price_cents(
  p_duration_minutes integer, p_is_member boolean)
returns integer
language sql
immutable
as $$
  select case
    when p_is_member and p_duration_minutes <= 60 then 1800  -- $18
    when p_is_member                              then 2200  -- $22
    when p_duration_minutes <= 60                 then 2300  -- $23
    else                                               2800  -- $28
  end;
$$;

comment on function public.default_price_cents(integer, boolean) is
  'Tara''s locked price table (2026-08-02). Supplies the DEFAULT when a clinic '
  'is created; it does not own the value. Tara can override either price on any '
  'clinic, and past registrations keep whatever they were charged.';

-- ── snapshot columns on the registration ────────────────────────────────────

alter table public.registrations
  add column if not exists price_cents_charged integer,
  add column if not exists was_member          boolean,
  add column if not exists duration_minutes    integer;

comment on column public.registrations.price_cents_charged is
  'HISTORICAL FACT. What this player owed for this clinic, fixed at the moment '
  'they registered. Never recompute it from the clinic: Tara reconciles real '
  'money against these numbers and a later price edit must not move them.';
comment on column public.registrations.was_member is
  'HISTORICAL FACT. Membership at register time. is_member is self-reported and '
  'Tara corrects it later; a correction must not change what someone already owed.';

-- ── revenue report ──────────────────────────────────────────────────────────

-- Admin-only. Answers the question Tara currently answers from a notebook:
-- how many member and non-member players did 60- and 90-minute clinics, what
-- should have been Zelled, and how much of it has she actually ticked off.
-- NOT security_invoker. These views read `clinics` and `registrations`, which
-- the client role has no grant on by design. The view runs with owner rights
-- and `where public.is_admin()` is the gate: is_admin() is SECURITY DEFINER and
-- reads the CALLER's jwt, so a player still sees zero rows. Same pattern as
-- clinics_admin.
create or replace view public.revenue_by_clinic as
  select
    c.id                as clinic_id,
    c.name,
    c.starts_at,
    c.duration_minutes,
    count(*) filter (where r.was_member)                        as member_players,
    count(*) filter (where not r.was_member)                    as nonmember_players,
    count(*)                                                    as total_players,
    coalesce(sum(r.price_cents_charged), 0)                     as expected_cents,
    coalesce(sum(r.price_cents_charged) filter (where r.paid), 0) as collected_cents,
    coalesce(sum(r.price_cents_charged) filter (where not r.paid), 0) as outstanding_cents
  from public.clinics c
  join public.registrations r
    on r.clinic_id = c.id
   and r.status = 'in'          -- only people who actually had a spot owe money
  where public.is_admin()
  group by c.id, c.name, c.starts_at, c.duration_minutes;

comment on view public.revenue_by_clinic is
  'Per-clinic reconciliation. Only status = ''in'' counts: a Player Pool entry '
  'or a cancellation owes nothing.';

-- The breakdown she asked for out loud: counts by membership and length, so she
-- can tell the club how much of the court time was member vs guest.
create or replace view public.revenue_by_segment as
  select
    date_trunc('month', c.starts_at) as month,
    r.duration_minutes,
    r.was_member,
    count(*)                                as players,
    sum(r.price_cents_charged)              as expected_cents,
    sum(r.price_cents_charged) filter (where r.paid)     as collected_cents,
    sum(r.price_cents_charged) filter (where not r.paid) as outstanding_cents
  from public.registrations r
  join public.clinics c on c.id = r.clinic_id
  where r.status = 'in'
    and public.is_admin()
  group by 1, 2, 3;

comment on view public.revenue_by_segment is
  'Tara''s notebook, replaced. Month x clinic length x member/non-member, with '
  'what was owed and what has been ticked off as paid.';

revoke all on public.revenue_by_clinic   from anon, authenticated;
revoke all on public.revenue_by_segment  from anon, authenticated;
grant select on public.revenue_by_clinic  to authenticated;  -- gated by is_admin() inside
grant select on public.revenue_by_segment to authenticated;

-- ── RPCs now write the snapshot ─────────────────────────────────────────────

-- Identical to the previous version except for the three snapshot columns on
-- the INSERT. The window logic, the FOR UPDATE serialisation, and the
-- unique_violation handling are unchanged.
create or replace function public.register_for_clinic(p_clinic uuid, p_player uuid)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c        public.clinics;
  v_member boolean;
  v_taken  integer;
  v_status registration_status;
  v_row    public.registrations;
begin
  if not (public.owns_player(p_player) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  select * into c from public.clinics
   where id = p_clinic and status = 'published'
   for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;

  if c.closes_at is not null and now() >= c.closes_at then
    raise exception 'registration_closed' using errcode = 'P0001';
  end if;

  select is_member into v_member from public.players where id = p_player;
  if v_member is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  if now() < c.member_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif not v_member and now() < c.public_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif v_member and now() < c.public_opens_at then
    select count(*) into v_taken
      from public.registrations
     where clinic_id = p_clinic and status = 'in';
    v_status := case when v_taken < c.internal_capacity then 'in' else 'pool' end;
  else
    v_status := 'pool';
  end if;

  insert into public.registrations (
      clinic_id, player_id, status, source,
      price_cents_charged, was_member, duration_minutes)
  values (p_clinic, p_player, v_status,
          case when public.owns_player(p_player) then 'self'::registration_source
                                                 else 'admin'::registration_source end,
          -- The snapshot. See the header of this migration for why.
          case when v_member then c.member_price_cents else c.nonmember_price_cents end,
          v_member,
          c.duration_minutes)
  returning * into v_row;

  return v_row;
exception
  when unique_violation then
    raise exception 'already_registered' using errcode = 'P0001';
end;
$$;

-- Tara adding somebody herself. Same snapshot, so a player she adds by hand
-- counts toward the revenue total exactly like one who registered themselves.
-- She asked for this explicitly: "it will count as normal and counted to the
-- payment total".
create or replace function public.place_player(
  p_clinic uuid, p_player uuid, p_status registration_status default 'in')
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c        public.clinics;
  v_member boolean;
  v        public.registrations;
begin
  perform public.require_admin();

  if p_status not in ('in', 'pool', 'response_needed') then
    raise exception 'invalid_status' using errcode = 'P0001';
  end if;

  select * into c from public.clinics where id = p_clinic;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;

  select is_member into v_member from public.players where id = p_player;
  if v_member is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  -- Deliberately ignores the registration window and the capacity: Tara's
  -- judgement overrides both. She said so about invitations ("no, we show you
  -- the numbers, you make the call") and the same applies here.
  insert into public.registrations (
      clinic_id, player_id, status, source,
      price_cents_charged, was_member, duration_minutes)
  values (p_clinic, p_player, p_status, 'admin',
          case when v_member then c.member_price_cents else c.nonmember_price_cents end,
          v_member,
          c.duration_minutes)
  on conflict (clinic_id, player_id) where status in ('in','pool','response_needed')
  do update set status = excluded.status
  returning * into v;

  return v;
end;
$$;

-- ── defaults: Tara picks a length, the prices fill themselves in ────────────

-- A DEFAULT cannot reference another column, so this is a trigger. It gives
-- the product behaviour Tara asked for ("lock that in"): she chooses 60 or 90
-- when creating a clinic and never types a price, but either price can still
-- be overridden on any individual clinic.
create or replace function public.apply_default_clinic_pricing()
returns trigger
language plpgsql
as $$
begin
  if new.duration_minutes is null then
    new.duration_minutes := greatest(
      1, (extract(epoch from (new.ends_at - new.starts_at)) / 60)::int);
  end if;

  if new.member_price_cents is null then
    new.member_price_cents := public.default_price_cents(new.duration_minutes, true);
  end if;

  if new.nonmember_price_cents is null then
    new.nonmember_price_cents := public.default_price_cents(new.duration_minutes, false);
  end if;

  return new;
end;
$$;

drop trigger if exists apply_default_clinic_pricing on public.clinics;
create trigger apply_default_clinic_pricing
  before insert on public.clinics
  for each row execute function public.apply_default_clinic_pricing();
