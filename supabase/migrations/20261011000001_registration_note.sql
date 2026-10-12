-- 20261011000001_registration_note.sql
--
-- Tara, 2026-10-11 (through Alex): "When people register for the clinics,
-- can there be a private note they can put when they register? So for
-- instance, if Quinn wants to register for a clinic, but she wants to be on
-- the same core as her friend Tammy then she can write a note when she
-- registers. That only I will see so make sure it says only Tara can see
-- this." Her words for the screen: the example "please put me on court with
-- my friend Jane" and the line "Only Tara sees this". Decision 0039.
--
-- What "only Tara" means in the database (hard rule 1: hiding is a database
-- concern, never a UI one):
--   * the note is a column of registrations, which no client role can read;
--   * it is read through exactly two views: registrations_admin (where
--     is_admin(), Tara) and my_registrations (owns_player, the person who
--     wrote it, so she can see and change her own words);
--   * pros do NOT see it: pro_today() is unchanged and names its columns,
--     and a pro is not is_admin() (decision 0025);
--   * no other player, no anon caller, no count of anything.
--
-- Writes: register_for_clinic takes it as an optional third argument (an
-- app without the field keeps calling with two, and PostgREST fills the
-- default), and set_my_registration_note changes it until the clinic starts.
-- Tara's own placements (place_player) carry no note: a note is the player's.
--
-- Engineering calls, ours (decision 0039 §3): at most 300 characters after
-- trimming; blank means no note; deleting an account erases the notes.

-- ------------------------------------------------------------------ column --
alter table public.registrations
  add column player_note text
  constraint registrations_player_note_shape
    check (player_note is null or (char_length(player_note) between 1 and 300 and player_note = btrim(player_note, E' \t\r\n')));

comment on column public.registrations.player_note is
  'The player''s private note to Tara, written at Register or after (decision 0039). '
  'Read only through registrations_admin (Tara) and my_registrations (the writer).';

-- -------------------------------------------------------- clean_player_note --
-- One rule for both writers: trimmed, blank is no note, longer than 300 is
-- refused (the app counts the same way, so this is the backstop).
create or replace function public.clean_player_note(p_note text)
returns text
language plpgsql
immutable
set search_path = public, pg_temp
as $$
declare
  v text := nullif(btrim(coalesce(p_note, ''), E' \t\r\n'), '');
begin
  if v is not null and char_length(v) > 300 then
    raise exception 'note_too_long' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

revoke all on function public.clean_player_note(text) from public, anon, authenticated;

-- ------------------------------------------------------ register_for_clinic --
-- Unchanged but for the note. Dropped first so there is exactly one
-- register_for_clinic and a two-argument call cannot be ambiguous.
drop function public.register_for_clinic(uuid, uuid);

CREATE FUNCTION public.register_for_clinic(p_clinic uuid, p_player uuid, p_note text DEFAULT NULL)
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

-- ------------------------------------------------ set_my_registration_note --
create or replace function public.set_my_registration_note(p_registration uuid, p_note text)
returns text
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_note text := public.clean_player_note(p_note);
  v_out  text;
  v_done boolean := false;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  -- Conditional (hard rule 3): her own live registration on a published
  -- clinic that has not started. Zero rows means one of those stopped being
  -- true (Tara removed her, the clinic started or was canceled): say so.
  update public.registrations r
     set player_note = v_note
    from public.clinics c
   where r.id = p_registration
     and c.id = r.clinic_id
     and public.owns_player(r.player_id)
     and r.status in ('in', 'pool', 'response_needed')
     and c.status = 'published'
     and c.starts_at > now()
  returning r.player_note, true into v_out, v_done;
  if not coalesce(v_done, false) then
    raise exception 'note_not_editable' using errcode = 'P0001';
  end if;
  return v_out;
end;
$$;

comment on function public.set_my_registration_note(uuid, text) is
  'The player changes or clears her own note to Tara on a live registration '
  'until the clinic starts (decision 0039). Returns the note as saved.';

