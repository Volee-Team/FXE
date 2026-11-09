-- 20261109000001_tara_items_0054.sql — decision 0054.
--
-- Tara's updated "Next update (notes taken 11/6/26)" list, relayed by John on
-- 2026-11-09, items 7, 8, 10 and 11 (1 to 6 are decisions 0051 to 0053):
--
--   7. "If someone is invited to same day clinic and denies it, don't put
--      them back on waitlist. Their name can be removed"
--   8. "Can there be a place in every 105 on the app for me to make 2-3
--      rounds of 105. Like a message board or something like / Round 1 /
--      Coirt 1: player a,bc / player d,e,f / Coirt 2 / 3 / 4 / 5 / Round 2
--      Etc / Round 3 Etc"
--  10. "I'd like the option to change the pricing if possible. I'm gonna need
--      this for the junior, so might be a good idea just to implement it in
--      the adults as well. For instance, some people sign up for an hour and
--      a half clinic and can only stay for an hour, so they ask to be charged
--      for an hour. I hate this, but I'm sure it's gonna happen"
--  11. "Making sure the app will prevent me from adding people or accepting
--      people if we've reached our cap"
--
-- Her answers the same day: "Warn me!" (11), "Just me and pros for rounds"
-- and "Hmmm pick from roster great" (8), "I would type amount: for example
-- 1.5 hour clinic is $28 for non. If we get 45 mins I would charge $14" (10).
--
--   7. respond_to_invitation: a decline on the clinic's own New York day
--      ends the registration (canceled, canceled_by empty: not a cancel in
--      her history line) instead of putting it back on the Waitlist. Tara's
--      notice drops "and is back on the Waitlist", as it already did for an
--      invitation to someone who never asked.
--  11. Tara is only warned (the apps). A player's Accept is refused with
--      clinic_full when You're In! plus guests is at capacity, unless the
--      clinic was already full when the invitation went out
--      (registrations.invited_when_full, stamped by a trigger on every path
--      into Response Needed): then she saw her warning and chose to. An
--      Accept takes the clinic FOR UPDATE, so two cannot take one spot.
--   8. clinic_round_spots: up to 3 rounds, courts 1 to 5, two sides of up to
--      3, each spot one of the clinic's You're In! registrations or live
--      guests. 105 clinics only (is_105). Written by Tara only
--      (admin_set_round_court); read by Tara and, read-only, by a pro for a
--      clinic in their week (clinic_rounds). Closed to everyone else: no
--      player and no signed-out caller can read it (hard rule 1: like a
--      court, a round is who plays with whom).
--  10. admin_set_registration_price: one registration's amount, typed by
--      Tara, kept (price_set_by_admin) through a clinic price change and the
--      rain half; null puts the clinic's price back. Never on a row marked
--      Paid or holding a live fee. Nobody is told.

-- ------------------------------------------------------------------ 11 --
alter table public.registrations add column invited_when_full boolean not null default false;
comment on column public.registrations.invited_when_full is
  'Decision 0054: the clinic was at capacity (You''re In! plus guests) when this row last went into Response Needed, so Tara chose to invite past it; respond_to_invitation then lets the Accept through.';

-- Stamped on every way into Response Needed (invite_from_pool, place_player,
-- admin_invite_player, and any later one), so no path can forget it. The row
-- itself is not counted, whatever it was before.
create or replace function public.stamp_invited_when_full()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_cap integer;
begin
  if new.status = 'response_needed'
     and (tg_op = 'INSERT' or old.status is distinct from 'response_needed') then
    select internal_capacity into v_cap from public.clinics where id = new.clinic_id;
    new.invited_when_full := v_cap is not null
      and (select count(*) from public.registrations
            where clinic_id = new.clinic_id and status = 'in' and id <> new.id)
        + (select count(*) from public.clinic_guests
            where clinic_id = new.clinic_id and removed_at is null) >= v_cap;
  end if;
  return new;
end;
$$;
revoke all on function public.stamp_invited_when_full() from public, anon, authenticated;
create trigger stamp_invited_when_full
  before insert or update of status on public.registrations
  for each row execute function public.stamp_invited_when_full();

