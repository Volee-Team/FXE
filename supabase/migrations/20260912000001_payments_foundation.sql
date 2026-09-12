-- Payments foundation: decision 0009. Schema, settings, RPCs and guards for
-- Stripe with a card on file. Nothing in this migration talks to Stripe and
-- nothing can charge anyone: `payments_enabled` is 'false' until Tara has
-- answered Q27–Q37 (hard rule 14) and Alex flips it.
--
-- SHAPE
-- * accounts gets a Stripe customer id and a card SUMMARY (brand, last4).
--   Card numbers never exist here; Stripe holds them. These columns are set
--   by the stripe-webhook edge function (service role), never by a client:
--   authenticated's column-level UPDATE on accounts stays first_name,
--   last_name, phone (20260802000003), so a player cannot forge a card.
-- * payments is the ledger: one row per money event (clinic fee, late cancel,
--   no show, refund). Status moves pending → processing → succeeded | failed
--   | canceled, changed only by the edge functions (service role) or the two
--   admin RPCs. Players read their own rows; Tara reads all.
-- * policy lives in app_settings so Tara's answers change a value, not code.

alter table public.accounts
  add column if not exists stripe_customer_id text unique,
  add column if not exists card_brand text,
  add column if not exists card_last4 text check (card_last4 is null or card_last4 ~ '^[0-9]{4}$'),
  add column if not exists card_added_at timestamptz;

comment on column public.accounts.stripe_customer_id is
  'Stripe customer for this account. Written only by the stripe-webhook edge function.';
comment on column public.accounts.card_last4 is
  'Display only ("Visa ···4242"). Never the card number; Stripe holds that.';

do $$ begin
  create type public.payment_kind as enum ('clinic_fee', 'late_cancel', 'no_show', 'refund');
exception when duplicate_object then null; end $$;
do $$ begin
  create type public.payment_status as enum ('pending', 'processing', 'succeeded', 'failed', 'canceled');
exception when duplicate_object then null; end $$;

create table if not exists public.payments (
  id                        uuid primary key default gen_random_uuid(),
  registration_id           uuid not null references public.registrations (id),
  account_id                uuid not null references public.accounts (id),
  kind                      public.payment_kind not null,
  amount_cents              integer not null check (amount_cents > 0),
  currency                  text not null default 'usd',
  status                    public.payment_status not null default 'pending',
  stripe_payment_intent_id  text unique,
  stripe_refund_id          text unique,
  refunds_payment_id        uuid references public.payments (id),
  failure_reason            text,
  requested_by              uuid references public.accounts (id),
  created_at                timestamptz not null default now(),
  updated_at                timestamptz not null default now(),
  constraint refund_points_at_a_payment check ((kind = 'refund') = (refunds_payment_id is not null))
);

comment on table public.payments is
  'Every money event, one row. Status is changed only by the Stripe edge functions '
  '(service role) or admin RPCs. Players see their own rows; admins see all.';

create index if not exists payments_registration_idx on public.payments (registration_id);
create index if not exists payments_account_idx on public.payments (account_id, created_at desc);

alter table public.payments enable row level security;

drop policy if exists payments_own on public.payments;
drop policy if exists payments_admin on public.payments;
create policy payments_own on public.payments
  for select using (account_id = auth.uid());
create policy payments_admin on public.payments
  for select using (public.is_admin());

-- Hard rule 11: revoke before grant, from PUBLIC too. Reads for the owner and
-- Tara through RLS; no client writes at all.
revoke all on public.payments from public, anon, authenticated;
grant select on public.payments to authenticated;

-- ------------------------------------------------------------ settings ----
-- Defaults are the ones proposed to Tara (questions-for-tara.md Q27–Q37).
-- payments_enabled stays false until she has answered.
insert into public.app_settings (key, value) values
  ('payments_enabled',       'false'),
  ('cancel_cutoff_hours',    '24'),
  ('late_cancel_fee',        'full'),   -- 'full' | a number of cents
  ('charge_fee_at',          'in'),     -- 'in' (when You're In!) | 'after'
  ('late_charge_needs_tap',  'true'),   -- late cancel / no show wait for Tara
  ('zelle_allowed',          'true')
on conflict (key) do nothing;

-- ------------------------------------------------------------ helpers ----
create or replace function public.payments_enabled()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select value = 'true' from public.app_settings where key = 'payments_enabled'), false);
$$;

