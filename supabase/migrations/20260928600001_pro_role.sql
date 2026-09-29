-- 20260928600001_pro_role.sql
--
-- THE PRO ROLE (decision 0025). Tara, 2026-09-28 (decision 0024): "For right
-- now, I'm going to be the only one that sees everything. Let the pros see
-- who is coming to the clinics that day. I don't want the pros to invite
-- people from the player pool. See anything financial at all." And on
-- 2026-09-22 (decision 0016) the pros "can label them as no show, late
-- cancellation, and see the clinic list".
--
-- So: Tara stays the only admin and is_admin() is unchanged. A pro is an
-- account with role 'pro' that gets exactly three things, all through
-- SECURITY DEFINER functions, and nothing through any table or view:
--
--   pro_today()                     today's clinics (New York date, published,
--                                   not canceled) and who is You're In! in
--                                   each: first and last name, court, the
--                                   no-show and late-cancel flags. Nothing else.
--   pro_set_no_show(reg, bool)      Came / No-show, today's clinics only
--   pro_mark_late_cancel(reg, note) a late cancellation, today's clinics only
--
-- and Tara alone moves an account between member and pro:
--
--   admin_set_pro(account, bool)    require_admin; member <-> pro only; never
--                                   an admin, a deleted account or herself
--
-- WHY PRO FUNCTIONS AND NOT "LET PROS CALL TARA'S TWO RPCs". admin_set_no_show
-- and admin_mark_late_cancel return the whole registrations row, which
-- carries paid and price_cents_charged: letting a pro call them would hand a
-- pro the money columns Tara said they must never see, through a return value,
-- which is the leak class of 2026-09-27 (court numbers read back from cancel
-- and accept). A blacklist that blanks those columns for a pro would leak the
-- next column anyone adds. So the pro functions return nothing, and the one
-- transition both roles perform lives in one place: the bodies of Tara's two
-- RPCs move, unchanged, into registration_set_no_show and
-- registration_mark_late_cancel, which her RPCs now call after require_admin()
-- and the pro RPCs call after require_pro_today(). Tara's behaviour is
-- identical; tests/sql/late_cancellation.sql and cancellation_policy.sql pin it.
--
-- WHAT A PRO NEVER GETS. is_admin() is false for a pro, so every admin RPC
-- (require_admin), every admin view (where is_admin()), every RLS policy and
-- the three edge functions that ask is_admin() refuse a pro exactly as they
-- refuse a member. No policy, view or grant mentions pros.
--
-- NOT EVEN THROUGH A REFUSAL. Tara's no-show and late-cancel rules refuse a
-- row that holds a live fee. Answered row by row, that refusal told a pro who
-- was charged and, after a decline, whose card failed: whatever the error was
-- called, it came on exactly the charged rows (the sql-auditor, 2026-09-28,
-- demonstrated it with payments on). So once any row of a clinic holds a live
-- fee, Tara has charged that clinic, and every mark a pro tries on it answers
-- clinic_locked, charged rows and uncharged alike; a charge that commits while
-- a mark waits for its row lock is caught by a second look afterwards. A pro
-- learns "Tara has charged this clinic" and nothing per player. Whether pros
-- may mark after she charges is Tara's call (decision 0025); the default is no.
--
-- HARD RULE 8. accounts.role decides is_admin(), and now is_pro(). The three
-- layers from 20260802000003 already cover the new value (a client holds
-- UPDATE on first_name, last_name and phone only; the policy's WITH CHECK;
-- the trigger). The trigger is tightened here to the rule this role creates:
-- a role changes only between member and pro, and only by an admin. No code
-- path may move an account to or from admin, which also means no future bug
-- can demote Tara or promote anyone past pro. Pinned by tests/sql/pro_role.sql.
--
-- THE ENUM VALUE. ALTER TYPE ... ADD VALUE runs inside this migration's
-- transaction, and Postgres refuses to use a new enum value before it commits
-- ("unsafe use of new value"). A SQL-language function body is parsed at
-- creation, so is_pro() compares role::text; PL/pgSQL bodies are parsed at
-- first call, after the commit. Nothing below turns 'pro' into the enum type
-- at creation time. (Tried both ways on 2026-09-28 before writing this.)
--
-- HARD RULE 11. Every new function is revoked from PUBLIC and anon first. The
-- client RPCs are then granted to authenticated; the internal helpers are
-- granted to nobody and are listed in tests/sql/grants_are_explicit.sql.

-- ------------------------------------------------------------ the value ----
alter type public.account_role add value if not exists 'pro';

-- ------------------------------------------------------------- helpers ----

