-- 20261116000001_court_reservations.sql — decision 0058.
--
-- John, 2026-11-16: "lets get court reservatiosn up asap." Tara asked on
-- 2026-11-05: "maybe we should also have the court reservation system within
-- the app as well." The club books courts on reservemycourt.com today. This is
-- step 1 of docs/courts/plan.md, the server. The members' site, Tara's laptop
-- and the app read it later.
--
-- THE RULE (every number below is a setting Tara changes later; questions 156
-- to 165 ask her for the real ones):
--   * Nobody but Tara books or reads a day until she switches it on
--     (courts_live, default false: question 164, the switch date).
--   * Members only (players.is_member on the account's adult row, which she
--     sets).
--   * Courts 1 to 5, open 7:00 AM to 9:00 PM New York every day.
--   * 60 or 90 minutes, starting on the hour or half hour.
--   * Up to 7 days ahead; a day opens at 7:00 AM New York, 7 days before.
--   * 1 booking a day and 2 upcoming per account.
--   * Free.
--   * A member cancels their own booking any time before it starts.
--   * A published, not canceled clinic holds courts from its start to its
--     end: the courts Tara assigned on its You're In! rows, or, until she
--     assigns any, one court per 4 spots counted down from court 5.
--   * Tara's blocks hold one court or every court. A block over bookings
--     lists them for her and cancels nobody.
--   * A member sees taken or free, never who or why. A clinic, a block and a
--     booking look the same, so neither a name (hidden fact 5) nor which
--     courts a particular clinic uses is shown beyond "taken".
--   * Tara books for anyone outside the member rules (hours, length, window,
--     limits, membership), but never over another booking, a block or a
--     clinic.
--   * Archive, never delete (hard rule 4): bookings are canceled and blocks
--     removed, with a time and who did it.
--
-- NO DOUBLE BOOKING: an exclusion constraint on (court, time range) while
-- booked is the guarantee. Every write here also takes one transaction-scoped
-- advisory lock, so the overlap with blocks and clinics (which a constraint
-- cannot see) and the per-account limits are decided one at a time. The
-- volume is a club's, so serializing is free. tests/sql/court_booking_race.sh
-- fires 50 members at one slot through the API, and one member at five courts
-- at once.
--
-- THE APPS ALREADY ON PHONES (1.0.3, 1.0.4) see nothing: new tables, new
-- functions and new app_settings keys only. No view or policy changes.
--
-- Pinned by tests/sql/court_reservations.sql (written red first).

create extension if not exists btree_gist with schema extensions;

-- ------------------------------------------------------------- settings
insert into public.app_settings (key, value) values
  ('courts_live',             'false'),
  ('court_members_only',      'true'),
  ('court_lengths',           '60,90'),
  ('court_start_step',        '30'),
  ('court_advance_days',      '7'),
  ('court_day_opens_at',      '07:00'),
  ('court_max_per_day',       '1'),
  ('court_max_upcoming',      '2'),
  ('court_players_per_court', '4')
on conflict (key) do nothing;

-- --------------------------------------------------------------- tables
create table public.courts (
  number    smallint primary key,
  name      text not null,
  is_active boolean not null default true,
  -- The same numbers as registrations.court_number (court_in_range).
  constraint court_number_in_range check (number between 1 and 5)
);
insert into public.courts (number, name)
select n, 'Court ' || n from generate_series(1, 5) n;

create table public.court_hours (
  weekday smallint primary key,   -- extract(dow): 0 is Sunday
  opens   time not null,
  closes  time not null,
  constraint court_hours_weekday check (weekday between 0 and 6),
  constraint court_hours_close_after_open check (closes > opens)
);
insert into public.court_hours (weekday, opens, closes)
select d, time '07:00', time '21:00' from generate_series(0, 6) d;

create table public.court_bookings (
  id            uuid primary key default gen_random_uuid(),
  court         smallint not null references public.courts (number),
  account_id    uuid not null references public.accounts (id),
  starts_at     timestamptz not null,
  ends_at       timestamptz not null,
  status        text not null default 'booked',
  playing_with  text,
  made_by_admin boolean not null default false,
  booked_at     timestamptz not null default now(),
  canceled_at   timestamptz,
  canceled_by   uuid references public.accounts (id),
  constraint court_booking_status check (status in ('booked', 'canceled')),
  constraint court_booking_ends_after_start check (ends_at > starts_at),
  constraint court_booking_canceled_when check ((status = 'canceled') = (canceled_at is not null)),
  constraint court_booking_playing_with_length check (playing_with is null or length(playing_with) <= 200),
  constraint court_bookings_no_overlap
    exclude using gist (court with =, tstzrange(starts_at, ends_at, '[)') with &&)
    where (status = 'booked')
);
create index court_bookings_account on public.court_bookings (account_id, starts_at)
  where status = 'booked';

