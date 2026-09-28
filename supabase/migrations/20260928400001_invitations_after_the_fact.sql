-- 20260928400001_invitations_after_the_fact.sql
--
-- The sql-auditor's review of 20260928300001 (2026-09-28) found the same
-- class of bug three more times: a transition that ignores whether the
-- clinic is still happening.
--
--   1. respond_to_invitation: Accept after the clinic has ENDED put the
--      player in You're In! of a finished clinic, and Tara's next Charge
--      clinic charged them (reproduced by the auditor in a lab copy: "PAY
--      Rob clinic_fee 2200 pending"). Refused now with clinic_ended. Decline
--      stays allowed. Where the line should be (start or end) is Tara's call,
--      question 91; the end is the one nobody can argue with.
--   2. invite_from_pool: Tara could invite from the Pool of a canceled
--      clinic, sending "A spot opened in ..." for a clinic that is not
--      happening, whose Accept 20260928300001 then refuses: a dead end.
--      Refused now with clinic_canceled.
--   3. resolve_late_request: approving after the clinic was canceled put the
--      player in and told them "You're in for ..." (never having been told of
--      the cancellation, which reaches live registrations only). Approve is
--      refused now with clinic_canceled; Decline stays allowed.
--
-- Locks, in the order every other writer uses (clinic, then registration):
-- invite_from_pool takes the clinic FOR SHARE before its conditional UPDATE,
-- as respond_to_invitation does. resolve_late_request takes it FOR UPDATE,
-- not FOR SHARE, because it goes on to call place_player, which takes FOR
-- UPDATE: two share-holders both upgrading would deadlock each other.
--
-- Bodies otherwise unchanged (respond_to_invitation from 20260928300001,
-- invite_from_pool from 20260728000003, resolve_late_request from
-- 20260827000002). Grants restated. Pinned by tests/sql/after_the_fact.sql
-- and, for the lock itself, tests/sql/accept_cancel_race.sh.

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
  v_ends  timestamptz;
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

create or replace function public.invite_from_pool(p_registration uuid)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.registrations; v_player public.players; v_clinic public.clinics; v_clinic_id uuid;
begin
  perform public.require_admin();

  -- The clinic first, locked FOR SHARE so cancel_clinic and this invitation
  -- are serialized; then the conditional transition (hard rule 3).
  select clinic_id into v_clinic_id from public.registrations where id = p_registration;
  select * into v_clinic from public.clinics where id = v_clinic_id for share;
  if found and v_clinic.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;

  update public.registrations
     set status = 'response_needed', invited_at = now()
   where id = p_registration and status = 'pool'
  returning * into v;
  if not found then
    raise exception 'not_in_pool' using errcode = 'P0001';
  end if;

  select * into v_player from public.players where id = v.player_id;
  perform public.notify_account(v_player.account_id, 'invitation_received',
    'registration', v.id,
    'A spot opened in ' || v_clinic.name || '. Accept or decline.');

  return v;
end;
$$;

create or replace function public.resolve_late_request(p_request uuid, p_approve boolean)
returns public.late_requests
language plpgsql
security definer
set search_path = public, pg_temp
as $$
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

revoke all on function public.respond_to_invitation(uuid, boolean) from public, anon;
grant execute on function public.respond_to_invitation(uuid, boolean) to authenticated;
revoke all on function public.invite_from_pool(uuid) from public, anon;
grant execute on function public.invite_from_pool(uuid) to authenticated;
revoke all on function public.resolve_late_request(uuid, boolean) from public, anon;
grant execute on function public.resolve_late_request(uuid, boolean) to authenticated;
