-- 20260928700001_declined_card.sql
--
-- Tara's round-four answers 78 and 83 (decision 0024, 2026-09-28), quoted
-- exactly:
--   78  "Cannot sign up without proper, transactional card. App needs to tell
--        them why their card isn’t working, yes."
--   83  "Can we have a button that says “resolved” and it clears - for me only
--        to see ofc"
-- Decision 0026 records how each is built, what was rejected, and what the
-- sql-auditor's review (2026-09-28) changed.
--
-- =========================================================== A. DECLINED ===
-- THE RULE. Once a charge on a player's card is declined, that player cannot
-- register for a clinic and cannot accept an invitation until they save a
-- card again or a later charge on their account goes through. Admins are
-- exempt. The rule is on exactly while card_required is (payments on and a
-- card required: the same two switches, in the same block of
-- register_for_clinic), and card_required is checked first, so a player with
-- no card at all is asked for one rather than told about an old decline.
--
-- WHAT COUNTS AS A DECLINE. A charge (clinic_fee, no_show or late_cancel:
-- every kind Charge clinic makes; never a refund) going from pending or
-- processing to 'failed' with a Stripe code in failure_code, on real money
-- (payment_is_real: before the switch to live the sandbox is the payment
-- system, after it test mode is not money). failure_code is set only when
-- Stripe said no to the CARD: stripe-webhook's payment_intent.payment_failed
-- records it only for a card_error, and stripe-charge's synchronous card error
-- carries it, while a request Stripe refused (an invalid_request_error: our
-- parameters, nothing reached the bank) keeps only its sentence
-- (_shared/stripe-errors.ts, changed in the same branch). What never blocks:
--   * a dropped connection, a timeout, a 5xx or a 429: the row goes back to
--     pending (decision 0019), never to failed;
--   * an idempotency error, or a charge past the retry window: HELD, the row
--     stays processing; Tara's "Did not go through" makes it canceled, and a
--     failure delivered for it later changes nothing here;
--   * our own refusals (no_card_on_file, account_deleted): failed, no code;
--   * a failed row written again (a webhook delivering the same outcome days
--     later): only a charge still in flight can become a decline.
--
-- ORDER. "Until a LATER charge goes through" is about when charges were
-- ATTEMPTED (first_attempted_at, else created_at), not when Stripe's answers
-- are recorded: a card error is written at once, a success only when its
-- webhook arrives, so within one Charge clinic the arrivals race. So a
-- decline stands only if it is about the card on file (attempted once that
-- card was saved), is no older than a decline already recorded, and no charge
-- attempted after it has gone through; and a success clears only a decline
-- attempted no later than it. card_declined_at is that attempt time. The four
-- orders are pinned in the probe (sql-auditor finding 1).
--
-- WHERE IT LIVES. accounts.card_declined_at and accounts.card_decline_code.
-- The code is Stripe's, except the five that Stripe asks be shown to the
-- cardholder as a plain decline (lost_card, stolen_card, fraudulent,
-- merchant_blacklist, pickup_card), kept here as generic_decline; Tara reads
-- the real code on the payment. Written only by the triggers below and by
-- stripe_cutover_to_live, never by a client. Hard rule 8, layer by layer:
--   1. Column grants. authenticated's UPDATE on accounts is column-level,
--      first_name, last_name and phone (20260802000003, restated
--      20260817000001); neither column is in it, so a player's UPDATE is
--      refused before any trigger runs. declined_card.sql attacks it.
--   2. RLS cannot compare a row with its old self, so the WITH CHECK layer
--      has nothing to add for a column no client may write at all.
--   3. The backstop in accounts_card_decline: a change to either column made
--      by a statement acting for a signed-in person (auth.uid() set, and not
--      from inside the ledger trigger) is refused, card_decline_not_writable;
--      and a card saved clears a decline only when no signed-in person is
--      behind the write. So no SECURITY DEFINER RPC, now or later, can clear
--      a decline for the person calling it, directly or by writing a card date.
-- The player reads their own decline through the accounts row they already
-- read their card summary from (accounts_self: their own row, or an admin);
-- nobody else's.
--
-- SET AND CLEARED BY
--   * payments_card_decline (AFTER UPDATE OF status ON payments): sets it,
--     and clears it on a success (the webhook, or Tara's "Went through" on a
--     held charge), as ORDER says.
--   * accounts_card_decline (BEFORE UPDATE ON accounts): a card saved by the
--     Stripe pipeline (setup_intent.succeeded writes card_last4 and a new
--     card_added_at, as service_role) clears it. A card REMOVED does not: the
--     decline stays, Register asks for a card first (card_required) and an
--     Accept, which checks no card, stays refused (sql-auditor finding 6).
--   * stripe_cutover_to_live: every card is gone at the swap to live, and
--     any decline recorded against a sandbox card goes with it.
--
-- THE REFUSAL. register_for_clinic and respond_to_invitation (Accept only;
-- Decline stays allowed) raise card_declined and move nothing. The code rides
-- in the error's HINT, which supabase-swift decodes (its PostgrestError has
-- no field for PostgREST's "details"), so the app says why without a second
-- read. Both bodies are the latest (20260928000001, 20260928400001) with that
-- check added and nothing else.
--
-- =========================================================== B. RESOLVED ===
-- payments.resolved_at and resolved_by: Tara's Resolved on a declined charge
-- she will not chase. Written only by admin_resolve_decline(p_payment):
-- require_admin, and conditional (hard rule 3) on a failed, unresolved
-- charge; anything else is decline_not_open and changes nothing.
-- authenticated has no UPDATE on payments at all, and SELECT only on the
-- column list of 20260927300003, which does not name these two.
--   * It clears the row everywhere Tara is asked to act, by one definition:
--     money_rows() gives a declined row whose failed charge is resolved the
--     state 'resolved', counted nowhere (like 'settled'), so
--     admin_money_declined, the Declined figures of admin_money_summary and
--     admin_money_clinics, Action Needed on the web and the phone, and the
--     This week tab's owed list (readMoneyOwed) all leave it out.
--   * Charge clinic does not charge it again (admin_charge_clinic skips a
--     'resolved' registration; sql-auditor finding 3): "will not chase" moves
--     no money. Whether it should mean "try again later" is hers to say.
--   * The ledger keeps the declined charge as it was, and payments_ledger
--     gains resolved_at so the Money tab's card list can say Resolved on it.
--   * It does NOT unblock the player: the card is still the card that was
--     declined. Only a new card or a later success does (part A).
--   * It does not move updated_at, which is when the charge failed
--     (money_rows.failed_at, and which failed charge money_rows shows).
--     payments_sync_registration_paid stamps updated_at on every update; it
--     now leaves it alone for an update that changes nothing but the
--     resolution, or nothing at all (a webhook delivering an outcome already
--     recorded). Every update that changes anything else is as before.
--   * money_rows gains failed_payment_id, the failed charge it already picks
--     for a declined row, so the charge Tara resolves is the one whose reason
--     she is reading. Adding an output column changes the return type, so
--     money_rows and admin_money_declined are dropped and recreated.
--
-- NO BACKFILL. A charge that failed before this migration blocks nobody.
-- CLAUDE.md's 2026-09-27 entries have card payments still switched off on
-- hosted (not re-checked from this branch, which does not touch hosted), and
-- a sandbox decline made while testing would be test money at the swap to
-- live anyway. If a live decline exists by the time this ships, it needs a
-- one-off backfill.
--
-- CONCURRENCY. Stripe delivers events concurrently, so the trigger locks the
-- account row before deciding: a failure recorded while a later-attempted
-- success commits then sees it (tests/sql/declined_card_race.sh, red without
-- the lock; found in the review after the sql-auditor's).
--
-- Probe: tests/sql/declined_card.sql and declined_card_race.sh. The webhook
-- path end to end: tests/stripe/run.sh, section 16.


-- ------------------------------------------------------------ columns ----
alter table public.accounts
  add column if not exists card_declined_at  timestamptz,
  add column if not exists card_decline_code text;

comment on column public.accounts.card_declined_at is
  'When the declined charge that still stands was ATTEMPTED (its first_attempted_at, '
  'else created_at): set by payments_card_decline, cleared by a charge attempted no '
  'earlier that went through, by a card saved by the Stripe pipeline '
  '(accounts_card_decline), or by stripe_cutover_to_live. While set, register_for_clinic '
  'and an Accept raise card_declined (decision 0024, Tara''s question 78). No client may '
  'write it. 20260928700001.';
comment on column public.accounts.card_decline_code is
  'Stripe''s code for that decline as the player may be told it: payments.failure_code, '
  'except lost_card, stolen_card, fraudulent, merchant_blacklist and pickup_card, kept '
  'as generic_decline (Stripe: present those to the cardholder as a generic decline). '
  'Tara reads the real code on the payment. 20260928700001.';

alter table public.payments
  add column if not exists resolved_at timestamptz,
  add column if not exists resolved_by uuid references public.accounts (id);

comment on column public.payments.resolved_at is
  'Tara pressed Resolved on this declined charge (decision 0024, question 83): '
  'she will not chase it. Leaves Action Needed and the Declined figures; the row '
  'itself is kept. Does not unblock the player. admin_resolve_decline only. '
  '20260928700001.';
comment on column public.payments.resolved_by is
  'The admin who pressed Resolved. 20260928700001.';

-- No privilege for any client on the four: accounts' UPDATE for authenticated
-- is column-level and names none of them; payments' SELECT for authenticated
-- is a column list (20260927300003) that names neither of its two, and it
-- has no write privilege at all. service_role's table-level DML
-- (20260912000002) covers new columns. Nothing to grant, nothing to revoke.

-- ------------------------------------------ the ledger decides a decline ----
create or replace function public.payments_card_decline()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  -- When this charge was attempted: Stripe's answers arrive in any order
  -- (a card error is written at once, a success when its webhook comes), so
  -- "a LATER charge went through" is about attempts, not about arrivals.
  v_attempt timestamptz := coalesce(new.first_attempted_at, new.created_at);
begin
  -- A refund is not a charge on the card, and test money after the switch
  -- to live is not money.
  if new.kind = 'refund' or not public.payment_is_real(new.livemode) then
    return null;
  end if;
  -- Declined: an attempt in flight comes back failed with Stripe's code.
  -- Our own refusals carry none, a retry or a hold never reaches failed, and
  -- a row that was already failed, canceled (Tara's "Did not go through") or
  -- succeeded is a late or repeated answer, not a new decline. It stands
  -- only if it is about the card on file (attempted once that card was
  -- saved), is no older than a decline already recorded, and no charge
  -- attempted after it has gone through.
  if new.status = 'failed' and old.status in ('pending', 'processing')
     and new.failure_code is not null then
    -- The account row first. Stripe delivers events concurrently, so a
    -- later-attempted success may be committing right now; once this lock is
    -- granted the UPDATE below is a new statement with a fresh snapshot and
    -- sees it (declined_card_race.sh, red without the lock).
    perform 1 from public.accounts where id = new.account_id for update;
    update public.accounts a
       set card_declined_at  = v_attempt,
           -- Stripe: present these to the cardholder as a generic decline.
           card_decline_code = case when new.failure_code in
                                 ('lost_card', 'stolen_card', 'fraudulent', 'merchant_blacklist', 'pickup_card')
                               then 'generic_decline' else new.failure_code end
     where a.id = new.account_id
       and (a.card_added_at is null or a.card_added_at <= v_attempt)
       and (a.card_declined_at is null or a.card_declined_at <= v_attempt)
       and not exists (select 1 from public.payments s
                        where s.account_id = new.account_id
                          and s.kind <> 'refund'
                          and s.status = 'succeeded'
                          and public.payment_is_real(s.livemode)
                          and coalesce(s.first_attempted_at, s.created_at) > v_attempt);
  -- A charge attempted no earlier than the decline went through: the card works.
  elsif new.status = 'succeeded' and old.status is distinct from 'succeeded' then
    -- The same lock, so a failure recorded alongside waits for this success.
    perform 1 from public.accounts where id = new.account_id for update;
    update public.accounts a
       set card_declined_at = null, card_decline_code = null
     where a.id = new.account_id
       and a.card_declined_at is not null
       and a.card_declined_at <= v_attempt;
  end if;
  return null;
end;
$$;

comment on function public.payments_card_decline() is
  'Trigger: a charge going from pending or processing to failed with a Stripe code marks '
  'its account''s card declined, at the time it was attempted, unless a charge attempted '
  'later has gone through or the card on file was saved after it; a charge going to '
  'succeeded clears a decline attempted no later than it. Refunds and test money after '
  'the switch to live are ignored. 20260928700001.';

drop trigger if exists payments_card_decline on public.payments;
create trigger payments_card_decline
  after update of status on public.payments
  for each row execute function public.payments_card_decline();

-- ------------------------------------------ the account keeps it honest ----
create or replace function public.accounts_card_decline()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  -- Hard rule 8, layer 3. The column grants already refuse a signed-in
  -- person's own UPDATE; this refuses any other path acting for one (a
  -- future SECURITY DEFINER RPC). The ledger trigger above writes from one
  -- level down (pg_trigger_depth() > 1), the Stripe pipeline as service_role
  -- (no auth.uid()), a migration as postgres: all allowed.
  if (new.card_declined_at is distinct from old.card_declined_at
      or new.card_decline_code is distinct from old.card_decline_code)
     and pg_trigger_depth() = 1
     and auth.uid() is not null then
    raise exception 'card_decline_not_writable' using errcode = '42501';
  end if;
  -- A card saved again ends a decline: stripe-webhook's setup_intent.succeeded
  -- writes card_last4 and a new card_added_at, as service_role. Only that:
  -- a card removed leaves the decline standing (an Accept, which checks no
  -- card, stays refused; Register asks for a card first), and a write made
  -- for a signed-in person, whatever path it takes, clears nothing
  -- (sql-auditor findings 5 and 6).
  if new.card_last4 is not null and new.card_added_at is not null
     and new.card_added_at is distinct from old.card_added_at
     and auth.uid() is null then
    new.card_declined_at  := null;
    new.card_decline_code := null;
  end if;
  return new;
end;
$$;

comment on function public.accounts_card_decline() is
  'Trigger: refuses a change to card_declined_at / card_decline_code made for a '
  'signed-in person, and clears them when the Stripe pipeline saves a card '
  '(card_added_at moves, card_last4 set, no signed-in person). 20260928700001.';

drop trigger if exists accounts_card_decline on public.accounts;
create trigger accounts_card_decline
  before update on public.accounts
  for each row execute function public.accounts_card_decline();

-- Hard rule 11: PUBLIC first. Trigger functions are called by nobody.
revoke all on function public.payments_card_decline() from public, anon, authenticated;
revoke all on function public.accounts_card_decline() from public, anon, authenticated;

-- ------------------------------------------------------ Tara's Resolved ----
create or replace function public.admin_resolve_decline(p_payment uuid)
returns public.payments
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.payments;
begin
  perform public.require_admin();
  -- Hard rule 3: conditional. A charge that has since gone through, a
  -- refund, a pending or held charge, or one already resolved is not an
  -- open decline, and a second tap changes nothing.
  update public.payments
     set resolved_at = now(),
         resolved_by = auth.uid()
   where id = p_payment
     and kind <> 'refund'
     and status = 'failed'
     and resolved_at is null
  returning * into v;
  if not found then
    raise exception 'decline_not_open' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

comment on function public.admin_resolve_decline(uuid) is
  'Tara''s Resolved on a declined charge (decision 0024, question 83): stamps '
  'resolved_at / resolved_by on a failed, unresolved charge, which takes it out of '
  'Action Needed and the Declined figures (money_rows state resolved) and keeps Charge '
  'clinic from charging it again. Does not unblock the player. decline_not_open '
  'otherwise. Admin only. 20260928700001.';

revoke all on function public.admin_resolve_decline(uuid) from public, anon;
grant execute on function public.admin_resolve_decline(uuid) to authenticated;


-- ------------------------------------- the ledger trigger keeps a date ----
-- payments_sync_registration_paid exactly as 20260927200001, plus the early
-- return at the top: an update that changes nothing but the resolution, or
-- nothing at all, keeps updated_at (and has no status transition, so the Paid
-- logic below it had nothing to do anyway).
create or replace function public.payments_sync_registration_paid()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare orig public.payments;
begin
  -- Tara's Resolved (20260928700001) is her note on a decline, not a change
  -- to it, and a webhook delivering an outcome already recorded changes
  -- nothing: neither moves updated_at, which is when a charge failed
  -- (money_rows.failed_at, and which failed charge money_rows shows).
  if (to_jsonb(new) - 'resolved_at' - 'resolved_by')
     = (to_jsonb(old) - 'resolved_at' - 'resolved_by') then
    return new;
  end if;
  new.updated_at := now();
  -- Test mode is not money (20260927200001): a sandbox fee succeeding does
  -- not mark anyone paid, and a sandbox refund does not unmark them.
  if new.livemode is false then
    return new;
  end if;
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
revoke all on function public.payments_sync_registration_paid() from public, anon, authenticated;

-- ------------------------------------------------------------ money_rows ----
-- Exactly as 20260927300001 plus two things: failed_payment_id, the failed
-- charge the lateral already picks for a declined row, and the state
-- 'resolved' for a declined row whose charge Tara resolved. 'resolved' is
-- counted nowhere, like 'settled'.
drop function if exists public.money_rows();
create function public.money_rows()
returns table (
  registration_id  uuid,
  clinic_id        uuid,
  player_id        uuid,
  account_id       uuid,
  owed_kind        public.payment_kind,
  amount_cents     integer,
  state            text,
  has_card         boolean,
  attempted_cents  integer,
  failure_code     text,
  failure_reason   text,
  failed_at        timestamptz,
  failed_payment_id uuid)
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  with since as (select public.payments_enabled_at() as t),
  owing as (
    select r.id, r.clinic_id, r.player_id, p.account_id, r.price_cents_charged, r.paid,
           case when r.status = 'in' and not r.no_show then 'clinic_fee'::public.payment_kind
                when r.status = 'in' and r.no_show     then 'no_show'::public.payment_kind
                when r.status = 'canceled' and r.late_cancel and not r.courtesy_used
                     and not exists (select 1 from public.registrations o
                                      where o.clinic_id = r.clinic_id
                                        and o.player_id = r.player_id
                                        and o.status = 'in')
                  then 'late_cancel'::public.payment_kind
           end as owed_kind
      from public.registrations r
      join public.clinics c on c.id = r.clinic_id
      join public.players p on p.id = r.player_id
      cross join since s
     where c.status <> 'canceled'
       and c.ends_at <= now()
       and s.t is not null
       and c.ends_at >= s.t
  ),
  judged as (
    select w.*,
           case
             when w.owed_kind is null then null
             when public.player_has_live_fee(w.player_id, w.clinic_id) then 'charged'
             when w.paid then 'settled'
             when exists (select 1 from public.payments x
                           where x.registration_id = w.id and x.kind = w.owed_kind
                             and x.status = 'succeeded'
                             and public.payment_is_real(x.livemode)) then 'refunded'
             when exists (select 1 from public.payments x
                           where x.registration_id = w.id and x.kind = w.owed_kind
                             and x.status = 'failed'
                             and public.payment_is_real(x.livemode)) then 'declined'
             else 'not_charged'
           end as state
      from owing w
  )
  select j.id, j.clinic_id, j.player_id, j.account_id, j.owed_kind, j.price_cents_charged,
         -- Tara's Resolved on the failed charge shown (20260928700001).
         case when j.state = 'declined' and f.resolved_at is not null then 'resolved' else j.state end,
         exists (select 1 from public.accounts a
                  where a.id = j.account_id
                    and a.stripe_customer_id is not null
                    and a.card_last4 is not null),
         f.amount_cents, f.failure_code, f.failure_reason, f.updated_at, f.id
    from judged j
    left join lateral (
      select x.id, x.amount_cents, x.failure_code, x.failure_reason, x.updated_at, x.resolved_at
        from public.payments x
       where j.state = 'declined'
         and x.registration_id = j.id and x.kind = j.owed_kind and x.status = 'failed'
         and public.payment_is_real(x.livemode)
       order by x.updated_at desc, x.created_at desc, x.id desc
       limit 1
    ) f on true;
$$;

comment on function public.money_rows() is
  'Internal. One row per registration in an ended, not canceled clinic that ended '
  'at or after payments_enabled_at: what it owes (the kind Charge clinic would '
  'charge, or null) and where that stands (charged, settled, refunded, declined, '
  'resolved, not_charged), with the failed charge a declined or resolved row shows. '
  'Aggregated by admin_money_*.';

revoke all on function public.money_rows() from public, anon, authenticated;


-- -------------------------------------------------- the declined list ----
-- Exactly as 20260927300001 plus payment_id, the failed charge Resolved
-- stamps. A resolved decline is not in it: money_rows calls it 'resolved'.
drop function if exists public.admin_money_declined();
create function public.admin_money_declined()
returns table (
  registration_id   uuid,
  clinic_id         uuid,
  clinic_name       text,
  clinic_starts_at  timestamptz,
  first_name        text,
  last_name         text,
  amount_cents      integer,
  failure_code      text,
  failure_reason    text,
  failed_at         timestamptz,
  account_deleted   boolean,
  payment_id        uuid)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
  select m.registration_id, m.clinic_id, c.name, c.starts_at, a.first_name, a.last_name,
         m.attempted_cents, m.failure_code, m.failure_reason, m.failed_at,
         a.deleted_at is not null,
         m.failed_payment_id
    from public.money_rows() m
    join public.clinics c  on c.id = m.clinic_id
    join public.accounts a on a.id = m.account_id
   where m.state = 'declined'
   order by m.failed_at desc, a.last_name, a.first_name;
end;
$$;

comment on function public.admin_money_declined() is
  'Registrations whose charge for what they owe failed, has not gone through since, '
  'and has not been marked Resolved, with the cardholder''s name, Stripe''s code, '
  'whether the account has since been deleted (Action Needed leaves those out), and '
  'the failed charge''s id for admin_resolve_decline. Admin only.';

revoke all on function public.admin_money_declined() from public, anon;
grant execute on function public.admin_money_declined() to authenticated;


-- ------------------------------------------------------ the ledger view ----
-- Same view as 20260928200001 with resolved_at appended (CREATE OR REPLACE
-- can only add columns at the end), so the card list can say Resolved.
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
    c.starts_at as clinic_starts_at,
    p.failure_code,
    p.livemode,
    p.dispute_status,
    p.resolved_at
  from public.payments p
  join public.accounts a      on a.id = p.account_id
  join public.registrations r on r.id = p.registration_id
  join public.clinics c       on c.id = r.clinic_id
  where public.is_admin()
    and (p.livemode is not false
         or not exists (select 1 from public.app_settings s where s.key = 'stripe_live_since'));

comment on view public.payments_ledger is
  'Card payments with the player and clinic named, Stripe''s decline code, livemode, '
  'dispute status and when Tara resolved a decline. Admin only (is_admin() inside). Test-mode rows are listed until '
  'stripe_cutover_to_live() records stripe_live_since, and hidden after. Zelle is the Paid '
  'flag on registrations, not a row here.';

-- Hard rule 11, restated because the view was just replaced.
revoke all on public.payments_ledger from public, anon, authenticated;
grant select on public.payments_ledger to authenticated;


-- ------------------------------------------------------ register_for_clinic --
-- Exactly as 20260928000001 plus the card_declined check, inside the block
-- that already holds card_required and after it.
create or replace function public.register_for_clinic(p_clinic uuid, p_player uuid)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c        public.clinics;
  v_member boolean;
  v_taken  integer;
  v_status registration_status;
  v_row    public.registrations;
  v_card   boolean;
  v_account uuid;
  v_b2b_opens timestamptz;
  v_declined boolean;
  v_decline_code text;
begin
  if not (public.owns_player(p_player) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  select * into c from public.clinics
   where id = p_clinic and status = 'published'
   for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;

  if c.closes_at is not null and now() >= c.closes_at then
    raise exception 'registration_closed' using errcode = 'P0001';
  end if;

  select is_member, account_id into v_member, v_account from public.players where id = p_player;
  if v_member is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  -- Decision 0012: "Gosh I say yes." A player cannot hold a spot without a
  -- card once payments are on. Tara placing someone by hand is not blocked.
  -- A card is the summary the webhook writes after Stripe saves one
  -- (card_last4), not the customer id, which exists from the moment someone
  -- opens the card sheet, saved card or not (found 2026-09-26, decision 0015 §5).
  if public.payments_enabled() and public.card_required() and not public.is_admin() then
    select a.stripe_customer_id is not null and a.card_last4 is not null into v_card
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = p_player;
    if not coalesce(v_card, false) then
      raise exception 'card_required' using errcode = 'P0001';
    end if;
    -- Decision 0024, Tara's question 78: "Cannot sign up without proper,
    -- transactional card." A card whose last charge was declined holds no
    -- spot until a card is saved again or a later charge goes through
    -- (20260928700001). The code rides in the HINT so the app can say why.
    select a.card_declined_at is not null, a.card_decline_code into v_declined, v_decline_code
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = p_player;
    if coalesce(v_declined, false) then
      raise exception 'card_declined' using errcode = 'P0001', hint = coalesce(v_decline_code, '');
    end if;
  end if;

  -- Decision 0013 §4: the waiver is signed before the first spot is held.
  if not public.is_admin() and not public.waiver_accepted(v_account) then
    raise exception 'waiver_required' using errcode = 'P0001';
  end if;

  if now() < c.member_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif not v_member and now() < c.public_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif v_member and now() < c.public_opens_at then
    select count(*) into v_taken
      from public.registrations
     where clinic_id = p_clinic and status = 'in';
    v_status := case when v_taken < c.internal_capacity then 'in' else 'pool' end;
  else
    v_status := 'pool';
  end if;

  -- Decision 0015 §13, Tara 2026-09-26: "members can sign up for back to
  -- back 105's (same day back to back) but nonmembers cannot until 48 [hours]
  -- prior to start time of clinic." A non-member already holding a live spot
  -- in a 105 on the same New York day may take a second one only from 48
  -- hours before the earlier of the two. Tara's own placements are exempt.
  if not v_member and not public.is_admin() and public.is_105(c.name, c.category) then
    -- Two registrations by the same player for two different 105s at the same
    -- instant share no row lock (each locks only its own clinic), so both
    -- could pass this check. Serialise them per player; cannot deadlock,
    -- since each holder already has its own clinic and waits for no other.
    perform pg_advisory_xact_lock(hashtextextended('register_105:' || p_player::text, 0));
    select min(public.back_to_back_105_opens_at(c.starts_at, o.starts_at)) into v_b2b_opens
      from public.registrations r2
      join public.clinics o on o.id = r2.clinic_id
     where r2.player_id = p_player
       and r2.clinic_id <> p_clinic
       and r2.status in ('in', 'pool', 'response_needed')
       and o.status = 'published'
       and public.is_105(o.name, o.category)
       and (o.starts_at at time zone 'America/New_York')::date
         = (c.starts_at at time zone 'America/New_York')::date;
    if v_b2b_opens is not null and now() < v_b2b_opens then
      raise exception 'back_to_back_105' using errcode = 'P0001';
    end if;
  end if;

  insert into public.registrations (
      clinic_id, player_id, status, source,
      price_cents_charged, was_member, duration_minutes)
  values (p_clinic, p_player, v_status,
          case when public.owns_player(p_player) then 'self'::registration_source
                                                 else 'admin'::registration_source end,
          case when v_member then c.member_price_cents else c.nonmember_price_cents end,
          v_member,
          c.duration_minutes)
  returning * into v_row;

  -- Tara's words, to the player whose spot it is, whoever tapped Register.
  -- #1 You're In, with the day and time in New York; #5 Added to Player Pool,
  -- which is for a first registration only, and this insert is one.
  if v_row.status = 'in' then
    perform public.notify_account(v_account, 'youre_in', 'registration', v_row.id,
      'You''re all set for ' || c.name || ' on '
      || to_char(c.starts_at at time zone 'America/New_York', 'FMDay') || ' at '
      || to_char(c.starts_at at time zone 'America/New_York', 'FMHH12:MI AM')
      || '. Looking forward to seeing you on court!');
  elsif v_row.status = 'pool' then
    perform public.notify_account(v_account, 'added_to_pool', 'registration', v_row.id,
      'Thanks for registering! I personally create each clinic based on playing levels and will send confirmations once lineups are set ASAP');
  end if;

  return v_row;
exception
  when unique_violation then
    raise exception 'already_registered' using errcode = 'P0001';
end;
$$;

revoke all on function public.register_for_clinic(uuid, uuid) from public, anon;
grant execute on function public.register_for_clinic(uuid, uuid) to authenticated;


-- ---------------------------------------------------- respond_to_invitation --
-- Exactly as 20260928400001 plus the card_declined check on Accept, after
-- the clinic's own checks and before the conditional UPDATE.
create or replace function public.respond_to_invitation(p_registration uuid, p_accept boolean)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row    public.registrations;
  v_player public.players;
  v_admin  uuid;
  v_clinic text;
  v_clinic_status clinic_status;
  v_ends  timestamptz;
  v_declined boolean;
  v_decline_code text;
begin
  select * into v_row from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not public.owns_player(v_row.player_id) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  -- Accepting a canceled clinic put a player in You're In! of a clinic that
  -- is not happening (backlog, 2026-09-28): the invitation's own Accept
  -- button on the lock screen never sees the clinic page's canceled banner.
  -- The clinic row is locked FOR SHARE first, so cancel_clinic (an UPDATE of
  -- that row) and this answer are serialized: whichever commits first, the
  -- other sees it. Declining a canceled clinic stays allowed; it changes
  -- nothing that matters.
  select status, ends_at into v_clinic_status, v_ends
    from public.clinics where id = v_row.clinic_id
     for share;
  if p_accept and v_clinic_status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  -- A finished clinic cannot be joined (20260928400001). Invitations never
  -- expire (hard rule 2), and since decision 0023 the Accept sits on a push
  -- that can be tapped days later: without this the player landed in You're
  -- In! of a clinic that was over and was charged at Tara's next tap. The
  -- line is the END, which nobody can argue with; whether it should be the
  -- start is question 91.
  if p_accept and v_ends <= now() then
    raise exception 'clinic_ended' using errcode = 'P0001';
  end if;
  -- Decision 0024, Tara's question 78: a declined card takes no spot, by
  -- Register or by Accept, while cards are required (the switches
  -- register_for_clinic reads). Decline stays allowed: it takes nothing.
  -- Checked before the conditional UPDATE, so nothing moves (20260928700001).
  if p_accept and not public.is_admin()
     and public.payments_enabled() and public.card_required() then
    select a.card_declined_at is not null, a.card_decline_code into v_declined, v_decline_code
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = v_row.player_id;
    if coalesce(v_declined, false) then
      raise exception 'card_declined' using errcode = 'P0001', hint = coalesce(v_decline_code, '');
    end if;
  end if;

  update public.registrations
     set status = case when p_accept then 'in'::registration_status
                                     else 'pool'::registration_status end,
         responded_at = now()
   where id = p_registration
     and status = 'response_needed'
  returning * into v_row;

  if not found then
    raise exception 'invitation_no_longer_available' using errcode = 'P0001';
  end if;

  select * into v_player from public.players where id = v_row.player_id;
  select name, status into v_clinic, v_clinic_status from public.clinics where id = v_row.clinic_id;
  -- #13 and #14, the catalogue's wording, to every admin.
  for v_admin in select public.admin_account_ids() loop
    perform public.notify_account(
      v_admin, case when p_accept then 'invitation_accepted' else 'invitation_declined' end,
      'registration', v_row.id,
      v_player.first_name || ' ' || v_player.last_name
        || case when p_accept then ' accepted their spot in ' || v_clinic || '.'
                else ' declined ' || v_clinic || ' and is back in the Player Pool.' end);
  end loop;

  -- #3 Invitation Accepted, hers, to the player who accepted. Not #1 as well:
  -- one tap, one push (finding (e)). Not when Tara has canceled the clinic:
  -- "Your spot is confirmed" would be false (#13 still tells her). A decline
  -- sends the player nothing: it is not a first registration, so not #5
  -- (finding (i)).
  if p_accept and v_clinic_status <> 'canceled' then
    perform public.notify_account(v_player.account_id, 'invitation_accepted_player', 'registration', v_row.id,
      'Awesome! Your spot is confirmed. See you soon!');
  end if;

  -- What goes back to a player carries no court (hard rule 1, fact 6).
  if not public.is_admin() then
    v_row.court_number := null;
    v_row.canceled_by  := null;
  end if;

  return v_row;
end;
$$;

revoke all on function public.respond_to_invitation(uuid, boolean) from public, anon;
grant execute on function public.respond_to_invitation(uuid, boolean) to authenticated;


-- ------------------------------------------------------ admin_charge_clinic --
-- Exactly as 20260927300001 plus one skip: a registration whose decline Tara
-- resolved (money_rows state 'resolved') is not charged again. Without it a
-- tap for the clinic's other fees would quietly retry the card she said she
-- would not chase (sql-auditor, 2026-09-28). Whether Resolved should mean
-- "try again later" instead is hers to say (decision 0026).
create or replace function public.admin_charge_clinic(p_clinic uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c        public.clinics;
  r        record;
  v_kind   payment_kind;
  v_since  timestamptz;
  n_charged int := 0; n_already int := 0; n_no_card int := 0; n_skipped int := 0;
  v_resolved uuid[];
begin
  perform public.require_admin();
  if not public.payments_enabled() then
    raise exception 'payments_disabled' using errcode = 'P0001';
  end if;
  select * into c from public.clinics where id = p_clinic;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  if c.ends_at > now() then
    raise exception 'clinic_not_over' using errcode = 'P0001';
  end if;
  -- Before card payments were on, the club ran on Zelle: nothing from then
  -- is charged by card, and nothing at all while the moment is unrecorded.
  v_since := public.payments_enabled_at();
  if v_since is null or c.ends_at < v_since then
    raise exception 'clinic_before_payments' using errcode = 'P0001';
  end if;

  -- Tara's Resolved (20260928700001) is "I will not chase it": a
  -- registration whose decline she resolved is not charged again by this tap.
  select coalesce(array_agg(m.registration_id), '{}') into v_resolved
    from public.money_rows() m
   where m.clinic_id = p_clinic and m.state = 'resolved';

  for r in select * from public.registrations where clinic_id = p_clinic
            order by registered_at, id
            for update
  loop
    if r.status = 'in' and not r.no_show then v_kind := 'clinic_fee';
    elsif r.status = 'in' and r.no_show then v_kind := 'no_show';
    elsif r.status = 'canceled' and r.late_cancel and not r.courtesy_used
          and not exists (select 1 from public.registrations o
                           where o.clinic_id = p_clinic
                             and o.player_id = r.player_id
                             and o.status = 'in') then
      v_kind := 'late_cancel';
    else
      n_skipped := n_skipped + 1;
      continue;
    end if;
    -- Paid by hand (Tara's tick) and not charged: settled, not owed.
    if r.paid and not public.player_has_live_fee(r.player_id, r.clinic_id) then
      n_skipped := n_skipped + 1;
      continue;
    end if;
    -- A decline she resolved: hers to chase or not, never this tap's.
    if r.id = any (v_resolved) then
      n_skipped := n_skipped + 1;
      continue;
    end if;
    begin
      perform public.admin_charge_registration(r.id, v_kind);
      n_charged := n_charged + 1;
    exception
      when others then
        if sqlerrm = 'already_charged' then n_already := n_already + 1;
        elsif sqlerrm = 'no_card_on_file' then n_no_card := n_no_card + 1;
        else raise;
        end if;
    end;
  end loop;

  return jsonb_build_object('charged', n_charged, 'already', n_already,
                            'no_card', n_no_card, 'not_owed', n_skipped);
end;
$$;

revoke all on function public.admin_charge_clinic(uuid) from public, anon;
grant execute on function public.admin_charge_clinic(uuid) to authenticated;


-- --------------------------------------------------- stripe_cutover_to_live --
-- Exactly as 20260927200001 plus one UPDATE that clears every card decline:
-- each was recorded against a sandbox card, gone at the swap. A statement of
-- its own, after the count, so accounts_cleared counts what it always did.
create or replace function public.stripe_cutover_to_live()
returns table (
  accounts_cleared      int,
  payments_canceled     int,
  payments_marked_test  int,
  live_since            timestamptz
)
language plpgsql
volatile
security invoker
set search_path = public, pg_temp
as $$
declare
  v_accounts int;
  v_canceled int;
  v_marked   int;
  v_at       timestamptz := now();
begin
  -- Once. A second run after the swap would wipe members' real cards.
  if exists (select 1 from public.app_settings s where s.key = 'stripe_live_since') then
    raise exception 'already_live' using errcode = 'P0001';
  end if;
  -- Too late: a live payment means live cards exist, and they are not ours to wipe.
  if exists (select 1 from public.payments p where p.livemode is true) then
    raise exception 'live_payments_exist' using errcode = 'P0001';
  end if;

  -- Every Stripe customer and card summary made so far belongs to test mode.
  -- With them gone, register_for_clinic asks for a card again (card_required)
  -- and the app's card step opens for everyone.
  update public.accounts a
     set stripe_customer_id = null, card_brand = null, card_last4 = null, card_added_at = null
   where a.stripe_customer_id is not null or a.card_brand is not null
      or a.card_last4 is not null or a.card_added_at is not null;
  get diagnostics v_accounts = row_count;

  -- And every card decline (20260928700001): each was recorded against a
  -- sandbox card, gone now with the rest, whether or not the account still
  -- had card data. Its own statement, so accounts_cleared counts what it
  -- always counted.
  update public.accounts a
     set card_declined_at = null, card_decline_code = null
   where a.card_declined_at is not null or a.card_decline_code is not null;

  -- Nothing still waiting may be sent with the live key. Conditional on the
  -- status (hard rule 3); the row stays, as canceled (hard rule 4).
  update public.payments p
     set status = 'canceled', failure_reason = 'live_cutover'
   where p.status in ('pending', 'processing');
  get diagnostics v_canceled = row_count;

  -- Before the swap no live key existed, so a row whose mode was never
  -- recorded is test mode.
  update public.payments p
     set livemode = false
   where p.livemode is null;
  get diagnostics v_marked = row_count;

  insert into public.app_settings (key, value) values ('stripe_live_since', v_at::text);

  return query select v_accounts, v_canceled, v_marked, v_at;
end;
$$;

comment on function public.stripe_cutover_to_live() is
  'Run once at the Stripe key swap (sandbox -> live), as postgres or service_role: '
  'clears every Stripe customer and card summary (and any card decline with them, '
  '20260928700001), cancels ledger rows still '
  'pending or processing, marks rows with no recorded mode as test mode, records '
  'app_settings.stripe_live_since. Refuses a second run and refuses once any live '
  'payment exists. 20260927200001.';

-- Hard rule 11: PUBLIC first. No client role may run it; service_role may,
-- so the lead can run it through the API as well as from the SQL editor.
revoke all on function public.stripe_cutover_to_live() from public, anon, authenticated;
grant execute on function public.stripe_cutover_to_live() to service_role;
