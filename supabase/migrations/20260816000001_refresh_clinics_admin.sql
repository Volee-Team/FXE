-- clinics_admin was stale: Tara could not see the prices players are quoted.
--
-- THE BUG
-- -------
-- `clinics_admin` was created on 2026-07-28 as `select * from public.clinics
-- where public.is_admin()`. Postgres resolves `*` ONCE, at creation, and stores
-- the expanded column list. Columns added to the base table afterwards never
-- appear in the view.
--
-- So when 20260810000001 added `member_price_cents` / `nonmember_price_cents`
-- and `duration_minutes` to `clinics`, the player-facing `clinics_public` was
-- explicitly recreated to carry them (20260812000001) and the ADMIN view was
-- not. Net effect: every player could see both published rates and the person
-- who sets those rates could not.
--
-- Recorded in docs/backlog.md on 2026-08-13, found while writing
-- `view_write_paths.sql`: naming those columns in an attack made it fail with
-- 42703 (undefined column) and report a FALSE PASS. Blocked-by-a-typo is not
-- blocked-by-a-privilege. Hit again on 2026-08-15 building the admin tab, where
-- selecting the pricing columns 400'd and the whole screen read "Couldn't load
-- clinics".
--
-- THE FIX, and why it is safe
-- ---------------------------
-- `create or replace view` may only APPEND columns, never rename, reorder or
-- drop them. The three missing columns were appended to `clinics`, so a fresh
-- `select *` produces the original list in its original order followed by the
-- new ones. That satisfies the constraint, which is why this can be a replace
-- rather than a drop and recreate. A drop would also silently take the view's
-- grants with it.
--
-- Columns are now listed EXPLICITLY rather than `select *`. That is the actual
-- lesson: `select *` in a view is a time bomb whose fuse is the next migration.
-- Listing them means the next person who adds a column has to decide whether
-- Tara should see it, instead of finding out months later that she cannot.
--
-- Hard rule 11: revoke before grant. `create or replace` preserves an existing
-- view's ACL rather than re-inheriting the schema default, so this is belt and
-- braces, not a fix for a live hole. It costs nothing and it means this file
-- reads correctly if anyone ever converts it to a drop-and-recreate.

create or replace view public.clinics_admin as
  select
    id,
    template_id,
    name,
    audience,
    category,
    description,
    price_cents,            -- deprecated, kept so nothing that reads it breaks
    starts_at,
    ends_at,
    member_opens_at,
    public_opens_at,
    closes_at,
    internal_capacity,
    status,
    canceled_at,
    created_at,
    -- The three that were missing.
    member_price_cents,
    nonmember_price_cents,
    duration_minutes
  from public.clinics
  where public.is_admin();

comment on view public.clinics_admin is
  'Every clinic, for administrators only; returns zero rows to a non-admin '
  'rather than raising. Columns are listed explicitly on purpose: this view was '
  'created with `select *` and silently missed the 2026-08-10 pricing columns '
  'for five weeks. Add new columns here deliberately.';

revoke all on public.clinics_admin from anon, authenticated;
grant select on public.clinics_admin to authenticated;