-- The club's calendar date for a moment. "Today" for a pro is New York's,
-- whatever the phone's zone, the same zone every registration rule uses.
create or replace function public.new_york_date(p_at timestamptz)
returns date
language sql
stable
set search_path = public, pg_temp
as $$
  select (p_at at time zone 'America/New_York')::date;
$$;

-- is_admin()'s twin. A deleted account is never a pro.
create or replace function public.is_pro()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.accounts
     where id = auth.uid() and role::text = 'pro' and deleted_at is null
  );
$$;

-- require_admin()'s twin.
create or replace function public.require_pro()
returns void
language plpgsql
stable
set search_path = public, pg_temp
as $$
begin
  if not public.is_pro() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
end;
$$;

-- Tara has charged this clinic: some row of it holds a live fee (the same
-- test her own no-show and late-cancel rules use, row by row).
create or replace function public.pro_clinic_locked(p_clinic uuid)
returns boolean
language sql
stable
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.registrations r
     where r.clinic_id = p_clinic
       and public.registration_has_live_fee(r.id)
  );
$$;

-- The pro write guard: the caller is a pro, and the registration belongs to a
-- published clinic whose New York date is today and which Tara has not
-- charged. The date is tested first, so a registration that does not exist
-- and one in any other day's clinic, canceled or not, get the same answer: the
-- refusal says nothing about registrations a pro was never shown. The clinic
-- row is locked FOR SHARE before the registration row (no function locks a
-- clinic after a registration, so the order cannot deadlock), and
-- cancel_clinic or an edit to the clinic's time, both UPDATEs of that row,
-- cannot slip between this check and the transition that follows it in the
-- same transaction (tests/sql/pro_mark_race.sh). Returns the clinic's id.
create or replace function public.require_pro_today(p_registration uuid)
returns uuid
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_clinic uuid;
  c        public.clinics;
begin
  perform public.require_pro();
  select r.clinic_id into v_clinic from public.registrations r where r.id = p_registration;
  if not found then
    raise exception 'not_today' using errcode = 'P0001';
  end if;
  select * into c from public.clinics where id = v_clinic for share;
  if public.new_york_date(c.starts_at) <> public.new_york_date(now()) then
    raise exception 'not_today' using errcode = 'P0001';
  end if;
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  if c.status <> 'published' then
    raise exception 'not_today' using errcode = 'P0001';
  end if;
  if public.pro_clinic_locked(v_clinic) then
    raise exception 'clinic_locked' using errcode = 'P0001';
  end if;
  return v_clinic;
end;
$$;

-- ------------------------------------------------- the two transitions ----
-- Moved verbatim from admin_set_no_show and admin_mark_late_cancel
-- (20260927100002, via 20260916000001 and 20260927100001). SECURITY INVOKER
-- and executable by nobody but the owner: they run only inside the
-- SECURITY DEFINER functions below, as the owner, after those have decided
-- who may call. Were a grant ever added by mistake, a client calling one
-- directly would run as itself, with no UPDATE on registrations.

create or replace function public.registration_set_no_show(p_registration uuid, p_no_show boolean)
returns public.registrations
language plpgsql
set search_path = public, pg_temp
as $$
declare v_row public.registrations;
begin
  -- The row lock pairs with admin_charge_clinic's: a flip and a charge on the
  -- same row take turns instead of interleaving.
  select * into v_row from public.registrations where id = p_registration for update;
  if not found or v_row.status <> 'in' then
    raise exception 'registration_not_in' using errcode = 'P0001';
  end if;
  if public.registration_has_live_fee(p_registration) then
    raise exception 'charged_refund_first' using errcode = 'P0001';
  end if;
  update public.registrations set no_show = p_no_show
   where id = p_registration and status = 'in'
  returning * into v_row;
  if not found then
    raise exception 'registration_not_in' using errcode = 'P0001';
  end if;
  return v_row;
end;
$$;

create or replace function public.registration_mark_late_cancel(p_registration uuid, p_note text default null)
returns public.registrations
language plpgsql
set search_path = public, pg_temp
as $$
declare
  v_row    public.registrations;
  c        public.clinics;
  v_note   text := nullif(btrim(coalesce(p_note, '')), '');
begin
  -- Row lock first: the same lock admin_charge_clinic and the no-show flip
  -- take, so a charge and this cannot interleave on one row.
  select * into v_row from public.registrations where id = p_registration for update;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if v_row.status <> 'in' then
    raise exception 'registration_not_in' using errcode = 'P0001';
  end if;

  select * into c from public.clinics where id = v_row.clinic_id;
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  -- Inside the cutoff, or after the clinic (she may record it afterwards).
  if now() < c.starts_at - make_interval(hours => public.cancel_cutoff_hours()) then
    raise exception 'not_late_yet' using errcode = 'P0001';
  end if;
  if public.registration_has_live_fee(p_registration) then
    raise exception 'charged_refund_first' using errcode = 'P0001';
  end if;

  update public.registrations
     set status = 'canceled', canceled_at = now(), canceled_by = auth.uid(),
         late_cancel = true,
         courtesy_used = public.courtesy_available(v_row.player_id),
         cancel_note = left(v_note, 280),
         no_show = false
   where id = p_registration
     and status = 'in'
  returning * into v_row;
  if not found then
    raise exception 'registration_not_in' using errcode = 'P0001';
  end if;

  return v_row;
