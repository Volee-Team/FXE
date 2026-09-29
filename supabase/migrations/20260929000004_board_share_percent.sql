-- 20260929000004_board_share_percent.sql
--
-- The board report's share is Tara's rate, not a fixed 10%.
--
-- Tara, 2026-09-29 (relayed by Alex): "Sorry I pay Foxcroft 10% of revenue.
-- But asking I pay them 8% revenue instead since stripe will take 2.9% of
-- every transaction. So when the app records how much I owe them I'm hoping
-- it's 7 or 8% and not 10%". The deal is not settled, so the rate is hers to
-- set on the Money tab and stays 10 until she changes it (question 101).
--
-- Where it lives: admin_settings, a new table no client can read. Not
-- app_settings, which every signed-in member may read: what the club pays
-- Foxcroft is business between Tara and the club, not a player-safe string.

create table public.admin_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);
alter table public.admin_settings enable row level security;
revoke all on table public.admin_settings from public, anon, authenticated;
grant select, insert, update, delete on table public.admin_settings to service_role;

insert into public.admin_settings (key, value) values ('board_share_percent', '10');

-- Internal: the rate as a number. Not a client RPC.
create or replace function public.board_share_percent()
returns numeric language sql stable security definer
set search_path = public, pg_temp as $$
  select coalesce((select value::numeric from public.admin_settings where key = 'board_share_percent'), 10);
$$;
revoke all on function public.board_share_percent() from public, anon, authenticated;

-- Tara reads and sets it (the Money tab). 0 to 25, at most one decimal.
create or replace function public.admin_board_share_percent()
returns numeric language plpgsql stable security definer
set search_path = public, pg_temp as $$
begin
  perform public.require_admin();
  return public.board_share_percent();
end; $$;
revoke all on function public.admin_board_share_percent() from public, anon;
grant execute on function public.admin_board_share_percent() to authenticated;

create or replace function public.admin_set_board_share_percent(p_percent numeric)
returns numeric language plpgsql volatile security definer
set search_path = public, pg_temp as $$
begin
  perform public.require_admin();
  if p_percent is null or p_percent < 0 or p_percent > 25 or p_percent <> round(p_percent, 1) then
    raise exception 'percent_out_of_range' using errcode = '22023';
  end if;
  update public.admin_settings set value = p_percent::text, updated_at = now()
   where key = 'board_share_percent';
  return p_percent;
end; $$;
revoke all on function public.admin_set_board_share_percent(numeric) from public, anon;
grant execute on function public.admin_set_board_share_percent(numeric) to authenticated;

-- The report: the same body as 20260928200001, with the rate in place of 10.
create or replace function public.admin_board_report(p_from date, p_to date)
 RETURNS TABLE(period_from date, period_to date, member_attendances integer, nonmember_attendances integer, member_players integer, nonmember_players integer, clinics integer, fees_due_cents bigint, collected_cents bigint, board_share_cents bigint, board_share_of_due_cents bigint)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- Every column reference below is qualified: in plpgsql the RETURNS TABLE
-- names (clinics, collected_cents, ...) are variables, and an unqualified
-- column of the same name would be ambiguous.
declare
  v_pct numeric := public.board_share_percent();
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
         floor(i.got * v_pct / 100.0 + 0.5)::bigint,
         floor(t.due * v_pct / 100.0 + 0.5)::bigint
    from att t
   cross join income i;
end;
$function$;

revoke all on function public.admin_board_report(date, date) from public, anon;
grant execute on function public.admin_board_report(date, date) to authenticated;
