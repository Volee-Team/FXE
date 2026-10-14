-- 20261015000002_payments_on.sql
--
-- PAYMENTS ON (checklist A9). Merge and push this ONLY when all of these are
-- true, in this order:
--   1. Apple approved the external TestFlight build (C11),
--   2. the sandbox rehearsal passed (A13),
--   3. the live keys are in and the cutover ran (A10, 20261015000001),
--   4. one real charge and its refund on Alex's own card went through (A2),
--   5. Alex said go.
-- Never while the keys are sandbox: a real card is declined in test mode.
--
-- From this moment nobody registers or accepts an invitation without a
-- saved card (card_required, decision 0040), and only clinics that END after
-- this moment are ever owed or charged (decision 0018): the clinics people
-- paid for by Zelle before today never read "not charged yet".
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
  if coalesce((select value from public.app_settings where key = 'payments_enabled'), '') <> 'true'
     or public.payments_enabled_at() is null then
    raise exception 'payments_on_incomplete';
  end if;
end $$;
