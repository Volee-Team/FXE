-- Tara's cancellation policy, and cards charged after the clinic (decision 0012).
--
-- Her policy, 2026-09-16: more than 4 hours out, no charge; within 4 hours,
-- full fee; no-shows, full fee; one courtesy late cancellation per player
-- every 90 days, "that the app takes care of"; and "I want to charge
-- everyone's card everytime they come to clinic ... no one will be charged
-- until after the clinic is over"; a card on file is required to register.
--
-- What changes from 0010: the emergency note is no longer required (the box
-- stays, optional); the courtesy is applied by the app; every charge waits
-- for the clinic to end and for Tara's one tap per clinic; registering needs
-- a card once payments are on. Nothing here charges anyone by itself:
-- payments_enabled is still 'false', and even when it is true the money moves
-- only when Tara taps admin_charge_clinic.

-- ----------------------------------------------------------------- settings
update public.app_settings set value = 'after_clinic' where key = 'charge_fee_at';
insert into public.app_settings (key, value) values
  ('card_required', 'true'),
  ('courtesy_cancel_days', '90')
on conflict (key) do update set value = excluded.value;

-- ------------------------------------------------------------------ columns
alter table public.registrations
  add column if not exists courtesy_used boolean not null default false,
  add column if not exists no_show boolean not null default false;
comment on column public.registrations.courtesy_used is
  'This late cancellation used the player''s one courtesy per courtesy_cancel_days. Set only by cancel_registration.';
comment on column public.registrations.no_show is
  'Tara marked the player as not having come. Set only by admin_set_no_show. Charged the full fee by admin_charge_clinic.';

alter table public.players
  add column if not exists level_note text;
comment on column public.players.level_note is
  'The player''s own note about their level, read only by Tara (her ask, 2026-09-16: "just coming back from a back injury so I''m a low 3.5"). Written by the owning account through create_my_account / update_my_profile.';

-- ------------------------------------------------------------- helpers
create or replace function public.courtesy_cancel_days()
returns integer language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select value::integer from public.app_settings where key = 'courtesy_cancel_days'), 90);
$$;

create or replace function public.card_required()
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select coalesce((select value = 'true' from public.app_settings where key = 'card_required'), false);
$$;

-- One courtesy per rolling window: available when no late cancellation in the
-- last courtesy_cancel_days used it.
create or replace function public.courtesy_available(p_player uuid)
returns boolean language sql stable security definer set search_path = public, pg_temp as $$
  select not exists (
    select 1 from public.registrations r
     where r.player_id = p_player
       and r.courtesy_used
       and r.canceled_at > now() - make_interval(days => public.courtesy_cancel_days())
  );
$$;

