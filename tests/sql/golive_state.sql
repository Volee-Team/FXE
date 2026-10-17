-- golive_state.sql
--
-- THE RULE: after a reset, a local or CI database is in the pre-live state,
-- whatever go-live migrations exist. The suite, the Stripe harness and the UI
-- tests were written against that state; the go-live migrations (the Stripe
-- cutover, payments on) replay on every reset, and supabase/seed.sql undoes
-- them locally (backlog, live review B3, 2026-10-04).
--
-- Run straight after a reset, before anything switches payments on (the
-- runner does: it resets first). Expected values are the pre-live state
-- itself, written out.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;

insert into _probe_result
select 'not_switched_to_live', '0', count(*)::text
  from public.app_settings where key = 'stripe_live_since';
insert into _probe_result
select 'payments_off', 'false', coalesce((select value from public.app_settings where key = 'payments_enabled'), '<missing>');
insert into _probe_result
select 'no_switch_on_moment', '<empty>', coalesce(nullif((select value from public.app_settings where key = 'payments_enabled_at'), ''), '<empty>');
insert into _probe_result
select 'payments_enabled_at_reads_null', 'null', coalesce(public.payments_enabled_at()::text, 'null');

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
