-- A switch for the double-105 rule, and it is off.
--
-- Tara, by text: 2026-11-24, with a non-member's message that she could not
-- join Friday's 10:30 105 while only on the Waitlist for the 9:00 one:
--   "hate to do this - but let's allow them to register for both 105's. I'll
--    control whether or not they do both or not."
-- 2026-11-25: "Can you guys take that rule down when you wake? The 105
--   waitlist rule. If possible need it done asap"
-- It overrules decision 0015 section 13 (a non-member holding one 105 cannot
-- take a second the same New York day until 48 hours before the earlier), and
-- the same rule in her note "Next update from 11/12", both written earlier.
--
-- A switch and not a removal, as level_check_enabled was (20261106000002):
-- this is the third time the rule has moved, and off keeps it tested. While
-- app_settings.double_105_rule_enabled is 'false', register_for_clinic skips
-- it; a missing row means on. Putting it back is one migration:
--   update app_settings set value = 'true' where key = 'double_105_rule_enabled'.
-- No app update: the app and /play only word the refusal when they get one.
-- supabase/seed.sql turns it on locally and in CI so the rule stays tested.
--
-- register_for_clinic is the body live on hosted (20261118000002) with only
-- the marked condition added. Pinned by tests/sql/back_to_back_105.sql.

insert into public.app_settings (key, value)
values ('double_105_rule_enabled', 'false')
on conflict (key) do update set value = excluded.value;

create or replace function public.double_105_rule_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select value = 'true' from public.app_settings where key = 'double_105_rule_enabled'), true);
$$;
comment on function public.double_105_rule_enabled() is
  'Decision 0015 section 13, switched off by Tara 2026-11-24: the double-105 rule on or off (app_settings.double_105_rule_enabled).';
-- Internal: only register_for_clinic asks. Named one by one, because hosted's
-- default privileges grant EXECUTE on a new function to anon and authenticated.
revoke all on function public.double_105_rule_enabled() from public, anon, authenticated;

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


-- create or replace keeps the grants; restated so this file is the whole story.
revoke all on function public.register_for_clinic(uuid, uuid, text) from public, anon;
grant execute on function public.register_for_clinic(uuid, uuid, text) to authenticated;
