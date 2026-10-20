-- 20261014000005_payments_on.sql
--
-- PAYMENTS ON (checklist A9). Merge and push this ONLY when all of these are
-- true, in this order:
--   1. Apple approved the external TestFlight build (C11),
--   2. the sandbox rehearsal passed (A13),
--   3. the live keys are in and the cutover ran (A10, 20261014000004),
--   4. Alex said go.
-- A real charge through the app cannot come first: with payments off no card
-- can be saved and no fee charged, and only clinics that END after this
-- moment are ever chargeable (review, 2026-10-13). The live account itself is
-- proved before this by a small charge and refund made in Stripe's own
-- dashboard on Alex's card; the app's first real charge is the first clinic
-- that ends after this migration, watched (checklist A9).
-- Never while the keys are sandbox: a real card is declined in test mode.
--
-- From this moment nobody registers or accepts an invitation without a
-- saved card (card_required, decision 0040), and only clinics that END after
-- this moment are ever owed or charged (decision 0018): the clinics people
-- paid for by Zelle before today never read "not charged yet".
--
-- The file's version is a placeholder: rename it to the date it merges
-- (scripts/check-migration-versions.sh refuses a migration older than main's
-- newest), or db push refuses it as out of order.
--
-- payments_enabled and payments_enabled_at change together, in this one
-- transaction, as 20260927300001 requires. supabase/seed.sql puts both back
-- locally and in CI (tests/sql/golive_state.sql).

update public.app_settings set value = 'true' where key = 'payments_enabled';
update public.app_settings set value = now()::text where key = 'payments_enabled_at';

-- Refuse to finish unless both took: a missing key would otherwise leave
-- payments half on (enabled with no moment means nothing is ever owed).
do $$
begin
  -- Never before the cutover: live charges against sandbox cards would fail.
  if not exists (select 1 from public.app_settings where key = 'stripe_live_since') then
    raise exception 'cutover_not_run';
  end if;
  if coalesce((select value from public.app_settings where key = 'payments_enabled'), '') <> 'true'
     or public.payments_enabled_at() is null then
    raise exception 'payments_on_incomplete';
  end if;
end $$;
