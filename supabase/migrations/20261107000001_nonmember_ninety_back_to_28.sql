-- 20261107000001_nonmember_ninety_back_to_28.sql
--
-- Tara, by text, 2026-11-07 (relayed by John):
--   "Can you change the pricing $30 back to $28. Or can I do that?"
--
-- Undoes 20261105000001 (non-member 90 minutes $28 -> $30 from the week of
-- 2026-11-08) in the same three places, plus the sign-ups it moved:
--
--   1. default_price_cents()  : $28 again for every clinic created from now on.
--   2. clinic_templates       : 3000 -> 2800 on 90-minute templates.
--   3. clinics from 2026-11-08: 3000 -> 2800 on 90-minute clinics.
--   4. registrations          : a non-member's unpaid 3000 on one of those
--                               clinics -> 2800. Checked on hosted before the
--                               push: 68 rows at 3000, none paid and none with a
--                               live fee (nothing has been charged for a clinic
--                               that has not happened). The same guard as the
--                               migration it undoes, so a paid row would stay.
--
-- Only rows at exactly 3000 move: a price Tara typed by hand stays hers.

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
    else                                               2800  -- $28 ($30 for two days, 2026-11-05 to 11-07)
  end;
$$;

comment on function public.default_price_cents(integer, boolean) is
  'Tara''s price table (2026-08-02). Non-member 90 minutes is $28 (it was $30 '
  'from 2026-11-05 to 2026-11-07, then back at her text). Supplies the DEFAULT '
  'when a clinic is created; it does not own the value. Tara can override '
  'either price on any clinic, and past registrations keep what they were charged.';

update public.clinic_templates
   set nonmember_price_cents = 2800
 where nonmember_price_cents = 3000
   and duration_minutes > 60;

update public.registrations r
   set price_cents_charged = 2800
  from public.clinics c
 where c.id = r.clinic_id
   and c.starts_at >= timestamp '2026-11-08 00:00' at time zone 'America/New_York'
   and c.duration_minutes > 60
   and c.nonmember_price_cents = 3000
   and r.was_member = false
   and r.price_cents_charged = 3000
   and not r.paid
   and not public.registration_has_live_fee(r.id);

update public.clinics
   set nonmember_price_cents = 2800
 where starts_at >= timestamp '2026-11-08 00:00' at time zone 'America/New_York'
   and duration_minutes > 60
   and nonmember_price_cents = 3000;

revoke all on function public.default_price_cents(integer, boolean) from public, anon;
grant execute on function public.default_price_cents(integer, boolean) to authenticated;
