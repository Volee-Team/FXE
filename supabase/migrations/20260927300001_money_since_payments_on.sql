-- 20260927300001_money_since_payments_on.sql
--
-- MVP fix round (2026-09-27), from an adversarial review of the money work.
-- Four findings, one migration, because all four change the same small set
-- of definitions (money_rows, the live-fee helpers, the one-charge indexes).
--
-- M1. MONEY BEFORE PAYMENTS WERE ON. money_rows(), and so the Money numbers,
--     Action Needed's "{clinic} ended, not charged yet", the This week tab's
--     owed list and admin_charge_clinic, treated every ended clinic since the
--     club began as owing a card charge. The day payments are switched on,
--     every clinic ever run would read "not charged yet", and one tap of
--     Charge clinic on an old clinic would charge people for a session they
--     paid by Zelle weeks ago, including rows Tara had ticked Paid.
--       * app_settings.payments_enabled_at: the moment card payments were
--         switched on. Empty until then. WHOEVER SETS payments_enabled TO
--         'true' SETS THIS IN THE SAME CHANGE (the same migration or the same
--         SQL editor transaction), to now(). payments_enabled_at() reads it
--         (null when empty or missing).
--       * money_rows() counts a registration only if its clinic ended at or
--         after that moment; null means nothing is owed or declined at all.
--       * admin_charge_clinic refuses such a clinic (clinic_before_payments),
--         and refuses every clinic while the moment is null.
--       * A registration Tara marked Paid (registrations.paid) that holds no
--         live fee is settled: money_rows gives it the state 'settled'
--         (counted nowhere), and admin_charge_clinic skips it as not owed.
--
-- M2. payments(refunds_payment_id) had only the partial UNIQUE index for app
--     refunds still waiting for their Stripe id, so every "is this fee
--     refunded" subquery (registration_has_live_fee, money_rows, the board
--     report) scanned. A plain partial index for refund rows.
--
-- S2. TEST MONEY AFTER THE SWITCH TO LIVE. stripe_cutover_to_live marks every
--     sandbox row livemode = false, but the one-charge rule still counted them:
--     a member charged in the sandbox for a clinic could not be charged for
--     real (already_charged, and the unique index), the roster read "Paid"
--     from a sandbox row, and the Money tab's Charged added sandbox money.
--       * payment_is_real(livemode): true unless the row is test mode AND the
--         club has switched to live (app_settings.stripe_live_since). Before
--         the switch the sandbox IS the payment system, so its rows keep their
--         slot: the sandbox run must see "already charged" on a second tap,
--         exactly as a member will. This is the rule payments_ledger already
--         uses to list test rows until the switch (20260927200001).
--       * registration_has_live_fee (and so player_has_live_fee,
--         admin_charge_registration, admin_set_no_show, admin_mark_late_cancel
--         and money_rows), registrations_admin.charge_status and the Money
--         tab's charged sums count only rows payment_is_real() accepts.
--       * payments_one_live_charge and payments_one_live_app_refund are
--         recreated with "and livemode is not false". An index predicate
--         cannot read app_settings, so before the switch a test-mode row's
--         slot is held by the function check alone, which runs under the
--         per-player advisory lock (20260927100001) and is enough.
--
-- M5. A DECLINE ON A DELETED ACCOUNT. admin_money_declined gains
--     account_deleted, so Action Needed can leave such a row out (nobody can
--     fix that card) while the Money list keeps it, under the name the
--     account still has. The return type changes, so the function is dropped
--     and recreated.

-- ------------------------------------------------------------ settings ----
insert into public.app_settings (key, value) values ('payments_enabled_at', '')
on conflict (key) do nothing;

