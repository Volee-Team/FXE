-- 20260926000001_card_on_file_consent_and_105.sql
--
-- Decision 0015 ("FXE Final Updates", Kat and Tara, 2026-09-26). Three things
-- that share register_for_clinic, so they ship together.
--
-- 1. WHAT "A CARD ON FILE" MEANS. Three places (registration, the roster's
--    has_card, admin_charge_registration) tested accounts.stripe_customer_id.
--    stripe-setup-intent creates that customer BEFORE the player saves a card,
--    so a player who opened the card sheet and closed it had a customer id and
--    no card, and passed all three. The Final Updates say "Ensure no user can
--    register for a clinic without a card on file"; a customer is not a card.
--    The test is now card_last4, which only the signed webhook writes, on
--    setup_intent.succeeded. Found reading the function for this change, not
--    by a test: card_consent.sql now attacks it (red on the old definition).
--
-- 2. THE CARD PERMISSION. "Need to add a check box that says I give
--    permission for my card to be charged and if deselected it does not let
--    them proceed. Consent needs to be saved & stored for as long as the
--    account is active and if they cancel their account - stored for another
--    90 days." One row per consent in card_consents (the text as shown, its
--    version, the time, the app version), written only by
--    record_card_consent() for the caller. stripe-setup-intent refuses to
--    start a card setup without one, so the box is enforced by the server, not
--    by the screen. delete_my_account() leaves the rows alone (it scrubs
--    personal data, and a consent is evidence, not profile); the nightly job
--    calls purge_expired_card_consents() to remove them 90 days after the
--    account's deleted_at. pg_cron was not used: whether it can be created from
--    a migration on the hosted plan was not verifiable tonight, and the
--    nightly job already reaches hosted.
--
-- Audited 2026-09-26 by the sql-auditor agent before any push: RESTRICT on the
-- consent foreign key, a per-player lock on the 105 check, clock-time 48
-- hours, idempotent consent, helpers internal, already_charged on a race.
--
-- 3. BACK-TO-BACK 105s, Tara: "members can sign up for back to back 105's
--    (same day back to back) but nonmembers cannot until 48 [hours] priors to
--    start time of clinic. For example: Sunday Sept 27 430-6pm 105 6-7pm 105
--    Nonmembers cannot sign up for both 105's (only one when registration
--    opens for them) until Friday Sept 25 4:30pm." Read as: a non-member
--    holding a live spot (You're In!, Player Pool, Response Needed) in a 105
--    on the same New York calendar day may take a second 105 only from 48
--    hours before the EARLIER of the two starts. Her example checks both
--    ways (Sunday 4:30 minus 48h = Friday 4:30, whichever she took first).
--    A 105 is a clinic with "105" in its name or category, the same test the
--    app's "?" explainer has used since 2026-08-16. Questions 60 to 63 ask
--    her the edges; each default is what is built.

-- ------------------------------------------------------------ helpers
create or replace function public.is_105(p_name text, p_category text)
returns boolean
language sql immutable set search_path = public, pg_temp
as $$
  select coalesce(p_name, '') ilike '%105%' or coalesce(p_category, '') ilike '%105%';
$$;
-- Internal: only register_for_clinic calls it, with owner rights (audit 2026-09-26).
revoke all on function public.is_105(text, text) from public, anon, authenticated;

create or replace function public.back_to_back_105_opens_at(p_a timestamptz, p_b timestamptz)
returns timestamptz
language sql immutable set search_path = public, pg_temp
as $$
  -- Clock time, two days earlier at the same New York time: her example is
  -- worded as a clock time ("until Friday Sept 25 4:30pm") and every other
  -- window here is one. Elapsed hours would move it by one on the two
  -- daylight-saving weekends (audit 2026-09-26). Question 60 asks her.
  select ((least(p_a, p_b) at time zone 'America/New_York') - interval '2 days') at time zone 'America/New_York';
$$;
revoke all on function public.back_to_back_105_opens_at(timestamptz, timestamptz) from public, anon, authenticated;

-- ------------------------------------------------------- card consent
insert into public.app_settings (key, value)
values ('card_consent_text', 'I give permission for my card to be charged'),
       ('card_consent_version', '2026-09-26')
on conflict (key) do nothing;

create table if not exists public.card_consents (
  id           uuid primary key default gen_random_uuid(),
  -- RESTRICT, not CASCADE: accounts cascade from auth.users, so a hard delete
  -- (the dashboard's Delete user) would have taken the consent with it on
  -- day 0. Now only purge_expired_card_consents() deletes a consent, and a
  -- hard delete of someone holding one fails loudly (audit 2026-09-26).
  account_id   uuid not null references public.accounts(id) on delete restrict,
  consent_text text not null,
  version      text not null,
  accepted_at  timestamptz not null default now(),
  app_version  text
);
create index if not exists card_consents_account on public.card_consents (account_id, accepted_at desc);
alter table public.card_consents enable row level security;
-- No policies and no client privilege: written by record_card_consent(),
-- read by the caller through my_card_consent() and by the edge functions as
-- service_role (default privileges from 20260912000002 give it DML).
revoke all on public.card_consents from public, anon, authenticated;

create or replace function public.card_consent_text()
returns text
language sql stable security definer set search_path = public, pg_temp
as $$
  select value from public.app_settings where key = 'card_consent_text';
$$;
revoke all on function public.card_consent_text() from public, anon;
grant execute on function public.card_consent_text() to authenticated;

-- The caller has consented to the CURRENT wording. A later change of the
-- words asks again, the way a new waiver version does.
create or replace function public.my_card_consent()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.card_consents k
     where k.account_id = auth.uid()
       and k.consent_text = public.card_consent_text()
  );
$$;
revoke all on function public.my_card_consent() from public, anon;
grant execute on function public.my_card_consent() to authenticated;

-- The server stores ITS copy of the words, not the client's: a client cannot
-- record consent to a sentence it made up.
create or replace function public.record_card_consent(p_app_version text default null)
returns timestamptz
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_id uuid := auth.uid();
  v_at timestamptz;
begin
  if v_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if not exists (select 1 from public.accounts where id = v_id and deleted_at is null) then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;
  -- Once per account and wording: a retry returns the first record.
  select accepted_at into v_at from public.card_consents
   where account_id = v_id and consent_text = public.card_consent_text()
   order by accepted_at limit 1;
  if v_at is not null then
    return v_at;
  end if;
  insert into public.card_consents (account_id, consent_text, version, app_version)
  values (v_id, public.card_consent_text(),
          coalesce((select value from public.app_settings where key = 'card_consent_version'), 'unknown'),
          left(nullif(btrim(coalesce(p_app_version, '')), ''), 60))
  returning accepted_at into v_at;
  return v_at;
end;
$$;
revoke all on function public.record_card_consent(text) from public, anon;
grant execute on function public.record_card_consent(text) to authenticated;

-- Retention: "stored for another 90 days" after the account is deleted.
-- Returns how many rows went. Run nightly by .github/workflows/backup.yml as
-- the database owner; no client role may run it.
create or replace function public.purge_expired_card_consents()
returns integer
language plpgsql security definer set search_path = public, pg_temp
as $$
declare n integer;
begin
  delete from public.card_consents k
   using public.accounts a
   where a.id = k.account_id
     and a.deleted_at is not null
     and a.deleted_at < now() - interval '90 days';
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.purge_expired_card_consents() from public, anon, authenticated;

-- ------------------------------------------ registration (card + 105)
create or replace function public.register_for_clinic(p_clinic uuid, p_player uuid)
returns public.registrations
language plpgsql security definer set search_path = public, pg_temp
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

  return v_row;
exception
  when unique_violation then
    raise exception 'already_registered' using errcode = 'P0001';
end;
$$;

-- ------------------------------------ the roster's card flag, same test
create or replace view public.registrations_admin as
  select id, clinic_id, player_id, status, paid, court_number, source,
         registered_at, invited_at, responded_at, canceled_at, canceled_by,
         late_cancel, cancel_note,
         exists (select 1 from public.players p join public.accounts a on a.id = p.account_id
                  where p.id = r.player_id and a.stripe_customer_id is not null
                    and a.card_last4 is not null) as has_card,
         (select x.status::text from public.payments x
           where x.registration_id = r.id and x.kind <> 'refund'
           order by x.created_at desc limit 1) as charge_status,
         courtesy_used, no_show
    from public.registrations r
   where public.is_admin();

-- ------------------------------------- Tara's charge, same test
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
  -- A saved card, not just a Stripe customer (see register_for_clinic).
  if a.stripe_customer_id is null or a.card_last4 is null then
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
exception
  -- Two taps at the same instant both pass the exists() check above; the
  -- unique index payments_one_live_charge (money-reports migration) stops the
  -- second, and this turns its error into the one Tara's screens understand.
  when unique_violation then
    raise exception 'already_charged' using errcode = 'P0001';
end;
$$;
