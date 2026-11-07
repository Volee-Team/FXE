-- 20261107000002_tara_next_update.sql
--
-- Tara's "Next update (notes taken 11/6/26)", items 1, 2, 5 and 6, relayed by
-- John 2026-11-07 ("yeah start on 5, 1, 6 and 2"). Item 5 (the "clinic is
-- full" question before an invite) is the apps' alone: the counts are already
-- on Tara's screen, and capacity never blocks her (place_player).
--
-- 1. "Allow me to send a message to anyone whenever they are (meaning in a
--    clinic, not registered, on a waitlist, etc)" and "option to message
--    individual": admin_message_player. From a clinic's roster it is kept on
--    that clinic like her group messages (audience 'player', one recipient
--    row, so my_clinic_messages shows it to that player and nobody else);
--    from the Players tab it is a notification only.
-- 2. "Allow me to invite anyone to a clinic that is not on a waitlist":
--    admin_invite_player. Always an invitation (Response Needed + "A spot
--    opened in ... Accept or decline."), never a placement: they did not ask
--    to come. Marked source 'invite', so a decline ends it (status canceled)
--    instead of putting them on a Waitlist they never joined, and Tara's
--    notice drops "and is back on the Waitlist". The same for Tara's
--    Cancel Invite (cancel_invitation: canceled, not the Waitlist, from which
--    Move In would put them straight in without their yes), and a decline is
--    not counted as their cancel in her history (canceled_by left empty).
--    place_player moving an invited player anywhere but Response Needed makes
--    the row hers (source 'admin'). Only someone who has signed the waiver:
--    Accept does not ask, register_for_clinic does. (The sql-auditor's
--    findings, 2026-11-07.)
-- 6. "Allow pros to have access to the week ahead and what players are
--    signed up ... their ONLY capabilities are to assign courts and see who is
--    in the clinic": pro_week (pro_today's columns, today and the six days
--    after, New York dates) and pro_assign_court (You're In! rows of those
--    clinics only; returns nothing, decision 0025's rule against handing a
--    pro a registrations row). pro_today, pro_set_no_show and
--    pro_mark_late_cancel are unchanged: the 1.0.x apps still call them.

alter type public.message_audience add value if not exists 'player';
alter type public.registration_source add value if not exists 'invite';

-- ------------------------------------------------------------------ 1
-- The group sender must not take 'player': it would store a message with no
-- recipient that nobody can read.
create or replace function public.send_clinic_message(p_clinic uuid, p_audience message_audience, p_body text)
 returns clinic_messages
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare m public.clinic_messages; r record;
begin
  perform public.require_admin();
  if p_audience::text = 'player' then
    raise exception 'invalid_audience' using errcode = 'P0001';
  end if;

  insert into public.clinic_messages (clinic_id, audience, body)
  values (p_clinic, p_audience, p_body)
  returning * into m;

  for r in
    select reg.player_id, p.account_id
      from public.registrations reg
      join public.players p on p.id = reg.player_id
     where reg.clinic_id = p_clinic
       and reg.status <> 'canceled'
       and (
         p_audience = 'everyone'
         or (p_audience = 'in'              and reg.status = 'in')
         or (p_audience = 'pool'            and reg.status = 'pool')
         or (p_audience = 'response_needed' and reg.status = 'response_needed')
         or (p_audience = 'unpaid'          and reg.paid = false and reg.status = 'in')
       )
  loop
    if p_audience <> 'everyone' then
      insert into public.clinic_message_recipients (message_id, player_id)
      values (m.id, r.player_id) on conflict do nothing;
    end if;
    perform public.notify_account(r.account_id, 'clinic_message', 'clinic', p_clinic, p_body);
  end loop;

  return m;
end;
$function$;

create or replace function public.admin_message_player(p_player uuid, p_body text, p_clinic uuid default null)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_account uuid;
  v_body    text := btrim(coalesce(p_body, ''));
  m         public.clinic_messages;
