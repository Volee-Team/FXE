-- 20261118000001_juniors_family.sql
--
-- Juniors, phase 1, the server (`docs/juniors/plan.md`, decision 0061). Her
-- document, spec 01: "Profile -> My Children -> Add a Child. Collect child
-- name and birthday. Support multiple children." "Require a parent-signed
-- waiver for each child." Five programs, "Program selection is always
-- manual", and "Junior Elite and Elite approvals are specific to the program
-- and carry between school-year and summer offerings. Tara can preapprove
-- current players."
--
-- Phase 0 (20261115000001) made the database safe for a child row. This
-- migration lets a parent create one, and keeps phase 0's rule: what the
-- apps already on phones read does not change. A child is reached only
-- through the functions below, which only the 1.0.5 app, the members' site
-- and Tara's laptop call. No new table has a client grant.
--
--   1. My Children: my_children, add_my_child, update_my_child,
--      remove_my_child. A child is a players row (kind junior, a birthday)
--      on the parent's account. An 'adult' account becomes 'both'. Removing
--      archives the row (hard rule 4) and is refused while the child holds
--      an upcoming spot. The same child (name and birthday) twice on one
--      account is refused: "avoid duplicate child profiles".
--   2. A waiver per child. `waivers` gains a kind (adult / junior); the
--      junior text is a waivers row of kind junior, made current by the
--      app_settings key junior_waiver_version. Her parent/guardian text is
--      not in the repo yet (question 145 said "Yes" to the form; the text
--      itself comes in a later, small migration), so this migration inserts
--      NO junior text and no junior_waiver_version. Until then every child
--      reads 'not_available', never 'needed': a parent cannot be asked to
--      sign something that does not exist, and phase 2's registration check
--      will refuse with its own error (junior_waiver_not_available) rather
--      than one a parent could fix, so the gap is loud, not silent.
--      "Once per child per year" is Tara publishing next year's version: a
--      new version makes every child 'needed' again. No date math.
--   3. junior_programs: her five, in her order, with her age guidance;
--      descriptions empty for her to write. Tara edits and archives them;
--      parents read the active ones.
--   4. program_approvals: a parent asks for a program that needs approval,
--      Tara approves or declines the request once (hard rule 3), or
--      preapproves a child directly. One approval per child and program,
--      with no season in it, so it covers school year and summer alike.
--      A decline stands until Tara approves: the parent cannot re-ask.
--   5. Nobody but the child's parent account and Tara reaches any of it.
--      Pros see a child in phase 3, on a day the child is rostered.
--
-- Probe: tests/sql/juniors_family.sql (red first; written from the rules).

-- 2. Waivers by kind ------------------------------------------------------
alter table public.waivers
  add column if not exists kind text not null default 'adult'
  check (kind in ('adult', 'junior'));
alter table public.waivers
  add constraint waivers_version_kind_key unique (version, kind);
comment on column public.waivers.kind is
  'adult: the clinics waiver (decision 0013), current = app_settings.waiver_version. '
  'junior: the parent/guardian waiver signed per child (decision 0061), '
  'current = app_settings.junior_waiver_version.';

-- The adult signature can only be on adult text, as the child's only on
-- junior text: each table carries its kind as a constant and the pair is
-- the foreign key.
alter table public.waiver_acceptances
  add column if not exists kind text not null default 'adult' check (kind = 'adult');
alter table public.waiver_acceptances
  drop constraint if exists waiver_acceptances_version_fkey;
alter table public.waiver_acceptances
  add constraint waiver_acceptances_version_kind_fkey
  foreign key (version, kind) references public.waivers (version, kind);

create table public.junior_waiver_acceptances (
  id          uuid primary key default gen_random_uuid(),
  player_id   uuid not null references public.players(id) on delete restrict,
  account_id  uuid not null references public.accounts(id) on delete restrict,
  version     text not null,
  kind        text not null default 'junior' check (kind = 'junior'),
  legal_name  text not null,
  email       text not null,
  accepted_at timestamptz not null default now(),
  app_version text,
  unique (player_id, version),
  foreign key (version, kind) references public.waivers (version, kind)
);
comment on table public.junior_waiver_acceptances is
  'A parent''s electronic signature of the junior waiver for one child, per '
  'version (decision 0061). Written only by accept_child_waiver(); no client '
  'reads it. RESTRICT on both sides: nothing deletes a signature.';