create table public.court_blocks (
  id         uuid primary key default gen_random_uuid(),
  court      smallint references public.courts (number),   -- null: every court
  starts_at  timestamptz not null,
  ends_at    timestamptz not null,
  reason     text not null,
  created_by uuid references public.accounts (id),
  created_at timestamptz not null default now(),
  removed_at timestamptz,
  removed_by uuid references public.accounts (id),
  constraint court_block_ends_after_start check (ends_at > starts_at),
  constraint court_block_reason check (length(btrim(reason)) between 1 and 200)
);
create index court_blocks_live on public.court_blocks (starts_at) where removed_at is null;

-- Reached only through the functions below (hard rules 1 and 11): no client
-- grant at all, RLS on with no policy, and service_role's DML as on every
-- table (20260912000002).
alter table public.courts         enable row level security;
alter table public.court_hours    enable row level security;
alter table public.court_bookings enable row level security;
alter table public.court_blocks   enable row level security;
revoke all on public.courts, public.court_hours, public.court_bookings, public.court_blocks
  from public, anon, authenticated;
grant select, insert, update, delete
  on public.courts, public.court_hours, public.court_bookings, public.court_blocks
  to service_role;

-- ------------------------------------------------------ internal helpers
-- These run only inside the SECURITY DEFINER functions below, as the owner.
create or replace function public.court_setting(p_key text)
returns text
language sql stable
set search_path = public, pg_temp as $$
  select value from public.app_settings where key = p_key;
$$;
revoke all on function public.court_setting(text) from public, anon, authenticated;

-- Everything that holds a court between two moments: bookings, Tara's
-- blocks (a null court is every active court) and published clinics. kind,
-- ref_id, label and the rest are for Tara's day only; a member's day keeps
-- the times and whether the booking is theirs.
create or replace function public.court_taken_ranges(p_from timestamptz, p_to timestamptz)
returns table (
  court smallint, starts_at timestamptz, ends_at timestamptz,
  kind text, ref_id uuid, account_id uuid, label text,
  playing_with text, made_by_admin boolean
)
language sql stable
set search_path = public, pg_temp as $$
  select b.court, b.starts_at, b.ends_at, 'booking', b.id, b.account_id,
         a.first_name || ' ' || a.last_name, b.playing_with, b.made_by_admin
    from public.court_bookings b
    join public.accounts a on a.id = b.account_id
   where b.status = 'booked' and b.starts_at < p_to and b.ends_at > p_from
  union all
  select c.number, k.starts_at, k.ends_at, 'block', k.id, null, k.reason, null, null
    from public.court_blocks k
    join public.courts c on c.number = k.court or (k.court is null and c.is_active)
   where k.removed_at is null and k.starts_at < p_to and k.ends_at > p_from
  union all
  select h.court, cl.starts_at, cl.ends_at, 'clinic', cl.id, null, cl.name, null, null
    from public.clinics cl
    cross join lateral (
      select array_agg(distinct r.court_number) as assigned
        from public.registrations r
       where r.clinic_id = cl.id and r.status = 'in' and r.court_number is not null
    ) a
    cross join lateral (
      select unnest(a.assigned)::smallint as court
       where a.assigned is not null
      union all
      select (6 - g)::smallint
        from generate_series(1, least(5, ceil(cl.internal_capacity
               / greatest(1, coalesce(public.court_setting('court_players_per_court'), '4')::int)::numeric)::int)) g
       where a.assigned is null
    ) h
   where cl.status = 'published' and cl.canceled_at is null
     and cl.starts_at < p_to and cl.ends_at > p_from;
$$;
revoke all on function public.court_taken_ranges(timestamptz, timestamptz) from public, anon, authenticated;