begin
  perform public.require_admin();
  if v_body = '' then
    raise exception 'message_empty' using errcode = 'P0001';
  end if;
  if length(v_body) > 2000 then
    raise exception 'message_too_long' using errcode = 'P0001';
  end if;

  -- A live account only: a deleted player's row has nobody to tell.
  select p.account_id into v_account
    from public.players p join public.accounts a on a.id = p.account_id
   where p.id = p_player and a.deleted_at is null;
  if v_account is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  if p_clinic is null then
    perform public.notify_account(v_account, 'clinic_message', 'player', p_player, v_body);
    return;
  end if;

  -- On a clinic: only someone on it (not canceled), and only a clinic they
  -- can open, so the message is never about a page they cannot see.
  if not exists (select 1 from public.clinics where id = p_clinic and status in ('published', 'canceled')) then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if not exists (select 1 from public.registrations
                  where clinic_id = p_clinic and player_id = p_player and status <> 'canceled') then
    raise exception 'player_not_on_clinic' using errcode = 'P0001';
  end if;
  insert into public.clinic_messages (clinic_id, audience, body)
  values (p_clinic, 'player', v_body)
  returning * into m;
  insert into public.clinic_message_recipients (message_id, player_id)
  values (m.id, p_player);
  perform public.notify_account(v_account, 'clinic_message', 'clinic', p_clinic, v_body);
end;
$function$;

-- ------------------------------------------------------------------ 2
create or replace function public.admin_invite_player(p_clinic uuid, p_player uuid)
 returns registrations
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  c         public.clinics;
  v_member  boolean;
  v_account uuid;
  v_status  registration_status;
  v         public.registrations;