revoke all on public.junior_waiver_acceptances from public, anon, authenticated;
alter table public.junior_waiver_acceptances enable row level security;

-- 3. Programs -------------------------------------------------------------
create table public.junior_programs (
  id             uuid primary key default gen_random_uuid(),
  name           text not null check (btrim(name) <> ''),
  description    text not null default '',
  age_guidance   text not null default '',
  needs_approval boolean not null default false,
  sort_order     int not null default 0,
  active         boolean not null default true,
  created_at     timestamptz not null default now(),
  updated_at     timestamptz not null default now()
);
create unique index junior_programs_name_key on public.junior_programs (lower(btrim(name)));
comment on table public.junior_programs is
  'Tara''s junior programs (spec 01, decision 0061). Shown to parents with her '
  'description and age guidance; never chosen from a birthday. Archived '
  '(active false), never deleted.';

revoke all on public.junior_programs from public, anon, authenticated;
alter table public.junior_programs enable row level security;

-- Her table, spec 01: "Suggested ages / approval".
insert into public.junior_programs (name, age_guidance, needs_approval, sort_order) values
  ('Red Dot',             'Ages 3-6',  false, 1),
  ('Orange Dot',          'Ages 6-10', false, 2),
  ('Recreational Yellow', 'Ages 10+',  false, 3),
  ('Junior Elite',        '',          true,  4),
  ('Elite',               '',          true,  5);

-- 4. Approvals ------------------------------------------------------------
create table public.program_approvals (
  player_id    uuid not null references public.players(id) on delete restrict,
  program_id   uuid not null references public.junior_programs(id) on delete restrict,
  status       text not null check (status in ('requested', 'approved', 'declined')),
  source       text not null check (source in ('parent', 'tara')),
  requested_by uuid references public.accounts(id) on delete set null,
  requested_at timestamptz,
  decided_by   uuid references public.accounts(id) on delete set null,
  decided_at   timestamptz,
  primary key (player_id, program_id)
);
comment on table public.program_approvals is
  'Decision 0061. A parent''s request for, or Tara''s decision on, a child in a '
  'program that needs approval (Junior Elite, Elite). No season: one approval '
  'covers school year and summer. Written only through the functions.';

revoke all on public.program_approvals from public, anon, authenticated;
alter table public.program_approvals enable row level security;

-- ------------------------------------------------------------ waiver helpers
create or replace function public.junior_waiver_version()
returns text
language sql stable security definer set search_path = public, pg_temp
as $$
  -- Current only if the setting names a junior text that exists.
  select w.version
    from public.app_settings s
    join public.waivers w on w.version = s.value and w.kind = 'junior'
   where s.key = 'junior_waiver_version';
$$;

-- Internal: has this child a signature on the current junior text? For
-- phase 2's registration check; no client calls it.
create or replace function public.junior_waiver_signed(p_child uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.junior_waiver_acceptances a
     where a.player_id = p_child and a.version = public.junior_waiver_version()
  );
$$;

create or replace function public.current_junior_waiver()
returns table (version text, title text, organizer text, body text, published_at timestamptz)
language sql stable security definer set search_path = public, pg_temp
as $$
  select w.version, w.title, w.organizer, w.body, w.published_at
    from public.waivers w
   where w.kind = 'junior' and w.version = public.junior_waiver_version();
$$;

-- ------------------------------------------------------------ 1. My Children
create or replace function public.my_children()
returns table (id uuid, first_name text, last_name text, date_of_birth date,
               age int, waiver_status text)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  return query
    select p.id, p.first_name, p.last_name, p.date_of_birth,
           public.player_age(p.date_of_birth),
           case when public.junior_waiver_version() is null then 'not_available'
                when public.junior_waiver_signed(p.id)      then 'signed'
                else 'needed' end
      from public.players p
     where p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
     order by p.date_of_birth, p.first_name, p.id;
