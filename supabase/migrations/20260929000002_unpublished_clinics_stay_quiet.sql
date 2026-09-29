-- 20260929000002_unpublished_clinics_stay_quiet.sql
--
-- The other doors (sql-auditor on 20260929000001, 2026-09-28). Hiding a
-- canceled draft from clinics_public was not enough: Tara can put someone in
-- a draft (Add player works on any card, decision 3), and then canceling it
-- told that player "<name> has been canceled." about a clinic they never saw,
-- and once its date passed it turned up in their Past list. Both now follow
-- the same rule as the clinic list: a clinic that was never published is
-- never mentioned to a player. A published clinic that is canceled still
-- notifies and still shows in Past, exactly as before.
--
-- Left for Alex (touches decision 3): whether place_player and
-- send_clinic_message should refuse a clinic that was never published.
-- Pinned by tests/sql/canceled_drafts.sql.

create or replace function public.cancel_clinic(p_clinic uuid)
returns public.clinics language plpgsql security definer
set search_path = public, pg_temp as $$
declare v public.clinics; r record;
begin
  perform public.require_admin();

  update public.clinics set status = 'canceled', canceled_at = now()
   where id = p_clinic and status <> 'canceled'
  returning * into v;
  if not found then
    raise exception 'already_canceled' using errcode = 'P0001';
  end if;

  -- Nobody is told about a clinic that was never published.
  if v.published_at is not null then
    for r in
      select distinct p.account_id
        from public.registrations reg
        join public.players p on p.id = reg.player_id
       where reg.clinic_id = p_clinic
         and reg.status in ('in', 'pool', 'response_needed')
    loop
      perform public.notify_account(r.account_id, 'clinic_canceled', 'clinic', p_clinic,
        v.name || ' has been canceled.');
    end loop;
  end if;

  return v;
end; $$;
revoke all on function public.cancel_clinic(uuid) from public, anon;
grant execute on function public.cancel_clinic(uuid) to authenticated;

-- Same columns, same order (CREATE OR REPLACE keeps the grants); only the
-- clinic condition changes, to clinics_public's.
create or replace view public.my_past_clinics as
  select r.id as registration_id, c.id as clinic_id, c.name, c.starts_at, c.ends_at,
         c.duration_minutes, c.category, c.audience, r.status, r.no_show, r.late_cancel,
         r.canceled_at, r.price_cents_charged, r.paid
    from public.registrations r
    join public.clinics c on c.id = r.clinic_id
   where public.owns_player(r.player_id)
     and (c.status = 'published' or (c.status = 'canceled' and c.published_at is not null))
     and c.ends_at <= now();