-- ------------------------------------------------------------- RPCs -----
-- Tara asks for a charge. The row is 'pending'; the stripe-charge edge
-- function picks it up, performs the PaymentIntent off-session, and the
-- webhook sets succeeded/failed. Amount defaults to the price snapshot on the
-- registration (decision 0002), so a price edit later never changes a fee.
create or replace function public.admin_charge_registration(
  p_registration uuid, p_kind public.payment_kind, p_amount_cents integer default null)
returns public.payments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  r public.registrations; a public.accounts; v public.payments; amt integer;
begin
  perform public.require_admin();
  if not public.payments_enabled() then
    raise exception 'payments_disabled' using errcode = 'P0001';
  end if;
  if p_kind = 'refund' then
    raise exception 'use_admin_refund_payment' using errcode = '22023';
  end if;
  select * into r from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  select a2.* into a from public.accounts a2 join public.players p on p.account_id = a2.id where p.id = r.player_id;
  if a.stripe_customer_id is null then
    raise exception 'no_card_on_file' using errcode = 'P0001';
  end if;
  amt := coalesce(p_amount_cents, r.price_cents_charged);
  if amt is null or amt <= 0 then
    raise exception 'amount_required' using errcode = '22023';
  end if;
  -- One live charge per registration and kind: a double tap is not two fees.
  if exists (select 1 from public.payments x where x.registration_id = p_registration
               and x.kind = p_kind and x.status in ('pending', 'processing', 'succeeded')) then
    raise exception 'already_charged' using errcode = 'P0001';
  end if;
  insert into public.payments (registration_id, account_id, kind, amount_cents, requested_by)
  values (p_registration, a.id, p_kind, amt, auth.uid())
  returning * into v;
  return v;
end;
$$;

-- Tara refunds a succeeded charge, whole. Partial refunds are not a v1 need.
create or replace function public.admin_refund_payment(p_payment uuid)
returns public.payments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare orig public.payments; v public.payments;
begin
  perform public.require_admin();
  select * into orig from public.payments where id = p_payment;
  if not found then
    raise exception 'payment_not_found' using errcode = 'P0002';
  end if;
  if orig.kind = 'refund' or orig.status <> 'succeeded' then
    raise exception 'not_refundable' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.payments x where x.refunds_payment_id = orig.id
               and x.status in ('pending', 'processing', 'succeeded')) then
    raise exception 'already_refunded' using errcode = 'P0001';
  end if;
  insert into public.payments (registration_id, account_id, kind, amount_cents, refunds_payment_id, requested_by)
  values (orig.registration_id, orig.account_id, 'refund', orig.amount_cents, orig.id, auth.uid())
  returning * into v;
  return v;
end;
$$;

-- ----------------------------------------------------------- triggers ---
-- The ledger drives the Paid checkbox, not the other way round: a succeeded
-- clinic fee marks the registration paid; a succeeded refund of one unmarks
-- it. set_paid (Zelle, by hand) still works and writes nothing here.
create or replace function public.payments_sync_registration_paid()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare orig public.payments;
begin
  new.updated_at := now();
  if new.status = 'succeeded' and (old.status is distinct from 'succeeded') then
    if new.kind = 'clinic_fee' then
      update public.registrations set paid = true where id = new.registration_id;
    elsif new.kind = 'refund' then
      select * into orig from public.payments where id = new.refunds_payment_id;
      if orig.kind = 'clinic_fee' then
        update public.registrations set paid = false where id = new.registration_id;
      end if;
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists payments_sync_registration_paid on public.payments;
create trigger payments_sync_registration_paid
  before update on public.payments
  for each row execute function public.payments_sync_registration_paid();

-- ------------------------------------------------------------- grants ---
revoke all on function public.payments_enabled() from public, anon, authenticated;
revoke all on function public.admin_charge_registration(uuid, public.payment_kind, integer) from public, anon, authenticated;
revoke all on function public.admin_refund_payment(uuid) from public, anon, authenticated;
revoke all on function public.payments_sync_registration_paid() from public, anon, authenticated;
grant execute on function public.payments_enabled() to authenticated;
grant execute on function public.admin_charge_registration(uuid, public.payment_kind, integer) to authenticated;
grant execute on function public.admin_refund_payment(uuid) to authenticated;
