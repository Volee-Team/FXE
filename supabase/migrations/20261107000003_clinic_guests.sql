-- 20261107000003_clinic_guests.sql
--
-- Tara's "Next update" item 4, answered 2026-11-07 (question 144): "If
-- somebody isn't in the app, I just want the capability of inputting their
-- name first and last. And then I would just take care of the payment and
-- getting from them ... I have somebody today, for instance, that wants to
-- come to the 430 coed tomorrow, but they don't want to input their credit
-- card." John: "yeah build guests now".
--
-- A guest is a name on one clinic, kept in its own table, not a player:
--   * every player row belongs to an account, and the 1.0.1 and 1.0.2 apps
--     decode players.account_id as required; a player without one would fail
--     Tara's whole roster load on her phone;
--   * a guest is never notified, never charged, never on a player's screen,
--     and never in a money report: nothing that reads registrations or players
--     sees one. Tara collects her own way.
-- Guests count toward the clinic's capacity wherever the server decides "is
-- there room" (register_for_clinic's member window, request_late_spot,
-- resolve_late_request), through clinic_taken. Removed, never deleted (hard
-- rule 4): removed_at.

create table public.clinic_guests (
  id           uuid primary key default gen_random_uuid(),
  clinic_id    uuid not null references public.clinics(id) on delete cascade,
  first_name   text not null check (length(first_name) between 1 and 60 and first_name = btrim(first_name)
                                    and first_name !~ '[[:cntrl:]]'),
  last_name    text not null check (length(last_name) between 1 and 60 and last_name = btrim(last_name)
                                    and last_name !~ '[[:cntrl:]]'),
  court_number smallint check (court_number between 1 and 5),
  added_at     timestamptz not null default now(),
  removed_at   timestamptz
);
create index clinic_guests_live on public.clinic_guests (clinic_id) where removed_at is null;
-- One live guest of a name per clinic: a retried Add (a lost response, a
-- second click after a timeout) must not take a second spot (the sql-auditor,
-- 2026-11-07).
create unique index clinic_guests_one_live_name
  on public.clinic_guests (clinic_id, lower(first_name), lower(last_name)) where removed_at is null;
alter table public.clinic_guests enable row level security;
revoke all on public.clinic_guests from public, anon, authenticated;
grant select, insert, update, delete on public.clinic_guests to service_role;
comment on table public.clinic_guests is
  'Tara''s guests (20261107000003): a first and last name on one clinic, for someone not in the app. Read and written only through the admin_* guest RPCs.';

-- You're In! plus live guests: the number every "is there room" asks.
create or replace function public.clinic_taken(p_clinic uuid)
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select (select count(*) from public.registrations where clinic_id = p_clinic and status = 'in')::integer
       + (select count(*) from public.clinic_guests where clinic_id = p_clinic and removed_at is null)::integer;
$$;
revoke all on function public.clinic_taken(uuid) from public, anon, authenticated;

create or replace function public.admin_add_guest(p_clinic uuid, p_first text, p_last text)
returns public.clinic_guests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.clinics;
  g public.clinic_guests;
  -- Spaces, tabs and line breaks off both ends; control characters inside are
  -- refused by the table's check.
  v_first text := btrim(coalesce(p_first, ''), E' \t\r\n');
  v_last  text := btrim(coalesce(p_last, ''), E' \t\r\n');
begin
  perform public.require_admin();
  if v_first = '' or v_last = '' then
    raise exception 'name_required' using errcode = 'P0001';
  end if;
  if length(v_first) > 60 or length(v_last) > 60 then
    raise exception 'name_too_long' using errcode = 'P0001';
  end if;
  -- The clinic's lock, as every placement takes it, so a guest and a member
  -- taking the last spot happen one after the other.
  select * into c from public.clinics where id = p_clinic for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.clinic_guests
              where clinic_id = p_clinic and removed_at is null
                and lower(first_name) = lower(v_first) and lower(last_name) = lower(v_last)) then
    raise exception 'guest_already_added' using errcode = 'P0001';
  end if;
  insert into public.clinic_guests (clinic_id, first_name, last_name)
  values (p_clinic, v_first, v_last)
  returning * into g;
  return g;
end;
$$;