-- Invitations already open: nobody recorded whether the clinic was full when
-- they went out. One that is full now was most likely sent past the cap on
-- purpose (capacity never stopped her before today), so it keeps the Accept
-- it was sent with; the rule applies to invitations from here on.
update public.registrations r
   set invited_when_full = true
  from public.clinics c
 where c.id = r.clinic_id
   and r.status = 'response_needed'
   and c.internal_capacity is not null
   and public.clinic_taken(c.id) >= c.internal_capacity;

-- --------------------------------------------------------------- 7 + 11 --
create or replace function public.respond_to_invitation(p_registration uuid, p_accept boolean)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $function$
declare
  v_row    public.registrations;
  v_player public.players;
  v_admin  uuid;
  v_clinic text;
  v_clinic_status clinic_status;
  v_ends  timestamptz;
  v_declined boolean;
  v_decline_code text;
  v_card   boolean;
  v_starts timestamptz;
  v_cap    integer;
  v_ends_it boolean;
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
  --
  -- An Accept locks it FOR UPDATE instead (20261109000001): the lock
  -- register_for_clinic, place_player and admin_add_guest take, so two
  -- players accepting the last spot at once are one after the other, and the
  -- second sees the first in You're In!.
  if p_accept then
    select status, starts_at, ends_at, internal_capacity into v_clinic_status, v_starts, v_ends, v_cap
      from public.clinics where id = v_row.clinic_id
       for update;
  else
    select status, starts_at, ends_at, internal_capacity into v_clinic_status, v_starts, v_ends, v_cap
      from public.clinics where id = v_row.clinic_id
       for share;
  end if;
  -- The row again, now that the clinic is held: what it says is what the
  -- conditional UPDATE below will see.
  select * into v_row from public.registrations where id = p_registration;
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
    -- Tara's question 107 (2026-10-12): "Yes", Accept needs a saved card,
    -- the same summary register_for_clinic reads (card_last4, decision 0015
    -- §5). Checked before the conditional UPDATE, so nothing moves.
    select a.stripe_customer_id is not null and a.card_last4 is not null into v_card
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = v_row.player_id;
    if not coalesce(v_card, false) then
      raise exception 'card_required' using errcode = 'P0001';
    end if;
    select a.card_declined_at is not null, a.card_decline_code into v_declined, v_decline_code
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = v_row.player_id;
    if coalesce(v_declined, false) then
      raise exception 'card_declined' using errcode = 'P0001', hint = coalesce(v_decline_code, '');
    end if;
  end if;

  -- Tara, 2026-11-06 (item 11, "Making sure the app will prevent me from
  -- adding people or accepting people if we've reached our cap"), answered
  -- 2026-11-09 "Warn me!": she is only ever warned, but a player's Accept no
  -- longer takes a spot that is not there. Unless the clinic was already full
  -- when she sent it (invited_when_full): she saw her warning and chose to.
  -- Only a still-open invitation is judged; anything else falls through to
  -- invitation_no_longer_available below. The 1.0.x apps and the members'
  -- site already show clinic_full as "That clinic is full now."
  if p_accept and not public.is_admin()
     and v_row.status = 'response_needed'
     and not v_row.invited_when_full
     and v_cap is not null
     and public.clinic_taken(v_row.clinic_id) >= v_cap then
    raise exception 'clinic_full' using errcode = 'P0001';
  end if;

  -- Item 7: "If someone is invited to same day clinic and denies it, don't
  -- put them back on waitlist. Their name can be removed." A decline on the
  -- clinic's own New York day ends it, like a decline of an invitation she
  -- sent to someone who never asked (source 'invite', 20261107000002).
  v_ends_it := not p_accept
               and (v_row.source = 'invite' or public.new_york_date(v_starts) = public.new_york_date(now()));

  update public.registrations
     set status = case when p_accept then 'in'::registration_status
                       -- An invitation Tara sent to someone who never asked
                       -- (source 'invite', 20261107000002): a decline ends
                       -- it, instead of putting them on a Waitlist they never
                       -- joined. And, since 20261109000001, any decline on
                       -- the clinic's own day (v_ends_it).
                       when v_ends_it then 'canceled'::registration_status
                       else 'pool'::registration_status end,
         responded_at = now(),
         canceled_at  = case when v_ends_it then now() else canceled_at end,
         -- Left empty: a decline is not a cancel, so Tara's history line
         -- ("2 canceled", admin_player_history counts canceled_by = the
         -- player) does not count it (the sql-auditor, 2026-11-07).
         canceled_by  = case when v_ends_it then null else canceled_by end
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
                when v_row.status = 'canceled' then ' declined ' || v_clinic || '.'
                else ' declined ' || v_clinic || ' and is back on the Waitlist.' end);
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
$function$;
revoke all on function public.respond_to_invitation(uuid, boolean) from public, anon;
grant execute on function public.respond_to_invitation(uuid, boolean) to authenticated;

