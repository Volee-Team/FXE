-- 20260927100001_one_fee_per_player_per_clinic.sql
--
-- A player could be charged twice for one clinic (MVP audit, 2026-09-27: a
-- blocker once payments are on). The one-charge guard was per registration
-- and per charge KIND: admin_charge_registration checked `x.kind = p_kind`,
-- and the unique index payments_one_live_charge is (registration_id, kind).
-- Two ways through it, neither of which any probe tried:
--
--   1. Came, Charge clinic, then the row flipped to No-show, then Charge
--      clinic again: a clinic_fee AND a no_show fee on the same row, because
--      admin_set_no_show checked only status = 'in'.
--   2. One tap. A player who canceled late keeps a canceled row carrying
--      late_cancel. If Tara approves their late request or adds them back, a
--      second registration exists (the one-live-row index ignores canceled
--      rows), and Charge clinic charged late_cancel on the old row AND
--      clinic_fee on the new one.
--
-- THE RULE NOW: one fee per player per clinic. A fee is LIVE while it is
-- pending, processing or succeeded and has not been refunded in full by
-- succeeded refunds. Whatever happened (came, no-show, late cancel, put back
-- in), a player holds at most one live fee per clinic.
--
-- * admin_charge_registration refuses (already_charged) when the player holds
--   a live fee in that clinic on ANY of their rows, of ANY kind. The check is
--   made under a per (player, clinic) advisory lock: two taps at the same
--   instant for different rows or kinds share no unique-index key, so without
--   the lock both would pass the read and both would insert (the lesson of
--   20260926000010: a check has to be a constraint or a lock, not a read).
-- * admin_set_no_show refuses (charged_refund_first) once that registration
--   holds a live fee. The label must not change under a charge; refund
--   first, then change it, then charge again.
-- * admin_charge_clinic skips a late cancellation when the same player holds a
--   You're In! row in that clinic (that row is the one charged, under its own
--   kind); refuses a canceled clinic (clinic_canceled), because cancel_clinic
--   leaves every row 'in' and a tap after a rain-out would have charged the
--   whole roster (the screens hid the button; the server did not refuse);
--   and locks the clinic's rows so a no-show flip cannot land between its
--   read of a row and its insert.
--
-- Our default, not Tara's words, and it only ever prevents a charge. The
-- question for her (does someone who canceled late and was put back in pay
-- once?) travels with this branch's report; the default built is "once".

-- ------------------------------------------------------------ helpers ----
-- Internal: called only by the SECURITY DEFINER functions below and in
-- 20260927100003, as the owner. No client role may call them.
create or replace function public.registration_has_live_fee(p_registration uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.payments x
     where x.registration_id = p_registration
       and x.kind <> 'refund'
       and x.status in ('pending', 'processing', 'succeeded')
       and x.amount_cents > coalesce((
             select sum(f.amount_cents) from public.payments f
              where f.refunds_payment_id = x.id
                and f.kind = 'refund'
                and f.status = 'succeeded'), 0)
  );
$$;

create or replace function public.player_has_live_fee(p_player uuid, p_clinic uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.registrations r
     where r.player_id = p_player
       and r.clinic_id = p_clinic
       and public.registration_has_live_fee(r.id)
  );
$$;

revoke all on function public.registration_has_live_fee(uuid) from public, anon, authenticated;
revoke all on function public.player_has_live_fee(uuid, uuid) from public, anon, authenticated;

-- ------------------------------------------- Tara's charge, per player ----
-- Same as 20260926000001 except the live check: per player per clinic, under
-- a lock, and made BEFORE the card check, so a player already charged counts
-- as "already charged" on a second tap even if their card has since gone.
create or replace function public.admin_charge_registration(
  p_registration uuid, p_kind public.payment_kind, p_amount_cents integer default null)