-- The caller may use a member's side: signed in, not deleted, switched on,
-- and a member while court_members_only is on. Raises otherwise.
create or replace function public.court_require_member()
returns uuid
language plpgsql stable
set search_path = public, pg_temp as $$
declare v_uid uuid := auth.uid();
begin
  if v_uid is null or not exists (
       select 1 from public.accounts where id = v_uid and deleted_at is null) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  if coalesce(public.court_setting('courts_live'), 'false') <> 'true' then
    raise exception 'courts_not_live' using errcode = 'P0001';
  end if;
  if coalesce(public.court_setting('court_members_only'), 'true') = 'true'
     and not exists (
       select 1 from public.players
        where account_id = v_uid and kind = 'adult' and is_member and is_active) then
    raise exception 'members_only' using errcode = 'P0001';
  end if;
  return v_uid;
end; $$;
revoke all on function public.court_require_member() from public, anon, authenticated;

-- One key for every court write, so overlaps and limits are decided in turn.
create or replace function public.court_write_lock()
returns void
language sql volatile
set search_path = public, pg_temp as $$
  select pg_advisory_xact_lock(20261116000001);
$$;
revoke all on function public.court_write_lock() from public, anon, authenticated;

-- ------------------------------------------------------- a member's side
create or replace function public.court_day(p_day date)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp as $$
declare
  v_uid   uuid := public.court_require_member();
  v_today date := (now() at time zone 'America/New_York')::date;
  v_from  timestamptz;
  v_to    timestamptz;
  v_open  time;
  v_close time;
begin
  if p_day is null or p_day < v_today then
    raise exception 'in_the_past' using errcode = 'P0001';
  end if;
  if p_day > v_today + coalesce(public.court_setting('court_advance_days'), '7')::int then
    raise exception 'too_far_ahead' using errcode = 'P0001';
  end if;
  select opens, closes into v_open, v_close
    from public.court_hours where weekday = extract(dow from p_day);
  v_from := p_day::timestamp at time zone 'America/New_York';
  v_to   := (p_day + 1)::timestamp at time zone 'America/New_York';
  return jsonb_build_object(
    'day',       p_day,
    'opens_at',  (p_day + v_open)  at time zone 'America/New_York',
    'closes_at', (p_day + v_close) at time zone 'America/New_York',
    'courts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'number', c.number,
               'name',   c.name,
               'taken',  coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'starts_at',  t.starts_at,
                          'ends_at',    t.ends_at,
                          'mine',       (t.kind = 'booking' and t.account_id = v_uid),
                          'booking_id', case when t.kind = 'booking' and t.account_id = v_uid
                                             then t.ref_id end)
                        order by t.starts_at, t.ends_at)
                   from public.court_taken_ranges(v_from, v_to) t
                  where t.court = c.number), '[]'::jsonb))
             order by c.number)
        from public.courts c where c.is_active), '[]'::jsonb));
end; $$;
comment on function public.court_day(date) is
  'A member''s day of courts (decision 0058): hours, and per court the taken times; never who or why, only whether a booking is the caller''s.';

create or replace function public.book_court(
  p_court integer, p_starts_at timestamptz, p_minutes integer, p_playing_with text default null)
returns uuid
language plpgsql volatile security definer
set search_path = public, pg_temp as $$
declare
  v_uid   uuid := public.court_require_member();
  v_local timestamp := p_starts_at at time zone 'America/New_York';
  v_day   date := (p_starts_at at time zone 'America/New_York')::date;
  v_today date := (now() at time zone 'America/New_York')::date;
  v_ends  timestamptz;
  v_open  time;
  v_close time;
  v_adv   int := coalesce(public.court_setting('court_advance_days'), '7')::int;
  v_step  int := coalesce(public.court_setting('court_start_step'), '30')::int;
  v_id    uuid;