-- The player's own view of it, for the cancel sheet.
create or replace function public.my_courtesy_available(p_player uuid)
returns boolean language plpgsql stable security definer set search_path = public, pg_temp as $$
begin
  if not (public.owns_player(p_player) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  return public.courtesy_available(p_player);
end;
$$;

-- --------------------------------------------------- cancel_registration
-- Same signature as 0010. Inside the cutoff the cancel now goes through with
-- or without a note; the courtesy is applied when available.
create or replace function public.cancel_registration(p_registration uuid, p_note text default null)
returns public.registrations
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  v_row      public.registrations;
  v_player   public.players;
  v_admin    uuid;
  v_starts   timestamptz;
  v_late     boolean := false;
  v_courtesy boolean := false;
  v_note     text := nullif(btrim(coalesce(p_note, '')), '');
begin
  select * into v_row from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not (public.owns_player(v_row.player_id) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  select starts_at into v_starts from public.clinics where id = v_row.clinic_id;
  if v_row.status = 'in' and not public.is_admin()
     and v_starts - now() < make_interval(hours => public.cancel_cutoff_hours()) then
    v_late := true;
    v_courtesy := public.courtesy_available(v_row.player_id);
  end if;

  update public.registrations
     set status = 'canceled', canceled_at = now(), canceled_by = auth.uid(),
         late_cancel = v_late,
         courtesy_used = v_courtesy,
         cancel_note = case when v_late then left(v_note, 280) else null end
   where id = p_registration
     and status in ('in', 'pool', 'response_needed')
  returning * into v_row;

  if not found then
    raise exception 'already_canceled' using errcode = 'P0001';
  end if;

  select * into v_player from public.players where id = v_row.player_id;
  for v_admin in select public.admin_account_ids() loop
    perform public.notify_account(v_admin, 'player_canceled', 'registration', v_row.id,
      v_player.first_name || ' ' || v_player.last_name || ' canceled.'
      || case when v_late and v_courtesy then ' Late, courtesy used.'
              when v_late then ' Late, fee applies.'
              else '' end
      || case when v_row.cancel_note is not null then ' Note: "' || v_row.cancel_note || '"' else '' end);
  end loop;

  return v_row;
end;
$$;

-- ------------------------------------------------- register_for_clinic
-- Unchanged except the card check, which only exists once payments are on.
create or replace function public.register_for_clinic(p_clinic uuid, p_player uuid)
returns public.registrations
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c        public.clinics;
  v_member boolean;
  v_taken  integer;
  v_status registration_status;
  v_row    public.registrations;
  v_card   boolean;
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

  select is_member into v_member from public.players where id = p_player;
  if v_member is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  -- Decision 0012: "Gosh I say yes." A player cannot hold a spot without a
  -- card once payments are on. Tara placing someone by hand is not blocked.
  if public.payments_enabled() and public.card_required() and not public.is_admin() then
    select a.stripe_customer_id is not null into v_card
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = p_player;
    if not coalesce(v_card, false) then
      raise exception 'card_required' using errcode = 'P0001';
    end if;
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

-- ------------------------------------------------------- no-shows
create or replace function public.admin_set_no_show(p_registration uuid, p_no_show boolean)
returns public.registrations
language plpgsql security definer set search_path = public, pg_temp as $$
declare v_row public.registrations;
begin
  perform public.require_admin();
  update public.registrations set no_show = p_no_show
   where id = p_registration and status = 'in'
  returning * into v_row;
  if not found then
    raise exception 'registration_not_in' using errcode = 'P0001';
  end if;
  return v_row;
end;
$$;

-- ---------------------------------------------- Tara's tap per clinic
-- After the clinic has ended: everyone still In owes the regular fee, a
-- no-show owes the full fee under that name, a late cancellation without the
-- courtesy owes the full fee. One pending ledger row each, at the price
-- snapshotted on the registration; stripe-charge turns them into Stripe
-- calls. Safe to tap twice: a row with a live charge of that kind is
-- skipped (admin_charge_registration raises already_charged), and a player
-- without a card is skipped and counted, never silently dropped.
create or replace function public.admin_charge_clinic(p_clinic uuid)
returns jsonb
language plpgsql security definer set search_path = public, pg_temp as $$
declare
  c        public.clinics;
  r        record;
  v_kind   payment_kind;
  n_charged int := 0; n_already int := 0; n_no_card int := 0; n_skipped int := 0;
begin
  perform public.require_admin();
  if not public.payments_enabled() then
    raise exception 'payments_disabled' using errcode = 'P0001';
  end if;
  select * into c from public.clinics where id = p_clinic;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if c.ends_at > now() then
    raise exception 'clinic_not_over' using errcode = 'P0001';
  end if;

  for r in select * from public.registrations where clinic_id = p_clinic loop
    if r.status = 'in' and not r.no_show then v_kind := 'clinic_fee';
    elsif r.status = 'in' and r.no_show then v_kind := 'no_show';
    elsif r.status = 'canceled' and r.late_cancel and not r.courtesy_used then v_kind := 'late_cancel';
    else n_skipped := n_skipped + 1; continue;
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

-- ------------------------------------------- profile: the note Tara reads
drop function if exists public.create_my_account(text, text, text, boolean, numeric);
create or replace function public.create_my_account(
  p_first_name   text,
  p_last_name    text,
  p_phone        text    default null,
  p_is_member    boolean default false,
  p_adult_rating numeric default null,
  p_level_note   text    default null   -- decision 0012: the note only Tara reads
) returns uuid
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid       uuid := auth.uid();
  v_email     text;
  v_player_id uuid;
  v_first     text := btrim(coalesce(p_first_name, ''));
  v_last      text := btrim(coalesce(p_last_name, ''));
begin
  if v_uid is null then
    raise exception 'create_my_account: not authenticated'
      using errcode = '42501';
  end if;

  -- Names are NOT NULL on both tables and are what Tara reads in her roster.
  -- An empty string satisfies NOT NULL and is useless to her, so reject it.
  if v_first = '' or v_last = '' then
    raise exception 'create_my_account: first and last name are required'
      using errcode = '22023';
  end if;

  -- Idempotent: a retry returns the existing adult player rather than failing.
  if exists (select 1 from public.accounts a where a.id = v_uid) then
    select p.id into v_player_id
    from public.players p
    where p.account_id = v_uid and p.kind = 'adult'
    order by p.created_at
    limit 1;
    return v_player_id;
  end if;

  select u.email into v_email from auth.users u where u.id = v_uid;
  if v_email is null then
    raise exception 'create_my_account: no auth user for %', v_uid
      using errcode = '42501';
  end if;

  -- account_type is 'adult': v1 is adults only (decision 0004). Juniors and
  -- the 'parent'/'both' types return in the fall and will set this differently.
  insert into public.accounts (id, first_name, last_name, email, phone, account_type, role)
  values (
    v_uid, v_first, v_last, v_email,
    nullif(btrim(coalesce(p_phone, '')), ''),
    'adult',
    'member'          -- NEVER from the caller. See hard rule 8.
  );

  -- is_member is self-reported, by design: Tara answered question 5 in
  -- for-tara.md with "leave it as-is, and I can correct anyone's status on
  -- their profile". It only affects which registration window opens first and
  -- which published rate is shown, both of which she can override.
  insert into public.players (account_id, kind, first_name, last_name, adult_rating, is_member, is_active, level_note)
  values (v_uid, 'adult', v_first, v_last, p_adult_rating, coalesce(p_is_member, false), true,
          nullif(left(btrim(coalesce(p_level_note, '')), 280), ''))
  returning id into v_player_id;

  return v_player_id;
end;
$$;

-- The player edits their own note through the same column grant path the
-- other self-service fields use (20260802000003).
grant update (level_note) on public.players to authenticated;

-- ------------------------------------------------------------- views
create or replace view public.registrations_admin as
  select id, clinic_id, player_id, status, paid, court_number, source,
         registered_at, invited_at, responded_at, canceled_at, canceled_by,
         late_cancel, cancel_note,
         exists (select 1 from public.players p join public.accounts a on a.id = p.account_id
                  where p.id = r.player_id and a.stripe_customer_id is not null) as has_card,
         (select x.status::text from public.payments x
           where x.registration_id = r.id and x.kind <> 'refund'
           order by x.created_at desc limit 1) as charge_status,
         courtesy_used, no_show
    from public.registrations r
   where public.is_admin();

create or replace view public.my_registrations as
  select id, clinic_id, player_id, status, paid, registered_at, invited_at, responded_at, canceled_at,
         late_cancel, courtesy_used
    from public.registrations r
   where public.owns_player(player_id);

-- ------------------------------------------------------------- grants
revoke all on function public.courtesy_cancel_days() from public, anon;
revoke all on function public.card_required() from public, anon;
revoke all on function public.courtesy_available(uuid) from public, anon, authenticated;
revoke all on function public.my_courtesy_available(uuid) from public, anon;
grant execute on function public.my_courtesy_available(uuid) to authenticated;
revoke all on function public.cancel_registration(uuid, text) from public, anon;
grant execute on function public.cancel_registration(uuid, text) to authenticated;
revoke all on function public.register_for_clinic(uuid, uuid) from public, anon;
grant execute on function public.register_for_clinic(uuid, uuid) to authenticated;
revoke all on function public.admin_set_no_show(uuid, boolean) from public, anon;
grant execute on function public.admin_set_no_show(uuid, boolean) to authenticated;
revoke all on function public.admin_charge_clinic(uuid) from public, anon;
grant execute on function public.admin_charge_clinic(uuid) to authenticated;
revoke all on function public.create_my_account(text, text, text, boolean, numeric, text) from public, anon;
grant execute on function public.create_my_account(text, text, text, boolean, numeric, text) to authenticated;
