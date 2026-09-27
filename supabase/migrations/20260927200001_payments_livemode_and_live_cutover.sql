-- 20260927200001_payments_livemode_and_live_cutover.sql
--
-- The switch from Stripe's sandbox to live money (MVP audit, 2026-09-27,
-- build-now item 3). One rule in three places: nothing made in test mode may
-- count as money, or pass as a card, once the live keys are in.
--
-- WHAT WAS WRONG
-- * stripe-setup-intent reused any stored stripe_customer_id, and
--   register_for_clinic treats card_last4 as proof of a card. After the key
--   swap every tester would still show "•••• 4242" and could still register;
--   every charge would then fail with "No such customer", and Change card
--   would answer a 500 the app reads as "Check your connection".
-- * payments had no livemode, so the board report would have counted sandbox
--   "collected" money as program income, and a sandbox clinic fee marked the
--   registration paid, which revenue_summary's Collected reads.
--
-- 1. payments.livemode is Stripe's own flag for the object behind the row.
--    stripe-charge writes the PaymentIntent's flag when it creates one; a
--    refund copies the payment it refunds (a Stripe Refund carries no
--    livemode, and a refund is always in its charge's mode); stripe-webhook
--    writes the signed event's flag, which is the authority. Null means
--    Stripe has not answered for this row yet, or the row is older than this
--    column. False means test mode.
--
-- 2. Test money is not money.
--    * admin_board_report and admin_board_report_clinics count no payment or
--      refund whose livemode is false. Redefined below from 20260926000010
--      with only those two conditions added.
--    * payments_sync_registration_paid ignores a row whose livemode is false:
--      a sandbox fee never marks a registration paid, so the Paid flag and
--      every number built on it (revenue_summary, revenue_by_clinic) stay
--      real-money only.
--    * payments_ledger, the Money tab's card list, keeps listing test rows
--      until the switch, so the sandbox run in docs/stripe-e2e-test.md can
--      be watched there, and hides them from the moment of the switch
--      (app_settings.stripe_live_since, written only by the cutover). A new
--      column, livemode, is appended so a screen can label them.
--
-- 3. stripe_cutover_to_live(), run ONCE, by a person, at the key swap. It is
--    not run by this migration: until the swap the testers' sandbox cards are
--    the only cards there are, and they must keep working. It
--      * nulls every account's stripe_customer_id, card_brand, card_last4 and
--        card_added_at, so the card step asks everyone for a real card;
--      * cancels every ledger row still pending or processing (its customer
--        no longer exists here, and it must never be sent with a live key);
--      * marks every row whose mode was never recorded as test mode (before
--        the swap no live key existed, so every such row is sandbox);
--      * records the moment as app_settings.stripe_live_since.
--    It refuses to run twice (already_live) and refuses once any live
--    payment exists (live_payments_exist): after that, live cards exist and
--    wiping them is not a cutover, it is data loss.
--    Callable by postgres (the SQL editor) and service_role only.
--
--    THE PROCEDURE (for the A10 row of docs/launch-checklist.md):
--      a. payments_enabled -> 'false', so no card sheet and no card step can
--         open while the keys change (ProfileView hides the card section and
--         the card step does not appear while payments are off);
--      b. swap the three Stripe secrets to live, and the webhook endpoint;
--      c. select * from public.stripe_cutover_to_live();   -- as postgres
--      d. payments_enabled -> 'true'.
--    Doing (c) before (b) leaves a window in which a member saves a sandbox
--    card after the wipe; the edge functions then self-heal (a customer the
--    live key cannot find is treated as none), but the order above has no
--    window at all.

-- ------------------------------------------------------------ column ----
alter table public.payments add column if not exists livemode boolean;

comment on column public.payments.livemode is
  'Stripe''s livemode flag for the PaymentIntent or Refund behind this row: '
  'written by stripe-charge and stripe-webhook (the signed event wins). Null '
  'until Stripe has answered, false in test mode. Test-mode rows are never '
  'money: excluded from the board report and from the Paid flag, and hidden '
  'from payments_ledger once stripe_cutover_to_live() has run.';

-- ------------------------------------------------ the Paid flag, real money only
-- Same function as 20260912000001 with the livemode guard added. The ledger
-- still drives the Paid checkbox; a test-mode row simply never touches it.
create or replace function public.payments_sync_registration_paid()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare orig public.payments;
begin
  new.updated_at := now();
  -- Test mode is not money (20260927200001): a sandbox fee succeeding does
  -- not mark anyone paid, and a sandbox refund does not unmark them.
  if new.livemode is false then
    return new;
  end if;
  if new.status = 'succeeded' and (old.status is distinct from 'succeeded') then
    if new.kind = 'clinic_fee' then
      update public.registrations set paid = true where id = new.registration_id;
    elsif new.kind = 'refund' then
      select * into orig from public.payments where id = new.refunds_payment_id;
      if orig.kind = 'clinic_fee' then
        update public.registrations set paid = false where id = new.registration_id;
      end if;
    end if;
  end if;
  return new;
end;
$$;
revoke all on function public.payments_sync_registration_paid() from public, anon, authenticated;

-- ------------------------------------------------------ the ledger view ----
-- Same view as 20260926000010, livemode appended (CREATE OR REPLACE can only
-- add columns at the end), and test rows hidden once the club is live.
create or replace view public.payments_ledger as
  select
    p.id,
    p.kind,
    p.amount_cents,
    p.currency,
    p.status,
    p.failure_reason,
    p.created_at,
    p.updated_at,
    p.registration_id,
    p.refunds_payment_id,
    p.account_id,
    a.first_name,
    a.last_name,
    c.id        as clinic_id,
    c.name      as clinic_name,
    c.starts_at as clinic_starts_at,
    p.failure_code,
    p.livemode
  from public.payments p
  join public.accounts a      on a.id = p.account_id
  join public.registrations r on r.id = p.registration_id
  join public.clinics c       on c.id = r.clinic_id
  where public.is_admin()
    and (p.livemode is not false
         or not exists (select 1 from public.app_settings s where s.key = 'stripe_live_since'));

comment on view public.payments_ledger is
  'Card payments with the player and clinic named, Stripe''s decline code and '
  'livemode. Admin only (is_admin() inside). Test-mode rows are listed until '
  'stripe_cutover_to_live() records stripe_live_since, and hidden after. Zelle '
  'is the Paid flag on registrations, not a row here.';

-- Hard rule 11, restated because the view was just replaced.
revoke all on public.payments_ledger from public, anon, authenticated;
grant select on public.payments_ledger to authenticated;

-- ------------------------------------------------------- the board report ----
-- Both functions exactly as 20260926000010, plus "livemode is not false" on
-- the fees and on the refunds that net them. Nothing else changed.
create or replace function public.admin_board_report(p_from date, p_to date)
returns table (
  period_from               date,
  period_to                 date,
  member_attendances        int,
  nonmember_attendances     int,
  member_players            int,
  nonmember_players         int,
  clinics                   int,
  fees_due_cents            bigint,
  collected_cents           bigint,
  board_share_cents         bigint,
  board_share_of_due_cents  bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- Every column reference below is qualified: in plpgsql the RETURNS TABLE
-- names (clinics, collected_cents, ...) are variables, and an unqualified
-- column of the same name would be ambiguous.
begin
  perform public.require_admin();
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'invalid_period' using errcode = '22023';
  end if;

  return query
  with attended as (
    select r.player_id,
           r.clinic_id,
           (r.was_member is true)  as member,
           r.price_cents_charged   as cents
      from public.registrations r
      join public.clinics c on c.id = r.clinic_id
     where r.status = 'in'
       and not r.no_show
       and c.status <> 'canceled'
       and c.ends_at <= now()
       and (c.starts_at at time zone 'America/New_York')::date between p_from and p_to
  ),
  fees as (
    select p.id, p.amount_cents
      from public.payments p
      join public.registrations r on r.id = p.registration_id
      join public.clinics c       on c.id = r.clinic_id
     where p.status = 'succeeded'
       and p.kind in ('clinic_fee', 'late_cancel', 'no_show')
       and p.livemode is not false          -- test mode is not income (20260927200001)
       and (c.starts_at at time zone 'America/New_York')::date between p_from and p_to
  ),
  refunded as (
    select x.amount_cents
      from public.payments x
      join fees f on f.id = x.refunds_payment_id
     where x.kind = 'refund'
       and x.status = 'succeeded'
       and x.livemode is not false
  ),
  att as (
    select count(*) filter (where a.member)                        as m_att,
           count(*) filter (where not a.member)                    as n_att,
           count(distinct a.player_id) filter (where a.member)     as m_ppl,
           count(distinct a.player_id) filter (where not a.member) as n_ppl,
           count(distinct a.clinic_id)                             as n_clinics,
           coalesce(sum(a.cents), 0)::bigint                       as due
      from attended a
  ),
  income as (
    select (coalesce((select sum(f.amount_cents) from fees f), 0)
          - coalesce((select sum(x.amount_cents) from refunded x), 0))::bigint as got
  )
  select p_from,
         p_to,
         t.m_att::int,
         t.n_att::int,
         t.m_ppl::int,
         t.n_ppl::int,
         t.n_clinics::int,
         t.due,
         i.got,
         -- Half up in both signs: floor(x + 0.5). Postgres round() on numeric
         -- goes half AWAY from zero, which is half down below zero; collected
         -- is only negative on bad data, but the rule is the rule.
         floor(i.got / 10.0 + 0.5)::bigint,
         floor(t.due / 10.0 + 0.5)::bigint
    from att t
   cross join income i;
end;
$$;

comment on function public.admin_board_report(date, date) is
  'The board report (Tara, 2026-09-26): attendance by member snapshot, fees due, '
  'card income net of refunds (live mode only, 20260927200001), and 10% of each, '
  'for New York dates p_from..p_to inclusive. Admin only. The 10% base is question 58.';

create or replace function public.admin_board_report_clinics(p_from date, p_to date)
returns table (
  clinic_id              uuid,
  clinic_name            text,
  starts_at              timestamptz,
  member_attendances     int,
  nonmember_attendances  int,
  fees_due_cents         bigint,
  collected_cents        bigint
)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- Same definitions as admin_board_report, per clinic. The probe asserts that
-- these rows add up to that function's totals, so the two copies cannot drift
-- apart without going red.
begin
  perform public.require_admin();
  if p_from is null or p_to is null or p_from > p_to then
    raise exception 'invalid_period' using errcode = '22023';
  end if;

  return query
  with attended as (
    select r.clinic_id             as cid,
           (r.was_member is true)  as member,
           r.price_cents_charged   as cents
      from public.registrations r
      join public.clinics c on c.id = r.clinic_id
     where r.status = 'in'
       and not r.no_show
       and c.status <> 'canceled'
       and c.ends_at <= now()
       and (c.starts_at at time zone 'America/New_York')::date between p_from and p_to
  ),
  fees as (
    select p.id, r.clinic_id as cid, p.amount_cents as cents
      from public.payments p
      join public.registrations r on r.id = p.registration_id
      join public.clinics c       on c.id = r.clinic_id
     where p.status = 'succeeded'
       and p.kind in ('clinic_fee', 'late_cancel', 'no_show')
       and p.livemode is not false          -- test mode is not income (20260927200001)
       and (c.starts_at at time zone 'America/New_York')::date between p_from and p_to
  ),
  movements as (
    select f.cid, f.cents::bigint as cents from fees f
    union all
    select f.cid, -x.amount_cents::bigint
      from public.payments x
      join fees f on f.id = x.refunds_payment_id
     where x.kind = 'refund'
       and x.status = 'succeeded'
       and x.livemode is not false
  ),
  att as (
    select a.cid,
           count(*) filter (where a.member)     as m_att,
           count(*) filter (where not a.member) as n_att,
           coalesce(sum(a.cents), 0)::bigint    as due
      from attended a
     group by a.cid
  ),
  got as (
    select m.cid, sum(m.cents)::bigint as cents
      from movements m
     group by m.cid
  )
  select c.id,
         c.name,
         c.starts_at,
         coalesce(t.m_att, 0)::int,
         coalesce(t.n_att, 0)::int,
         coalesce(t.due, 0)::bigint,
         coalesce(g.cents, 0)::bigint
    from public.clinics c
    left join att t on t.cid = c.id
    left join got g on g.cid = c.id
   where t.cid is not null
      or coalesce(g.cents, 0) <> 0
   order by c.starts_at, c.name;
end;
$$;

comment on function public.admin_board_report_clinics(date, date) is
  'The board report per clinic: every clinic somebody attended in the period, '
  'plus any with net live card income and no attendance, so the rows add up to '
  'admin_board_report. Admin only.';

revoke all on function public.admin_board_report(date, date) from public, anon;
revoke all on function public.admin_board_report_clinics(date, date) from public, anon;
grant execute on function public.admin_board_report(date, date) to authenticated;
grant execute on function public.admin_board_report_clinics(date, date) to authenticated;

-- ------------------------------------------------------------ the cutover ----
-- SECURITY INVOKER on purpose: nothing about it should run with more rights
-- than the person running it, and the two roles allowed to run it (postgres,
-- service_role) already hold DML on every table and bypass RLS.
create or replace function public.stripe_cutover_to_live()
returns table (
  accounts_cleared      int,
  payments_canceled     int,
  payments_marked_test  int,
  live_since            timestamptz
)
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_accounts int;
  v_canceled int;
  v_marked   int;
  v_at       timestamptz := now();
begin
  -- Once. A second run after the swap would wipe members' real cards.
  if exists (select 1 from public.app_settings s where s.key = 'stripe_live_since') then
    raise exception 'already_live' using errcode = 'P0001';
  end if;
  -- Too late: a live payment means live cards exist, and they are not ours to wipe.
  if exists (select 1 from public.payments p where p.livemode is true) then
    raise exception 'live_payments_exist' using errcode = 'P0001';
  end if;

  -- Every Stripe customer and card summary made so far belongs to test mode.
  -- With them gone, register_for_clinic asks for a card again (card_required)
  -- and the app's card step opens for everyone.
  update public.accounts a
     set stripe_customer_id = null, card_brand = null, card_last4 = null, card_added_at = null
   where a.stripe_customer_id is not null or a.card_brand is not null
      or a.card_last4 is not null or a.card_added_at is not null;
  get diagnostics v_accounts = row_count;

  -- Nothing still waiting may be sent with the live key. Conditional on the
  -- status (hard rule 3); the row stays, as canceled (hard rule 4).
  update public.payments p
     set status = 'canceled', failure_reason = 'live_cutover'
   where p.status in ('pending', 'processing');
  get diagnostics v_canceled = row_count;

  -- Before the swap no live key existed, so a row whose mode was never
  -- recorded is test mode.
  update public.payments p
     set livemode = false
   where p.livemode is null;
  get diagnostics v_marked = row_count;

  insert into public.app_settings (key, value) values ('stripe_live_since', v_at::text);

  return query select v_accounts, v_canceled, v_marked, v_at;
end;
$$;

comment on function public.stripe_cutover_to_live() is
  'Run once at the Stripe key swap (sandbox -> live), as postgres or service_role: '
  'clears every Stripe customer and card summary, cancels ledger rows still '
  'pending or processing, marks rows with no recorded mode as test mode, records '
  'app_settings.stripe_live_since. Refuses a second run and refuses once any live '
  'payment exists. 20260927200001.';

-- Hard rule 11: PUBLIC first. No client role may run it; service_role may,
-- so the lead can run it through the API as well as from the SQL editor.
revoke all on function public.stripe_cutover_to_live() from public, anon, authenticated;
grant execute on function public.stripe_cutover_to_live() to service_role;
