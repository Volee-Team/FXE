-- 20260921000001_tara_review_policy.sql
--
-- Decision 0013 (Tara's first full review, 2026-09-21). Four policy changes
-- and two loose ends, all hers, none inferred:
--
--   1. No courtesy late cancellation ("NOT DOING THIS ANYMORE").
--      courtesy_cancel_days becomes 0 and courtesy_available() is false
--      whenever the window is 0. Columns and history stay (hard rule 4).
--   2. The cutoff is 3 hours, not 4 ("3 hours instead of 4").
--   3. The card is the only way to pay ("Everyone using the app has to
--      input a credit card"). zelle_allowed becomes false; both admin
--      surfaces hide the Paid toggle and the reminder while it is false.
--   4. The note only she sees shows on the roster AND the player's page
--      ("Both"): search_players returns level_note (in 20260921000002,
--      with the waiver column, so the function is defined once).
--
-- Plus two backlog rows that needed nobody's answer:
--   5. leave_pool archived a Player Pool drop-out by DELETE since July,
--      against hard rule 4. It now cancels the row like every other exit.
--   6. players.is_member was column-writable by the owning account while
--      the UI said "Set by Tara" (decision 5 override). The grant goes;
--      create_my_account (SECURITY DEFINER) still records the self-report
--      at sign-up, and admin_set_membership is Tara's override.

-- ---------------------------------------------------------------- settings
update public.app_settings set value = '0'     where key = 'courtesy_cancel_days';
update public.app_settings set value = '3'     where key = 'cancel_cutoff_hours';
update public.app_settings set value = 'false' where key = 'zelle_allowed';

create or replace function public.zelle_allowed()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select coalesce((select value = 'true' from public.app_settings where key = 'zelle_allowed'), false);
$$;
revoke all on function public.zelle_allowed() from public, anon;
grant execute on function public.zelle_allowed() to authenticated;

-- ---------------------------------------------------- courtesy switched off
create or replace function public.courtesy_available(p_player uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select public.courtesy_cancel_days() > 0
     and not exists (
    select 1 from public.registrations r
     where r.player_id = p_player
       and r.courtesy_used
       and r.canceled_at > now() - make_interval(days => public.courtesy_cancel_days())
  );
$$;

-- cancel_registration: same body as 20260916000001 minus the courtesy wording
-- in Tara's notification. courtesy_used is still recorded (always false while
-- the window is 0) so the ledger logic in admin_charge_clinic is unchanged.
create or replace function public.cancel_registration(p_registration uuid, p_note text default null)
returns public.registrations
language plpgsql security definer set search_path = public, pg_temp
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

  select * into v_player from public.players where id = v_row.player_id;
  for v_admin in select public.admin_account_ids() loop
    perform public.notify_account(v_admin, 'player_canceled', 'registration', v_row.id,
      v_player.first_name || ' ' || v_player.last_name || ' canceled.'
      || case when v_late and v_courtesy then ' Late, courtesy used.'
              when v_late then ' Late, fee applies.'
              else '' end
      || case when v_row.cancel_note is not null then ' Note: "' || v_row.cancel_note || '"' else '' end);
  end loop;

  return v_row;
end;
$$;

-- ------------------------------------------------ leave_pool archives now
-- Was: delete from registrations where status = 'pool'. A drop-out left no
-- row and no timestamp for Tara. Now it is a cancellation like the others:
-- conditional on the status (hard rule 3), stamped, never late (a Pool entry
-- holds no spot, decision 0010), and the row stays (hard rule 4).
create or replace function public.leave_pool(p_registration uuid)
returns boolean
language plpgsql security definer set search_path = public, pg_temp
as $$
declare v_player uuid;
begin
  select player_id into v_player from public.registrations where id = p_registration;
  if v_player is null then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not public.owns_player(v_player) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  update public.registrations
     set status = 'canceled', canceled_at = now(), canceled_by = auth.uid(),
         late_cancel = false, courtesy_used = false, cancel_note = null
   where id = p_registration and status = 'pool';
  if not found then
    raise exception 'not_in_pool' using errcode = 'P0001';
  end if;
  return true;
end;
$$;

-- ------------------------------------------ is_member is Tara's column now
-- Column grants are additive per column; revoking the whole table-level
-- UPDATE first would take level_note and the rest with it, so revoke the
-- one column. (Postgres: "revoke update (col)" removes exactly that column.)
revoke update (is_member) on public.players from authenticated;
