-- Tara, 2026-10-30, by text: "making sure it says waitlist not pool - for me
-- and others ... Players are still seeing player pool. That needs to be
-- waitlist ... To avoid confusion". Decision 0041 had already renamed the
-- term; this applies it to the two notification sentences the database
-- writes. Only the words change: the stored status stays 'pool'.
--
-- Both bodies are copied from the live definitions (pg_get_functiondef after
-- every earlier migration), with one phrase replaced in each:
--   cancel_registration   "removed from the Player Pool for" -> "removed from the Waitlist for"
--   respond_to_invitation "is back in the Player Pool."      -> "is back on the Waitlist."
-- CREATE OR REPLACE keeps each function's owner and grants.

CREATE OR REPLACE FUNCTION public.cancel_registration(p_registration uuid, p_note text DEFAULT NULL::text)
 RETURNS registrations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
      'You''ve been removed from the Waitlist for ' || v_clinic
      || '. Hope to see you at another clinic soon!');
  end if;

  -- What goes back to a player carries no court and no canceler (M6).
  if not public.is_admin() then
    v_row.court_number := null;
    v_row.canceled_by  := null;
  end if;

  return v_row;
end;
$function$

;

CREATE OR REPLACE FUNCTION public.respond_to_invitation(p_registration uuid, p_accept boolean)
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
$function$

;

