-- 20261001000001_app_diagnostics.sql
--
-- Crash and hang reports from members' phones (decision 0035).
--
-- Until now, a crash on a member's phone reached us only if she told Tara.
-- Apple's MetricKit hands the app itself a diagnostic for every crash, hang,
-- CPU exception, excessive disk write and slow launch, on the next launch (or
-- at once on iOS 15+). The app (DiagnosticsReporter.swift) sends each one
-- here through report_app_diagnostic; the team reads them through
-- admin_app_diagnostics. Nothing goes to a third party.
--
-- WHAT IS IN A ROW. MetricKit's JSON: call stacks as binary UUIDs and
-- offsets, exception codes, the OS and app version, the device model. No
-- name, no email, no screen content, nothing from the nine hidden facts; the
-- app adds nothing of its own beyond the version strings and model.
--
-- account_id is WHO SENT IT, not who crashed: a report that arrived while
-- signed out waits in a file on the phone and goes up with the next person
-- to sign in on it. It exists for one reason, to rate-limit.
--
-- ON DELETE SET NULL, so the column is nullable. accounts.id cascades from
-- auth.users; account deletion (20260921000003) is a soft delete that keeps
-- the row, so this only matters for a hard delete. A crash report is not
-- the personal history hard rule 4 keeps, and it is not personal data that
-- must follow the person out either: it is a fact about the build. So the
-- report stays, unattached, and never blocks a delete (RESTRICT would).
--
-- BOUNDS. A member can write here, so every way to make a row large is
-- capped: the payload at 64 KB of its text form (octet_length(payload::text),
-- not pg_column_size, which would measure the compressed size and let a
-- megabyte of repetition through), each label at 100 characters, and 20 rows
-- per account per rolling 24 hours. Worst case for a hostile member is about
-- 1.3 MB a day of their own rows, which the team can see and delete.
--
-- No client grant at all (hard rule 11: Supabase's default privileges give
-- every new table ALL to anon and authenticated, so revoke first). The only
-- way in is the RPC; the only way out is the admin RPC.

create table public.app_diagnostics (
  id          uuid primary key default gen_random_uuid(),
  account_id  uuid references public.accounts(id) on delete set null,
  received_at timestamptz not null default now(),
  kind        text not null check (kind in ('crash', 'hang', 'cpu', 'disk', 'launch')),
  app_version text check (char_length(app_version) <= 100),
  build       text check (char_length(build)       <= 100),
  os_version  text check (char_length(os_version)  <= 100),
  device      text check (char_length(device)      <= 100),
  payload     jsonb not null check (octet_length(payload::text) <= 65536)
);
-- The rate limit's question, "how many from this account since yesterday".
create index app_diagnostics_account_received on public.app_diagnostics (account_id, received_at);

alter table public.app_diagnostics enable row level security;
revoke all on table public.app_diagnostics from public, anon, authenticated;
-- No policy: with RLS on and no grant, nothing reaches a client either way.
-- service_role is the platform's trusted role (20260912000002); its default
-- privileges already cover a new table, written here so it is not inherited.
grant select, insert, update, delete on table public.app_diagnostics to service_role;

-- The phone's one write. The account is auth.uid(), never a parameter.
create or replace function public.report_app_diagnostic(
  p_kind        text,
  p_app_version text,
  p_build       text,
  p_os_version  text,
  p_device      text,
  p_payload     jsonb
) returns void
language plpgsql volatile security definer
set search_path = public, pg_temp as $$
declare
  v_id uuid := auth.uid();
  n    int;
begin
  if v_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not exists (select 1 from public.accounts where id = v_id and deleted_at is null) then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;
  if p_kind is null or p_kind not in ('crash', 'hang', 'cpu', 'disk', 'launch') then
    raise exception 'invalid_kind' using errcode = '22023';
  end if;
  if p_payload is null then
    raise exception 'payload_required' using errcode = '22023';
  end if;
  if octet_length(p_payload::text) > 65536 then
    raise exception 'payload_too_large' using errcode = '22023';
  end if;

  -- One account's reports are counted and written one at a time, so two
  -- calls at once cannot both see 19 and both write.
  perform pg_advisory_xact_lock(hashtextextended('app_diagnostics:' || v_id::text, 0));
  select count(*) into n from public.app_diagnostics
   where account_id = v_id and received_at > now() - interval '24 hours';
  if n >= 20 then
    -- The phone drops this one silently: a crash loop is already visible
    -- in the twenty that landed.
    raise exception 'too_many_reports' using errcode = 'P0001';
  end if;

  insert into public.app_diagnostics (account_id, kind, app_version, build, os_version, device, payload)
  values (v_id, p_kind, left(p_app_version, 100), left(p_build, 100),
          left(p_os_version, 100), left(p_device, 100), p_payload);
end; $$;
revoke all on function public.report_app_diagnostic(text, text, text, text, text, jsonb) from public, anon;
grant execute on function public.report_app_diagnostic(text, text, text, text, text, jsonb) to authenticated;

-- The team's read, newest first. account_id only: a crash is read by build
-- and device, and whose phone it was is one join away for the few who need
-- it, not printed beside every stack trace.
create or replace function public.admin_app_diagnostics(p_limit int default 100)
returns table (
  id uuid, account_id uuid, received_at timestamptz, kind text,
  app_version text, build text, os_version text, device text, payload jsonb
)
language plpgsql stable security definer
set search_path = public, pg_temp as $$
begin
  perform public.require_admin();
  return query
    select d.id, d.account_id, d.received_at, d.kind,
           d.app_version, d.build, d.os_version, d.device, d.payload
      from public.app_diagnostics d
     order by d.received_at desc, d.id
     limit least(greatest(coalesce(p_limit, 100), 1), 500);
end; $$;
revoke all on function public.admin_app_diagnostics(int) from public, anon;
grant execute on function public.admin_app_diagnostics(int) to authenticated;
