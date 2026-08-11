-- The report in the shape Tara actually asked for.
--
-- Alex relaying her, 2026-08-10: "tara legit just needs the non members and
-- members who played either 60 / 90min clinics, so like 4 variables --> then
-- the total money i guess calculated would be nice"
--
-- revenue_by_segment already contains this, but as four separate ROWS per
-- month. She wants four NUMBERS and a total, on one line, which is what she
-- reads off her notebook today. Pivoting it in SQL means the app and the web
-- admin both render one row instead of each reimplementing the pivot.
--
-- Anything not 60 or 90 minutes lands in `other_players` rather than being
-- silently dropped, so the four buckets plus other always reconcile to the
-- total. If that column is ever non-zero it is a real signal, not noise.

create or replace function public.revenue_summary(
  p_from timestamptz default null,
  p_to   timestamptz default null)
returns table (
  member_60_players     bigint,
  member_90_players     bigint,
  nonmember_60_players  bigint,
  nonmember_90_players  bigint,
  other_players         bigint,
  total_players         bigint,
  expected_cents        bigint,
  collected_cents       bigint,
  outstanding_cents     bigint
)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select
    count(*) filter (where r.was_member     and r.duration_minutes = 60),
    count(*) filter (where r.was_member     and r.duration_minutes = 90),
    count(*) filter (where not r.was_member and r.duration_minutes = 60),
    count(*) filter (where not r.was_member and r.duration_minutes = 90),
    count(*) filter (where r.duration_minutes not in (60, 90)),
    count(*),
    coalesce(sum(r.price_cents_charged), 0),
    coalesce(sum(r.price_cents_charged) filter (where r.paid), 0),
    coalesce(sum(r.price_cents_charged) filter (where not r.paid), 0)
  from public.registrations r
  join public.clinics c on c.id = r.clinic_id
  where public.is_admin()             -- the gate; SECURITY DEFINER needs it explicitly
    and r.status = 'in'               -- a Player Pool entry owes nothing
    and (p_from is null or c.starts_at >= p_from)
    and (p_to   is null or c.starts_at <  p_to);
$$;

comment on function public.revenue_summary(timestamptz, timestamptz) is
  'Tara''s four numbers plus the money, for a date range. Null bounds mean all '
  'time. Only status = ''in'' counts. Admin only: a non-admin gets a row of '
  'zeroes rather than an error, because the caller is a report screen she is '
  'the only one who can open.';

revoke all on function public.revenue_summary(timestamptz, timestamptz) from anon;
grant execute on function public.revenue_summary(timestamptz, timestamptz) to authenticated;
