-- 20260927300003_held_charges.sql
--
-- MVP fix round (2026-09-27), two findings on charges stripe-charge cannot
-- safely retry.
--
-- S1. A RETRY PAST STRIPE'S MEMORY. Stripe keeps an idempotency key for 24
--     hours. stripe-charge held a stuck row past RETRY_WINDOW_HOURS, but it
--     measured from created_at, and a row that went back to pending after a
--     dropped connection was picked up again by the main loop with no age
--     check at all: a retry a day later went out under a key Stripe had
--     forgotten, and could charge a second time. payments.first_attempted_at
--     is stamped once, at the first claim, and every age test measures from
--     it. A row never attempted stays sendable however old it is. Written by
--     the edge function as service_role only; no client role can read or
--     write it, so the table-level SELECT authenticated held on payments is
--     replaced by the same list of columns minus this one (the pattern
--     notifications uses, 20260923000001; no client reads payments directly,
--     the screens read payments_ledger).
--
-- S3. A HELD CHARGE HAD NO WAY OUT. A row held in processing with
--     failure_reason idempotency_error or retry_window_passed may or may not
--     have gone through; only a person looking in Stripe can tell, and until
--     now the only resolution was SQL. admin_resolve_held_payment(payment,
--     outcome) records what she found:
--       * 'succeeded': status succeeded, through the same BEFORE UPDATE
--         trigger the webhook's update fires, so a clinic fee marks the
--         registration paid (and a refund unmarks it);
--       * 'canceled': status canceled, which frees the one-charge slot so she
--         can charge again.
--     Conditional on status = 'processing' and one of the two reasons (hard
--     rule 3): anything else is payment_not_held and changes nothing. The
--     reason stays on the row as the record of why it was held.

-- ------------------------------------------------------------ S1 column ----
alter table public.payments add column if not exists first_attempted_at timestamptz;

comment on column public.payments.first_attempted_at is
  'When stripe-charge first claimed this row (pending -> processing), set once. '
  'Every retry-window test measures from it: past RETRY_WINDOW_HOURS the row is '
  'held, never re-sent. Null: never attempted. service_role only. 20260927300003.';

-- Rows already past their first claim get the best stand-in there is.
update public.payments set first_attempted_at = created_at
 where first_attempted_at is null and status <> 'pending';

-- The owner and admins read payments through RLS; the column list is every
-- column but first_attempted_at. A column added later is unreadable until
-- it is listed here, which is the point.
revoke select on public.payments from authenticated;
grant select (id, registration_id, account_id, kind, amount_cents, currency, status,
              stripe_payment_intent_id, stripe_refund_id, refunds_payment_id,
              failure_reason, requested_by, created_at, updated_at, failure_code, livemode)
  on public.payments to authenticated;

-- ------------------------------------------------------------ S3 resolve ----
create or replace function public.admin_resolve_held_payment(p_payment uuid, p_outcome text)
returns public.payments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.payments;
begin
  perform public.require_admin();
  if p_outcome is null or p_outcome not in ('succeeded', 'canceled') then
    raise exception 'invalid_outcome' using errcode = '22023';
  end if;
  update public.payments
     set status = p_outcome::public.payment_status
   where id = p_payment
     and status = 'processing'
     and failure_reason in ('idempotency_error', 'retry_window_passed')
  returning * into v;
  if not found then
    raise exception 'payment_not_held' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

comment on function public.admin_resolve_held_payment(uuid, text) is
  'Tara records what Stripe shows for a held charge (processing with '
  'idempotency_error or retry_window_passed): succeeded (marks paid through the '
  'ledger trigger) or canceled (frees the charge). Admin only. 20260927300003.';

revoke all on function public.admin_resolve_held_payment(uuid, text) from public, anon;
grant execute on function public.admin_resolve_held_payment(uuid, text) to authenticated;
