-- 20261127000003_private_clinics.sql
--
-- Private clinics (decision 0062).
--
-- Tara, 2026-11-23: "private events/clinics and allow me to privately invite
-- people to that clinic for payment. Maybe I still can do this actually but
-- not 'publish' it?" She could not: admin_invite_player refuses a clinic
-- that is not published (clinic_not_published, because a player could not
-- open the invitation), and a published clinic is listed to every member.
-- John approved a Private switch.
--
--   * clinics.is_private, false for every clinic until she switches it.
--     Set only by admin_set_clinic_private (Tara's phone and laptop), not by
--     admin_upsert_clinic, whose signature both clients call positionally.
--   * clinics_public lists a private clinic only to an account with a player
--     on it in You're In!, Waitlist or Response Needed. Every other rule of
--     the view (canceled only for who was on it, no juniors, Ladies/Men by
--     gender, the level column) is 20261120000002's, unchanged.
--   * register_for_clinic (so the Waitlist too: joining it is a registration
--     that lands in pool) and request_late_spot refuse a private clinic to a
--     player not on it with clinic_not_found, the unpublished clinic's
--     answer, so the refusal does not say it exists. Tara is exempt in
--     register_for_clinic as she is from its other rules.
--   * Unchanged, and meant to work on a private clinic: admin_invite_player,
--     place_player, invite_from_pool, guests, messages, charging,
--     respond_to_invitation, cancel_registration, the calendar feed,
--     my_registrations and my_past_clinics (all read the player's own
--     registrations, never the list).
--   * A player's own call never puts anyone on a private clinic, not even
--     someone already on it (already_registered, as any second sign-up), so
--     a removal racing a sign-up cannot let them back on.
--   * Pros keep seeing a private clinic in their week (pro_week, pro_today,
--     the rounds): they are staff working it, as Tara is, not players.
--   * Nothing broadcasts a clinic: publish_clinic tells nobody, and every
--     notification about a clinic goes to who is on it. The switch itself
--     tells nobody either way.
--   * admin_copy_week carries the flag to the copy, so a private event copied
--     with the week is not listed to everyone the day she publishes it.
--   * clinics_admin shows is_private.
--
-- register_for_clinic is 20261125000001's body, request_late_spot is
-- 20261125000002's (keeping its FOR SHARE) and admin_copy_week is
-- 20260928800002's, each with only the marked lines added.
-- Pinned by tests/sql/private_clinics.sql.

alter table public.clinics add column is_private boolean not null default false;
comment on column public.clinics.is_private is
  'Decision 0062: listed only to who is on it, and nobody else can register. Set only by admin_set_clinic_private.';

create or replace function public.admin_set_clinic_private(p_clinic uuid, p_private boolean)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  if p_private is null then
    raise exception 'invalid_value' using errcode = 'P0001';
  end if;
  -- An UPDATE takes the clinic row's lock, the one register_for_clinic
  -- (FOR UPDATE) and request_late_spot (FOR SHARE) take: a sign-up lands
  -- wholly before the switch or reads it after.
  update public.clinics set is_private = p_private where id = p_clinic;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  return p_private;
end;
$$;
comment on function public.admin_set_clinic_private(uuid, boolean) is
  'Admin only (decision 0062). Makes a clinic private (listed only to who is on it) or not. Tells nobody.';
revoke all on function public.admin_set_clinic_private(uuid, boolean) from public, anon, authenticated;
grant execute on function public.admin_set_clinic_private(uuid, boolean) to authenticated;

-- 20261120000002's view with one condition added at the end. Same columns,
-- so the grants and owner rights carry over; restated below all the same.
create or replace view public.clinics_public as
  select id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         status, canceled_at, member_price_cents, nonmember_price_cents,
         duration_minutes,
         (case when public.level_check_enabled() then min_rating end)::numeric(2,1) as min_rating
    from public.clinics c
   where (c.status = 'published'
          or (c.status = 'canceled' and c.published_at is not null
              and exists (select 1 from public.registrations r
                            join public.players p on p.id = r.player_id
                           where r.clinic_id = c.id and p.account_id = auth.uid())))
     and c.ends_at > now()
     -- Juniors clinics are read through the family functions (phase 1 and
     -- 2): an app that cannot register a child would only show a Register
     -- button that wrong_player_kind refuses.
     and c.audience <> 'juniors'
     and (
       c.audience not in ('ladies', 'men')
       or not exists (select 1 from public.players p
                       where p.account_id = auth.uid() and p.kind = 'adult')
       or exists (select 1 from public.players p
                   where p.account_id = auth.uid() and p.kind = 'adult'
                     and public.audience_open_to(c.audience, p.gender))
       or exists (select 1 from public.registrations r
                    join public.players p on p.id = r.player_id
                   where r.clinic_id = c.id and p.account_id = auth.uid() and p.kind = 'adult')
     )
     -- 20261127000003, decision 0062: a private clinic only for an account
     -- with a player Tara put on it (or who was on it before she switched).
     and (not c.is_private
          or exists (select 1 from public.registrations r
                       join public.players p on p.id = r.player_id
                      where r.clinic_id = c.id and p.account_id = auth.uid()
                        and r.status in ('in', 'pool', 'response_needed')));

revoke all on public.clinics_public from public, anon, authenticated;
grant select on public.clinics_public to authenticated;

-- 20261107000004's view with is_private appended (a view can only gain
-- columns at the end).
create or replace view public.clinics_admin as
  select id, template_id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         internal_capacity, status, canceled_at, created_at,
         member_price_cents, nonmember_price_cents, duration_minutes,
         (case when public.level_check_enabled() then min_rating end)::numeric(2,1) as min_rating,
         rain_half,
         is_private
    from public.clinics
   where public.is_admin();
