-- Three gaps from the 2026-08-27 audit, one enabling step for Tara's account.
--
-- 1. TEMPLATES BECOME READABLE. admin_upsert_template worked and nothing could
--    LIST templates: the table is (correctly) revoked from every client and no
--    view existed. So "create from template" was dead on arrival and Tara would
--    retype all six fields for all eight clinics every Saturday — defeating the
--    spec's own one-to-two-minutes-per-clinic goal. Same pattern as
--    clinics_admin: an explicit-column view gated on is_admin(), returning zero
--    rows to a non-admin rather than raising.
--
-- 2. THE CLINIC LIST GETS A DATE FLOOR. clinics_public had no date clause and
--    clinic_status has no terminal state, so finished clinics accumulated
--    forever and sorted to the TOP of a starts_at-ascending list: Home's
--    prefix(3) showed the three OLDEST clinics. The floor lives in the VIEW,
--    not in each client, so it holds for the iOS app, the web admin's player
--    preview, and every future client at once. `ends_at > now()` keeps a clinic
--    visible while it is in progress; it disappears only once it is over.
--    (clinics_admin deliberately keeps everything: Tara's Past section is real.)
--
-- 3. TARA'S ACCOUNT BOOTSTRAPS ITSELF. Hosted has zero accounts and there is
--    deliberately no RPC that grants admin (hard rule 8: a privilege column is
--    never writable by the role it grants privilege to). So how does the FIRST
--    admin come to exist? A BEFORE INSERT trigger promotes exactly one
--    hardcoded email at account creation. This does not violate rule 8: no
--    client chooses the role — the schema does, for one email, recorded in git.
--    The guard trigger only polices UPDATEs (it references OLD), so insert-time
--    promotion composes cleanly with it. When Tara signs up in the deployed web
--    admin with this email, she arrives as an administrator with no hand-run
--    SQL against production.

-- ---------------------------------------------------------------- templates --
create view public.templates_admin as
  select id, name, audience, category, description,
         default_start_time, duration_minutes, internal_capacity,
         member_price_cents, nonmember_price_cents, created_at
  from public.clinic_templates
  where public.is_admin() and archived_at is null;

comment on view public.templates_admin is
  'Clinic templates, admins only; zero rows for a non-admin. Columns listed '
  'explicitly (never select *): clinics_admin was created with select * and '
  'silently missed later columns for five weeks. price_cents (deprecated) and '
  'archived_at are deliberately absent.';

revoke all on public.templates_admin from public, anon, authenticated;
grant select on public.templates_admin to authenticated;

-- --------------------------------------------------------------- date floor --
create or replace view public.clinics_public as
  select id, name, audience, category, description,
         price_cents,                 -- deprecated, kept so nothing breaks
         starts_at, ends_at,
         member_opens_at, public_opens_at, closes_at,
         status, canceled_at,
         member_price_cents,
         nonmember_price_cents,
         duration_minutes
  from public.clinics
  where status in ('published', 'canceled')
    and ends_at > now();

comment on view public.clinics_public is
  'Player-facing clinic list. Omits internal_capacity and every count (hard '
  'rule 1). Date floor ends_at > now(): a finished clinic is history a player '
  'has no action on, and without the floor past clinics sorted to the TOP of '
  'the list. Admins see everything via clinics_admin instead.';

revoke all on public.clinics_public from public, anon, authenticated;
grant select on public.clinics_public to authenticated;

-- ---------------------------------------------------------------- bootstrap --
create or replace function public.bootstrap_first_admin()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  -- Exactly one email, Tara's own (fersctennispro@gmail.com), lowercased both
  -- sides so a capitalised sign-up still matches. Everyone else keeps whatever
  -- create_my_account hardcoded ('member').
  if lower(new.email) = 'fersctennispro@gmail.com' then
    new.role := 'admin';
  end if;
  return new;
end;
$$;

drop trigger if exists bootstrap_first_admin on public.accounts;
create trigger bootstrap_first_admin
  before insert on public.accounts
  for each row execute function public.bootstrap_first_admin();