-- -------------------------------------------------------------------- 10 --
alter table public.registrations add column price_set_by_admin boolean not null default false;
comment on column public.registrations.price_set_by_admin is
  'Decision 0054: Tara typed this registration''s amount (admin_set_registration_price); a clinic price change and the rain half leave it alone.';

-- reprice_clinic and the rain trigger skip a price she set by hand. Otherwise
-- as 20261107000004.
create or replace function public.reprice_clinic(p_clinic uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.clinics;
  n integer;
begin
  select * into c from public.clinics where id = p_clinic;
  -- Every row of the clinic, not only those about to change: a no-show
  -- unmarked while rain is turned on would otherwise read the old flag and
  -- keep the old price (the sql-auditor, 2026-11-07). Clinic then rows, the
  -- order admin_charge_clinic takes, so no deadlock.
  perform 1 from public.registrations where clinic_id = p_clinic order by id for update;
  update public.registrations r
     set price_cents_charged = public.clinic_price_for(c, r.was_member, r.status, r.no_show)
   where r.clinic_id = p_clinic
     and not r.paid
     and not r.price_set_by_admin
     and not public.registration_has_live_fee(r.id)
     and r.price_cents_charged is distinct from public.clinic_price_for(c, r.was_member, r.status, r.no_show);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.reprice_clinic(uuid) from public, anon, authenticated;

create or replace function public.keep_rain_price()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.clinics;
begin
  select * into c from public.clinics where id = new.clinic_id;
  if c.rain_half and not new.paid and not new.price_set_by_admin
     and (tg_op = 'INSERT' or not public.registration_has_live_fee(new.id)) then
    new.price_cents_charged := public.clinic_price_for(c, new.was_member, new.status, new.no_show);
  end if;
  return new;
end;
$$;
revoke all on function public.keep_rain_price() from public, anon, authenticated;

-- One person's amount, in cents, typed by Tara; null puts the clinic's
-- price back (with the rain half, when it is on). Any registration that can
-- still owe: You're In!, Waitlist, Response Needed, or a late cancel. Never
-- one marked Paid or holding a live fee: money taken is a refund, not a
-- reprice.
create or replace function public.admin_set_registration_price(p_registration uuid, p_cents integer)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_clinic uuid;
  c public.clinics;
  v public.registrations;
begin
  perform public.require_admin();
  -- $0.01 to $1,000, as a clinic's own price (admin_set_clinic_prices).
  if p_cents is not null and p_cents not between 1 and 100000 then
    raise exception 'invalid_price' using errcode = 'P0001';
  end if;
  select clinic_id into v_clinic from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  -- Clinic, then the row: the order reprice_clinic and the charges take.
  select * into c from public.clinics where id = v_clinic for update;
  select * into v from public.registrations where id = p_registration for update;
  if v.status = 'canceled' and not v.late_cancel then
    raise exception 'nothing_owed' using errcode = 'P0001';
  end if;
  if v.paid then
    raise exception 'already_paid' using errcode = 'P0001';
  end if;
  if public.registration_has_live_fee(v.id) then
    raise exception 'charged_refund_first' using errcode = 'P0001';
  end if;
  update public.registrations
     set price_cents_charged = coalesce(p_cents, public.clinic_price_for(c, v.was_member, v.status, v.no_show)),
         price_set_by_admin  = p_cents is not null
   where id = v.id
  returning * into v;
  return v;
end;
$$;
revoke all on function public.admin_set_registration_price(uuid, integer) from public, anon;
grant execute on function public.admin_set_registration_price(uuid, integer) to authenticated;

-- Her roster shows the amount and whether she set it. Otherwise as
-- 20261013000001; the two columns are added at the end.
create or replace view public.registrations_admin as
SELECT id,
    clinic_id,
    player_id,
    status,
    paid,
    court_number,
    source,
    registered_at,
    invited_at,
    responded_at,
    canceled_at,
    canceled_by,
    late_cancel,
    cancel_note,
    (EXISTS ( SELECT 1
           FROM (players p
             JOIN accounts a ON ((a.id = p.account_id)))
          WHERE ((p.id = r.player_id) AND (a.stripe_customer_id IS NOT NULL) AND (a.card_last4 IS NOT NULL)))) AS has_card,
    ( SELECT
                CASE
                    WHEN ((x.status = 'succeeded'::payment_status) AND (EXISTS ( SELECT 1
                       FROM payments rf
                      WHERE ((rf.refunds_payment_id = x.id) AND (rf.kind = 'refund'::payment_kind) AND (rf.status = 'succeeded'::payment_status) AND (rf.amount_cents >= x.amount_cents))))) THEN 'refunded'::text
                    ELSE (x.status)::text
                END AS status
           FROM payments x
          WHERE ((x.registration_id = r.id) AND (x.kind <> 'refund'::payment_kind) AND ((x.livemode IS NOT FALSE) OR (NOT (EXISTS ( SELECT 1
                   FROM app_settings s
                  WHERE (s.key = 'stripe_live_since'::text))))))
          ORDER BY x.created_at DESC
         LIMIT 1) AS charge_status,
    courtesy_used,
    no_show,
    player_note,
    fee_waived_at,
    price_cents_charged,
    price_set_by_admin
   FROM registrations r
  WHERE is_admin();

revoke all on public.registrations_admin from public, anon, authenticated;
grant select on public.registrations_admin to authenticated;

-- --------------------------------------------------------------------- 8 --
create table public.clinic_round_spots (
  clinic_id       uuid not null references public.clinics(id) on delete cascade,
  round_number    smallint not null check (round_number between 1 and 3),
  court_number    smallint not null check (court_number between 1 and 5),
  side            smallint not null check (side between 1 and 2),
  slot            smallint not null check (slot between 1 and 3),
  registration_id uuid references public.registrations(id) on delete cascade,
  guest_id        uuid references public.clinic_guests(id) on delete cascade,
  set_at          timestamptz not null default now(),
  primary key (clinic_id, round_number, court_number, side, slot),
  check (num_nonnulls(registration_id, guest_id) = 1)
);
-- One place per person per round.
create unique index clinic_round_spots_one_registration
  on public.clinic_round_spots (clinic_id, round_number, registration_id) where registration_id is not null;
create unique index clinic_round_spots_one_guest
  on public.clinic_round_spots (clinic_id, round_number, guest_id) where guest_id is not null;
create index clinic_round_spots_registration on public.clinic_round_spots (registration_id);
create index clinic_round_spots_guest on public.clinic_round_spots (guest_id);
alter table public.clinic_round_spots enable row level security;
revoke all on public.clinic_round_spots from public, anon, authenticated;
grant select, insert, update, delete on public.clinic_round_spots to service_role;
comment on table public.clinic_round_spots is
  'Decision 0054: Tara''s 105 rounds. A layout she rewrites, not history, so a court is replaced whole. Read only through clinic_rounds, written only through admin_set_round_court.';

-- One court of one round, whole: p_people is six ids, side 1's three spots
-- then side 2's, each a You're In! registration or a live guest of this
-- clinic, or null for an empty spot. Someone already on another court of the
-- same round moves here. All six null clears the court.
create or replace function public.admin_set_round_court(
  p_clinic uuid, p_round integer, p_court integer, p_people uuid[])
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c public.clinics;
  i integer;
  v_id uuid;
  v_reg uuid;
  v_guest uuid;
begin
  perform public.require_admin();
  if p_round is null or p_round not between 1 and 3 then
    raise exception 'invalid_round' using errcode = 'P0001';
  end if;
  if p_court is null or p_court not between 1 and 5 then
    raise exception 'invalid_court' using errcode = 'P0001';
  end if;
  if p_people is null or cardinality(p_people) <> 6 or array_ndims(p_people) <> 1 then
    raise exception 'invalid_people' using errcode = 'P0001';
  end if;
  if (select count(*) from unnest(p_people) x where x is not null)
     <> (select count(distinct x) from unnest(p_people) x where x is not null) then
    raise exception 'already_in_round' using errcode = 'P0001';
  end if;
  -- The clinic's lock: two of her devices saving the same court are one
  -- after the other, and nobody leaves the clinic halfway through.
  select * into c from public.clinics where id = p_clinic for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if not public.is_105(c.name, c.category) then
    raise exception 'not_105' using errcode = 'P0001';
  end if;
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;

  delete from public.clinic_round_spots
   where clinic_id = p_clinic and round_number = p_round and court_number = p_court;

  for i in 1..6 loop
    v_id := p_people[i];
    continue when v_id is null;
    v_reg := null; v_guest := null;
    select id into v_reg from public.registrations
     where id = v_id and clinic_id = p_clinic and status = 'in';
    if v_reg is null then
      select id into v_guest from public.clinic_guests
       where id = v_id and clinic_id = p_clinic and removed_at is null;
    end if;
    if v_reg is null and v_guest is null then
      raise exception 'not_in_clinic' using errcode = 'P0001';
    end if;
    -- On another court of this round: moved here.
    delete from public.clinic_round_spots
     where clinic_id = p_clinic and round_number = p_round
       and (registration_id = v_reg or guest_id = v_guest);
    insert into public.clinic_round_spots
      (clinic_id, round_number, court_number, side, slot, registration_id, guest_id)
    values (p_clinic, p_round, p_court, ((i - 1) / 3) + 1, ((i - 1) % 3) + 1, v_reg, v_guest);
  end loop;
end;
$$;
revoke all on function public.admin_set_round_court(uuid, integer, integer, uuid[]) from public, anon;
grant execute on function public.admin_set_round_court(uuid, integer, integer, uuid[]) to authenticated;

-- Every spot of a clinic's rounds, with the name. person_id is the
-- registration's id or the guest's, the id admin_set_round_court takes back.
-- gone: since placed, they left You're In! or the guest was removed; the
-- spot stays, struck, until she picks again. Tara, and a pro for a clinic in
-- their week (pro_week's window), read-only. Nobody else.
create or replace function public.clinic_rounds(p_clinic uuid)
returns table(round_number smallint, court_number smallint, side smallint, slot smallint,
              person_id uuid, first_name text, last_name text, is_guest boolean, gone boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
declare
  c public.clinics;
begin
  if not public.is_admin() then
    perform public.require_pro();
    select * into c from public.clinics where id = p_clinic;
    -- One answer for anything outside the week, as pro_assign_court.
    if not found or c.status <> 'published'
       or public.new_york_date(c.starts_at) not between public.new_york_date(now())
                                                    and public.new_york_date(now()) + 6 then
      raise exception 'not_this_week' using errcode = 'P0001';
    end if;
  end if;
  return query
    select s.round_number, s.court_number, s.side, s.slot,
           coalesce(s.registration_id, s.guest_id),
           coalesce(p.first_name, g.first_name), coalesce(p.last_name, g.last_name),
           s.guest_id is not null,
           case when s.registration_id is not null then r.status <> 'in'
                else g.removed_at is not null end
      from public.clinic_round_spots s
      left join public.registrations r on r.id = s.registration_id
      left join public.players p on p.id = r.player_id
      left join public.clinic_guests g on g.id = s.guest_id
     where s.clinic_id = p_clinic
     order by s.round_number, s.court_number, s.side, s.slot;
end;
$$;
revoke all on function public.clinic_rounds(uuid) from public, anon;
grant execute on function public.clinic_rounds(uuid) to authenticated;