end;
$$;

create or replace function public.add_my_child(p_first_name text, p_last_name text, p_date_of_birth date)
returns table (id uuid, first_name text, last_name text, date_of_birth date)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_first text := left(btrim(coalesce(p_first_name, '')), 60);
  v_last  text := left(btrim(coalesce(p_last_name, '')), 60);
  v_id    uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if v_first = '' or v_last = '' then
    raise exception 'name_required' using errcode = 'P0001';
  end if;
  if p_date_of_birth is null or p_date_of_birth > current_date then
    raise exception 'invalid_birthday' using errcode = '22023';
  end if;
  -- Locks the account, so two taps on Add cannot make two copies.
  perform 1 from public.accounts a
   where a.id = auth.uid() and a.deleted_at is null
   for update;
  if not found then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;
  if exists (select 1 from public.players p
              where p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
                and lower(p.first_name) = lower(v_first) and lower(p.last_name) = lower(v_last)
                and p.date_of_birth = p_date_of_birth) then
    raise exception 'child_exists' using errcode = 'P0001';
  end if;

  insert into public.players (account_id, kind, first_name, last_name, date_of_birth)
  values (auth.uid(), 'junior', v_first, v_last, p_date_of_birth)
  returning players.id into v_id;

  -- Spec 06, scenario 1: an adult who adds a child keeps everything, and is
  -- now both. A parent-only account stays a parent.
  update public.accounts a set account_type = 'both'
   where a.id = auth.uid() and a.account_type = 'adult';

  return query select p.id, p.first_name, p.last_name, p.date_of_birth
                 from public.players p where p.id = v_id;
end;
$$;

create or replace function public.update_my_child(p_child uuid, p_first_name text, p_last_name text, p_date_of_birth date)
returns table (id uuid, first_name text, last_name text, date_of_birth date)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_first text := left(btrim(coalesce(p_first_name, '')), 60);
  v_last  text := left(btrim(coalesce(p_last_name, '')), 60);
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  perform 1 from public.accounts a where a.id = auth.uid() for update;
  perform 1 from public.players p
   where p.id = p_child and p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
   for update;
  if not found then
    raise exception 'not_your_child' using errcode = '42501';
  end if;
  if v_first = '' or v_last = '' then
    raise exception 'name_required' using errcode = 'P0001';
  end if;
  if p_date_of_birth is null or p_date_of_birth > current_date then
    raise exception 'invalid_birthday' using errcode = '22023';
  end if;
  if exists (select 1 from public.players p
              where p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
                and p.id <> p_child
                and lower(p.first_name) = lower(v_first) and lower(p.last_name) = lower(v_last)
                and p.date_of_birth = p_date_of_birth) then
    raise exception 'child_exists' using errcode = 'P0001';
  end if;

  update public.players p
     set first_name = v_first, last_name = v_last, date_of_birth = p_date_of_birth
   where p.id = p_child;

  return query select p.id, p.first_name, p.last_name, p.date_of_birth
                 from public.players p where p.id = p_child;
end;
$$;

