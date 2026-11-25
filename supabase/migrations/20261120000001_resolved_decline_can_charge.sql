-- A decline Tara Resolved can be charged again from the roster.
--
-- Tara, 2026-11-20, with a screenshot of a roster row reading "Declined" and
-- no Charge button: "This lady said that her AMEX had fraud, but it's good to
-- go now. I'm not quite sure how to charge her after it's been declined."
-- Hosted: the $28 fee failed at 11:43 (do_not_honor), Tara pressed Resolved
-- at 12:36, the player saved her card again at 13:00. money_rows then calls
-- the row 'resolved', and admin_fees_due and admin_charge_player only knew
-- 'not_charged' and 'declined', so the roster drew no button and a charge
-- would have been refused not_owed. Nothing could undo Resolved.
--
-- Decision 0026 had chosen "Resolved means I will not chase it" as a default
-- for Tara to confirm. Her first real use says otherwise: Resolved clears her
-- lists (her words when she asked for it: "it clears - for me only to see"),
-- it does not forgive the fee. So, amended:
--   * admin_fees_due lists a resolved decline, with state 'resolved', so the
--     roster (phone and laptop) shows Charge on it again;
--   * admin_charge_player charges it;
--   * money_rows is unchanged: Action Needed, the Money tab's Declined
--     figures and the This week owed list still leave a resolved decline out,
--     and admin_charge_clinic (Charge clinic, unused since 0037) still skips
--     it. A new decline on the charge comes back to her lists unresolved.
-- No app build: both clients draw whatever admin_fees_due returns.
-- Pinned by tests/sql/charge_each_player.sql (resolved_decline_back_on_the_roster,
-- resolved_decline_charges_again), red on both before this.

create or replace function public.admin_fees_due(p_clinic uuid)
returns table (registration_id uuid, kind public.payment_kind, amount_cents integer, state text, has_card boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  -- Nothing is due while card payments are off: no button to draw.
  if not public.payments_enabled() then
    return;
  end if;
  return query
    select m.registration_id, m.owed_kind, m.amount_cents, m.state, m.has_card
      from public.money_rows(p_clinic) m
     where m.clinic_id = p_clinic
       and m.owed_kind is not null
       and m.state in ('not_charged', 'declined', 'resolved');
end;
$$;

create or replace function public.admin_charge_player(p_registration uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r      public.registrations;
  c      public.clinics;
  m      record;
  v      public.payments;
  v_since timestamptz;
  v_clinic uuid;
begin
  perform public.require_admin();
  if not public.payments_enabled() then
    raise exception 'payments_disabled' using errcode = 'P0001';
  end if;
  select clinic_id into v_clinic from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  -- Clinic first (FOR SHARE), registration second (FOR UPDATE): the order
  -- place_player and the pro's Today lookup use, so no deadlock, and a cancel of
  -- the clinic in the same instant waits for this or this waits for it
  -- (sql-auditor, 2026-10-04: a rain-out cancel racing a Charge tap).
  select * into c from public.clinics where id = v_clinic for share;
  -- Locked, so a Came/No-show flip or a removal cannot land between deciding
  -- what is owed and charging it.
  select * into r from public.registrations where id = p_registration for update;
  -- The clinic's refusals, word for word Charge clinic's, so the app's
  -- messages for them already exist.
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  if c.status <> 'published' then
    raise exception 'clinic_not_published' using errcode = 'P0001';
  end if;
  if c.ends_at > now() then
    raise exception 'clinic_not_over' using errcode = 'P0001';
  end if;
  v_since := public.payments_enabled_at();
  if v_since is null or c.ends_at < v_since then
    raise exception 'clinic_before_payments' using errcode = 'P0001';
  end if;

  select * into m from public.money_rows(r.clinic_id) x where x.registration_id = p_registration;
  -- A live charge already: the same answer a second Charge clinic tap gives.
  if m.state = 'charged' then
    raise exception 'already_charged' using errcode = 'P0001';
  end if;
  -- Owes nothing (Waitlist, removed, paid by hand, refunded): no fee. A
  -- decline she resolved still owes and is charged (2026-11-20).
  if m.owed_kind is null or m.state not in ('not_charged', 'declined', 'resolved') then
    raise exception 'not_owed' using errcode = 'P0001';
  end if;

  v := public.admin_charge_registration(p_registration, m.owed_kind);
  return jsonb_build_object('payment_id', v.id, 'kind', v.kind, 'amount_cents', v.amount_cents);
end;
$$;

-- create or replace keeps the existing grants; restated so this file is the
-- whole story (hard rule 11).
revoke all on function public.admin_fees_due(uuid) from public, anon;
grant execute on function public.admin_fees_due(uuid) to authenticated;
revoke all on function public.admin_charge_player(uuid) from public, anon;
grant execute on function public.admin_charge_player(uuid) to authenticated;