begin
  if p_court is null or not exists (
       select 1 from public.courts where number = p_court and is_active) then
    raise exception 'no_such_court' using errcode = 'P0001';
  end if;
  if p_minutes is null or not (p_minutes::text = any (
       string_to_array(coalesce(public.court_setting('court_lengths'), '60,90'), ','))) then
    raise exception 'bad_length' using errcode = 'P0001';
  end if;
  if p_starts_at is null or extract(second from v_local) <> 0
     or (extract(hour from v_local) * 60 + extract(minute from v_local))::int % v_step <> 0 then
    raise exception 'bad_start' using errcode = 'P0001';
  end if;
  v_ends := p_starts_at + make_interval(mins => p_minutes);
  if p_starts_at <= now() then
    raise exception 'in_the_past' using errcode = 'P0001';
  end if;
  select opens, closes into v_open, v_close
    from public.court_hours where weekday = extract(dow from v_day);
  if v_open is null or v_local < v_day + v_open
     or (v_ends at time zone 'America/New_York') > v_day + v_close then
    raise exception 'outside_hours' using errcode = 'P0001';
  end if;
  if v_day > v_today + v_adv then
    raise exception 'too_far_ahead' using errcode = 'P0001';
  end if;
  if now() < ((v_day - v_adv)
              + coalesce(public.court_setting('court_day_opens_at'), '07:00')::time)
             at time zone 'America/New_York' then
    raise exception 'not_open_yet' using errcode = 'P0001';
  end if;

  perform public.court_write_lock();

  if (select count(*) from public.court_bookings
       where account_id = v_uid and status = 'booked'
         and (starts_at at time zone 'America/New_York')::date = v_day)
     >= coalesce(public.court_setting('court_max_per_day'), '1')::int then
    raise exception 'day_limit' using errcode = 'P0001';
  end if;
  if (select count(*) from public.court_bookings
       where account_id = v_uid and status = 'booked' and ends_at > now())
     >= coalesce(public.court_setting('court_max_upcoming'), '2')::int then
    raise exception 'upcoming_limit' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.court_taken_ranges(p_starts_at, v_ends) t
              where t.court = p_court) then
    raise exception 'court_taken' using errcode = 'P0001';
  end if;

  begin
    insert into public.court_bookings (court, account_id, starts_at, ends_at, playing_with)
    values (p_court, v_uid, p_starts_at, v_ends,
            nullif(left(btrim(coalesce(p_playing_with, '')), 200), ''))
    returning id into v_id;
  exception when exclusion_violation then
    raise exception 'court_taken' using errcode = 'P0001';
  end;
  return v_id;
end; $$;
comment on function public.book_court(integer, timestamptz, integer, text) is
  'A member books a court (decision 0058). Refusals: not_authorized, courts_not_live, members_only, no_such_court, bad_length, bad_start, in_the_past, outside_hours, too_far_ahead, not_open_yet, day_limit, upcoming_limit, court_taken.';

create or replace function public.cancel_court_booking(p_booking uuid)
returns void
language plpgsql volatile security definer
set search_path = public, pg_temp as $$
begin
  update public.court_bookings
     set status = 'canceled', canceled_at = now(), canceled_by = auth.uid()
   where id = p_booking and account_id = auth.uid()
     and status = 'booked' and starts_at > now();
  if not found then
    raise exception 'not_cancelable' using errcode = 'P0001';
  end if;
end; $$;

create or replace function public.my_court_bookings()
returns table (
  id uuid, court integer, court_name text,
  starts_at timestamptz, ends_at timestamptz, playing_with text
)
language sql stable security definer
set search_path = public, pg_temp as $$
  select b.id, b.court::integer, c.name, b.starts_at, b.ends_at, b.playing_with
    from public.court_bookings b
    join public.courts c on c.number = b.court
   where b.account_id = auth.uid() and b.status = 'booked' and b.ends_at > now()
   order by b.starts_at;
$$;

-- ---------------------------------------------------------- Tara's side
create or replace function public.admin_court_day(p_day date)
returns jsonb
language plpgsql stable security definer
set search_path = public, pg_temp as $$
declare
  v_from  timestamptz;
  v_to    timestamptz;
  v_open  time;
  v_close time;
begin
  perform public.require_admin();
  if p_day is null then
    raise exception 'bad_day' using errcode = 'P0001';
  end if;
  select opens, closes into v_open, v_close
    from public.court_hours where weekday = extract(dow from p_day);
  v_from := p_day::timestamp at time zone 'America/New_York';
  v_to   := (p_day + 1)::timestamp at time zone 'America/New_York';
  return jsonb_build_object(
    'day',       p_day,
    'opens_at',  (p_day + v_open)  at time zone 'America/New_York',
    'closes_at', (p_day + v_close) at time zone 'America/New_York',
    'live',      coalesce(public.court_setting('courts_live'), 'false') = 'true',
    'courts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'number',    c.number,
               'name',      c.name,
               'is_active', c.is_active,
               'taken',     coalesce((
                 select jsonb_agg(jsonb_build_object(
                          'kind',          t.kind,
                          'id',            t.ref_id,
                          'starts_at',     t.starts_at,
                          'ends_at',       t.ends_at,
                          'account_id',    t.account_id,
                          'label',         t.label,
                          'playing_with',  t.playing_with,
                          'made_by_admin', t.made_by_admin)
                        order by t.starts_at, t.ends_at)
                   from public.court_taken_ranges(v_from, v_to) t
                  where t.court = c.number), '[]'::jsonb))
             order by c.number)
        from public.courts c), '[]'::jsonb));
