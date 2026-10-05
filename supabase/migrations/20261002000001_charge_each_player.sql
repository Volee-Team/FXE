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

-- ----------------------------------------------------------- money_rows --
-- The one rule for what is owed, from 20260928700001, with three changes
-- the sql-auditor asked for on 2026-10-04 (before this migration reached
-- hosted):
--   * a clinic owes only once PUBLISHED (a draft Tara never published was
--     chargeable after its end time; it was never shown to anyone),
--   * one late fee per person per clinic (only the newest late cancel owes),
--   * an optional clinic filter, so a per-clinic caller no longer computes
--     every registration since payments went on. Called with no argument it
--     is exactly the old whole-club list, which every admin_money_* uses.
drop function if exists public.money_rows();
create function public.money_rows(p_clinic uuid default null)
returns table (
  registration_id  uuid,
  clinic_id        uuid,
  player_id        uuid,
  account_id       uuid,
  owed_kind        public.payment_kind,
  amount_cents     integer,
  state            text,
  has_card         boolean,
  attempted_cents  integer,
  failure_code     text,
  failure_reason   text,
  failed_at        timestamptz,
  failed_payment_id uuid)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with since as (select public.payments_enabled_at() as t),
  owing as (
    select r.id, r.clinic_id, r.player_id, p.account_id, r.price_cents_charged, r.paid,
           case when r.status = 'in' and not r.no_show then 'clinic_fee'::public.payment_kind
                when r.status = 'in' and r.no_show     then 'no_show'::public.payment_kind
                when r.status = 'canceled' and r.late_cancel and not r.courtesy_used
                     and not exists (select 1 from public.registrations o
                                      where o.clinic_id = r.clinic_id
                                        and o.player_id = r.player_id
                                        and o.status = 'in')
                     -- One late fee per person per clinic: only the newest
                     -- late cancel owes (cancel, approved back in, cancel
                     -- again left two owing rows, two Charge buttons).
                     and not exists (select 1 from public.registrations l
                                      where l.clinic_id = r.clinic_id
                                        and l.player_id = r.player_id
                                        and l.status = 'canceled' and l.late_cancel and not l.courtesy_used
                                        and (l.canceled_at, l.id) > (r.canceled_at, r.id))
                  then 'late_cancel'::public.payment_kind
           end as owed_kind
      from public.registrations r
      join public.clinics c on c.id = r.clinic_id
      join public.players p on p.id = r.player_id
      cross join since s
     -- Published only: a draft Tara never published was never shown to a
     -- player and owes nothing (sql-auditor, 2026-10-04; a Copy-to-next-week
     -- draft left unpublished was chargeable once its end time passed).
     where c.status = 'published'
       and (p_clinic is null or r.clinic_id = p_clinic)
       and c.ends_at <= now()
       and s.t is not null
       and c.ends_at >= s.t
  ),
  judged as (
    select w.*,
           case
             when w.owed_kind is null then null
             when public.player_has_live_fee(w.player_id, w.clinic_id) then 'charged'
             when w.paid then 'settled'
             when exists (select 1 from public.payments x
                           where x.registration_id = w.id and x.kind = w.owed_kind
                             and x.status = 'succeeded'
                             and public.payment_is_real(x.livemode)) then 'refunded'
             when exists (select 1 from public.payments x
                           where x.registration_id = w.id and x.kind = w.owed_kind
                             and x.status = 'failed'
                             and public.payment_is_real(x.livemode)) then 'declined'
             else 'not_charged'
           end as state
      from owing w
  )
  select j.id, j.clinic_id, j.player_id, j.account_id, j.owed_kind, j.price_cents_charged,
         -- Tara's Resolved on the failed charge shown (20260928700001).
         case when j.state = 'declined' and f.resolved_at is not null then 'resolved' else j.state end,
         exists (select 1 from public.accounts a
                  where a.id = j.account_id
                    and a.stripe_customer_id is not null
                    and a.card_last4 is not null),
         f.amount_cents, f.failure_code, f.failure_reason, f.updated_at, f.id
    from judged j
    left join lateral (
      select x.id, x.amount_cents, x.failure_code, x.failure_reason, x.updated_at, x.resolved_at
        from public.payments x
       where j.state = 'declined'
         and x.registration_id = j.id and x.kind = j.owed_kind and x.status = 'failed'
         and public.payment_is_real(x.livemode)
       order by x.updated_at desc, x.created_at desc, x.id desc
       limit 1
    ) f on true;
$$;

comment on function public.money_rows(uuid) is
  'Internal. One row per registration in an ended, published clinic that ended '
  'at or after payments_enabled_at: what it owes (the kind Charge clinic would '
  'charge, or null) and where that stands (charged, settled, refunded, declined, '
  'resolved, not_charged), with the failed charge a declined or resolved row shows. '
  'Aggregated by admin_money_*.';

revoke all on function public.money_rows(uuid) from public, anon, authenticated;


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
      from public.money_rows(p_clinic) m
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