revoke all on public.clinics_admin from public, anon, authenticated;
grant select on public.clinics_admin to authenticated;

CREATE OR REPLACE FUNCTION public.register_for_clinic(p_clinic uuid, p_player uuid, p_note text DEFAULT NULL::text)
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
  v_kind   public.player_kind;
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
  -- 20261127000003, decision 0062: a private clinic is Tara's to fill, so a
  -- player's own call never inserts. To anyone she has not put on it, it
  -- answers as an unpublished one does, so the refusal does not say it
  -- exists; to someone on it, as any second registration does. Never "on it,
  -- so go ahead": a removal committing between this check and the insert
  -- would let them back on (the sql-auditor, 2026-11-27). Read under the FOR
  -- UPDATE above, so a switch in flight (an UPDATE of this row) is seen whole.
  if c.is_private and not public.is_admin() then
    if exists (select 1 from public.registrations r
                where r.clinic_id = p_clinic and r.player_id = p_player
                  and r.status in ('in', 'pool', 'response_needed')) then
      raise exception 'already_registered' using errcode = 'P0001';
    end if;
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;

  if c.closes_at is not null and now() >= c.closes_at then
    raise exception 'registration_closed' using errcode = 'P0001';
  end if;

  -- An archived child (one the parent removed) holds nothing
  -- (20261118000002). An adult is read as before, active or not, and Tara
  -- places anyone. FOR KEY SHARE: remove_my_child takes the row FOR UPDATE,
  -- so a removal and a registration are one after the other, while Tara's
  -- membership switch (a plain UPDATE) does not wait on it.
  select is_member, account_id, kind into v_member, v_account, v_kind
    from public.players
   where id = p_player and (is_active or kind = 'adult' or public.is_admin())
   for key share;
  if v_member is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;
  -- A child in an adult clinic, or an adult in a juniors one, hears that
  -- first: guard_player_kind's answer (20261115000001), before any waiver
  -- or card question that would not apply anyway.
  if not public.is_admin() and (v_kind = 'junior') <> (c.audience = 'juniors') then
    raise exception 'wrong_player_kind' using errcode = 'P0001';
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
  -- An adult signs the adult waiver; a child needs the parent's signature
  -- on the junior waiver for that child (decision 0061, 20261118000002),
  -- and while no junior text is published a child holds no spot at all,
  -- with its own error so the gap is never mistaken for the parent's.
  if not public.is_admin() then
    if v_kind = 'junior' then
      if public.junior_waiver_version() is null then
        raise exception 'junior_waiver_not_available' using errcode = 'P0001';
      elsif not public.junior_waiver_signed(p_player) then
        raise exception 'junior_waiver_required' using errcode = 'P0001';
      end if;
    elsif not public.waiver_accepted(v_account) then
      raise exception 'waiver_required' using errcode = 'P0001';
    end if;
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
  -- Switched off since 2026-11-25 (app_settings.double_105_rule_enabled):
  -- Tara, 2026-11-24, "let's allow them to register for both 105's. I'll
  -- control whether or not they do both or not."
  if not v_member and not public.is_admin() and public.double_105_rule_enabled()
     and public.is_105(c.name, c.category) then
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