returns public.payments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r public.registrations; a public.accounts; v public.payments; amt integer;
begin
  perform public.require_admin();
  if not public.payments_enabled() then
    raise exception 'payments_disabled' using errcode = 'P0001';
  end if;
  if p_kind = 'refund' then
    raise exception 'use_admin_refund_payment' using errcode = '22023';
  end if;
  select * into r from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  -- One fee per player per clinic. The lock is held to the end of the
  -- transaction, so a second charge for this player in this clinic waits,
  -- then reads this one's committed row and is refused.
  perform pg_advisory_xact_lock(hashtextextended('charge:' || r.player_id::text || ':' || r.clinic_id::text, 0));
  if public.player_has_live_fee(r.player_id, r.clinic_id) then
    raise exception 'already_charged' using errcode = 'P0001';
  end if;
  select a2.* into a from public.accounts a2 join public.players p on p.account_id = a2.id where p.id = r.player_id;
  -- A saved card, not just a Stripe customer (see register_for_clinic).
  if a.stripe_customer_id is null or a.card_last4 is null then
    raise exception 'no_card_on_file' using errcode = 'P0001';
  end if;
  amt := coalesce(p_amount_cents, r.price_cents_charged);
  if amt is null or amt <= 0 then
    raise exception 'amount_required' using errcode = '22023';
  end if;
  insert into public.payments (registration_id, account_id, kind, amount_cents, requested_by)
  values (p_registration, a.id, p_kind, amt, auth.uid())
  returning * into v;
  return v;
exception
  -- The unique index payments_one_live_charge still catches the same kind on
  -- the same row (including a refunded fee of that kind, which stays
  -- 'succeeded'); this turns it into the error Tara's screens understand.
  when unique_violation then
    raise exception 'already_charged' using errcode = 'P0001';
end;
$$;

-- ------------------------------------------------------- no-shows ----
create or replace function public.admin_set_no_show(p_registration uuid, p_no_show boolean)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_row public.registrations;
begin
  perform public.require_admin();
  -- The row lock pairs with admin_charge_clinic's: a flip and a charge on the
  -- same row take turns instead of interleaving.
  select * into v_row from public.registrations where id = p_registration for update;
  if not found or v_row.status <> 'in' then
    raise exception 'registration_not_in' using errcode = 'P0001';
  end if;
  if public.registration_has_live_fee(p_registration) then
    raise exception 'charged_refund_first' using errcode = 'P0001';
  end if;
  update public.registrations set no_show = p_no_show
   where id = p_registration and status = 'in'
  returning * into v_row;
  if not found then
    raise exception 'registration_not_in' using errcode = 'P0001';
  end if;
  return v_row;
end;
$$;

-- ---------------------------------------------- Tara's tap per clinic ----
create or replace function public.admin_charge_clinic(p_clinic uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c        public.clinics;
  r        record;
  v_kind   payment_kind;
  n_charged int := 0; n_already int := 0; n_no_card int := 0; n_skipped int := 0;
begin
  perform public.require_admin();
  if not public.payments_enabled() then
    raise exception 'payments_disabled' using errcode = 'P0001';
  end if;
  select * into c from public.clinics where id = p_clinic;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  if c.ends_at > now() then
    raise exception 'clinic_not_over' using errcode = 'P0001';
  end if;

  for r in select * from public.registrations where clinic_id = p_clinic
            order by registered_at, id
            for update
  loop
    if r.status = 'in' and not r.no_show then v_kind := 'clinic_fee';
    elsif r.status = 'in' and r.no_show then v_kind := 'no_show';
    elsif r.status = 'canceled' and r.late_cancel and not r.courtesy_used
          and not exists (select 1 from public.registrations o
                           where o.clinic_id = p_clinic
                             and o.player_id = r.player_id
                             and o.status = 'in') then
      v_kind := 'late_cancel';
    else
      n_skipped := n_skipped + 1;
      continue;
    end if;
    begin
      perform public.admin_charge_registration(r.id, v_kind);
      n_charged := n_charged + 1;
    exception
      when others then
        if sqlerrm = 'already_charged' then n_already := n_already + 1;
        elsif sqlerrm = 'no_card_on_file' then n_no_card := n_no_card + 1;
        else raise;
        end if;
    end;
  end loop;

  return jsonb_build_object('charged', n_charged, 'already', n_already,
                            'no_card', n_no_card, 'not_owed', n_skipped);
end;
$$;

-- ------------------------------------------------------------- grants ----
-- CREATE OR REPLACE keeps a function's ACL, but hard rule 11 is restated on
-- every replace so the grant is visible where the function is.
revoke all on function public.admin_charge_registration(uuid, public.payment_kind, integer) from public, anon;
grant execute on function public.admin_charge_registration(uuid, public.payment_kind, integer) to authenticated;
revoke all on function public.admin_set_no_show(uuid, boolean) from public, anon;
grant execute on function public.admin_set_no_show(uuid, boolean) to authenticated;
revoke all on function public.admin_charge_clinic(uuid) from public, anon;
grant execute on function public.admin_charge_clinic(uuid) to authenticated;