create or replace function public.remove_my_child(p_child uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  perform 1 from public.players p
   where p.id = p_child and p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
   for update;
  if not found then
    raise exception 'not_your_child' using errcode = '42501';
  end if;
  -- A spot still to come is Tara's roster: the parent cancels it first.
  if exists (select 1 from public.registrations r
               join public.clinics c on c.id = r.clinic_id
              where r.player_id = p_child and c.starts_at > now()
                and r.status in ('in', 'pool', 'response_needed')) then
    raise exception 'child_has_upcoming' using errcode = 'P0001';
  end if;
  -- Archived, not deleted (hard rule 4): Tara's history keeps the name.
  update public.players p set is_active = false
   where p.id = p_child and p.is_active;
end;
$$;

-- ------------------------------------------------------------ 2. Waiver per child
create or replace function public.child_waiver_status(p_child uuid)
returns text
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not exists (select 1 from public.players p
                  where p.id = p_child and p.kind = 'junior'
                    and (p.account_id = auth.uid() or public.is_admin())) then
    raise exception 'not_your_child' using errcode = '42501';
  end if;
  return case when public.junior_waiver_version() is null then 'not_available'
              when public.junior_waiver_signed(p_child)      then 'signed'
              else 'needed' end;
end;
$$;

-- The parent signs for the child. As the adult waiver: the email comes from
-- the account, never the client; signing the same version twice keeps the
-- first record.
create or replace function public.accept_child_waiver(p_child uuid, p_version text, p_legal_name text, p_app_version text default null)
returns table (player_id uuid, version text, accepted_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_name    text := btrim(coalesce(p_legal_name, ''));
  v_current text := public.junior_waiver_version();
  v_email   text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  perform 1 from public.players p
   where p.id = p_child and p.account_id = auth.uid() and p.kind = 'junior' and p.is_active;
  if not found then
    raise exception 'not_your_child' using errcode = '42501';
  end if;
  if v_current is null then
    raise exception 'junior_waiver_not_available' using errcode = 'P0001';
  end if;
  if p_version is distinct from v_current then
    raise exception 'waiver_version_stale' using errcode = 'P0001';
  end if;
  if length(v_name) < 3 or position(' ' in v_name) = 0 then
    raise exception 'legal_name_required' using errcode = 'P0001';
  end if;
  select a.email into v_email from public.accounts a
   where a.id = auth.uid() and a.deleted_at is null;
  if v_email is null then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;

  insert into public.junior_waiver_acceptances (player_id, account_id, version, legal_name, email, app_version)
  values (p_child, auth.uid(), p_version, left(v_name, 120), v_email, left(p_app_version, 40))
  on conflict on constraint junior_waiver_acceptances_player_id_version_key do nothing;

  return query select a.player_id, a.version, a.accepted_at
                 from public.junior_waiver_acceptances a
                where a.player_id = p_child and a.version = p_version;
end;
$$;

-- ------------------------------------------------------------ 3. Programs
create or replace function public.list_junior_programs()
returns table (id uuid, name text, description text, age_guidance text,
               needs_approval boolean, sort_order int)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  return query
    select g.id, g.name, g.description, g.age_guidance, g.needs_approval, g.sort_order
      from public.junior_programs g
     where g.active
     order by g.sort_order, g.name;
end;
$$;

create or replace function public.admin_junior_programs()
returns setof public.junior_programs
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query select * from public.junior_programs g order by g.active desc, g.sort_order, g.name;
end;
$$;

-- p_id null makes a program; otherwise edits it. Archive with p_active false.
create or replace function public.admin_save_junior_program(
  p_id uuid, p_name text, p_description text, p_age_guidance text,
  p_needs_approval boolean, p_sort_order int, p_active boolean)
returns public.junior_programs
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_name text := left(btrim(coalesce(p_name, '')), 60);
  v      public.junior_programs;
begin
  perform public.require_admin();
  if v_name = '' then
    raise exception 'name_required' using errcode = 'P0001';
  end if;
  begin
    if p_id is null then
      insert into public.junior_programs (name, description, age_guidance, needs_approval, sort_order, active)
      values (v_name, left(btrim(coalesce(p_description, '')), 2000), left(btrim(coalesce(p_age_guidance, '')), 120),
              coalesce(p_needs_approval, false), coalesce(p_sort_order, 0), coalesce(p_active, true))
      returning * into v;
    else
      update public.junior_programs g
         set name = v_name,
             description = left(btrim(coalesce(p_description, '')), 2000),
             age_guidance = left(btrim(coalesce(p_age_guidance, '')), 120),
             needs_approval = coalesce(p_needs_approval, g.needs_approval),
             sort_order = coalesce(p_sort_order, g.sort_order),
             active = coalesce(p_active, g.active),
             updated_at = now()
       where g.id = p_id
      returning * into v;
      if not found then
        raise exception 'program_not_found' using errcode = 'P0002';
      end if;
    end if;
  exception when unique_violation then
    raise exception 'program_name_taken' using errcode = 'P0001';
  end;
  return v;
end;
$$;

-- ------------------------------------------------------------ 4. Approvals
create or replace function public.request_program_approval(p_child uuid, p_program uuid)
returns table (player_id uuid, program_id uuid, status text)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_needs boolean;
  v_status text;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  perform 1 from public.players p
   where p.id = p_child and p.account_id = auth.uid() and p.kind = 'junior' and p.is_active;
  if not found then
    raise exception 'not_your_child' using errcode = '42501';
  end if;
  select g.needs_approval into v_needs from public.junior_programs g
   where g.id = p_program and g.active;
  if not found then
    raise exception 'program_not_found' using errcode = 'P0002';
  end if;
  if not v_needs then
    raise exception 'approval_not_needed' using errcode = 'P0001';
  end if;

  -- Conditional (hard rule 3): a second tap, or a request after Tara has
  -- decided, changes nothing.
  insert into public.program_approvals as a (player_id, program_id, status, source, requested_by, requested_at)
  values (p_child, p_program, 'requested', 'parent', auth.uid(), now())
  on conflict on constraint program_approvals_pkey do nothing;

  select a.status into v_status from public.program_approvals a
   where a.player_id = p_child and a.program_id = p_program;
  if v_status = 'declined' then
    raise exception 'approval_declined' using errcode = 'P0001';
  end if;
  return query select p_child, p_program, v_status;
end;
$$;

create or replace function public.my_program_approvals()
returns table (player_id uuid, child_first_name text, program_id uuid, program_name text,
               status text, requested_at timestamptz, decided_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  return query
    select a.player_id, p.first_name, a.program_id, g.name, a.status, a.requested_at, a.decided_at
      from public.program_approvals a
      join public.players p on p.id = a.player_id
      join public.junior_programs g on g.id = a.program_id
     where p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
     order by p.first_name, g.sort_order;
end;
$$;

-- Tara's list for Action Needed: open requests first.
create or replace function public.admin_program_approvals()
returns table (player_id uuid, child_first_name text, child_last_name text,
               date_of_birth date, age int,
               parent_account_id uuid, parent_first_name text, parent_last_name text, parent_phone text,
               program_id uuid, program_name text, status text, source text,
               requested_at timestamptz, decided_at timestamptz)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
    select a.player_id, p.first_name, p.last_name, p.date_of_birth, public.player_age(p.date_of_birth),
           acc.id, acc.first_name, acc.last_name, acc.phone,
           a.program_id, g.name, a.status, a.source, a.requested_at, a.decided_at
      from public.program_approvals a
      join public.players p    on p.id = a.player_id
      join public.accounts acc on acc.id = p.account_id
      join public.junior_programs g on g.id = a.program_id
     where p.is_active and acc.deleted_at is null
     order by (a.status = 'requested') desc, a.requested_at nulls last, p.last_name, p.first_name, g.sort_order;
end;
$$;

-- Tara answers a request, once.
create or replace function public.admin_decide_program_approval(p_child uuid, p_program uuid, p_approve boolean)
returns table (player_id uuid, program_id uuid, status text)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_status text;
begin
  perform public.require_admin();
  if p_approve is null then
    raise exception 'decision_required' using errcode = '22023';
  end if;
  update public.program_approvals a
     set status = case when p_approve then 'approved' else 'declined' end,
         decided_by = auth.uid(), decided_at = now()
   where a.player_id = p_child and a.program_id = p_program and a.status = 'requested'
  returning a.status into v_status;
  if not found then
    if exists (select 1 from public.program_approvals a
                where a.player_id = p_child and a.program_id = p_program) then
      raise exception 'approval_already_decided' using errcode = 'P0001';
    end if;
    raise exception 'approval_not_found' using errcode = 'P0002';
  end if;
  return query select p_child, p_program, v_status;
end;
$$;

-- Tara approves a child directly: "Tara can preapprove current players".
-- Also how she changes her mind after a decline.
create or replace function public.admin_preapprove_program(p_child uuid, p_program uuid)
returns table (player_id uuid, program_id uuid, status text)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_needs boolean;
begin
  perform public.require_admin();
  perform 1 from public.players p
   where p.id = p_child and p.kind = 'junior' and p.is_active;
  if not found then
    raise exception 'child_not_found' using errcode = 'P0002';
  end if;
  select g.needs_approval into v_needs from public.junior_programs g where g.id = p_program;
  if not found then
    raise exception 'program_not_found' using errcode = 'P0002';
  end if;
  if not v_needs then
    raise exception 'approval_not_needed' using errcode = 'P0001';
  end if;

  insert into public.program_approvals as a (player_id, program_id, status, source, decided_by, decided_at)
  values (p_child, p_program, 'approved', 'tara', auth.uid(), now())
  on conflict on constraint program_approvals_pkey do update
     set status = 'approved', decided_by = excluded.decided_by, decided_at = excluded.decided_at
   where a.status <> 'approved';

  return query select a.player_id, a.program_id, a.status from public.program_approvals a
                where a.player_id = p_child and a.program_id = p_program;
end;
$$;

-- ------------------------------------------------------------ grants
revoke all on function public.junior_waiver_version() from public, anon, authenticated;
revoke all on function public.junior_waiver_signed(uuid) from public, anon, authenticated;
revoke all on function public.current_junior_waiver() from public, anon, authenticated;
revoke all on function public.my_children() from public, anon, authenticated;
revoke all on function public.add_my_child(text, text, date) from public, anon, authenticated;
revoke all on function public.update_my_child(uuid, text, text, date) from public, anon, authenticated;
revoke all on function public.remove_my_child(uuid) from public, anon, authenticated;
revoke all on function public.child_waiver_status(uuid) from public, anon, authenticated;
revoke all on function public.accept_child_waiver(uuid, text, text, text) from public, anon, authenticated;
revoke all on function public.list_junior_programs() from public, anon, authenticated;
revoke all on function public.admin_junior_programs() from public, anon, authenticated;
revoke all on function public.admin_save_junior_program(uuid, text, text, text, boolean, int, boolean) from public, anon, authenticated;
revoke all on function public.request_program_approval(uuid, uuid) from public, anon, authenticated;
revoke all on function public.my_program_approvals() from public, anon, authenticated;
revoke all on function public.admin_program_approvals() from public, anon, authenticated;
revoke all on function public.admin_decide_program_approval(uuid, uuid, boolean) from public, anon, authenticated;
revoke all on function public.admin_preapprove_program(uuid, uuid) from public, anon, authenticated;

grant execute on function public.junior_waiver_version() to authenticated;
grant execute on function public.current_junior_waiver() to authenticated;
grant execute on function public.my_children() to authenticated;
grant execute on function public.add_my_child(text, text, date) to authenticated;
grant execute on function public.update_my_child(uuid, text, text, date) to authenticated;
grant execute on function public.remove_my_child(uuid) to authenticated;
grant execute on function public.child_waiver_status(uuid) to authenticated;
grant execute on function public.accept_child_waiver(uuid, text, text, text) to authenticated;
grant execute on function public.list_junior_programs() to authenticated;
grant execute on function public.admin_junior_programs() to authenticated;
grant execute on function public.admin_save_junior_program(uuid, text, text, text, boolean, int, boolean) to authenticated;
grant execute on function public.request_program_approval(uuid, uuid) to authenticated;
grant execute on function public.my_program_approvals() to authenticated;
grant execute on function public.admin_program_approvals() to authenticated;
grant execute on function public.admin_decide_program_approval(uuid, uuid, boolean) to authenticated;
grant execute on function public.admin_preapprove_program(uuid, uuid) to authenticated;
