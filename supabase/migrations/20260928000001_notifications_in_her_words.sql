-- 20260928000001_notifications_in_her_words.sql
--
-- Tara's own notification words in the database, for the next TestFlight
-- build. Every player-facing sentence below is hers, verbatim from her
-- catalogue (docs/notifications.md, 2026-08-02): punctuation, capitals and the
-- missing closing period on #5 included. The admin rows (#13, #14, #15) are
-- the catalogue's wording for notices to herself ("any sensible wording").
--
--   #1  You're In            to the player, when register_for_clinic lands
--                            the registration in You're In!, and when Tara's
--                            place_player puts someone there who was not
--                            already in
--   #3  Invitation Accepted  to the player who accepts (respond_to_invitation),
--                            unless the clinic has been canceled
--   #5  Added to Player Pool to the player, when register_for_clinic lands the
--                            registration in the Player Pool
--   #6  Removed from Pool    to the player, when Tara removes someone from the
--                            Player Pool (cancel_registration by an admin who
--                            does not own the player). Server half only: no
--                            screen offers Remove on a Pool row yet (iOS has
--                            it on You're In! rows; the web admin not at all)
--   #13 #14                  "{player} accepted their spot in {clinic}." and
--                            "{player} declined {clinic} and is back in the
--                            Player Pool.", replacing "{player} accepted." and
--                            "{player} declined."
--   #15                      "{player} canceled {clinic}." replacing
--                            "{player} canceled.", with the late-fee and note
--                            suffixes exactly as before
--
-- Every new row names the registration it is about ('registration', its id),
-- which the app already opens for the player (my_registrations) and for Tara
-- (registrations_admin): notification_targets.sql.
--
-- NOT changed, deliberately: #2 (invite_from_pool) and #7 (cancel_clinic)
-- keep our words while contradictions (a) and (d) wait on her; #4, #9, #10
-- and #11 are not added; resolve_late_request is untouched.
--
-- Where the triggers are narrower than "every time the status changes", and
-- why (each pinned by notification_copy.sql):
--
--   * #1 is not sent on accepting an invitation: that is #3, and both would
--     be two pushes for one tap (finding (e)).
--   * #3 is not sent when the clinic has been canceled: respond_to_invitation
--     still accepts an invitation Tara's cancel_clinic overtook (the screen
--     opened from the invitation push keeps its Accept button), and "Your
--     spot is confirmed" would then be false. Tara still gets #13, which is
--     how she finds out. (Whether that accept should be refused at all is a
--     separate call: docs/backlog.md.)
--   * #5 is sent only by register_for_clinic, a first registration. A decline
--     and a withdrawn invitation also reach the Pool; "Thanks for
--     registering!" is wrong for both, so they send nothing (finding (i)).
--     Tara putting someone into the Pool by hand sends nothing either.
--   * #1 from place_player needs a clinic the player can open and that has
--     not started: published, starts_at in the future. A draft is invisible
--     to players (clinics_public), a canceled clinic makes "all set" false,
--     and a walk-up added after the start is already standing on the court.
--   * #1 from place_player is not sent when the placement IS Tara approving a
--     late request: resolve_late_request calls place_player and then sends
--     its own answer to the player in the same transaction, so both would be
--     two rows for one tap. Recognised by the late request this transaction
--     approved (resolved_at = now(), which is the transaction's start time).
--   * #6 is Tara's removal only. A player canceling their own Pool entry
--     sends #15 to Tara as before; Tara removing someone from You're In!
--     sends nothing, because there are no words for it yet (contradiction
--     (b), question 79).
--   * #6 needs a published clinic: from a draft the player never knew they
--     were in its Pool; from a canceled clinic they were already told.
--
-- "Not when they were already in" (place_player) needs the status before the
-- upsert, and the answer must be exact under a double tap or a player
-- registering at the same instant. So place_player now reads the clinic row
-- FOR UPDATE, the lock register_for_clinic already takes (same order: clinic,
-- then registration, so the two cannot deadlock; nothing takes a registration
-- lock and then waits for a clinic's). Any other insert of a registration for
-- the clinic waits on it too, whatever path it comes by: the foreign key's
-- check takes FOR KEY SHARE on the clinic row, which FOR UPDATE blocks
-- (measured: an insert waited out a 4-second hold). It also reads the
-- player's live row FOR UPDATE, so an Accept already in flight is waited for
-- and seen, never raced past. Both locks are pinned by place_player_race.sh.
-- Capacity is still never checked here (decision 4): the locks serialise,
-- they never refuse.
--
-- {day} and {time} are New York wall clock, as her catalogue and
-- NotificationCopy.swift render them ("Thursday", "9:00 AM"): FMDay drops the
-- blank padding to nine characters, FMHH12 drops the leading zero, and AT
-- TIME ZONE comes before to_char, so an 8:30 PM Friday clinic is not read as
-- Saturday 00:30 UTC.
--
-- Bodies built in SQL carry no hidden fact: a clinic name, its day and time
-- (all on clinics_public), nothing else. No court, count, location or other
-- player's name reaches a player's row.
--
-- Everything not named above is the current body, unchanged (register_for_clinic
-- from 20260926000001, place_player from 20260810000001, respond_to_invitation
-- and cancel_registration from 20260927300002): security definer, the pinned
-- search_path, the capacity lock and the 105 advisory lock, and every
-- conditional transition. The grants are restated exactly as they were.

-- ------------------------------------------------------ register_for_clinic --
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
  v_card   boolean;
  v_account uuid;
  v_b2b_opens timestamptz;
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
    select count(*) into v_taken
      from public.registrations
     where clinic_id = p_clinic and status = 'in';
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
      price_cents_charged, was_member, duration_minutes)
  values (p_clinic, p_player, v_status,
          case when public.owns_player(p_player) then 'self'::registration_source
                                                 else 'admin'::registration_source end,
          case when v_member then c.member_price_cents else c.nonmember_price_cents end,
          v_member,
          c.duration_minutes)
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
$$;

revoke all on function public.register_for_clinic(uuid, uuid) from public, anon;
grant execute on function public.register_for_clinic(uuid, uuid) to authenticated;

-- ------------------------------------------------------------ place_player --
create or replace function public.place_player(
  p_clinic uuid, p_player uuid, p_status registration_status default 'in')
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c         public.clinics;
  v_member  boolean;
  v_account uuid;
  v_prev    registration_status;
  v         public.registrations;
begin
  perform public.require_admin();

  if p_status not in ('in', 'pool', 'response_needed') then
    raise exception 'invalid_status' using errcode = 'P0001';
  end if;

  -- FOR UPDATE: the lock register_for_clinic takes, so a placement and a
  -- registration for this clinic (or two taps of the same placement) happen
  -- one after the other, and v_prev below is exact. It serialises; capacity
  -- still never blocks Tara.
  select * into c from public.clinics where id = p_clinic for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;

  select is_member, account_id into v_member, v_account from public.players where id = p_player;
  if v_member is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  -- Where the player stood before this placement, locked so that their own
  -- Accept landing at the same moment waits for it rather than racing it.
  select status into v_prev from public.registrations
   where clinic_id = p_clinic and player_id = p_player
     and status in ('in', 'pool', 'response_needed')
   for update;

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

  -- #1 You're In, when this placement is what put them in: not when they
  -- were already in, not for a clinic they cannot open or that has started,
  -- and not when the placement is a late request Tara approved in this
  -- transaction (resolve_late_request tells them itself). Nothing for the
  -- Pool: #5 is for registering.
  if v.status = 'in' and v_prev is distinct from 'in'
     and c.status = 'published' and c.starts_at > now()
     and not exists (select 1 from public.late_requests lr
                      where lr.clinic_id = p_clinic and lr.player_id = p_player
                        and lr.status = 'approved' and lr.resolved_at = now()) then
    perform public.notify_account(v_account, 'youre_in', 'registration', v.id,
      'You''re all set for ' || c.name || ' on '
      || to_char(c.starts_at at time zone 'America/New_York', 'FMDay') || ' at '
      || to_char(c.starts_at at time zone 'America/New_York', 'FMHH12:MI AM')
      || '. Looking forward to seeing you on court!');
  end if;

  return v;
end;
$$;

revoke all on function public.place_player(uuid, uuid, registration_status) from public, anon;
grant execute on function public.place_player(uuid, uuid, registration_status) to authenticated;

-- --------------------------------------------------- respond_to_invitation --
create or replace function public.respond_to_invitation(p_registration uuid, p_accept boolean)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row    public.registrations;
  v_player public.players;
  v_admin  uuid;
  v_clinic text;
  v_clinic_status clinic_status;
begin
  select * into v_row from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not public.owns_player(v_row.player_id) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  update public.registrations
     set status = case when p_accept then 'in'::registration_status
                                     else 'pool'::registration_status end,
         responded_at = now()
   where id = p_registration
     and status = 'response_needed'
  returning * into v_row;

  if not found then
    raise exception 'invitation_no_longer_available' using errcode = 'P0001';
  end if;

  select * into v_player from public.players where id = v_row.player_id;
  select name, status into v_clinic, v_clinic_status from public.clinics where id = v_row.clinic_id;
  -- #13 and #14, the catalogue's wording, to every admin.
  for v_admin in select public.admin_account_ids() loop
    perform public.notify_account(
      v_admin, case when p_accept then 'invitation_accepted' else 'invitation_declined' end,
      'registration', v_row.id,
      v_player.first_name || ' ' || v_player.last_name
        || case when p_accept then ' accepted their spot in ' || v_clinic || '.'
                else ' declined ' || v_clinic || ' and is back in the Player Pool.' end);
  end loop;

  -- #3 Invitation Accepted, hers, to the player who accepted. Not #1 as well:
  -- one tap, one push (finding (e)). Not when Tara has canceled the clinic:
  -- "Your spot is confirmed" would be false (#13 still tells her). A decline
  -- sends the player nothing: it is not a first registration, so not #5
  -- (finding (i)).
  if p_accept and v_clinic_status <> 'canceled' then
    perform public.notify_account(v_player.account_id, 'invitation_accepted_player', 'registration', v_row.id,
      'Awesome! Your spot is confirmed. See you soon!');
  end if;

  -- What goes back to a player carries no court (hard rule 1, fact 6).
  if not public.is_admin() then
    v_row.court_number := null;
    v_row.canceled_by  := null;
  end if;

  return v_row;
end;
$$;

revoke all on function public.respond_to_invitation(uuid, boolean) from public, anon;
grant execute on function public.respond_to_invitation(uuid, boolean) to authenticated;

-- ----------------------------------------------------- cancel_registration --
create or replace function public.cancel_registration(p_registration uuid, p_note text default null)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row      public.registrations;
  v_player   public.players;
  v_admin    uuid;
  v_starts   timestamptz;
  v_late     boolean := false;
  v_courtesy boolean := false;
  v_note     text := nullif(btrim(coalesce(p_note, '')), '');
  v_prev     registration_status;
  v_clinic   text;
  v_clinic_status clinic_status;
begin
  select * into v_row from public.registrations where id = p_registration for update;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not (public.owns_player(v_row.player_id) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  -- Held under the row lock above, so it is the status this cancel ends.
  v_prev := v_row.status;

  -- Tara removing someone else's charged spot: refund first (M4).
  if not public.owns_player(v_row.player_id) and public.registration_has_live_fee(p_registration) then
    raise exception 'charged_refund_first' using errcode = 'P0001';
  end if;

  select starts_at, name, status into v_starts, v_clinic, v_clinic_status
    from public.clinics where id = v_row.clinic_id;
  if v_row.status = 'in' and not public.is_admin()
     and v_starts - now() < make_interval(hours => public.cancel_cutoff_hours()) then
    v_late := true;
    v_courtesy := public.courtesy_available(v_row.player_id);
  end if;

  update public.registrations
     set status = 'canceled', canceled_at = now(), canceled_by = auth.uid(),
         late_cancel = v_late,
         courtesy_used = v_courtesy,
         cancel_note = case when v_late then left(v_note, 280) else null end
   where id = p_registration
     and status in ('in', 'pool', 'response_needed')
  returning * into v_row;

  if not found then
    raise exception 'already_canceled' using errcode = 'P0001';
  end if;

  select * into v_player from public.players where id = v_row.player_id;

  -- The admins hear about a player's OWN cancellation (#15, the catalogue's
  -- "{player} canceled {clinic}.", suffixes unchanged). An admin removing
  -- someone else already knows: that notice read as the player's act.
  if public.owns_player(v_row.player_id) then
    for v_admin in select public.admin_account_ids() loop
      perform public.notify_account(v_admin, 'player_canceled', 'registration', v_row.id,
        v_player.first_name || ' ' || v_player.last_name || ' canceled ' || v_clinic || '.'
        || case when v_late and v_courtesy then ' Late, courtesy used.'
                when v_late then ' Late, fee applies.'
                else '' end
        || case when v_row.cancel_note is not null then ' Note: "' || v_row.cancel_note || '"' else '' end);
    end loop;
  -- Tara removed someone from the Player Pool of a published clinic: her #6,
  -- to them. Removal from You're In! sends nothing: she has no words for it.
  elsif v_prev = 'pool' and v_clinic_status = 'published' then
    perform public.notify_account(v_player.account_id, 'removed_from_pool', 'registration', v_row.id,
      'You''ve been removed from the Player Pool for ' || v_clinic
      || '. Hope to see you at another clinic soon!');
  end if;

  -- What goes back to a player carries no court and no canceler (M6).
  if not public.is_admin() then
    v_row.court_number := null;
    v_row.canceled_by  := null;
  end if;

  return v_row;
end;
$$;

revoke all on function public.cancel_registration(uuid, text) from public, anon;
grant execute on function public.cancel_registration(uuid, text) to authenticated;
