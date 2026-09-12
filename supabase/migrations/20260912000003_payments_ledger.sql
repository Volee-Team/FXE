-- Payments ledger, the admin's read of the card-payments table.
--
-- Why: the web Money tab needs "who, which clinic, how much, did it go
-- through" in one read. `payments` alone has ids; `registrations` is not
-- readable by `authenticated` at all (information hiding, decision 0002), so
-- PostgREST cannot embed through it. Same shape as revenue_by_clinic
-- (2026-08-10): a view that runs as its owner, gated by is_admin() inside, with
-- select for authenticated and nothing else. Zelle is not in here; Zelle is the
-- Paid checkbox on the roster (questions 34-35 for Tara, still open).

create or replace view public.payments_ledger as
  select
    p.id,
    p.kind,
    p.amount_cents,
    p.currency,
    p.status,
    p.failure_reason,
    p.created_at,
    p.updated_at,
    p.registration_id,
    p.refunds_payment_id,
    p.account_id,
    a.first_name,
    a.last_name,
    c.id        as clinic_id,
    c.name      as clinic_name,
    c.starts_at as clinic_starts_at
  from public.payments p
  join public.accounts a      on a.id = p.account_id
  join public.registrations r on r.id = p.registration_id
  join public.clinics c       on c.id = r.clinic_id
  where public.is_admin();

comment on view public.payments_ledger is
  'Card payments with the player and clinic named. Admin only (is_admin() '
  'inside). Zelle is the Paid flag on registrations, not a row here.';

-- Hard rule 11: the schema's default privileges hand every new relation to
-- anon and authenticated. Take it back, then grant exactly what the page reads.
revoke all on public.payments_ledger from public, anon, authenticated;
grant select on public.payments_ledger to authenticated;
