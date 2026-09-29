-- 20260929000005_app_link_visits.sql
--
-- How many people opened the app link, and how many of them by the QR code.
-- Kat, 2026-09-29: "The QR code though needs to track # of scans".
--
-- Counts only: one row per New York day and source ('qr' for the printed and
-- emailed code, which now carries ?via=qr, 'link' for anything else), never
-- an IP address, a device or anything about the person. The `app-visit` edge
-- function is the only writer; Tara reads the totals on her Players tab.
--
-- Anyone can reach the edge function (a scan comes from a phone with no
-- account), so anyone could inflate the count; the worst case is a wrong
-- number, never a leak. Noted in decision 0031.

create table public.app_link_visits (
  day    date not null,
  via    text not null check (via in ('qr', 'link')),
  visits integer not null default 0 check (visits >= 0),
  primary key (day, via)
);
alter table public.app_link_visits enable row level security;
revoke all on table public.app_link_visits from public, anon, authenticated;
grant select, insert, update on table public.app_link_visits to service_role;

-- The edge function's one write: add one to today's row, New York date.
create or replace function public.record_app_link_visit(p_via text)
returns void language plpgsql volatile security definer
set search_path = public, pg_temp as $$
declare v text := case when p_via = 'qr' then 'qr' else 'link' end;
begin
  insert into public.app_link_visits (day, via, visits)
  values ((now() at time zone 'America/New_York')::date, v, 1)
  on conflict (day, via) do update set visits = public.app_link_visits.visits + 1;
end; $$;
revoke all on function public.record_app_link_visit(text) from public, anon, authenticated;
grant execute on function public.record_app_link_visit(text) to service_role;

-- Tara's view: every day with a visit, newest first.
create or replace function public.admin_app_link_visits()
returns table (day date, via text, visits integer)
language plpgsql stable security definer
set search_path = public, pg_temp as $$
begin
  perform public.require_admin();
  return query select v.day, v.via, v.visits from public.app_link_visits v order by v.day desc, v.via;
end; $$;
revoke all on function public.admin_app_link_visits() from public, anon;
grant execute on function public.admin_app_link_visits() to authenticated;