comment on function public.payments_enabled() is
  'True while app_settings.payments_enabled is ''true''. Whoever sets it to '
  '''true'' also sets app_settings.payments_enabled_at to now() in the same '
  'change (20260927300001): only clinics ending at or after that moment are '
  'ever owed, charged or declined.';

create or replace function public.payments_enabled_at()
returns timestamptz
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select nullif(btrim(s.value), '')::timestamptz
    from public.app_settings s where s.key = 'payments_enabled_at';
$$;

comment on function public.payments_enabled_at() is
  'Internal. When card payments were switched on (app_settings.payments_enabled_at), '
  'or null if never. Clinics ending before it owe nothing by card. 20260927300001.';

create or replace function public.payment_is_real(p_livemode boolean)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select p_livemode is not false
      or not exists (select 1 from public.app_settings s where s.key = 'stripe_live_since');
$$;

comment on function public.payment_is_real(boolean) is
  'Internal. Whether a ledger row with this livemode counts as a charge: every '
  'row before the switch to live, and after it every row not in test mode. '
  '20260927300001.';

revoke all on function public.payments_enabled_at() from public, anon, authenticated;
revoke all on function public.payment_is_real(boolean) from public, anon, authenticated;

-- ------------------------------------------------------------- indexes ----
create index if not exists payments_refund_of_idx
  on public.payments (refunds_payment_id) where kind = 'refund';

drop index if exists public.payments_one_live_charge;
create unique index payments_one_live_charge
  on public.payments (registration_id, kind)
  where kind <> 'refund' and status in ('pending', 'processing', 'succeeded')
    and livemode is not false;

drop index if exists public.payments_one_live_app_refund;
create unique index payments_one_live_app_refund
  on public.payments (refunds_payment_id)
  where kind = 'refund' and status in ('pending', 'processing', 'succeeded')
    and stripe_refund_id is null and livemode is not false;

-- ------------------------------------------------- the live-fee helper ----
-- Same as 20260927100001 with payment_is_real() on the fee and its refunds.
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
       and public.payment_is_real(x.livemode)
       and x.amount_cents > coalesce((
             select sum(f.amount_cents) from public.payments f
              where f.refunds_payment_id = x.id
                and f.kind = 'refund'
                and f.status = 'succeeded'
                and public.payment_is_real(f.livemode)), 0)
  );
$$;
revoke all on function public.registration_has_live_fee(uuid) from public, anon, authenticated;

-- ------------------------------------------------- the roster's view ----
-- Same columns, same order as 20260926000001; charge_status skips rows that
-- are not real money. payment_is_real() is inlined, not called: a view checks
-- table privileges as its owner but EXECUTE as the caller, and the helper is
-- internal (found by the probes: "permission denied for function").
create or replace view public.registrations_admin as
  select id, clinic_id, player_id, status, paid, court_number, source,
         registered_at, invited_at, responded_at, canceled_at, canceled_by,
         late_cancel, cancel_note,
         exists (select 1 from public.players p join public.accounts a on a.id = p.account_id
                  where p.id = r.player_id and a.stripe_customer_id is not null
                    and a.card_last4 is not null) as has_card,
         (select x.status::text from public.payments x
           where x.registration_id = r.id and x.kind <> 'refund'
             and (x.livemode is not false
                  or not exists (select 1 from public.app_settings s where s.key = 'stripe_live_since'))
           order by x.created_at desc limit 1) as charge_status,
         courtesy_used, no_show
    from public.registrations r
   where public.is_admin();

revoke all on public.registrations_admin from public, anon, authenticated;
grant select on public.registrations_admin to authenticated;

-- ---------------------------------------------------------- money_rows ----
-- Same as 20260927100003 plus: only clinics ending at or after
-- payments_enabled_at; 'settled' for a row Tara marked Paid with no live fee;
-- test money after the switch neither refunds nor declines anything.
create or replace function public.money_rows()
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
  failed_at        timestamptz)
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
                  then 'late_cancel'::public.payment_kind
           end as owed_kind
      from public.registrations r
      join public.clinics c on c.id = r.clinic_id
      join public.players p on p.id = r.player_id
      cross join since s
     where c.status <> 'canceled'
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
  select j.id, j.clinic_id, j.player_id, j.account_id, j.owed_kind, j.price_cents_charged, j.state,
         exists (select 1 from public.accounts a
                  where a.id = j.account_id
                    and a.stripe_customer_id is not null
                    and a.card_last4 is not null),
         f.amount_cents, f.failure_code, f.failure_reason, f.updated_at
    from judged j
    left join lateral (
      select x.amount_cents, x.failure_code, x.failure_reason, x.updated_at
        from public.payments x
       where j.state = 'declined'
         and x.registration_id = j.id and x.kind = j.owed_kind and x.status = 'failed'
         and public.payment_is_real(x.livemode)
       order by x.updated_at desc, x.created_at desc, x.id desc
       limit 1
    ) f on true;
$$;

comment on function public.money_rows() is
  'Internal. One row per registration in an ended, not canceled clinic that ended '
  'at or after payments_enabled_at: what it owes (the kind Charge clinic would '
  'charge, or null) and where that stands (charged, settled, refunded, declined, '
  'not_charged). Aggregated by admin_money_*.';

revoke all on function public.money_rows() from public, anon, authenticated;

-- ------------------------------------------------------------ the summary ----
-- Same as 20260927100003; the charged sums count real money only.
create or replace function public.admin_money_summary()
returns table (
  charged_cents        bigint,
  declined_count       int,
  declined_cents       bigint,
  not_charged_count    int,
  not_charged_cents    bigint,
  not_charged_clinics  int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
  with fees as (
    select x.id, x.amount_cents
      from public.payments x
     where x.kind <> 'refund' and x.status = 'succeeded'
       and public.payment_is_real(x.livemode)
  ),
  refunded as (
    select x.amount_cents
      from public.payments x
      join fees f on f.id = x.refunds_payment_id
     where x.kind = 'refund' and x.status = 'succeeded'
       and public.payment_is_real(x.livemode)
  ),
  m as (select * from public.money_rows())
  select (coalesce((select sum(f.amount_cents) from fees f), 0)
        - coalesce((select sum(x.amount_cents) from refunded x), 0))::bigint,
         (select count(*) from m where m.state = 'declined')::int,
         (select coalesce(sum(m.attempted_cents), 0) from m where m.state = 'declined')::bigint,
         (select count(*) from m where m.state = 'not_charged')::int,
         (select coalesce(sum(m.amount_cents), 0) from m where m.state = 'not_charged')::bigint,
         (select count(distinct m.clinic_id) from m where m.state = 'not_charged')::int;
end;
$$;

create or replace function public.admin_money_clinics()
returns table (
  clinic_id          uuid,
  clinic_name        text,
  starts_at          timestamptz,
  canceled           boolean,
  charged_cents      bigint,
  declined_count     int,
  not_charged_count  int,
  not_charged_cents  bigint,
  chargeable_count   int)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
  with fees as (
    select x.id, r.clinic_id as cid, x.amount_cents as cents
      from public.payments x
      join public.registrations r on r.id = x.registration_id
     where x.kind <> 'refund' and x.status = 'succeeded'
       and public.payment_is_real(x.livemode)
  ),
  moves as (
    select f.cid, f.cents::bigint as cents from fees f
    union all
    select f.cid, -x.amount_cents::bigint
      from public.payments x
      join fees f on f.id = x.refunds_payment_id
     where x.kind = 'refund' and x.status = 'succeeded'
       and public.payment_is_real(x.livemode)
  ),
  got as (
    select mv.cid, sum(mv.cents)::bigint as cents from moves mv group by mv.cid
  ),
  owing as (
    select m.clinic_id as cid,
           count(*) filter (where m.state = 'declined')                                   as n_declined,
           count(*) filter (where m.state = 'not_charged')                                as n_not,
           coalesce(sum(m.amount_cents) filter (where m.state = 'not_charged'), 0)::bigint as c_not,
           count(*) filter (where m.state = 'not_charged' and m.has_card)                  as n_chargeable
      from public.money_rows() m
     where m.state in ('declined', 'not_charged')
     group by m.clinic_id
  )
  select c.id, c.name, c.starts_at, c.status = 'canceled',
         coalesce(g.cents, 0)::bigint,
         coalesce(o.n_declined, 0)::int,
         coalesce(o.n_not, 0)::int,
         coalesce(o.c_not, 0)::bigint,
         coalesce(o.n_chargeable, 0)::int
    from public.clinics c
    left join owing o on o.cid = c.id
    left join got g   on g.cid = c.id
   where o.cid is not null
      or coalesce(g.cents, 0) <> 0
   order by c.starts_at desc, c.name;
end;
$$;

comment on function public.admin_money_clinics() is
  'Per clinic: charged (net, real money), declined, not charged yet, and how many '
  'of those have a card (what Charge clinic would charge now). Only clinics with '
  'something open or with card income. Admin only.';

-- ------------------------------------------------------ the declined list ----
drop function if exists public.admin_money_declined();
create function public.admin_money_declined()
returns table (
  registration_id   uuid,
  clinic_id         uuid,
  clinic_name       text,
  clinic_starts_at  timestamptz,
  first_name        text,
  last_name         text,
  amount_cents      integer,
  failure_code      text,
  failure_reason    text,
  failed_at         timestamptz,
  account_deleted   boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
  select m.registration_id, m.clinic_id, c.name, c.starts_at, a.first_name, a.last_name,
         m.attempted_cents, m.failure_code, m.failure_reason, m.failed_at,
         a.deleted_at is not null
    from public.money_rows() m
    join public.clinics c  on c.id = m.clinic_id
    join public.accounts a on a.id = m.account_id
   where m.state = 'declined'
   order by m.failed_at desc, a.last_name, a.first_name;
end;
$$;

comment on function public.admin_money_declined() is
  'Registrations whose charge for what they owe failed and has not gone through '
  'since, with the cardholder''s name, Stripe''s code, and whether the account '
  'has since been deleted (Action Needed leaves those out). Admin only.';

-- ---------------------------------------------- Tara's tap per clinic ----
-- Same as 20260927100001 plus the payments_enabled_at refusal and the skip
-- of a row she marked Paid that holds no live fee.
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
  v_since  timestamptz;
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
  -- Before card payments were on, the club ran on Zelle: nothing from then
  -- is charged by card, and nothing at all while the moment is unrecorded.
  v_since := public.payments_enabled_at();
  if v_since is null or c.ends_at < v_since then
    raise exception 'clinic_before_payments' using errcode = 'P0001';
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
    -- Paid by hand (Tara's tick) and not charged: settled, not owed.
    if r.paid and not public.player_has_live_fee(r.player_id, r.clinic_id) then
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
revoke all on function public.admin_money_summary() from public, anon;
revoke all on function public.admin_money_clinics() from public, anon;
revoke all on function public.admin_money_declined() from public, anon;
grant execute on function public.admin_money_summary() to authenticated;
grant execute on function public.admin_money_clinics() to authenticated;
grant execute on function public.admin_money_declined() to authenticated;
revoke all on function public.admin_charge_clinic(uuid) from public, anon;
grant execute on function public.admin_charge_clinic(uuid) to authenticated;