revoke all on function public.register_for_clinic(uuid, uuid, text) from public, anon;
grant execute on function public.register_for_clinic(uuid, uuid, text) to authenticated;

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
  v_kind   public.player_kind;
begin
  if not public.owns_player(p_player) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  -- 20261118000002: an archived child asks for nothing (FOR KEY SHARE,
  -- against remove_my_child's FOR UPDATE), and a child only with a
  -- signature on the current junior waiver, as register_for_clinic. An
  -- adult is unchanged.
  select kind into v_kind from public.players
   where id = p_player and (is_active or kind = 'adult')
   for key share;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  -- 20261125000002: FOR SHARE, as respond_to_invitation. A cancel in flight
  -- (an UPDATE of this row) makes the request wait and then see 'canceled';
  -- a request in flight makes the cancel wait, and the cancel's own
  -- statements then see it, tell the player and close it. Without it a
  -- request filed while Tara canceled stayed pending, untold
  -- (tests/sql/late_request_cancel_race.sh).
  select * into c from public.clinics where id = p_clinic for share;
  if not found or c.status <> 'published' then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  -- 20261127000003, decision 0062: a private clinic takes no request.
  -- Anyone not on it hears what an unpublished clinic says; someone on it,
  -- what they would hear below (register_for_clinic's rule).
  if c.is_private then
    if exists (select 1 from public.registrations r
                where r.clinic_id = p_clinic and r.player_id = p_player
                  and r.status in ('in', 'pool', 'response_needed')) then
      raise exception 'already_registered' using errcode = 'P0001';
    end if;
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if c.canceled_at is not null then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  -- As register_for_clinic: the kind first, then the child's waiver.
  if (v_kind = 'junior') <> (c.audience = 'juniors') then
    raise exception 'wrong_player_kind' using errcode = 'P0001';
  end if;
  if v_kind = 'junior' then
    if public.junior_waiver_version() is null then
      raise exception 'junior_waiver_not_available' using errcode = 'P0001';
    elsif not public.junior_waiver_signed(p_player) then
      raise exception 'junior_waiver_required' using errcode = 'P0001';
    end if;
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

revoke all on function public.request_late_spot(uuid, uuid, text) from public, anon;
grant execute on function public.request_late_spot(uuid, uuid, text) to authenticated;

create or replace function public.admin_copy_week(p_week_start date)
returns table (created integer, skipped integer)
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_created integer;
  v_sources integer;
begin
  perform public.require_admin();

  if p_week_start is null or extract(dow from p_week_start) <> 0 then
    raise exception 'not_a_sunday' using errcode = '22023';
  end if;

  -- One copy into a given week at a time. Taken before any read, so a second
  -- call waits here and then reads what the first committed.
  perform pg_advisory_xact_lock(hashtextextended('copy_week:' || (p_week_start + 7)::text, 0));

  with src as (
    select c.template_id, c.name, c.audience, c.category, c.description,
           c.duration_minutes, c.internal_capacity, c.is_private,
           ((c.starts_at at time zone 'America/New_York') + interval '7 days')
             at time zone 'America/New_York' as new_starts,
           ((c.ends_at at time zone 'America/New_York') + interval '7 days')
             at time zone 'America/New_York' as new_ends,
           row_number() over (partition by c.name, c.starts_at order by c.created_at, c.id) as nth
      from public.clinics c
     where public.service_week_start(c.starts_at) = p_week_start
       and c.status <> 'canceled'
  ),
  todo as (
    select s.*
      from src s
     where s.nth > (select count(*) from public.clinics x
                     where x.name = s.name
                       and x.starts_at = s.new_starts
                       and x.status <> 'canceled')
  ),
  ins as (
    insert into public.clinics (
      template_id, name, audience, category, description,
      starts_at, ends_at, duration_minutes, internal_capacity,
      member_opens_at, public_opens_at, status, is_private)
    select t.template_id, t.name, t.audience, t.category, t.description,
           t.new_starts, t.new_ends, t.duration_minutes, t.internal_capacity,
           public.member_opens_at(t.new_starts), public.public_opens_at(t.new_starts),
           'draft', t.is_private
      from todo t
    returning 1
  )
  select (select count(*) from ins), (select count(*) from src)
    into v_created, v_sources;

  return query select v_created, v_sources - v_created;
end;
$$;

revoke all on function public.admin_copy_week(date) from public, anon, authenticated;
grant execute on function public.admin_copy_week(date) to authenticated;
