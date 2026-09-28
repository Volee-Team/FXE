-- 20260928300001_no_accepting_a_canceled_clinic.sql
--
-- respond_to_invitation refuses Accept once Tara has canceled the clinic.
--
-- Found by the notification-copy branch (docs/backlog.md, 2026-09-28): Tara
-- invites Rob, then cancels the clinic for rain; the invitation's Accept (on
-- the clinic page opened from the push, and since decision 0023 right on the
-- lock screen) still went through, and Rob landed in You're In! of a clinic
-- that is not happening. cancel_clinic had already told him it was canceled;
-- the accept then said nothing to him (20260928000001 withheld "Your spot is
-- confirmed") and told Tara he had accepted.
--
-- Not a policy question: a canceled clinic has no spots. The refusal raises
-- clinic_canceled; the app reads any refusal of an answer as "that just
-- changed" and shows the clinic, which says it is canceled.
--
-- The body below is 20260928000001's, unchanged except for the lock and the
-- check before the conditional UPDATE. Grants restated exactly.
--
-- Pinned by tests/sql/notification_copy.sql (checks 24a and 24b).

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

  -- Accepting a canceled clinic put a player in You're In! of a clinic that
  -- is not happening (backlog, 2026-09-28): the invitation's own Accept
  -- button on the lock screen never sees the clinic page's canceled banner.
  -- The clinic row is locked FOR SHARE first, so cancel_clinic (an UPDATE of
  -- that row) and this answer are serialized: whichever commits first, the
  -- other sees it. Declining a canceled clinic stays allowed; it changes
  -- nothing that matters.
  select status into v_clinic_status
    from public.clinics where id = v_row.clinic_id
     for share;
  if p_accept and v_clinic_status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
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