begin
  perform public.require_admin();

  -- The lock register_for_clinic and place_player take, so this and a
  -- registration by the same player happen one after the other.
  select * into c from public.clinics where id = p_clinic for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  -- A draft is invisible to players: an invitation to it could not be opened.
  if c.status <> 'published' then
    raise exception 'clinic_not_published' using errcode = 'P0001';
  end if;
  if c.ends_at <= now() then
    raise exception 'clinic_ended' using errcode = 'P0001';
  end if;

  select p.is_member, p.account_id into v_member, v_account
    from public.players p join public.accounts a on a.id = p.account_id
   where p.id = p_player and a.deleted_at is null;
  if v_member is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  -- Accept is the player's own tap, often from the lock screen, and
  -- respond_to_invitation does not ask for the waiver: register_for_clinic
  -- does. Someone invited who never asked to come must have signed it
  -- (decision 0013 §4; the sql-auditor, 2026-11-07).
  if not public.waiver_accepted(v_account) then
    raise exception 'waiver_required' using errcode = 'P0001';
  end if;

  -- Already In, on the Waitlist or invited: her other buttons are for that.
  select status into v_status from public.registrations
   where clinic_id = p_clinic and player_id = p_player
     and status in ('in', 'pool', 'response_needed');
  if found then
    raise exception 'already_registered' using errcode = 'P0001', hint = v_status::text;
  end if;

  insert into public.registrations (
      clinic_id, player_id, status, source, invited_at,
      price_cents_charged, was_member, duration_minutes)
  values (p_clinic, p_player, 'response_needed', 'invite', now(),
          case when v_member then c.member_price_cents else c.nonmember_price_cents end,
          v_member, c.duration_minutes)
  returning * into v;

  -- Her words for an invitation (#2 in the catalogue), the same as from the
  -- Waitlist.
  perform public.notify_account(v_account, 'invitation_received', 'registration', v.id,
    'A spot opened in ' || c.name || '. Accept or decline.');

  return v;
end;
$function$;

create or replace function public.respond_to_invitation(p_registration uuid, p_accept boolean)
 RETURNS registrations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row    public.registrations;
  v_player public.players;
  v_admin  uuid;
  v_clinic text;
  v_clinic_status clinic_status;
  v_ends  timestamptz;
  v_declined boolean;
  v_decline_code text;
  v_card   boolean;
begin
  select * into v_row from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not public.owns_player(v_row.player_id) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  -- Accepting a canceled clinic put a player in You're In! of a clinic that
  -- is not happening (backlog, 2026-09-28): the invitation's own Accept
  -- button on the lock screen never sees the clinic page's canceled banner.
  -- The clinic row is locked FOR SHARE first, so cancel_clinic (an UPDATE of
  -- that row) and this answer are serialized: whichever commits first, the
  -- other sees it. Declining a canceled clinic stays allowed; it changes
  -- nothing that matters.
  select status, ends_at into v_clinic_status, v_ends
    from public.clinics where id = v_row.clinic_id
     for share;
  if p_accept and v_clinic_status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  -- A finished clinic cannot be joined (20260928400001). Invitations never
  -- expire (hard rule 2), and since decision 0023 the Accept sits on a push
  -- that can be tapped days later: without this the player landed in You're
  -- In! of a clinic that was over and was charged at Tara's next tap. The
  -- line is the END, which nobody can argue with; whether it should be the
  -- start is question 91.
  if p_accept and v_ends <= now() then
    raise exception 'clinic_ended' using errcode = 'P0001';
  end if;
  -- Decision 0024, Tara's question 78: a declined card takes no spot, by
  -- Register or by Accept, while cards are required (the switches
  -- register_for_clinic reads). Decline stays allowed: it takes nothing.
  -- Checked before the conditional UPDATE, so nothing moves (20260928700001).
  if p_accept and not public.is_admin()
     and public.payments_enabled() and public.card_required() then
    -- Tara's question 107 (2026-10-12): "Yes", Accept needs a saved card,
    -- the same summary register_for_clinic reads (card_last4, decision 0015
    -- §5). Checked before the conditional UPDATE, so nothing moves.
    select a.stripe_customer_id is not null and a.card_last4 is not null into v_card
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = v_row.player_id;
    if not coalesce(v_card, false) then
      raise exception 'card_required' using errcode = 'P0001';
    end if;
    select a.card_declined_at is not null, a.card_decline_code into v_declined, v_decline_code
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = v_row.player_id;
    if coalesce(v_declined, false) then
      raise exception 'card_declined' using errcode = 'P0001', hint = coalesce(v_decline_code, '');
    end if;
  end if;

  update public.registrations
     set status = case when p_accept then 'in'::registration_status
                       -- An invitation Tara sent to someone who never asked
                       -- (source 'invite', 20261107000002): a decline ends
                       -- it, instead of putting them on a Waitlist they never
                       -- joined.
                       when source = 'invite' then 'canceled'::registration_status
                       else 'pool'::registration_status end,
         responded_at = now(),
         canceled_at  = case when not p_accept and source = 'invite' then now() else canceled_at end,
         -- Left empty: a decline is not a cancel, so Tara's history line
         -- ("2 canceled", admin_player_history counts canceled_by = the
         -- player) does not count it (the sql-auditor, 2026-11-07).
         canceled_by  = case when not p_accept and source = 'invite' then null else canceled_by end
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
                when v_row.status = 'canceled' then ' declined ' || v_clinic || '.'
                else ' declined ' || v_clinic || ' and is back on the Waitlist.' end);
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
$function$;

-- Withdrawing an invite, and Tara placing an invited player.
create or replace function public.cancel_invitation(p_registration uuid)
 RETURNS registrations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v public.registrations; v_account uuid;
begin
  perform public.require_admin();
  -- An invitation to someone who never asked to come (source 'invite',
  -- 20261107000002) ends when withdrawn; it does not put them on a Waitlist
  -- they never joined, from which Move In would put them straight in (the
  -- sql-auditor, 2026-11-07). Canceled by Tara, so not theirs in the history.
  update public.registrations
     set status      = case when source = 'invite' then 'canceled'::registration_status else 'pool'::registration_status end,
         invited_at  = case when source = 'invite' then invited_at else null end,
         canceled_at = case when source = 'invite' then now() else canceled_at end,
         canceled_by = case when source = 'invite' then auth.uid() else canceled_by end
   where id = p_registration and status = 'response_needed'
  returning * into v;
  if not found then
    -- The player accepted or declined first. Not an error worth alarming
    -- about, but the caller must know it did not happen.
    raise exception 'invitation_already_answered' using errcode = 'P0001';
  end if;

  select account_id into v_account from public.players where id = v.player_id;
  if v_account is not null then
    perform public.notify_account(v_account, 'invitation_withdrawn', 'registration', v.id,
      'The levels didn’t line up for this clinic, so we’ve released your spot. We keep each court close in level so everyone gets a great practice. We’ll catch you at the next clinic!');
  end if;
  return v;
