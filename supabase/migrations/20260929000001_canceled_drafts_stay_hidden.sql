-- 20260929000001_canceled_drafts_stay_hidden.sql
--
-- A clinic a player never saw published must never appear to them.
--
-- Found by the laptop-tools builder (2026-09-28, decision 0027, backlog):
-- clinics_public lists every clinic whose status is published OR canceled,
-- and cancel_clinic accepts a draft, so a draft Tara canceled without ever
-- publishing turned up in every player's list wearing a Canceled chip. Copy to
-- next week makes that common: it creates drafts, and canceling an unwanted
-- copy is how she drops one.
--
-- The fix records the moment a clinic is first published, and the view shows
-- a canceled clinic only if it had one. A clinic that was published and then
-- canceled still shows Canceled, because a player holding a spot must see it.
--
-- Rejected: refusing cancel_clinic on a draft (archive, never delete, hard
-- rule 4, and she would lose the one way to drop a copy); a separate
-- 'archived' status (an enum change with a wide blast radius for one flag).

-- 1. The stamp. Set by a trigger, so every path that publishes stamps it:
--    publish_clinic, a seed or migration inserting a published row, and any
--    future RPC. Never cleared: a canceled clinic keeps it.
alter table public.clinics add column published_at timestamptz;

create or replace function public.stamp_clinic_published()
returns trigger language plpgsql set search_path = public, pg_temp as $$
begin
  if new.status = 'published' and new.published_at is null then
    new.published_at := now();
  end if;
  if tg_op = 'UPDATE' and old.published_at is not null then
    new.published_at := old.published_at;          -- once stamped, kept
  end if;
  return new;
end; $$;
revoke all on function public.stamp_clinic_published() from public, anon, authenticated;

create trigger stamp_clinic_published
  before insert or update on public.clinics
  for each row execute function public.stamp_clinic_published();

-- 2. Backfill. Published rows get their creation time. A clinic already
--    canceled cannot say whether it was ever published, so it keeps today's
--    behaviour (shown): hiding one a player did see would be the worse error.
update public.clinics
   set published_at = coalesce(created_at, now())
 where status in ('published', 'canceled') and published_at is null;

-- 3. The view: same columns, same order (CREATE OR REPLACE keeps its grants);
--    only the WHERE changes.
create or replace view public.clinics_public as
  select id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         status, canceled_at, member_price_cents, nonmember_price_cents,
         duration_minutes
    from public.clinics
   where (status = 'published'
          or (status = 'canceled' and published_at is not null))
     and ends_at > now();
