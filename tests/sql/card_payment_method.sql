-- card_payment_method.sql
--
-- THE RULES (20261014000003)
--   1. A card summary names its exact Stripe PaymentMethod, and whenever the
--      summary is cleared, by any path, the PaymentMethod id goes with it.
--   2. An edit that keeps the card keeps the id.
--   3. No client role can write the id; only service_role (stripe-webhook).
--
-- The clearing paths named in the rule: the live cutover, a member deleting
-- their account, and a direct clear as the edge functions do it.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  MARIA constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN   constant uuid := '33333333-3333-3333-3333-333333333333';
  ROB   constant uuid := '44444444-4444-4444-4444-444444444444';
  v text;
begin
  update public.accounts
     set stripe_customer_id = 'cus_' || left(id::text, 8), card_brand = 'visa',
         card_last4 = '4242', card_payment_method_id = 'pm_' || left(id::text, 8), card_added_at = now()
   where id in (MARIA, KEN, ROB);

  -- 2. An edit that keeps the card keeps the id.
  update public.accounts set card_brand = 'mastercard' where id = MARIA;
  select coalesce(card_payment_method_id, 'NULL') into v from public.accounts where id = MARIA;
  insert into _probe_result values ('brand_edit_keeps_id', 'pm_22222222', v);
  update public.accounts set phone = '5550199' where id = MARIA;
  select coalesce(card_payment_method_id, 'NULL') into v from public.accounts where id = MARIA;
  insert into _probe_result values ('other_edit_keeps_id', 'pm_22222222', v);

  -- 1a. A direct clear, as stripe-setup-intent, stripe-charge and the
  -- detach do it: they set the summary null and never name the id.
  update public.accounts set card_brand = null, card_last4 = null, card_added_at = null where id = MARIA;
  select coalesce(card_payment_method_id, 'NULL') into v from public.accounts where id = MARIA;
  insert into _probe_result values ('direct_clear_clears_id', 'NULL', v);

  -- 1b. A member deleting their account.
  perform set_config('role', 'authenticated', true);
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform public.delete_my_account();
  perform set_config('role', 'postgres', true);
  select coalesce(card_payment_method_id, 'NULL') into v from public.accounts where id = KEN;
  insert into _probe_result values ('account_deletion_clears_id', 'NULL', v);

  -- 1c. The live cutover (rolled back with the rest of this probe).
  perform * from public.stripe_cutover_to_live();
  select coalesce(card_payment_method_id, 'NULL') into v from public.accounts where id = ROB;
  insert into _probe_result values ('cutover_clears_id', 'NULL', v);

  -- 1d. The id alone cannot outlive the summary: writing it with no card
  -- summary leaves nothing.
  update public.accounts set card_payment_method_id = 'pm_orphan' where id = ROB;
  select coalesce(card_payment_method_id, 'NULL') into v from public.accounts where id = ROB;
  insert into _probe_result values ('no_id_without_a_card', 'NULL', v);
end $$;

-- 3. Privileges, enumerated rather than attempted (the local image segfaults
-- on a call a role may not make; CLAUDE.md, known local defect).
insert into _probe_result
select 'members_cannot_write_the_id', 'false',
       has_column_privilege('authenticated', 'public.accounts', 'card_payment_method_id', 'UPDATE')::text;
insert into _probe_result
select 'anon_cannot_read_the_id', 'false',
       has_column_privilege('anon', 'public.accounts', 'card_payment_method_id', 'SELECT')::text;
insert into _probe_result
select 'the_webhook_can_write_it', 'true',
       has_column_privilege('service_role', 'public.accounts', 'card_payment_method_id', 'UPDATE')::text;

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