end;
$function$;

create or replace function public.place_player(p_clinic uuid, p_player uuid, p_status registration_status DEFAULT 'in'::registration_status)
 RETURNS registrations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  -- Tara moving an invitation (source 'invite') anywhere but Response Needed
  -- makes it hers: a later decline goes back to the Waitlist like any other
  -- (20261107000002).
  do update set status = excluded.status,
                source = case when registrations.source = 'invite' and excluded.status <> 'response_needed'
                              then 'admin'::registration_source else registrations.source end
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
$function$;

-- ------------------------------------------------------------------ 6
create or replace function public.pro_week()
 returns table(clinic_id uuid, clinic_name text, starts_at timestamp with time zone, ends_at timestamp with time zone,
               registration_id uuid, first_name text, last_name text, court_number smallint,
               no_show boolean, late_cancel boolean)
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  perform public.require_pro();
  -- pro_today's columns exactly (decision 0025: the column list is the
  -- contract), for today and the six New York days after it.
  return query
    select c.id, c.name, c.starts_at, c.ends_at,
           r.id, p.first_name, p.last_name, r.court_number, r.no_show, r.late_cancel
      from public.clinics c
      left join public.registrations r
             on r.clinic_id = c.id and r.status = 'in'
      left join public.players p on p.id = r.player_id
     where c.status = 'published'
       and public.new_york_date(c.starts_at) between public.new_york_date(now())
                                                 and public.new_york_date(now()) + 6
     order by c.starts_at, c.id, r.court_number nulls last, p.last_name, p.first_name, r.id;
end;
$function$;

create or replace function public.pro_assign_court(p_registration uuid, p_court smallint)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_clinic uuid;
  c        public.clinics;
begin
  perform public.require_pro();
  if p_court is not null and p_court not between 1 and 5 then
    raise exception 'invalid_court' using errcode = 'P0001';
  end if;
  -- Every refusal reads the same, so a pro learns nothing about a row outside
  -- the week's You're In! lists (not even that it exists).
  select r.clinic_id into v_clinic from public.registrations r
   where r.id = p_registration and r.status = 'in';
  if not found then
    raise exception 'not_this_week' using errcode = 'P0001';
  end if;
  select * into c from public.clinics where id = v_clinic for share;
  if c.status <> 'published'
     or public.new_york_date(c.starts_at) not between public.new_york_date(now())
                                                  and public.new_york_date(now()) + 6 then
    raise exception 'not_this_week' using errcode = 'P0001';
  end if;
  update public.registrations set court_number = p_court
   where id = p_registration and status = 'in';
  if not found then
    raise exception 'not_this_week' using errcode = 'P0001';
  end if;
end;
$function$;

revoke all on function public.send_clinic_message(uuid, message_audience, text) from public, anon;
grant execute on function public.send_clinic_message(uuid, message_audience, text) to authenticated;
revoke all on function public.admin_message_player(uuid, text, uuid) from public, anon;
grant execute on function public.admin_message_player(uuid, text, uuid) to authenticated;
revoke all on function public.admin_invite_player(uuid, uuid) from public, anon;
grant execute on function public.admin_invite_player(uuid, uuid) to authenticated;
revoke all on function public.respond_to_invitation(uuid, boolean) from public, anon;
grant execute on function public.respond_to_invitation(uuid, boolean) to authenticated;
revoke all on function public.cancel_invitation(uuid) from public, anon;
grant execute on function public.cancel_invitation(uuid) to authenticated;
revoke all on function public.place_player(uuid, uuid, registration_status) from public, anon;
grant execute on function public.place_player(uuid, uuid, registration_status) to authenticated;
revoke all on function public.pro_week() from public, anon;
grant execute on function public.pro_week() to authenticated;
revoke all on function public.pro_assign_court(uuid, smallint) from public, anon;
grant execute on function public.pro_assign_court(uuid, smallint) to authenticated;
