-- "Can I still get in?" — the second half of Tara's close-time answer.
--
-- Tara, 2026-08-27:
--   "lets say 3 hours prior and if they try to register within 3 hours, they
--    have the option to send me a direct message to get into the clinic,
--    assuming there is space and it isn't full."
--
-- 20260827000001 built the first half: registration closes 3 hours before the
-- clinic. That alone makes the product WORSE for a player who is 2 hours out and
-- wants in, because before it they could register and now they hit a wall. This
-- is the other half.
--
-- WHY A TABLE AND NOT A MESSAGE
-- -----------------------------
-- Her words are "send me a direct message", and a message is what it feels like
-- to the player. But she has to ACT on it: put them in, or say no. A row in
-- `notifications` is text with no state, so she would have no way to see which
-- requests she had already handled, and a player would have no way to learn the
-- answer. A request has a lifecycle (pending -> approved / declined), so it is a
-- table, and the message is a column on it.
--
-- The player-facing framing stays hers: the app says she has been messaged.
--
-- HARD RULES THIS RESPECTS
--   2. Approving is Tara's decision, always. Nothing here auto-places anyone,
--      and a request is not a registration.
--   3. Every transition is conditional: resolving checks the row is still
--      pending, so two taps cannot place someone twice.
--   4. Archive never delete: a declined request keeps its row and its timestamp.
--   1. A player never learns a count. The capacity check happens server-side and
--      the failure is phrased as "the clinic is full", never "3 of 8 spots".

create table if not exists public.late_requests (
  id          uuid primary key default gen_random_uuid(),
  clinic_id   uuid not null references public.clinics(id) on delete cascade,
  player_id   uuid not null references public.players(id) on delete cascade,
  message     text,
  status      text not null default 'pending'
                check (status in ('pending', 'approved', 'declined')),
  created_at  timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.accounts(id)
);

-- One live request per player per clinic. Without this, tapping twice on a bad
-- connection puts two identical rows in Tara's queue and she has to work out
-- they are the same person.
create unique index if not exists late_requests_one_pending
  on public.late_requests (clinic_id, player_id)
  where status = 'pending';

create index if not exists late_requests_pending_by_clinic
  on public.late_requests (clinic_id) where status = 'pending';

alter table public.late_requests enable row level security;

-- Hard rule 11: revoke before grant, and from PUBLIC too. A new table inherits
-- whatever the schema default hands out, and on 2026-08-16 that default changed
-- underneath this project once already.
revoke all on public.late_requests from public, anon, authenticated;
grant select on public.late_requests to authenticated;

-- Reads are scoped by policy; every WRITE goes through the RPCs below.
create policy late_requests_own on public.late_requests
  for select using (public.owns_player(player_id) or public.is_admin());

-- ---------------------------------------------------------------- player ----

create or replace function public.request_late_spot(
  p_clinic  uuid,
  p_player  uuid,
  p_message text default null
) returns public.late_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c        public.clinics;
  v_req    public.late_requests;
  v_taken  int;
  v_name   text;
  v_admin  uuid;
begin
  if not public.owns_player(p_player) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  select * into c from public.clinics where id = p_clinic;
  if not found or c.status <> 'published' then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if c.canceled_at is not null then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;

  -- This path exists only INSIDE the closed window. Before it, the player
  -- registers normally, and offering both would be two doors to one room.
  if c.closes_at is null or now() < c.closes_at then
    raise exception 'registration_still_open' using errcode = 'P0001';
  end if;
  if now() >= c.starts_at then
    raise exception 'clinic_already_started' using errcode = 'P0001';
  end if;

  -- Already in, pooled, or invited: nothing to ask for.
  if exists (select 1 from public.registrations r
              where r.clinic_id = p_clinic and r.player_id = p_player
                and r.status <> 'canceled') then
    raise exception 'already_registered' using errcode = 'P0001';
  end if;

  -- Her condition, verbatim: "assuming there is space and it isn't full".
  select count(*) into v_taken from public.registrations
   where clinic_id = p_clinic and status = 'in';
  if v_taken >= c.internal_capacity then
    raise exception 'clinic_full' using errcode = 'P0001';
  end if;

  insert into public.late_requests (clinic_id, player_id, message)
  values (p_clinic, p_player, nullif(btrim(coalesce(p_message, '')), ''))
  returning * into v_req;

  -- Tell every admin. This is the "direct message" from her side.
  select p.first_name || ' ' || p.last_name into v_name
    from public.players p where p.id = p_player;

  -- admin_account_ids() returns SETOF uuid, so it is selected FROM, not
  -- unnested. Matches how respond_to_invitation already fans out to admins.
  for v_admin in select public.admin_account_ids() loop
    perform public.notify_account(
      v_admin, 'LATE_REQUEST', 'clinic', p_clinic,
      v_name || ' is asking to join ' || c.name || '.'
      || coalesce(' "' || v_req.message || '"', ''));
  end loop;

  return v_req;
end;
$$;

comment on function public.request_late_spot(uuid, uuid, text) is
  'A player asks Tara to let them into a clinic after registration has closed. '
  'Only inside the closed window, only before the clinic starts, only when it is '
  'not full. Creates a request for her to approve or decline; never a '
  'registration (hard rule 2).';

-- ----------------------------------------------------------------- admin ----

create or replace function public.resolve_late_request(
  p_request uuid,
  p_approve boolean
) returns public.late_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_req   public.late_requests;
  c       public.clinics;
  v_taken int;
  v_acct  uuid;
begin
  perform public.require_admin();

  -- Hard rule 3: conditional transition. Two taps cannot place someone twice,
  -- and resolving an already-resolved request is a no-op rather than a second
  -- registration.
  update public.late_requests
     set status      = case when p_approve then 'approved' else 'declined' end,
         resolved_at = now(),
         resolved_by = auth.uid()
   where id = p_request and status = 'pending'
  returning * into v_req;

  if not found then
    raise exception 'request_not_pending' using errcode = 'P0001';
  end if;

  select * into c from public.clinics where id = v_req.clinic_id;

  if p_approve then
    -- Re-check capacity at approval time. The request was made when there was
    -- room; someone else may have been placed since.
    select count(*) into v_taken from public.registrations
     where clinic_id = v_req.clinic_id and status = 'in';
    if v_taken >= c.internal_capacity then
      raise exception 'clinic_full' using errcode = 'P0001';
    end if;

    perform public.place_player(v_req.clinic_id, v_req.player_id, 'in');
  end if;

  select p.account_id into v_acct from public.players p where p.id = v_req.player_id;
  if v_acct is not null then
    perform public.notify_account(
      v_acct,
      case when p_approve then 'LATE_REQUEST_APPROVED' else 'LATE_REQUEST_DECLINED' end,
      'clinic', v_req.clinic_id,
      case when p_approve
           then 'You''re in for ' || c.name || '.'
           else 'Tara couldn''t fit you into ' || c.name || ' this time.' end);
  end if;

  return v_req;
end;
$$;

comment on function public.resolve_late_request(uuid, boolean) is
  'Tara approves or declines a late request. Approving places the player via '
  'place_player after re-checking capacity, because the clinic may have filled '
  'since they asked.';

revoke all on function public.request_late_spot(uuid, uuid, text) from public, anon, authenticated;
revoke all on function public.resolve_late_request(uuid, boolean) from public, anon, authenticated;
grant execute on function public.request_late_spot(uuid, uuid, text) to authenticated;
grant execute on function public.resolve_late_request(uuid, boolean) to authenticated;
