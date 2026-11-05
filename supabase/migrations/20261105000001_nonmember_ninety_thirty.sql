-- 20261105000001_nonmember_ninety_thirty.sql
--
-- Tara, by text, 2026-11-04 (relayed by John):
--   "All clinics starting next week for nonmembers will go from $28 to $30"
--
-- The $28 is the non-member price of a 90-minute clinic (the only $28 in
-- Tara's table, default_price_cents). Three places hold it:
--
--   1. default_price_cents()  : every clinic created from now on, including
--      copy_week's copies, which take their prices from the length.
--   2. clinic_templates       : a template carries its own two prices.
--   3. clinics already made for "next week" or later: the service week that
--      starts Sunday 2026-11-08 (service_week_start). The date is written down
--      rather than computed from now(), so local, CI and hosted all mean the
--      same week whenever the migration runs.
--
-- Registrations snapshot what the player owes at sign-up (hard rule 7's
-- instinct: a later edit does not move a past debt). A non-member who already
-- signed up for one of those clinics at $28 is moved to $30 too, because
-- Tara's sentence is about the clinics, and nothing has been charged for a
-- clinic that has not happened (charges are her tap after the clinic). Only a
-- row still at exactly 2800 moves: a price Tara set by hand stays hers.
-- This week's clinics keep $28. One edge: a 90-minute clinic Tara creates for
-- the rest of THIS week after the push gets $30 from the default, because the
-- default takes no date; she can set the price on that clinic by hand.

create or replace function public.default_price_cents(
  p_duration_minutes integer, p_is_member boolean)
returns integer
language sql
immutable
as $$
  select case
    when p_is_member and p_duration_minutes <= 60 then 1800  -- $18
    when p_is_member                              then 2200  -- $22
    when p_duration_minutes <= 60                 then 2300  -- $23
    else                                               3000  -- $30 (was $28 until the week of 2026-11-08)
  end;
$$;

comment on function public.default_price_cents(integer, boolean) is
  'Tara''s price table (2026-08-02; non-member 90 minutes $28 -> $30 from the '
  'week of 2026-11-08). Supplies the DEFAULT when a clinic is created; it does '
  'not own the value. Tara can override either price on any clinic, and past '
  'registrations keep whatever they were charged.';

update public.clinic_templates
   set nonmember_price_cents = 3000
 where nonmember_price_cents = 2800
   and duration_minutes > 60;

update public.registrations r
   set price_cents_charged = 3000
  from public.clinics c
 where c.id = r.clinic_id
   and c.starts_at >= timestamp '2026-11-08 00:00' at time zone 'America/New_York'
   and c.duration_minutes > 60
   and c.nonmember_price_cents = 2800
   and r.was_member = false
   and r.price_cents_charged = 2800
   -- Never a row already paid or charged (the sql-auditor, 2026-11-05: if
   -- this reached hosted after a clinic that week had been charged, the
   -- snapshot would move away from the $28 actually taken).
   and not r.paid
   and not public.registration_has_live_fee(r.id);

update public.clinics
   set nonmember_price_cents = 3000
 where starts_at >= timestamp '2026-11-08 00:00' at time zone 'America/New_York'
   and duration_minutes > 60
   and nonmember_price_cents = 2800;

-- Restated, as every migration that replaces a function does.
revoke all on function public.default_price_cents(integer, boolean) from public, anon;
grant execute on function public.default_price_cents(integer, boolean) to authenticated;