create or replace function public.admin_remove_guest(p_guest uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  update public.clinic_guests set removed_at = now()
   where id = p_guest and removed_at is null;
  if not found then
    raise exception 'guest_not_found' using errcode = 'P0002';
  end if;
end;
$$;

create or replace function public.admin_set_guest_court(p_guest uuid, p_court smallint)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  if p_court is not null and p_court not between 1 and 5 then
    raise exception 'invalid_court' using errcode = 'P0001';
  end if;
  update public.clinic_guests set court_number = p_court
   where id = p_guest and removed_at is null;
  if not found then
    raise exception 'guest_not_found' using errcode = 'P0002';
  end if;
end;
$$;

-- Live guests on the clinics asked for, in the order she added them.
create or replace function public.admin_clinic_guests(p_clinics uuid[])
returns setof public.clinic_guests
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
    select * from public.clinic_guests
     where clinic_id = any(p_clinics) and removed_at is null
     order by clinic_id, added_at, id;
end;
$$;

-- The three "is there room" answers, each the live definition with its count
-- replaced by clinic_taken (hosted and local hashes matched before this).
create or replace function public.register_for_clinic(p_clinic uuid, p_player uuid, p_note text DEFAULT NULL::text)
 RETURNS registrations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c        public.clinics;
  v_member boolean;
  v_taken  integer;
  v_status registration_status;
  v_row    public.registrations;
  v_card   boolean;
  v_account uuid;
  v_b2b_opens timestamptz;
  v_declined boolean;
  v_decline_code text;
  v_note   text;
begin
  if not (public.owns_player(p_player) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  -- The note for Tara (decision 0039), checked before anything else so a
  -- note that is too long refuses cleanly instead of after the clinic lock.
  -- Only the player's own words: Tara registering someone cannot put a
  -- sentence in their mouth that they then read back as theirs.
  v_note := case when public.owns_player(p_player) then public.clean_player_note(p_note) end;

  select * into c from public.clinics
   where id = p_clinic and status = 'published'
   for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;

  if c.closes_at is not null and now() >= c.closes_at then
    raise exception 'registration_closed' using errcode = 'P0001';
  end if;

  select is_member, account_id into v_member, v_account from public.players where id = p_player;
  if v_member is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  -- Decision 0012: "Gosh I say yes." A player cannot hold a spot without a
  -- card once payments are on. Tara placing someone by hand is not blocked.
  -- A card is the summary the webhook writes after Stripe saves one
  -- (card_last4), not the customer id, which exists from the moment someone
  -- opens the card sheet, saved card or not (found 2026-09-26, decision 0015 §5).
  if public.payments_enabled() and public.card_required() and not public.is_admin() then
    select a.stripe_customer_id is not null and a.card_last4 is not null into v_card
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = p_player;
    if not coalesce(v_card, false) then
      raise exception 'card_required' using errcode = 'P0001';
    end if;
    -- Decision 0024, Tara's question 78: "Cannot sign up without proper,
    -- transactional card." A card whose last charge was declined holds no
    -- spot until a card is saved again or a later charge goes through
    -- (20260928700001). The code rides in the HINT so the app can say why.
    select a.card_declined_at is not null, a.card_decline_code into v_declined, v_decline_code
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = p_player;
    if coalesce(v_declined, false) then
      raise exception 'card_declined' using errcode = 'P0001', hint = coalesce(v_decline_code, '');
    end if;
  end if;

  -- Decision 0013 §4: the waiver is signed before the first spot is held.
  if not public.is_admin() and not public.waiver_accepted(v_account) then
    raise exception 'waiver_required' using errcode = 'P0001';
  end if;

  if now() < c.member_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif not v_member and now() < c.public_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif v_member and now() < c.public_opens_at then
    -- Decision 0050, Tara 2026-11-06: a member is in automatically only from
    -- the member open (Thursday 8am) to the public open (Friday noon), while
    -- there is room. From the public open on, the Waitlist, like everyone.
    -- You're In! and Tara's guests (20261107000003).
    v_taken := public.clinic_taken(p_clinic);
    v_status := case when v_taken < c.internal_capacity then 'in' else 'pool' end;
  else
    v_status := 'pool';
  end if;

  -- Decision 0015 §13, Tara 2026-09-26: "members can sign up for back to
  -- back 105's (same day back to back) but nonmembers cannot until 48 [hours]
  -- prior to start time of clinic." A non-member already holding a live spot
  -- in a 105 on the same New York day may take a second one only from 48
  -- hours before the earlier of the two. Tara's own placements are exempt.
  if not v_member and not public.is_admin() and public.is_105(c.name, c.category) then
    -- Two registrations by the same player for two different 105s at the same
    -- instant share no row lock (each locks only its own clinic), so both
    -- could pass this check. Serialise them per player; cannot deadlock,
    -- since each holder already has its own clinic and waits for no other.
    perform pg_advisory_xact_lock(hashtextextended('register_105:' || p_player::text, 0));
    select min(public.back_to_back_105_opens_at(c.starts_at, o.starts_at)) into v_b2b_opens
      from public.registrations r2
      join public.clinics o on o.id = r2.clinic_id
     where r2.player_id = p_player
       and r2.clinic_id <> p_clinic
       and r2.status in ('in', 'pool', 'response_needed')
       and o.status = 'published'
       and public.is_105(o.name, o.category)
       and (o.starts_at at time zone 'America/New_York')::date
         = (c.starts_at at time zone 'America/New_York')::date;
    if v_b2b_opens is not null and now() < v_b2b_opens then
      raise exception 'back_to_back_105' using errcode = 'P0001';
    end if;
  end if;

  insert into public.registrations (
      clinic_id, player_id, status, source,
      price_cents_charged, was_member, duration_minutes, player_note)
  values (p_clinic, p_player, v_status,
          case when public.owns_player(p_player) then 'self'::registration_source
                                                 else 'admin'::registration_source end,
          case when v_member then c.member_price_cents else c.nonmember_price_cents end,
          v_member,
          c.duration_minutes,
          v_note)
  returning * into v_row;

  -- Tara's words, to the player whose spot it is, whoever tapped Register.
  -- #1 You're In, with the day and time in New York; #5 Added to Player Pool,
  -- which is for a first registration only, and this insert is one.
  if v_row.status = 'in' then
    perform public.notify_account(v_account, 'youre_in', 'registration', v_row.id,
      'You''re all set for ' || c.name || ' on '
      || to_char(c.starts_at at time zone 'America/New_York', 'FMDay') || ' at '
      || to_char(c.starts_at at time zone 'America/New_York', 'FMHH12:MI AM')
      || '. Looking forward to seeing you on court!');
  elsif v_row.status = 'pool' then
    perform public.notify_account(v_account, 'added_to_pool', 'registration', v_row.id,
      'Thanks for registering! I personally create each clinic based on playing levels and will send confirmations once lineups are set ASAP');
  end if;

  return v_row;
exception
  when unique_violation then
    raise exception 'already_registered' using errcode = 'P0001';
end;
$function$;

create or replace function public.request_late_spot(p_clinic uuid, p_player uuid, p_message text DEFAULT NULL::text)
 RETURNS late_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- You're In! and Tara's guests (20261107000003).
  v_taken := public.clinic_taken(p_clinic);
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
$function$;

create or replace function public.resolve_late_request(p_request uuid, p_approve boolean)
 RETURNS late_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_req   public.late_requests;
  c       public.clinics;
  v_taken int;
  v_acct  uuid;
  v_clinic_id uuid;
begin
  perform public.require_admin();

  -- The clinic first, FOR UPDATE: place_player below takes FOR UPDATE on it
  -- too, and a FOR SHARE here would let two approvals deadlock upgrading.
  select clinic_id into v_clinic_id from public.late_requests where id = p_request;
  select * into c from public.clinics where id = v_clinic_id for update;
  if p_approve and c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;

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

  if p_approve then
    -- Re-check capacity at approval time. The request was made when there was
    -- room; someone else may have been placed since.
    -- You're In! and Tara's guests (20261107000003).
    v_taken := public.clinic_taken(v_req.clinic_id);
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
$function$;

revoke all on function public.admin_add_guest(uuid, text, text) from public, anon;
grant execute on function public.admin_add_guest(uuid, text, text) to authenticated;
revoke all on function public.admin_remove_guest(uuid) from public, anon;
grant execute on function public.admin_remove_guest(uuid) to authenticated;
revoke all on function public.admin_set_guest_court(uuid, smallint) from public, anon;
grant execute on function public.admin_set_guest_court(uuid, smallint) to authenticated;
revoke all on function public.admin_clinic_guests(uuid[]) from public, anon;
grant execute on function public.admin_clinic_guests(uuid[]) to authenticated;
revoke all on function public.register_for_clinic(p_clinic uuid, p_player uuid, p_note text) from public, anon;
grant execute on function public.register_for_clinic(p_clinic uuid, p_player uuid, p_note text) to authenticated;
revoke all on function public.request_late_spot(p_clinic uuid, p_player uuid, p_message text) from public, anon;
grant execute on function public.request_late_spot(p_clinic uuid, p_player uuid, p_message text) to authenticated;
revoke all on function public.resolve_late_request(p_request uuid, p_approve boolean) from public, anon;
grant execute on function public.resolve_late_request(p_request uuid, p_approve boolean) to authenticated;
