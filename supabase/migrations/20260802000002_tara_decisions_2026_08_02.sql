-- FXE Tennis: Tara's answered decisions, 2026-08-02.
--
-- Only the decisions with a database consequence are here. Decisions that are
-- purely client-side (the admin phone/laptop split, the "?" chart button, the
-- notification-permission disclosure, the brand palette, the Apple Developer
-- account name) are recorded in CLAUDE.md instead, because inventing a column
-- for a UX requirement is how schemas rot.

-- ------------------------------------- decision 13: notification visibility ----
--
-- Tara explicitly does NOT want to manage or monitor who has notifications on
-- or off. The admin-facing indicator is removed, and so is the column that
-- would feed it.
--
-- Why the column goes and does not merely stop being displayed:
--
--  * iOS already knows its own permission state locally, from
--    UNUserNotificationCenter. The client never needed a server round-trip to
--    decide whether to nag its own user.
--  * `devices` already tells the server whether a push can be delivered at all,
--    which is the only server-side question worth asking.
--  * A column that exists is a column somebody eventually renders. Deleting it
--    is what actually enforces the decision.
--
-- The replacement is a client-side UX requirement, not a schema object: at
-- signup, and persistently in-app whenever permission is denied, the app states
-- that all clinic communication happens through the app and that with
-- notifications off the player will miss important information. Recorded in
-- CLAUDE.md.
--
-- This overrides docs/notifications.md finding (k), which argued for keeping
-- the column. That note predates Tara's answer being applied.
alter table public.accounts drop column push_enabled;

-- ------------------------------- decisions 8 and 9: audience and category ----
--
-- DECISION 8: audience is Ladies / Men / Coed for v1. Juniors deferred to fall.
--
-- 'juniors' STAYS in the enum. Dropping an enum value in Postgres is not a
-- one-liner: there is no DROP VALUE, so it means creating a replacement type,
-- rewriting every dependent column and default, recreating any index and view
-- that touches them, and dropping the old type. That is a migration with real
-- blast radius, run twice (out in August, back in the fall), to delete four
-- characters that no player can see. The constraint Tara actually stated is a
-- UI constraint: the audience picker offers three options. A DB value nobody
-- can select is inert.
--
-- The seed keeps a juniors clinic template for the same reason: when juniors
-- return, the path is already exercised.
comment on type public.clinic_audience is
  'v1 UI offers ladies / men / coed only (Tara 2026-08-02). juniors is retained '
  'deliberately: juniors return in the fall, and dropping an enum value costs a '
  'full type rewrite. Do not remove it. Enforce the three-option limit in the '
  'admin picker, not here.';

-- DECISION 8, second half: no category filter in v1. Tara was unsure what
-- "category" meant and said there is no need to filter anything, because there
-- are not many clinics weekly and clinics are simply listed by week.
--
-- The column stays: nullable, free text, displayed if present, never filtered
-- on. No index is added, because an index is the thing you add when you intend
-- to filter, and adding one would be a quiet promise that we do.
comment on column public.clinics.category is
  'Free text, optional, display only. No filtering in v1 (Tara 2026-08-02: '
  'clinics are listed by week, there are not many, nothing needs filtering). '
  'Deliberately unindexed. Do not build a category filter without asking her.';

comment on column public.clinic_templates.category is
  'Free text, optional, display only. See public.clinics.category.';

