-- 20260927100002_admin_late_cancel_quiet_removal.sql
--
-- Two things Tara does to someone else's spot (MVP audit, 2026-09-27).
--
-- 1. SHE CAN RECORD A LATE CANCELLATION. Members text her "can't come" an
--    hour before a clinic, which is how she runs things today. cancel_
--    registration marks a cancel late only when the caller is NOT an admin
--    (20260921000001), and nothing else writes late_cancel, so her Remove
--    silently waived the fee; the only workaround was to leave the player In
--    and mark No-show, which holds the spot from the Player Pool and puts the
--    wrong label on the fee, in the ledger, in the member's Past and in the
--    board report. The "never late" rule was decision 0010 §6, our own
--    inference; her 2026-09-22 answer overrides it: pros "can label them as
--    no show, late cancellation" (decision 0016), so she can too.
--
--    admin_mark_late_cancel(p_registration, p_note) is a conditional update
--    from 'in' to 'canceled' with late_cancel set and canceled_by the admin,
--    the same record a player's own late cancel leaves (the courtesy is
--    applied the same way; it is switched off, decision 0013). Charge clinic
--    already charges such a row as late_cancel. Guards, each the narrowest
--    that prevents a wrong fee:
--      * only inside the cutoff or later (not_late_yet): before it, a cancel
--        is free under her policy, and Remove is the tool;
--      * not once the row holds a live fee (charged_refund_first), the same
--        rule as a no-show flip (20260927100001);
--      * not on a canceled clinic (clinic_canceled).
--    It tells nobody. The player's words for "Tara took you off" are hers to
--    write (the audit's needs-Tara list), and telling the admins about an
--    admin's own action is the echo fixed in 2 below.
--
-- 2. HER REMOVAL IS NOT THE PLAYER CANCELING. cancel_registration sent
--    "{player} canceled." to every admin whoever the caller was, so when Tara
--    removed Maria, her own Action Needed then read "Maria Alvarez canceled.",
--    as if Maria had done it. The admin fan-out now runs only when the caller
--    owns the player (the player canceling their own spot). No new words, no
--    policy; telling the player is the needs-Tara half and is not built.
--    A plain Remove stays exactly what it was otherwise: never late, no fee.

-- --------------------------------------------------- cancel_registration ----
-- Same body as 20260921000001 except the fan-out condition.
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
  select * into v_row from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not (public.owns_player(v_row.player_id) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
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

  return v_row;
end;
$$;

-- ------------------------------------------------ admin_mark_late_cancel ----
create or replace function public.admin_mark_late_cancel(p_registration uuid, p_note text default null)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row    public.registrations;
  c        public.clinics;
  v_note   text := nullif(btrim(coalesce(p_note, '')), '');
begin
  perform public.require_admin();

  -- Row lock first: the same lock admin_charge_clinic and admin_set_no_show
  -- take, so a charge and this cannot interleave on one row.
  select * into v_row from public.registrations where id = p_registration for update;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if v_row.status <> 'in' then
    raise exception 'registration_not_in' using errcode = 'P0001';
  end if;

  select * into c from public.clinics where id = v_row.clinic_id;
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  -- Inside the cutoff, or after the clinic (she may record it afterwards).
  if now() < c.starts_at - make_interval(hours => public.cancel_cutoff_hours()) then
    raise exception 'not_late_yet' using errcode = 'P0001';
  end if;
  if public.registration_has_live_fee(p_registration) then
    raise exception 'charged_refund_first' using errcode = 'P0001';
  end if;

  update public.registrations
     set status = 'canceled', canceled_at = now(), canceled_by = auth.uid(),
         late_cancel = true,
         courtesy_used = public.courtesy_available(v_row.player_id),
         cancel_note = left(v_note, 280),
         no_show = false
   where id = p_registration
     and status = 'in'
  returning * into v_row;
  if not found then
    raise exception 'registration_not_in' using errcode = 'P0001';
  end if;

  return v_row;
end;
$$;

comment on function public.admin_mark_late_cancel(uuid, text) is
  'Tara records a late cancellation for someone else (a text an hour before): '
  'You''re In! to Canceled, late_cancel true, canceled_by her, optional note. '
  'Charge clinic then charges it as late_cancel. Inside the cutoff or later only; '
  'not once charged; tells nobody.';

-- ------------------------------------------------------------- grants ----
revoke all on function public.cancel_registration(uuid, text) from public, anon;
grant execute on function public.cancel_registration(uuid, text) to authenticated;
revoke all on function public.admin_mark_late_cancel(uuid, text) from public, anon;
grant execute on function public.admin_mark_late_cancel(uuid, text) to authenticated;
