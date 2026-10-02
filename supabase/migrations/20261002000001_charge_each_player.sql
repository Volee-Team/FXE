-- 20261002000001_charge_each_player.sql
--
-- Tara, 2026-10-02 (through Alex): she wants to charge each person on her own
-- tap, "charge charge charge", a green button beside every name, and to take
-- someone off the roster so they are never charged ("this kid was puking and
-- she didn't charge that person"). Decision 0037.
--
-- The second half needs nothing new: cancel_registration already lets an
-- admin remove someone after the clinic has ended, never late, telling them
-- nothing, and a removed registration owes nothing (money_rows). The first
-- half is two functions, and NEITHER carries its own copy of the rule for
-- what someone owes. That rule lives in money_rows() (20260928700001), which
-- Charge clinic's skips, the Money tab and Action Needed already agree with;
-- a second copy here would drift the first time one of them changed.
--
--   admin_fees_due(clinic)        what each person on that clinic owes now:
--                                 one row per registration money_rows calls
--                                 'not_charged' or 'declined'. The app draws
--                                 a Charge button for exactly these rows,
--                                 or "No card" where none is saved.
--   admin_charge_player(reg)      one person's fee, on her tap. Same refusals
--                                 as Charge clinic for the clinic (payments
--                                 off, not over, canceled, before payments),
--                                 then 'not_owed' unless that row is due, then
--                                 admin_charge_registration with the kind
--                                 money_rows says. A double tap is one fee
--                                 (the unique index behind already_charged).
--
-- Not changed: admin_charge_clinic. It stays on the server, unused by the
-- phone, so nothing that calls it breaks (hard rule 6).

-- --------------------------------------------------------- admin_fees_due --
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
      from public.money_rows() m
     where m.clinic_id = p_clinic
       and m.owed_kind is not null
       and m.state in ('not_charged', 'declined');
end;
$$;

comment on function public.admin_fees_due(uuid) is
  'Admin only. Each registration on the clinic that owes a fee now and holds '
  'no live charge (money_rows state not_charged or declined), with the kind '
  'and amount admin_charge_player would charge, and whether a card is saved. '
  'Empty while payments are off.';

revoke all on function public.admin_fees_due(uuid) from public, anon;
grant execute on function public.admin_fees_due(uuid) to authenticated;


-- ---------------------------------------------------- admin_charge_player --
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
begin
  perform public.require_admin();
  if not public.payments_enabled() then
    raise exception 'payments_disabled' using errcode = 'P0001';
  end if;
  -- Locked, so a Came/No-show flip or a removal cannot land between deciding
  -- what is owed and charging it.
  select * into r from public.registrations where id = p_registration for update;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  select * into c from public.clinics where id = r.clinic_id;
  -- The clinic's refusals, word for word Charge clinic's, so the app's
  -- messages for them already exist.
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  if c.ends_at > now() then
    raise exception 'clinic_not_over' using errcode = 'P0001';
  end if;
  v_since := public.payments_enabled_at();
  if v_since is null or c.ends_at < v_since then
    raise exception 'clinic_before_payments' using errcode = 'P0001';
  end if;

  select * into m from public.money_rows() x where x.registration_id = p_registration;
  -- A live charge already: the same answer a second Charge clinic tap gives.
  if m.state = 'charged' then
    raise exception 'already_charged' using errcode = 'P0001';
  end if;
  -- Owes nothing (Player Pool, removed, paid by hand, refunded, a decline she
  -- resolved): no fee, and the app has no button for it anyway.
  if m.owed_kind is null or m.state not in ('not_charged', 'declined') then
    raise exception 'not_owed' using errcode = 'P0001';
  end if;

  v := public.admin_charge_registration(p_registration, m.owed_kind);
  return jsonb_build_object('payment_id', v.id, 'kind', v.kind, 'amount_cents', v.amount_cents);
end;
$$;

comment on function public.admin_charge_player(uuid) is
  'Admin only. Charges one registration the fee money_rows says it owes, on '
  'Tara''s tap (decision 0037). Refuses as admin_charge_clinic does for the '
  'clinic, then already_charged, not_owed, or no_card_on_file. Queues one '
  'pending payments row; stripe-charge sends it to Stripe.';

revoke all on function public.admin_charge_player(uuid) from public, anon;
grant execute on function public.admin_charge_player(uuid) to authenticated;