-- ---------------------------------- decisions 6 and 7: adult NTRP rating ----
--
-- Tara: use the SAME NTRP scale and the SAME explanatory chart Volee already
-- uses, behind a tappable "?" button. That settles the "value list pending
-- Tara" comment this column shipped with.
--
-- Stored as numeric, not text, to match Volee's own `profiles.ntrp
-- numeric(2,1)` exactly. A player's rating then moves between the two systems
-- with no translation table, which is what docs/ntrp-chart.md promises. Text
-- could not honour that promise: Volee stores 5.0, the chart RENDERS "5.0+",
-- and a text column would have had to pick one and translate at every boundary.
-- "5.0+" is a display label. It is not a value.
--
-- Range is the seven buckets that have copy written for them: 2.0 to 5.0 in
-- half steps. Volee's column permits 1.5 to 7.0 for its internal ladder maths,
-- but its user-facing list is 2.0 to 5.0 and FXE mirrors the user-facing list.
-- Constraining to exactly the values that can be rendered means no stored
-- rating can produce a blank row in the chart.
alter table public.players
  alter column adult_rating type numeric(2,1)
  using nullif(trim(adult_rating), '')::numeric(2,1);

alter table public.players
  add constraint adult_rating_is_ntrp_bucket
  check (
    adult_rating is null
    or (adult_rating between 2.0 and 5.0 and (adult_rating * 2) = trunc(adult_rating * 2))
  );

comment on column public.players.adult_rating is
  'USTA NTRP bucket, 2.0 to 5.0 in half steps (Tara 2026-08-02: same scale and '
  'same chart as Volee). Same representation as Volee profiles.ntrp, so ratings '
  'move between the apps untranslated. 5.0 is the ceiling and RENDERS as "5.0+"; '
  'the "+" is a label, never a stored value. Adults only.';

-- search_players declares this column in its OUT signature, so it has to be
-- rebuilt for the new type. RETURNS TABLE cannot be altered in place.
drop function if exists public.search_players(text, boolean);

create or replace function public.search_players(p_query text, p_include_inactive boolean default false)
returns table (
  id uuid, first_name text, last_name text, kind player_kind,
  age integer, adult_rating numeric, is_member boolean, is_active boolean,
  has_notes boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
    select p.id, p.first_name, p.last_name, p.kind,
           public.player_age(p.date_of_birth), p.adult_rating,
           p.is_member, p.is_active,
           exists (select 1 from public.player_notes n
                    where n.player_id = p.id and n.body <> '')
      from public.players p
     where (p_include_inactive or p.is_active)
       and (
         p_query is null or p_query = ''
         or p.first_name ilike '%' || p_query || '%'
         or p.last_name  ilike '%' || p_query || '%'
       )
     order by p.last_name, p.first_name;
end;
$$;

grant execute on function public.search_players(text, boolean) to authenticated;

-- ------------------------------------------- decision 11: payment details ----
--
-- The required string, character for character:
--
--   Payment can be made via zelle to fersctennispro@gmail.com (preferred) or Venmo FXE Tennis
--
-- Lower-case "zelle" and the absence of a terminal period are hers. Not
-- corrected. If this string is ever "tidied up", it stops being the string she
-- specified.
--
-- WHERE IT LIVES, AND WHY NOT SOMEWHERE ELSE
--
--  * Not a Swift constant alone. The payment reminder body is composed
--    server-side inside an RPC, so the string has to exist in the database
--    regardless. Two copies drift.
--  * Not a hardcoded SQL literal alone. A Zelle address or a Venmo handle is
--    exactly the kind of thing that changes on a Tuesday. Baking it into a
--    function body means a migration and a redeploy to fix a typo in an email
--    address.
--  * A one-row settings table it is. Tara edits it from the admin laptop page
--    (decision 1), the app reads one string, and the exact wording is pinned by
--    a probe so a careless edit is visible.
--
-- The read is deliberately wide (any authenticated user) and the write is
-- admin-only. This table is for values every player is allowed to see. Nothing
-- hidden goes in it: see the information_hiding probe, which asserts no
-- location-shaped key and no link ever lands here.
create table public.app_settings (
  key        text primary key,
  value      text not null,
  updated_at timestamptz not null default now()
);

comment on table public.app_settings is
  'Small, player-safe, admin-editable strings. Readable by every authenticated '
  'user, so NEVER store anything from the nine hidden facts here, and never a '
  'location, address, map link, or set of directions.';

insert into public.app_settings (key, value) values
  ('payment_instructions',
   'Payment can be made via zelle to fersctennispro@gmail.com (preferred) or Venmo FXE Tennis')
on conflict (key) do nothing;

alter table public.app_settings enable row level security;

create policy app_settings_read on public.app_settings
  for select using (true);
create policy app_settings_admin_write on public.app_settings
  for all using (public.is_admin()) with check (public.is_admin());

revoke all on public.app_settings from anon, authenticated;
grant select on public.app_settings to authenticated;

-- Convenience accessor so callers do not spread the magic key string around.
create or replace function public.payment_instructions()
returns text
language sql
stable
as $$
  select value from public.app_settings where key = 'payment_instructions';
$$;

grant execute on function public.payment_instructions() to authenticated;

-- -------------------------------- decisions 3, 4 and 5: already satisfied ----
--
-- Recorded here so a future session does not "add" them a second time.
--
-- DECISION 3, manual placement: public.place_player(clinic, player, status)
-- already inserts or moves a player into any status, including moving someone
-- between You're In! and Player Pool by hand. Admin-gated by require_admin().
--
-- DECISION 4, capacity never blocks Tara: place_player deliberately performs no
-- capacity check. The only capacity decision in the app is inside
-- register_for_clinic, which is the player self-service path. Tara sees counts
-- and is never stopped by them. Pinned by tests/sql/schema_decisions.sql.
--
-- DECISION 5, member status self-reported with an admin override:
-- players.is_member is writable by the owning account (players_update_own,
-- account_id = auth.uid()) and by any admin (the same policy's is_admin()
-- branch). Self-report and override both already work with no new RPC.
--
-- Note the consequence, since it is a deliberate accepted risk rather than an
-- oversight: a player can tick "I am a member" and gain the Thursday window.
-- That is what self-reported means. Tara corrects it on the profile.