revoke all on function public.set_my_registration_note(uuid, text) from public, anon;
grant execute on function public.set_my_registration_note(uuid, text) to authenticated;

-- ---------------------------------------------------------------- the views --
-- Columns appended at the end (create or replace view allows only that).
create or replace view public.my_registrations as
  select id, clinic_id, player_id, status, paid, registered_at, invited_at, responded_at, canceled_at,
         late_cancel, courtesy_used, player_note
    from public.registrations r
   where public.owns_player(player_id);

revoke all on public.my_registrations from public, anon, authenticated;
grant select on public.my_registrations to authenticated;

create or replace view public.registrations_admin as
SELECT id,
    clinic_id,
    player_id,
    status,
    paid,
    court_number,
    source,
    registered_at,
    invited_at,
    responded_at,
    canceled_at,
    canceled_by,
    late_cancel,
    cancel_note,
    (EXISTS ( SELECT 1
           FROM (players p
             JOIN accounts a ON ((a.id = p.account_id)))
          WHERE ((p.id = r.player_id) AND (a.stripe_customer_id IS NOT NULL) AND (a.card_last4 IS NOT NULL)))) AS has_card,
    ( SELECT (x.status)::text AS status
           FROM payments x
          WHERE ((x.registration_id = r.id) AND (x.kind <> 'refund'::payment_kind) AND ((x.livemode IS NOT FALSE) OR (NOT (EXISTS ( SELECT 1
                   FROM app_settings s
                  WHERE (s.key = 'stripe_live_since'::text))))))
          ORDER BY x.created_at DESC
         LIMIT 1) AS charge_status,
    courtesy_used,
    no_show,
    player_note
   FROM registrations r
  WHERE is_admin();

revoke all on public.registrations_admin from public, anon, authenticated;
grant select on public.registrations_admin to authenticated;

-- -------------------------------------------------------- delete_my_account --
create or replace function public.delete_my_account()
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_id   uuid := auth.uid();
  v_role text;
begin
  if v_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select role into v_role from public.accounts where id = v_id;
  if v_role is null then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;
  if v_role = 'admin' then
    raise exception 'admin_cannot_delete' using errcode = 'P0001';
  end if;

  -- Personal data goes; the account row and its id stay so history keeps
  -- its foreign keys. The email is replaced with a value that can never be
  -- signed in with or mailed (RFC 2606 reserves .invalid).
  update public.accounts
     set first_name = 'Deleted', last_name = 'Account',
         email      = 'deleted-' || v_id || '@deleted.invalid',
         phone      = null,
         card_brand = null, card_last4 = null, card_added_at = null,
         deleted_at = coalesce(deleted_at, now())
   where id = v_id;

  update public.players
     set first_name = 'Deleted', last_name = 'Player',
         date_of_birth = null, level_note = null, is_active = false
   where account_id = v_id;

  -- A push token is a device, not history; a notification is personal.
  delete from public.devices       where account_id = v_id;
  delete from public.notifications where account_id = v_id;

  -- Spots in clinics still to come are given back; their rows stay as
  -- canceled (hard rule 4). A clinic already played is history and keeps
  -- its "in": that is the record she said to keep, and the row Money reads.
  -- Her notes to Tara are her own words: gone on every registration, played
  -- or not (decision 0039). Tara's notes about her stay, as before.
  update public.registrations r
     set player_note = null
    from public.players p
   where p.id = r.player_id and p.account_id = v_id
     and r.player_note is not null;

  update public.registrations r
     set status = 'canceled', canceled_at = now(), canceled_by = v_id
    from public.players p, public.clinics c
   where p.id = r.player_id and p.account_id = v_id
     and c.id = r.clinic_id and c.starts_at > now()
     and r.status in ('in', 'pool', 'response_needed');

  return v_id;
end;
$function$;

revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;
