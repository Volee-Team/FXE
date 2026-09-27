-- 20260926000010_money_reports.sql
--
-- The board report, and why a card was declined. Tara's "Final Updates" doc,
-- 2026-09-26, verbatim:
--
--   "is there a report on the app I can upload and send to the board for
--    their 10% back of the program."
--   "app report shows # of members and nonmembers that attended and total
--    income. In addition to what 10% of that income is."
--
-- and, from Kat and Tara on the admin panel:
--
--   "IF the reason codes are easily passed from Strip, then please include
--    those with cardholder name where the card was charged and declined
--    (i.e. NSF, Card Expired, Etc)."
--
-- ------------------------------------------------------------ DECLINES ----
-- payments.failure_code is Stripe's machine code for a decline: decline_code
-- when Stripe sends one (insufficient_funds, expired_card, do_not_honor,
-- lost_card, ...), else the error's code (card_declined, incorrect_cvc,
-- authentication_required, processing_error, ...). failure_reason stays: it is
-- Stripe's sentence, and the page falls back to it when there is no code.
-- Written only by the stripe-webhook and stripe-charge edge functions
-- (service_role); no client role can write payments at all (hard rule 11).
-- The page turns the code into words ("Insufficient funds (NSF)"); the
-- database keeps what Stripe said, so a new label never needs a migration.
--
-- --------------------------------------------------------- THE REPORT ----
-- admin_board_report(p_from, p_to): one row. admin_board_report_clinics: the
-- per-clinic rows behind it, for the CSV the board gets.
--
-- ATTENDED means a registration that is You're In! (status 'in'), not marked a
-- no-show, in a clinic that is not canceled and has ended (ends_at <= now()),
-- whose start falls on a New York calendar date between p_from and p_to,
-- inclusive at both ends.
--
--   member_attendances / nonmember_attendances  count of attended rows
--   member_players / nonmember_players          the same rows, distinct people
--   clinics                                     distinct clinics among them
--   fees_due_cents     sum of price_cents_charged over the attended rows: what
--                      attendance was worth at the prices charged
--   collected_cents    succeeded card payments of kind clinic_fee, late_cancel
--                      or no_show whose clinic starts in the period, minus the
--                      succeeded refunds of exactly those payments. Late-cancel
--                      and no-show fees are program income, so they count here
--                      even though those people did not attend.
--   board_share_cents          10% of collected, rounded half up (toward
--                              +infinity at exactly half a cent, negatives too)
--   board_share_of_due_cents   10% of fees due, the same rounding
--
-- WHY each choice:
-- * Member or not is registrations.was_member, the snapshot taken at
--   registration (decision 0002), NOT players.is_member. Tara corrects
--   membership later (admin_set_membership); a correction in October must not
--   rewrite what August's report told the board. A row with no snapshot (none
--   since 2026-08-10: every write path sets it) counts as non-member, so the
--   two attendance numbers always add up to the attended total. A person
--   whose membership changed between two registrations in one period is one
--   member player AND one non-member player: that is what they attended as.
-- * The period is New York calendar dates, like the service week (decision
--   0001). A 9 pm Saturday clinic on the 31st is 01:00 UTC on the 1st;
--   bucketing by the UTC date would move it into next month's report.
-- * Two 10% numbers because until Stripe is live nothing is "collected" by
--   card (payments_enabled is false; the Zelle checkbox is not in this ledger).
--   Collected is the one we would send; fees due is what it would be if every
--   attendance were paid at its snapshot price. The web labels both.
-- * The per-clinic rows are the attended clinics PLUS any clinic in the
--   period with net card income but nobody attended (everyone a no-show or a
--   late cancel). Without those rows the CSV's clinic lines would not add up
--   to its totals line, and a board reads a column total first. `clinics` in
--   the summary stays "clinics somebody attended".
-- * A CANCELED CLINIC WHOSE FEE WAS TAKEN (Tara charged before canceling, or
--   a late-cancel fee on a clinic she later called off): nobody attended, so
--   it adds nothing to attendance, fees due or `clinics`, but the money was
--   taken, so it counts in collected and gets its own clinic row reading
--   0 | 0 | $0.00 | the fee. If she refunds it, the refund nets it to zero and
--   the row disappears. The probe pins this case by name.
-- * A registration with no was_member snapshot counts as non-member (above);
--   one with no price snapshot adds nothing to fees due.
--
-- OPEN: the 10% base (collected vs due, gross vs net of Stripe's fee) is
-- question 58 for Tara; default gross collected. Until she answers, both
-- numbers are shown and neither has Stripe's fee taken out. Two more are
-- with Alex to relay (numbered on the questions branch): a refund made after
-- a month's report was sent lands in the month of the clinic, so re-running
-- that month gives a smaller number than the board already has (default kept:
-- by clinic date); and late-cancel and no-show fees count as program income
-- (default kept: they count).
--
-- REFUNDS count by the clinic of the payment they refund, whenever they
-- happen, and only once succeeded. A refund made in Stripe's dashboard is
-- recorded by the stripe-webhook edge function as its own row (see
-- supabase/functions/README.md), so it reaches this report the same way.
--
-- GUARDS: SECURITY DEFINER (they read registrations and clinics, which no
-- client can), search_path pinned, require_admin() first so a member gets
-- not_authorized rather than a row of zeroes, invalid_period for a null or
-- backwards range. Revoked from PUBLIC and anon, granted to authenticated
-- (hard rule 11: revoke from anon alone is decoration while PUBLIC holds it).
-- Returns counts and money only to Tara; hard rule 1's "never return a count
-- to a player" is kept by require_admin(), and the probe attacks it.

-- ------------------------------------------------------------ column ----
alter table public.payments add column if not exists failure_code text;

comment on column public.payments.failure_code is
  'Stripe''s machine code for a decline: decline_code when present, else code '
  '(insufficient_funds, expired_card, card_declined, ...). Written only by the '
  'Stripe edge functions. failure_reason keeps Stripe''s sentence.';

-- ------------------------------------------------------ one live charge ----
-- The report sums the ledger, so a doubled row is a doubled number in front
-- of the board. admin_charge_registration and admin_refund_payment each check
-- "is there already a live one?" and then insert: two taps in the same
-- instant both pass the check (neither sees the other's uncommitted row) and
-- both insert. Hard rule 3's lesson for status writes applies to inserts too:
-- the check has to be a constraint, not a read. These make the second insert
-- fail; 20260926000001 turns that failure into already_charged.
--
-- Charges: at most one pending, processing or succeeded row per registration
-- and kind. A failed or canceled one does not block a retry (that is how
-- "a failed fee can be charged again" works).
create unique index if not exists payments_one_live_charge
  on public.payments (registration_id, kind)
  where kind <> 'refund' and status in ('pending', 'processing', 'succeeded');

-- Refunds: at most one live refund per payment AMONG THE ONES THE APP ASKED
-- FOR (stripe_refund_id is null until stripe-charge has called Stripe, which
-- is exactly the window in which two taps race). Deliberately narrower than
-- "one live refund per payment": refunds are made in Stripe's dashboard in v1
-- (Kat, 2026-09-22), the webhook records each one as its own row with its
-- Stripe id, and two partial refunds of one charge are two real refunds. An
-- index over every live refund would make the webhook's second insert fail
-- and the money would go unrecorded. admin_refund_payment's own check still
-- refuses an app refund once any live refund exists.
create unique index if not exists payments_one_live_app_refund
  on public.payments (refunds_payment_id)
  where kind = 'refund' and status in ('pending', 'processing', 'succeeded')
    and stripe_refund_id is null;

-- ------------------------------------------------------ the ledger view ----
-- Same view as 20260912000003 with failure_code appended. CREATE OR REPLACE
-- can only add columns at the end, which is also what keeps every existing
-- column in its place for the page's select("*").
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
    p.failure_code
  from public.payments p
  join public.accounts a      on a.id = p.account_id
  join public.registrations r on r.id = p.registration_id
  join public.clinics c       on c.id = r.clinic_id
  where public.is_admin();

comment on view public.payments_ledger is
  'Card payments with the player and clinic named, and Stripe''s decline code. '
  'Admin only (is_admin() inside). Zelle is the Paid flag on registrations, not a row here.';

-- Hard rule 11, restated because this view was just replaced: revoke, then
-- grant exactly what the page reads.
revoke all on public.payments_ledger from public, anon, authenticated;
grant select on public.payments_ledger to authenticated;

-- ------------------------------------------------------- the summary ----
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
       and (c.starts_at at time zone 'America/New_York')::date between p_from and p_to
  ),
  refunded as (
    select x.amount_cents
      from public.payments x
      join fees f on f.id = x.refunds_payment_id
     where x.kind = 'refund'
       and x.status = 'succeeded'
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
  'card income net of refunds, and 10% of each, for New York dates p_from..p_to '
  'inclusive. Admin only. The 10% base is question 58.';

-- ---------------------------------------------------- the clinic rows ----
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
  'plus any with net card income and no attendance, so the rows add up to '
  'admin_board_report. Admin only.';

-- ------------------------------------------------------------ grants ----
revoke all on function public.admin_board_report(date, date) from public, anon;
revoke all on function public.admin_board_report_clinics(date, date) from public, anon;
grant execute on function public.admin_board_report(date, date) to authenticated;
grant execute on function public.admin_board_report_clinics(date, date) to authenticated;
