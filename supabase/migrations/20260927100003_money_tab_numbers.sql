-- 20260927100003_money_tab_numbers.sql
--
-- The Money numbers, from the ledger (MVP audit, 2026-09-27). The Money tab
-- showed Expected / Collected / Not charged yet from revenue_summary(), which
-- sums every You're In! row by the Zelle-era Paid flag: future clinics, a
-- clinic canceled by rain (cancel_clinic leaves its rows 'in') and no-shows
-- whose fee already went through all counted as not charged, late and no-show
-- fees never reached Collected (the flag flips only on a clinic fee), and its
-- Collected disagreed with the board report's "Collected by card" on the same
-- tab. Tara, 2026-09-22: "Shouldn't really be 'still owed' correct?" She is
-- right; decision 0016 relabelled the line, this replaces the arithmetic.
-- revenue_summary() stays in the database (hard rule 6); the page stops
-- calling it for money.
--
-- THE RULES (every number is Tara's only: require_admin() first, so a member
-- gets not_authorized, never a count, hard rule 1):
--
-- * CHARGED: succeeded fees (clinic, late-cancel, no-show) minus the succeeded
--   refunds of those fees, every clinic, all time. Exactly the board report's
--   "Collected by card" without the date range, so the two cannot disagree; a
--   fee taken on a clinic later canceled was taken, and counts.
--
-- * Every other number is about what is OWED, and only for clinics that have
--   ended and are not canceled. A row owes what Charge clinic would charge it:
--   You're In! owes the clinic fee, a no-show the no-show fee, a late cancel
--   without the courtesy the late-cancel fee, except when the same player
--   holds a You're In! row in that clinic (one fee per player per clinic,
--   20260927100001). Each owing row is in exactly one state:
--     charged      the player holds a live fee in that clinic (pending,
--                  processing, or succeeded and not refunded in full);
--     refunded     not that, and a fee of exactly what it owes went through
--                  on this row and was refunded in full: Tara gave it back,
--                  so it is settled, not "not charged yet";
--     declined     not those, and a charge of what it owes failed on this row;
--     not_charged  none of those: never charged, or only canceled attempts.
--   A decline is counted under Declined, not twice. Existence, not "the
--   latest row": a retry that went through is live (charged) whatever the
--   order, and every row a probe inserts shares one now(), so "latest by
--   created_at" would be a coin toss there.
--
-- * DECLINED: owing rows in the declined state, with the cardholder's name
--   (the account's, as payments_ledger shows it), the clinic, and Stripe's
--   code and sentence for the most recent failure.
-- * NOT CHARGED YET: owing rows in the not_charged state and what they owe at
--   the price snapshot, including players with no card; per clinic, how many
--   of them have a card (what one more tap of Charge clinic would charge).
--
-- money_rows() is the one definition; the three admin functions only
-- aggregate it, so the summary, the clinic rows and the declined list cannot
-- drift apart (money_reports.sql asserts the clinic rows add up).

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
  with owing as (
    select r.id, r.clinic_id, r.player_id, p.account_id, r.price_cents_charged,
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
     where c.status <> 'canceled'
       and c.ends_at <= now()
  ),
  judged as (
    select w.*,
           case
             when w.owed_kind is null then null
             when public.player_has_live_fee(w.player_id, w.clinic_id) then 'charged'
             when exists (select 1 from public.payments x
                           where x.registration_id = w.id and x.kind = w.owed_kind
                             and x.status = 'succeeded') then 'refunded'
             when exists (select 1 from public.payments x
                           where x.registration_id = w.id and x.kind = w.owed_kind
                             and x.status = 'failed') then 'declined'
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
       order by x.updated_at desc, x.created_at desc, x.id desc
       limit 1
    ) f on true;
$$;

comment on function public.money_rows() is
  'Internal. One row per registration in an ended, not canceled clinic: what it '
  'owes (the kind Charge clinic would charge, or null) and where that stands '
  '(charged, refunded, declined, not_charged). Aggregated by admin_money_*.';

revoke all on function public.money_rows() from public, anon, authenticated;

-- ------------------------------------------------------------ the summary ----
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
-- Every column reference is qualified: the RETURNS TABLE names are plpgsql
-- variables (see admin_board_report).
begin
  perform public.require_admin();
  return query
  with fees as (
    select x.id, x.amount_cents
      from public.payments x
     where x.kind <> 'refund' and x.status = 'succeeded'
  ),
  refunded as (
    select x.amount_cents
      from public.payments x
      join fees f on f.id = x.refunds_payment_id
     where x.kind = 'refund' and x.status = 'succeeded'
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

comment on function public.admin_money_summary() is
  'The Money tab''s line: charged (succeeded fees minus succeeded refunds, all '
  'time, the board report''s collected), declined, and not charged yet for '
  'ended, not canceled clinics. Admin only.';

-- ------------------------------------------------------ the clinic rows ----
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
-- Every clinic with a row that owes something, plus any clinic with net card
-- income (a canceled clinic whose fee was taken), newest first, so the
-- charged column adds up to admin_money_summary's.
begin
  perform public.require_admin();
  return query
  with fees as (
    select x.id, r.clinic_id as cid, x.amount_cents as cents
      from public.payments x
      join public.registrations r on r.id = x.registration_id
     where x.kind <> 'refund' and x.status = 'succeeded'
  ),
  moves as (
    select f.cid, f.cents::bigint as cents from fees f
    union all
    select f.cid, -x.amount_cents::bigint
      from public.payments x
      join fees f on f.id = x.refunds_payment_id
     where x.kind = 'refund' and x.status = 'succeeded'
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
     where m.owed_kind is not null
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
  'Per clinic: charged (net), declined, not charged yet, and how many of those '
  'have a card (what Charge clinic would charge now). Admin only.';

-- ------------------------------------------------------ the declined list ----
create or replace function public.admin_money_declined()
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
  failed_at         timestamptz)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
  select m.registration_id, m.clinic_id, c.name, c.starts_at, a.first_name, a.last_name,
         m.attempted_cents, m.failure_code, m.failure_reason, m.failed_at
    from public.money_rows() m
    join public.clinics c  on c.id = m.clinic_id
    join public.accounts a on a.id = m.account_id
   where m.state = 'declined'
   order by m.failed_at desc, a.last_name, a.first_name;
end;
$$;

comment on function public.admin_money_declined() is
  'Registrations whose charge for what they owe failed and has not gone through '
  'since, with the cardholder''s name and Stripe''s code. Admin only.';

-- ------------------------------------------------------------- grants ----
revoke all on function public.admin_money_summary() from public, anon;
revoke all on function public.admin_money_clinics() from public, anon;
revoke all on function public.admin_money_declined() from public, anon;
grant execute on function public.admin_money_summary() to authenticated;
grant execute on function public.admin_money_clinics() to authenticated;
grant execute on function public.admin_money_declined() to authenticated;
