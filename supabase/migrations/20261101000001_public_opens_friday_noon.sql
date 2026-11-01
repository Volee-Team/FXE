-- Everyone else opens Friday at noon, not 8:00 (decision 0046, 2026-11-01).
--
-- Tara, relayed by John: "she wants to switch it to friday noon". Members are
-- unchanged (Thursday 08:00), so their head start grows from 24 to 28 hours.
--
-- Only the default moves. public_opens_at() supplies the value every admin
-- path stores on the clinic row (admin_upsert_clinic,
-- create_clinic_from_template, admin_copy_week); registration reads the
-- stored column, so a clinic Tara set by hand keeps her time.

create or replace function public.public_opens_at(p_starts_at timestamptz)
returns timestamptz
language sql
stable
as $$
  select ((public.service_week_start(p_starts_at) - 2)::timestamp + time '12:00')
           at time zone 'America/New_York';
$$;

comment on function public.public_opens_at(timestamptz) is
  'Default public registration open: 12:00 (noon) America/New_York on the Friday '
  'two days before the clinic''s anchor Sunday, 28 hours after the member open '
  '(decision 0046; 08:00 until 2026-11-01). Members keep access afterwards; this '
  'widens the audience.';

revoke all on function public.public_opens_at(timestamptz) from public, anon;
grant execute on function public.public_opens_at(timestamptz) to authenticated;

-- ---------------------------------------------------------------- backfill ----

-- Clinics already created still carry the 08:00 default. A row moves only when
--   * its public open is exactly the OLD default (Friday 08:00 of its week), so
--     a time Tara typed herself is never reverted (hard rule 6), and
--   * that moment is still ahead, so a week already open to everyone is not
--     closed again to non-members for four hours.
-- The old formula is inlined: the function that produced it no longer exists.
update public.clinics c
   set public_opens_at = public.public_opens_at(c.starts_at)
 where c.public_opens_at = ((public.service_week_start(c.starts_at) - 2)::timestamp + time '08:00')
                             at time zone 'America/New_York'
   and c.public_opens_at > now();