end; $$;

create or replace function public.admin_block_courts(
  p_court integer, p_starts_at timestamptz, p_ends_at timestamptz, p_reason text)
returns jsonb
language plpgsql volatile security definer
set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  perform public.require_admin();
  if p_court is not null and not exists (select 1 from public.courts where number = p_court) then
    raise exception 'no_such_court' using errcode = 'P0001';
  end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at
     or length(btrim(coalesce(p_reason, ''))) not between 1 and 200 then
    raise exception 'bad_block' using errcode = 'P0001';
  end if;
  perform public.court_write_lock();
  insert into public.court_blocks (court, starts_at, ends_at, reason, created_by)
  values (p_court, p_starts_at, p_ends_at, btrim(p_reason), auth.uid())
  returning id into v_id;
  -- The bookings under it, for her to call or cancel. None is canceled here.
  return jsonb_build_object(
    'block_id',  v_id,
    'conflicts', coalesce((
      select jsonb_agg(jsonb_build_object(
               'booking_id', b.id, 'court', b.court,
               'starts_at', b.starts_at, 'ends_at', b.ends_at,
               'name', a.first_name || ' ' || a.last_name, 'phone', a.phone)
             order by b.starts_at, b.court)
        from public.court_bookings b
        join public.accounts a on a.id = b.account_id
       where b.status = 'booked' and (p_court is null or b.court = p_court)
         and b.starts_at < p_ends_at and b.ends_at > p_starts_at), '[]'::jsonb));
end; $$;

create or replace function public.admin_remove_court_block(p_block uuid)
returns void
language plpgsql volatile security definer
set search_path = public, pg_temp as $$
begin
  perform public.require_admin();
  update public.court_blocks set removed_at = now(), removed_by = auth.uid()
   where id = p_block and removed_at is null;
  if not found then
    raise exception 'not_found' using errcode = 'P0001';
  end if;
end; $$;

create or replace function public.admin_book_court(
  p_account uuid, p_court integer, p_starts_at timestamptz, p_ends_at timestamptz, p_note text)
returns uuid
language plpgsql volatile security definer
set search_path = public, pg_temp as $$
declare v_id uuid;
begin
  perform public.require_admin();
  if p_account is null or not exists (
       select 1 from public.accounts where id = p_account and deleted_at is null) then
    raise exception 'no_such_account' using errcode = 'P0001';
  end if;
  if p_court is null or not exists (select 1 from public.courts where number = p_court) then
    raise exception 'no_such_court' using errcode = 'P0001';
  end if;
  if p_starts_at is null or p_ends_at is null or p_ends_at <= p_starts_at then
    raise exception 'bad_length' using errcode = 'P0001';
  end if;
  perform public.court_write_lock();
  if exists (select 1 from public.court_taken_ranges(p_starts_at, p_ends_at) t
              where t.court = p_court) then
    raise exception 'court_taken' using errcode = 'P0001';
  end if;
  begin
    insert into public.court_bookings (court, account_id, starts_at, ends_at, playing_with, made_by_admin)
    values (p_court, p_account, p_starts_at, p_ends_at,
            nullif(left(btrim(coalesce(p_note, '')), 200), ''), true)
    returning id into v_id;
  exception when exclusion_violation then
    raise exception 'court_taken' using errcode = 'P0001';
  end;
  return v_id;
end; $$;

create or replace function public.admin_cancel_court_booking(p_booking uuid)
returns void
language plpgsql volatile security definer
set search_path = public, pg_temp as $$
begin
  perform public.require_admin();
  update public.court_bookings
     set status = 'canceled', canceled_at = now(), canceled_by = auth.uid()
   where id = p_booking and status = 'booked';
  if not found then
    raise exception 'not_cancelable' using errcode = 'P0001';
  end if;
end; $$;

-- Court settings only, each checked, all or nothing.
create or replace function public.admin_set_court_settings(p_settings jsonb)
returns void
language plpgsql volatile security definer
set search_path = public, pg_temp as $$
declare
  k text;
  v text;
  n int;
  part text;
