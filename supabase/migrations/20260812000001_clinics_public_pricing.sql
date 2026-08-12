-- clinics_public predates the pricing rebuild: it still carries the dead
-- single price_cents and cannot show a player the member vs non-member rate.
-- The app needs both rates (a published rate sheet is not secret) plus the
-- clinic length so it can label "60 min · $18".
--
-- Non-destructive per hard rule 6: the legacy price_cents column stays (it is
-- harmless and something may read it), and the two real columns plus
-- duration_minutes are added alongside. The Swift model maps only the real
-- ones. Capacity and every count stay absent, as they must.
--
-- Recreating a view with `create or replace` cannot drop or reorder existing
-- columns; new columns may only be appended. That constraint suits us: append
-- the three, leave the rest untouched.

create or replace view public.clinics_public as
  select id, name, audience, category, description,
         price_cents,                 -- deprecated, superseded by the two below
         starts_at, ends_at,
         member_opens_at, public_opens_at, closes_at,
         status, canceled_at,
         member_price_cents,
         nonmember_price_cents,
         duration_minutes
  from public.clinics
  where status in ('published', 'canceled');

comment on view public.clinics_public is
  'Player-facing clinic list. Carries both published rates so the client shows '
  'the one matching the viewer''s membership; a rate sheet is not secret. '
  'Deliberately omits internal_capacity and every count (hard rule 1). '
  'price_cents is deprecated; use member_price_cents / nonmember_price_cents.';
