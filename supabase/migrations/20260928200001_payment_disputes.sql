-- 20260928200001_payment_disputes.sql
--
-- Chargebacks (Stripe "disputes") on card payments, so Tara hears about one
-- from her own admin instead of from Stripe's dashboard (Alex, 2026-09-27:
-- Payouts and dispute alerts, "so she never needs the Stripe dashboard day to
-- day"). A dispute is the cardholder's bank taking a payment back; Tara
-- answers it in Stripe with evidence, by a deadline.
--
-- ------------------------------------------------------------ THE SHAPE ----
-- 1. Eight columns on payments, written only by the stripe-webhook edge
--    function (service_role) through stripe_record_dispute() below, on
--    charge.dispute.created / .updated / .closed:
--      stripe_dispute_id        Stripe's id (dp_...)
--      dispute_status           Stripe's word: warning_needs_response,
--                               warning_under_review, warning_closed (an
--                               inquiry), needs_response, under_review, won, lost
--      dispute_reason           Stripe's code (fraudulent, product_not_received, ...)
--      dispute_amount_cents     what the bank disputes (can be less than the fee)
--      dispute_withdrawn_cents  what Stripe has actually taken from the club's
--                               balance for it, net of anything given back and
--                               not counting Stripe's fee: minus the sum of the
--                               dispute's balance_transactions. 0 for an
--                               inquiry, for a won dispute, and for a charge
--                               already refunded in full (Stripe, on
--                               is_charge_refundable: "After the payment has
--                               been fully refunded, no further funds are
--                               withdrawn from your Stripe account as a result
--                               of this dispute.")
--      disputed_at              when the dispute was opened (Stripe's created)
--      dispute_due_by           Stripe's respond-by (evidence_details.due_by);
--                               null when there is none
--      dispute_event_at         the Stripe event that last wrote the others
--    authenticated gets NO privilege on any of them: payments' SELECT for
--    authenticated is a column list since 20260927300003, and these are not
--    in it. A member cannot read the dispute on a payment, not even their own
--    (they can see its updated_at move, which says only that the row changed;
--    they filed the dispute themselves). Tara reads disputes through
--    admin_money_disputes() and payments_ledger.
--
-- 2. stripe_record_dispute(): the rule for writing them, in one conditional
--    UPDATE (hard rule 3). The fee is found by the PaymentIntent the ledger
--    stores; failing that, by the row the PaymentIntent's metadata names
--    (fxe_payment_id, read by the webhook), if that row has no PaymentIntent
--    yet: a held charge Tara marked "Went through" never learns its id
--    (admin_resolve_held_payment), and its dispute must still land. That id
--    is then stored, as recordPaymentOutcome does. Stripe does not deliver
--    events in order and retries a failed delivery for days, so:
--      * an event older than the one already recorded changes nothing;
--      * a decided dispute (won, lost, warning_closed) is never reopened by a
--        created/updated event for the same dispute, late, in the same second
--        or later;
--      * a replayed event writes the same values again: idempotent;
--      * a LOST dispute is never replaced by a different dispute on the same
--        payment. These columns hold one dispute per payment; replacing a
--        lost one would silently give its money back to the numbers.
--    It answers 'recorded', 'stale' (the event is older, or would reopen a
--    decision), 'second_dispute' (another dispute on a payment whose dispute
--    was lost: kept out, Stripe's own dispute email still reaches the
--    account) or 'no_payment' (no charge of this app: a dispute on something
--    else in Tara's Stripe account). It never touches the fee's status or
--    amount, the Paid flag, or any other row. SECURITY INVOKER and
--    service_role only, like stripe_cutover_to_live().
--
-- 3. admin_money_disputes(): Tara's list of OPEN disputes (every status but
--    won, lost and warning_closed), with the cardholder's name, the clinic,
--    the disputed amount, Stripe's reason and respond-by, soonest deadline
--    first. Test-mode disputes follow payment_is_real(): listed while the
--    sandbox is the payment system, gone once the club is live. Admin only.
--
-- 4. payments_ledger gains dispute_status (appended), so the Money tab's card
--    list can say "Disputed", "Dispute won" or "Dispute lost" on the payment.
--
-- ------------------------------------------------------- THE MONEY RULE ----
-- A LOST dispute is money that left, the same as a refund Tara did not choose.
-- So "Collected by card" in the board report and "Charged" on the Money tab
-- subtract what Stripe withdrew for every lost dispute on a fee they count
-- (dispute_withdrawn_cents; admin_board_report, admin_board_report_clinics,
-- admin_money_summary, admin_money_clinics, redefined below with only that
-- change). Like a refund, it counts in the month of the clinic, whenever it
-- happens. Pinned with hand-worked values in tests/sql/money_reports.sql.
--   * What Stripe withdrew, not what the bank disputed: they differ when the
--     charge was already refunded (Stripe withdraws nothing more), so the
--     refund and the dispute never both come off the same money.
--   * An OPEN dispute subtracts nothing, though Stripe may already hold the
--     money: it may be won. It is shown instead, in Action Needed (web and
--     phone) and on the ledger row.
--   * A WON dispute and a closed inquiry subtract nothing.
--   * Stripe's dispute fee is not in this ledger, like every other Stripe fee
--     (the board report is gross; question 58).
--   * money_rows() is deliberately UNCHANGED. A fee with a lost dispute stays
--     'charged' and keeps the one-fee slot (registration_has_live_fee), so
--     Charge clinic never charges that player again for that clinic. Charging
--     a card again after the bank sided with the cardholder is Tara's call to
--     make in Stripe, not the app's (CLAUDE.md: when unsure, leave it to Tara).
--     Pinned in tests/sql/money_since_payments_on.sql.
--   * The registration's Paid flag is not touched by a dispute.

-- ------------------------------------------------------------ columns ----
alter table public.payments
  add column if not exists stripe_dispute_id    text,
  add column if not exists dispute_status       text,
  add column if not exists dispute_reason       text,
  add column if not exists dispute_amount_cents integer,
  add column if not exists dispute_withdrawn_cents integer,
  add column if not exists disputed_at          timestamptz,
  add column if not exists dispute_due_by       timestamptz,
  add column if not exists dispute_event_at     timestamptz;

do $$ begin
  alter table public.payments add constraint payments_dispute_complete
    check (dispute_status is null
           or (stripe_dispute_id is not null and dispute_amount_cents is not null
               and dispute_amount_cents >= 0 and dispute_withdrawn_cents is not null
               and dispute_withdrawn_cents >= 0 and dispute_event_at is not null));
exception when duplicate_object then null; end $$;

comment on column public.payments.stripe_dispute_id is
  'Stripe''s dispute id (dp_...) on this payment, if the cardholder''s bank disputed it. '
  'Written only by stripe-webhook through stripe_record_dispute(). 20260928200001.';
comment on column public.payments.dispute_status is
  'Stripe''s dispute status: warning_needs_response, warning_under_review, warning_closed, '
  'needs_response, under_review, won, lost. A lost dispute is subtracted from Charged and '
  'Collected by card. Service role only. 20260928200001.';
comment on column public.payments.dispute_reason is
  'Stripe''s dispute reason code (fraudulent, product_not_received, ...). 20260928200001.';
comment on column public.payments.dispute_amount_cents is
  'What the bank is taking back, in cents; can be less than the fee. 20260928200001.';
comment on column public.payments.dispute_withdrawn_cents is
  'What Stripe has taken from the club''s balance for the dispute, net of anything given '
  'back, not counting Stripe''s fee (minus the sum of its balance_transactions). What a '
  'lost dispute subtracts from Charged and Collected. 20260928200001.';
comment on column public.payments.disputed_at is
  'When the dispute was opened (Stripe''s created). 20260928200001.';
comment on column public.payments.dispute_due_by is
  'Stripe''s respond-by (evidence_details.due_by); null when there is none. 20260928200001.';
comment on column public.payments.dispute_event_at is
  'The created time of the Stripe event that last wrote the dispute columns; an older '
  'event never overwrites a newer one. 20260928200001.';

-- No client privilege on any of the eight. Nothing to revoke (20260927300003
-- replaced authenticated's table SELECT with a column list that does not
-- name them), and nothing is granted here. service_role holds table-level DML
-- (20260912000002), which covers new columns.

-- ------------------------------------------------ the webhook's writer ----
create or replace function public.stripe_record_dispute(
  p_payment_intent  text,
  p_dispute_id      text,
  p_status          text,
  p_reason          text,
  p_amount_cents    integer,
  p_withdrawn_cents integer,
  p_disputed_at     timestamptz,
  p_due_by          timestamptz,
  p_event_at        timestamptz,
  p_payment_id      uuid default null)
returns text
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_row   public.payments;
  v_id    uuid;
  decided constant text[] := array['won', 'lost', 'warning_closed'];
begin
  if p_payment_intent is null or p_dispute_id is null or p_status is null
     or p_amount_cents is null or p_amount_cents < 0
     or p_withdrawn_cents is null or p_withdrawn_cents < 0 or p_event_at is null then
    raise exception 'dispute_incomplete' using errcode = '22023';
  end if;

  -- The fee: by its PaymentIntent, else the row the PaymentIntent's metadata
  -- names, only while that row has no PaymentIntent of its own.
  select * into v_row from public.payments p
   where p.stripe_payment_intent_id = p_payment_intent and p.kind <> 'refund';
  if v_row.id is null and p_payment_id is not null then
    select * into v_row from public.payments p
     where p.id = p_payment_id and p.kind <> 'refund' and p.stripe_payment_intent_id is null;
  end if;
  if v_row.id is null then
    return 'no_payment';
  end if;

  -- The guards live in the WHERE, so they are checked again on the locked
  -- row if another delivery of this dispute committed in between.
  update public.payments p
     set stripe_payment_intent_id = p_payment_intent,
         stripe_dispute_id        = p_dispute_id,
         dispute_status           = p_status,
         dispute_reason           = p_reason,
         dispute_amount_cents     = p_amount_cents,
         dispute_withdrawn_cents  = p_withdrawn_cents,
         disputed_at              = p_disputed_at,
         dispute_due_by           = p_due_by,
         dispute_event_at         = p_event_at
   where p.id = v_row.id
     and p.kind <> 'refund'
     and (p.stripe_payment_intent_id = p_payment_intent or p.stripe_payment_intent_id is null)
     -- An older event never overwrites a newer one.
     and (p.dispute_event_at is null or p.dispute_event_at <= p_event_at)
     -- A decided dispute stays decided: only another decision replaces it.
     and not (p.stripe_dispute_id is not distinct from p_dispute_id
              and coalesce(p.dispute_status = any (decided), false)
              and not (p_status = any (decided)))
     -- A lost dispute is never replaced by another one: its money stays out.
     and not (p.stripe_dispute_id is distinct from p_dispute_id
              and coalesce(p.dispute_status = 'lost', false))
  returning p.id into v_id;

  if v_id is not null then
    return 'recorded';
  end if;
  select * into v_row from public.payments p where p.id = v_row.id;
  if v_row.stripe_dispute_id is distinct from p_dispute_id and v_row.dispute_status = 'lost' then
    return 'second_dispute';
  end if;
  return 'stale';
end;
$$;

comment on function public.stripe_record_dispute(text, text, text, text, integer, integer, timestamptz, timestamptz, timestamptz, uuid) is
  'stripe-webhook''s writer for charge.dispute.* events: records the dispute on the fee '
  'with that PaymentIntent (or the held row its metadata names) unless the event is older '
  'than the one recorded, would reopen a decided dispute, or is a second dispute on a '
  'payment whose dispute was lost. Answers recorded, stale, second_dispute or no_payment. '
  'service_role only. 20260928200001.';

-- Hard rule 11: PUBLIC first. No client role may run it; the webhook runs as
-- service_role.
revoke all on function public.stripe_record_dispute(text, text, text, text, integer, integer, timestamptz, timestamptz, timestamptz, uuid)
  from public, anon, authenticated;
grant execute on function public.stripe_record_dispute(text, text, text, text, integer, integer, timestamptz, timestamptz, timestamptz, uuid)
  to service_role;

-- --------------------------------------------------- Tara's open list ----
create or replace function public.admin_money_disputes()
returns table (
  payment_id        uuid,
  registration_id   uuid,
  clinic_id         uuid,
  clinic_name       text,
  clinic_starts_at  timestamptz,
  first_name        text,
  last_name         text,
  amount_cents      integer,
  reason            text,
  status            text,
  respond_by        timestamptz,
  disputed_at       timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
-- Every column reference is qualified: the RETURNS TABLE names are plpgsql
-- variables (see admin_board_report).
begin
  perform public.require_admin();
  return query
  select p.id, p.registration_id, c.id, c.name, c.starts_at, a.first_name, a.last_name,
         p.dispute_amount_cents, p.dispute_reason, p.dispute_status, p.dispute_due_by, p.disputed_at
    from public.payments p
    join public.registrations r on r.id = p.registration_id
    join public.clinics c       on c.id = r.clinic_id
    join public.accounts a      on a.id = p.account_id
   where p.dispute_status is not null
     and p.dispute_status not in ('won', 'lost', 'warning_closed')
     and public.payment_is_real(p.livemode)
   order by p.dispute_due_by nulls last, p.disputed_at, p.id;
end;
$$;

comment on function public.admin_money_disputes() is
  'Open disputes on card payments (every Stripe status but won, lost and warning_closed), '
  'with the cardholder''s name, the clinic, the disputed amount, Stripe''s reason and '
  'respond-by, soonest deadline first. Admin only. 20260928200001.';

revoke all on function public.admin_money_disputes() from public, anon;
grant execute on function public.admin_money_disputes() to authenticated;

-- ------------------------------------------------------ the ledger view ----
-- Same view as 20260927200001 with dispute_status appended (CREATE OR REPLACE
-- can only add columns at the end).
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
    p.livemode,
    p.dispute_status
  from public.payments p
  join public.accounts a      on a.id = p.account_id
  join public.registrations r on r.id = p.registration_id
  join public.clinics c       on c.id = r.clinic_id
  where public.is_admin()
    and (p.livemode is not false
         or not exists (select 1 from public.app_settings s where s.key = 'stripe_live_since'));

comment on view public.payments_ledger is
  'Card payments with the player and clinic named, Stripe''s decline code, livemode and '
  'dispute status. Admin only (is_admin() inside). Test-mode rows are listed until '
  'stripe_cutover_to_live() records stripe_live_since, and hidden after. Zelle is the Paid '
  'flag on registrations, not a row here.';

-- Hard rule 11, restated because the view was just replaced.
revoke all on public.payments_ledger from public, anon, authenticated;
grant select on public.payments_ledger to authenticated;

-- ---------------------------------------------------- the board report ----
-- Both functions exactly as 20260927200001, plus: a lost dispute on a
-- counted fee is subtracted (lost_cents). Nothing else changed.
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
    select p.id, p.amount_cents,
           -- A lost dispute: what Stripe withdrew for it left (20260928200001).
           case when p.dispute_status = 'lost' then p.dispute_withdrawn_cents else 0 end as lost_cents
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
          - coalesce((select sum(x.amount_cents) from refunded x), 0)
          - coalesce((select sum(f.lost_cents) from fees f), 0))::bigint as got
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
  'card income net of refunds and lost disputes (live mode only, 20260927200001; '
  'disputes 20260928200001), and 10% of each, for New York dates p_from..p_to '
  'inclusive. Admin only. The 10% base is question 58.';

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
    select p.id, r.clinic_id as cid, p.amount_cents as cents,
           case when p.dispute_status = 'lost' then p.dispute_withdrawn_cents else 0 end as lost_cents
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
    union all
    -- A lost dispute is money that left (20260928200001).
    select f.cid, -f.lost_cents::bigint from fees f where f.lost_cents <> 0
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
  'admin_board_report. Net of refunds and lost disputes. Admin only.';

revoke all on function public.admin_board_report(date, date) from public, anon;
revoke all on function public.admin_board_report_clinics(date, date) from public, anon;
grant execute on function public.admin_board_report(date, date) to authenticated;
grant execute on function public.admin_board_report_clinics(date, date) to authenticated;

-- -------------------------------------------------------- the Money tab ----
-- Both functions exactly as 20260927300001, plus the same lost-dispute
-- subtraction, so Charged stays the board report's collected over all time.
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
    select x.id, x.amount_cents,
           case when x.dispute_status = 'lost' then x.dispute_withdrawn_cents else 0 end as lost_cents
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
        - coalesce((select sum(x.amount_cents) from refunded x), 0)
        - coalesce((select sum(f.lost_cents) from fees f), 0))::bigint,
         (select count(*) from m where m.state = 'declined')::int,
         (select coalesce(sum(m.attempted_cents), 0) from m where m.state = 'declined')::bigint,
         (select count(*) from m where m.state = 'not_charged')::int,
         (select coalesce(sum(m.amount_cents), 0) from m where m.state = 'not_charged')::bigint,
         (select count(distinct m.clinic_id) from m where m.state = 'not_charged')::int;
end;
$$;

comment on function public.admin_money_summary() is
  'The Money tab''s line: charged (succeeded fees minus succeeded refunds and lost '
  'disputes, all time, real money: the board report''s collected), declined, and not '
  'charged yet for ended, not canceled clinics. Admin only.';

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
    select x.id, r.clinic_id as cid, x.amount_cents as cents,
           case when x.dispute_status = 'lost' then x.dispute_withdrawn_cents else 0 end as lost_cents
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
    union all
    -- A lost dispute is money that left (20260928200001).
    select f.cid, -f.lost_cents::bigint from fees f where f.lost_cents <> 0
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
  'Per clinic: charged (net of refunds and lost disputes, real money), declined, not '
  'charged yet, and how many of those have a card (what Charge clinic would charge '
  'now). Only clinics with something open or with card income. Admin only.';

revoke all on function public.admin_money_summary() from public, anon;
revoke all on function public.admin_money_clinics() from public, anon;
grant execute on function public.admin_money_summary() to authenticated;
grant execute on function public.admin_money_clinics() to authenticated;