begin
  perform public.require_admin();
  if p_settings is null or jsonb_typeof(p_settings) <> 'object' then
    raise exception 'bad_setting' using errcode = 'P0001';
  end if;
  for k, v in select key, value #>> '{}' from jsonb_each(p_settings) loop
    if k in ('courts_live', 'court_members_only') then
      if v is null or v not in ('true', 'false') then
        raise exception 'bad_setting' using errcode = 'P0001';
      end if;
    elsif k = 'court_lengths' then
      if v is null or v !~ '^[0-9]+(,[0-9]+)*$' then
        raise exception 'bad_setting' using errcode = 'P0001';
      end if;
      foreach part in array string_to_array(v, ',') loop
        n := part::int;
        if n < 15 or n > 240 or n % 15 <> 0 then
          raise exception 'bad_setting' using errcode = 'P0001';
        end if;
      end loop;
    elsif k = 'court_start_step' then
      if v is null or v not in ('15', '30', '60') then
        raise exception 'bad_setting' using errcode = 'P0001';
      end if;
    elsif k = 'court_day_opens_at' then
      if v is null or v !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
        raise exception 'bad_setting' using errcode = 'P0001';
      end if;
    elsif k in ('court_advance_days', 'court_max_per_day', 'court_max_upcoming', 'court_players_per_court') then
      if v is null or v !~ '^[0-9]{1,3}$' then
        raise exception 'bad_setting' using errcode = 'P0001';
      end if;
      n := v::int;
      if (k = 'court_advance_days'      and n not between 0 and 60)
      or (k = 'court_max_per_day'       and n not between 1 and 10)
      or (k = 'court_max_upcoming'      and n not between 1 and 20)
      or (k = 'court_players_per_court' and n not between 1 and 8) then
        raise exception 'bad_setting' using errcode = 'P0001';
      end if;
    else
      raise exception 'unknown_setting' using errcode = 'P0001';
    end if;
    update public.app_settings set value = v, updated_at = now() where key = k;
  end loop;
end; $$;

create or replace function public.admin_set_court_hours(p_weekday integer, p_opens time, p_closes time)
returns void
language plpgsql volatile security definer
set search_path = public, pg_temp as $$
begin
  perform public.require_admin();
  if p_weekday is null or p_weekday not between 0 and 6
     or p_opens is null or p_closes is null or p_closes <= p_opens then
    raise exception 'bad_hours' using errcode = 'P0001';
  end if;
  update public.court_hours set opens = p_opens, closes = p_closes where weekday = p_weekday;
end; $$;

-- -------------------------------------------- deleting an account
-- Every path that deletes (delete_my_account or anything else that sets
-- accounts.deleted_at) cancels that account's upcoming bookings, by a
-- trigger, as calendar feeds and crash reports are forgotten
-- (20261014000002). Past bookings stay as history.
create or replace function public.court_bookings_forget_deleted_account()
returns trigger
language plpgsql security definer
set search_path = public, pg_temp as $$
begin
  update public.court_bookings
     set status = 'canceled', canceled_at = now(), canceled_by = new.id
   where account_id = new.id and status = 'booked' and starts_at > now();
  return new;
end; $$;
revoke all on function public.court_bookings_forget_deleted_account() from public, anon, authenticated;
create trigger court_bookings_forget_deleted_account
  after update of deleted_at on public.accounts
  for each row
  when (new.deleted_at is not null and old.deleted_at is null)
  execute function public.court_bookings_forget_deleted_account();

-- ---------------------------------------------------------------- grants
-- Every new function is born PUBLIC EXECUTE; revoke from all three, then
-- grant the signed-in client exactly what it calls. The admin_ ones open
-- with require_admin().
revoke all on function
  public.court_day(date),
  public.book_court(integer, timestamptz, integer, text),
  public.cancel_court_booking(uuid),
  public.my_court_bookings(),
  public.admin_court_day(date),
  public.admin_block_courts(integer, timestamptz, timestamptz, text),
  public.admin_remove_court_block(uuid),
  public.admin_book_court(uuid, integer, timestamptz, timestamptz, text),
  public.admin_cancel_court_booking(uuid),
  public.admin_set_court_settings(jsonb),
  public.admin_set_court_hours(integer, time, time)
  from public, anon, authenticated;
grant execute on function
  public.court_day(date),
  public.book_court(integer, timestamptz, integer, text),
  public.cancel_court_booking(uuid),
  public.my_court_bookings(),
  public.admin_court_day(date),
  public.admin_block_courts(integer, timestamptz, timestamptz, text),
  public.admin_remove_court_block(uuid),
  public.admin_book_court(uuid, integer, timestamptz, timestamptz, text),
  public.admin_cancel_court_booking(uuid),
  public.admin_set_court_settings(jsonb),
  public.admin_set_court_hours(integer, time, time)
  to authenticated;
