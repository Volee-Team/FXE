-- 20260927300002_cancel_registration_guards.sql
--
-- MVP fix round (2026-09-27), two findings on cancel_registration.
--
-- M4. TARA'S REMOVE ON A CHARGED SPOT. An admin removing someone else's
--     registration (the roster's "Remove from clinic") went through even when
--     that row held a live fee: the spot vanished from You're In!, the fee
--     stayed taken, and nothing on any screen said a refund was owed.
--     admin_set_no_show and admin_mark_late_cancel already refuse a charged
--     row (charged_refund_first); Remove now does the same. Refund first,
--     then remove. A player canceling their own spot is unchanged, and so is
--     an admin canceling a player they own (their own spot).
--
-- M6. THE WHOLE ROW WENT BACK TO THE PLAYER. cancel_registration returns the
--     registrations row, and a player calling it received court_number (a
--     court assignment is hidden fact 6, hard rule 1) and canceled_by. Both
--     are nulled in the returned value unless the caller is an admin; the
--     stored row is untouched. Pinned by information_hiding.sql.
--     respond_to_invitation had the same leak (found by the sql-auditor on
--     this change): place_player and invite_from_pool change only the status,
--     so a court Tara assigned stays on the row, and accepting the invitation
--     handed it back. Same scrub, same probe.
--
-- The Remove guard reads the row FOR UPDATE, the lock admin_charge_clinic,
-- admin_set_no_show and admin_mark_late_cancel take, so a charge landing
-- while Tara taps Remove on her other screen is seen, not raced past.
--
-- Everything else is 20260927100002's body, unchanged.

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
begin
  select * into v_row from public.registrations where id = p_registration for update;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not (public.owns_player(v_row.player_id) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  -- Tara removing someone else's charged spot: refund first (M4).
  if not public.owns_player(v_row.player_id) and public.registration_has_live_fee(p_registration) then
    raise exception 'charged_refund_first' using errcode = 'P0001';
  end if;

  select starts_at into v_starts from public.clinics where id = v_row.clinic_id;
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

  -- The admins hear about a player's OWN cancellation. An admin removing
  -- someone else already knows: that notice read as the player's act.
  if public.owns_player(v_row.player_id) then
    select * into v_player from public.players where id = v_row.player_id;
    for v_admin in select public.admin_account_ids() loop
      perform public.notify_account(v_admin, 'player_canceled', 'registration', v_row.id,
        v_player.first_name || ' ' || v_player.last_name || ' canceled.'
        || case when v_late and v_courtesy then ' Late, courtesy used.'
                when v_late then ' Late, fee applies.'
                else '' end
        || case when v_row.cancel_note is not null then ' Note: "' || v_row.cancel_note || '"' else '' end);
    end loop;
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

-- ------------------------------------------------- respond_to_invitation ----
-- Same body as 20260728000003 plus the scrub at the end.
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
  for v_admin in select public.admin_account_ids() loop
    perform public.notify_account(
      v_admin, case when p_accept then 'invitation_accepted' else 'invitation_declined' end,
      'registration', v_row.id,
      v_player.first_name || ' ' || v_player.last_name
        || case when p_accept then ' accepted.' else ' declined.' end);
  end loop;

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