end;
$$;

-- ------------------------------------------------- Tara's two, delegating ----
-- Same signatures, same return type, same behaviour; only the body moved.

create or replace function public.admin_set_no_show(p_registration uuid, p_no_show boolean)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return public.registration_set_no_show(p_registration, p_no_show);
end;
$$;

create or replace function public.admin_mark_late_cancel(p_registration uuid, p_note text default null)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return public.registration_mark_late_cancel(p_registration, p_note);
end;
$$;

-- ------------------------------------------------------------ the pro ----

-- Who is coming today. You're In! only: never the Player Pool, never Response
-- Needed, never a canceled row. The columns are the whole contract; a new
-- column in registrations, clinics or players reaches a pro only by being
-- added here, and tests/sql/pro_role.sql asserts this exact column list. A
-- clinic with nobody in it yet is one row with null registration columns, so
-- the screen can still show it.
create or replace function public.pro_today()
returns table (
  clinic_id       uuid,
  clinic_name     text,
  starts_at       timestamptz,
  ends_at         timestamptz,
  registration_id uuid,
  first_name      text,
  last_name       text,
  court_number    smallint,
  no_show         boolean,
  late_cancel     boolean
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_pro();
  return query
    select c.id, c.name, c.starts_at, c.ends_at,
           r.id, p.first_name, p.last_name, r.court_number, r.no_show, r.late_cancel
      from public.clinics c
      left join public.registrations r
             on r.clinic_id = c.id and r.status = 'in'
      left join public.players p on p.id = r.player_id
     where c.status = 'published'
       and public.new_york_date(c.starts_at) = public.new_york_date(now())
     order by c.starts_at, c.id, r.court_number nulls last, p.last_name, p.first_name, r.id;
end;
$$;

-- Came / No-show on today's clinics. Returns nothing: the row carries money.
create or replace function public.pro_set_no_show(p_registration uuid, p_no_show boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_clinic uuid;
begin
  if p_no_show is null then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  v_clinic := public.require_pro_today(p_registration);
  begin
    perform public.registration_set_no_show(p_registration, p_no_show);
  exception when others then
    -- A charge committed between the guard and the row lock: the clinic's
    -- word, never the row's (see the header).
    if sqlerrm = 'charged_refund_first' then
      raise exception 'clinic_locked' using errcode = 'P0001';
    end if;
    raise;
  end;
  -- The second look: a charge that committed while this waited for the row
  -- stops this mark too, whichever row it charged. Raising undoes the flip.
  if public.pro_clinic_locked(v_clinic) then
    raise exception 'clinic_locked' using errcode = 'P0001';
  end if;
end;
$$;

-- A late cancellation on today's clinics: the same record Tara's leaves
-- (You're In! to Canceled, late, canceled_by the caller, optional note), the
-- same guards (inside the cutoff or later, not once charged, not on a canceled
-- clinic), plus the clinic-level lock above. Tells nobody, like hers. Returns
-- nothing.
create or replace function public.pro_mark_late_cancel(p_registration uuid, p_note text default null)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_clinic uuid;
begin
  v_clinic := public.require_pro_today(p_registration);
  begin
    perform public.registration_mark_late_cancel(p_registration, p_note);
  exception when others then
    if sqlerrm = 'charged_refund_first' then
      raise exception 'clinic_locked' using errcode = 'P0001';
    end if;
    raise;
  end;
  if public.pro_clinic_locked(v_clinic) then
    raise exception 'clinic_locked' using errcode = 'P0001';
  end if;
end;
$$;

-- ------------------------------------------------------ Tara's switch ----

-- Member <-> pro, and nothing else. The UPDATE is conditional (hard rule 3):
-- it only ever touches a live member or pro, so an admin, a deleted account or
-- a row that changed meanwhile is left alone and named in the refusal. Setting
-- the state an account already has returns it again rather than failing: the
-- web admin's second tap on a stale page lands where she meant it to.
-- Returns the account's role afterwards ('member' or 'pro').
create or replace function public.admin_set_pro(p_account uuid, p_pro boolean)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_role    text;
  v_deleted timestamptz;
begin
  perform public.require_admin();
  if p_account is null or p_pro is null then
    raise exception 'invalid_argument' using errcode = '22023';
  end if;
  if p_account = auth.uid() then
    raise exception 'cannot_change_own_role' using errcode = 'P0001';
  end if;

  update public.accounts
     set role = (case when p_pro then 'pro' else 'member' end)::public.account_role
   where id = p_account
     and role::text in ('member', 'pro')
     and deleted_at is null
  returning role::text into v_role;
  if found then
    return v_role;
  end if;

  select a.role::text, a.deleted_at into v_role, v_deleted
    from public.accounts a where a.id = p_account;
  if not found then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;
  if v_deleted is not null then
    raise exception 'account_deleted' using errcode = 'P0001';
  end if;
  if v_role = 'admin' then
    raise exception 'cannot_change_an_admin' using errcode = 'P0001';
  end if;
  raise exception 'account_changed' using errcode = 'P0001';
end;
$$;

-- ------------------------------------------- hard rule 8, the backstop ----
-- Same function as 20260802000003 plus the member <-> pro rule. Kept on
-- purpose even though admin_set_pro is the only writer: the trigger is for
-- the code path nobody has written yet.
create or replace function public.guard_account_privilege_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'account_id_is_immutable' using errcode = '42501';
  end if;
  if new.role is distinct from old.role then
    if not public.is_admin() then
      raise exception 'only_an_admin_may_change_a_role' using errcode = '42501';
    end if;
    if old.role::text not in ('member', 'pro') or new.role::text not in ('member', 'pro') then
      raise exception 'only_member_and_pro_may_change' using errcode = '42501';
    end if;
  end if;
  return new;
end;
$$;

-- --------------------------------------------------------------- notes ----
comment on function public.pro_today() is
  'A pro''s Today tab (decision 0025): today''s New York-date published clinics, '
  'and per You''re In! registration only the id, first and last name, court, '
  'no_show and late_cancel. Refuses anyone who is not a pro.';
comment on function public.pro_set_no_show(uuid, boolean) is
  'A pro marks Came / No-show on a You''re In! row of today''s clinic. Returns nothing.';
comment on function public.pro_mark_late_cancel(uuid, text) is
  'A pro records a late cancellation on today''s clinic, with Tara''s guards. Returns nothing.';
comment on function public.admin_set_pro(uuid, boolean) is
  'Tara moves an account between member and pro. Never an admin, a deleted account or herself.';
comment on function public.registration_set_no_show(uuid, boolean) is
  'Internal: the no-show transition shared by admin_set_no_show and pro_set_no_show.';
comment on function public.registration_mark_late_cancel(uuid, text) is
  'Internal: the late-cancel transition shared by admin_mark_late_cancel and pro_mark_late_cancel.';

-- -------------------------------------------------------------- grants ----
-- Client RPCs: revoke first (PUBLIC holds EXECUTE on every new function), then
-- grant the signed-in role explicitly.
revoke all on function public.new_york_date(timestamptz)        from public, anon;
revoke all on function public.is_pro()                          from public, anon;
revoke all on function public.require_pro()                     from public, anon;
revoke all on function public.pro_today()                       from public, anon;
revoke all on function public.pro_set_no_show(uuid, boolean)    from public, anon;
revoke all on function public.pro_mark_late_cancel(uuid, text)  from public, anon;
revoke all on function public.admin_set_pro(uuid, boolean)      from public, anon;
grant execute on function public.new_york_date(timestamptz)        to authenticated;
grant execute on function public.is_pro()                          to authenticated;
grant execute on function public.require_pro()                     to authenticated;
grant execute on function public.pro_today()                       to authenticated;
grant execute on function public.pro_set_no_show(uuid, boolean)    to authenticated;
grant execute on function public.pro_mark_late_cancel(uuid, text)  to authenticated;
grant execute on function public.admin_set_pro(uuid, boolean)      to authenticated;

-- Internal helpers: nobody but the owner.
revoke all on function public.require_pro_today(uuid)                   from public, anon, authenticated;
revoke all on function public.pro_clinic_locked(uuid)                   from public, anon, authenticated;
revoke all on function public.registration_set_no_show(uuid, boolean)   from public, anon, authenticated;
revoke all on function public.registration_mark_late_cancel(uuid, text) from public, anon, authenticated;

-- Restated for the two redefined in place (create or replace keeps the ACL;
-- written down so the grant is a fact in this file, not an inheritance).
revoke all on function public.admin_set_no_show(uuid, boolean)     from public, anon;
revoke all on function public.admin_mark_late_cancel(uuid, text)   from public, anon;
grant execute on function public.admin_set_no_show(uuid, boolean)     to authenticated;
grant execute on function public.admin_mark_late_cancel(uuid, text)   to authenticated;
