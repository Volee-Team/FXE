-- 20261118000002_juniors_family_review.sql
--
-- Decision 0061, "Review". The sql-auditor read 20261118000001 before it
-- went anywhere and found one high, three mediums and six lows. Each fix
-- below was pinned red first: tests/sql/juniors_review.sql, pro_role.sql
-- r10, and the state rows added to juniors_family.sql.
--
--  H1  A parent could put an UNSIGNED child on a juniors clinic:
--      register_for_clinic, request_late_spot and respond_to_invitation
--      took the child through owns_player() and asked only the account's
--      adult waiver. Now a child needs a signature on the current junior
--      waiver (junior_waiver_required), and while no junior text exists,
--      junior_waiver_not_available. A child no longer needs the PARENT's
--      adult waiver, which is about an adult playing. Tara is exempt, as
--      she is from the adult one.
--  M2  An archived child (removed by the parent) could still be registered,
--      ask late or accept: each now reads the player FOR SHARE and only
--      while active (player_not_found). FOR SHARE waits for
--      remove_my_child's FOR UPDATE, so the two cannot interleave. And
--      remove_my_child also waits for a pending late request.
--  M3  update_my_child could rename a child, or change the birthday, after
--      Tara had decided a program for them or a waiver had been signed,
--      and the decision or signature then belonged to someone else. Now
--      child_locked; Tara corrects such a child. The signature also keeps
--      the child's name and birthday as signed, so delete_my_account's
--      blanking cannot empty the legal record.
--  M4  pro_today, pro_week and clinic_round_people showed a rostered
--      child's full name to every pro. Decision 0061: pros see children in
--      phase 3. Until then a pro sees a juniors clinic, not its children.
--  L5  my_news counted an archived child for juniors news; my_clinic_messages
--      showed a child's clinic messages to the old apps. Both now follow
--      phase 0's rule: active rows, the adult's clinics.
--  L6  set_my_gender and request_level_approval are the adult's:
--      wrong_player_kind on a child.
--  L7  waiver_version() and current_waiver() read adult text only.
--  L8  A trigger on junior_waiver_acceptances: the child is an active junior
--      of the signing account, whatever path writes the row, and a
--      signature is never edited (signature_is_final).
--  L9  At most 10 children per account (too_many_children). A default
--      John can change (decision 0061).

-- M3: the record keeps the child as signed. The table is new and empty on
-- every database this runs on (20261118000001 is pushed with it).
alter table public.junior_waiver_acceptances
  add column child_first_name    text not null,
  add column child_last_name     text not null,
  add column child_date_of_birth date not null;
comment on column public.junior_waiver_acceptances.child_first_name is
  'The child as signed for (20261118000002): kept when delete_my_account blanks the players row.';

-- L8 -----------------------------------------------------------------------
create or replace function public.guard_junior_waiver_acceptance()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if tg_op = 'UPDATE' then
    raise exception 'signature_is_final' using errcode = 'P0001';
  end if;
  if not exists (select 1 from public.players p
                  where p.id = new.player_id and p.kind = 'junior' and p.is_active
                    and p.account_id = new.account_id) then
    raise exception 'not_your_child' using errcode = '42501';
  end if;
  return new;
end;
$$;
revoke all on function public.guard_junior_waiver_acceptance() from public, anon, authenticated;

drop trigger if exists guard_junior_waiver_acceptance on public.junior_waiver_acceptances;
create trigger guard_junior_waiver_acceptance
  before insert or update on public.junior_waiver_acceptances
  for each row execute function public.guard_junior_waiver_acceptance();

-- M3, L9, M2 in the family functions ----------------------------------------
create or replace function public.add_my_child(p_first_name text, p_last_name text, p_date_of_birth date)
returns table (id uuid, first_name text, last_name text, date_of_birth date)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_first text := left(btrim(coalesce(p_first_name, '')), 60);
  v_last  text := left(btrim(coalesce(p_last_name, '')), 60);
  v_id    uuid;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if v_first = '' or v_last = '' then
    raise exception 'name_required' using errcode = 'P0001';
  end if;
  if p_date_of_birth is null or p_date_of_birth > current_date then
    raise exception 'invalid_birthday' using errcode = '22023';
  end if;
  -- Locks the account, so two taps on Add cannot make two copies, nor an
  -- eleventh child.
  perform 1 from public.accounts a
   where a.id = auth.uid() and a.deleted_at is null
   for update;
  if not found then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;
  -- L9: decision 0061's default, John's to change.
  if (select count(*) from public.players p
       where p.account_id = auth.uid() and p.kind = 'junior' and p.is_active) >= 10 then
    raise exception 'too_many_children' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.players p
              where p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
                and lower(p.first_name) = lower(v_first) and lower(p.last_name) = lower(v_last)
                and p.date_of_birth = p_date_of_birth) then
    raise exception 'child_exists' using errcode = 'P0001';
  end if;

  insert into public.players (account_id, kind, first_name, last_name, date_of_birth)
  values (auth.uid(), 'junior', v_first, v_last, p_date_of_birth)
  returning players.id into v_id;

  update public.accounts a set account_type = 'both'
   where a.id = auth.uid() and a.account_type = 'adult';

  return query select p.id, p.first_name, p.last_name, p.date_of_birth
                 from public.players p where p.id = v_id;
end;
$$;

create or replace function public.update_my_child(p_child uuid, p_first_name text, p_last_name text, p_date_of_birth date)
returns table (id uuid, first_name text, last_name text, date_of_birth date)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_first text := left(btrim(coalesce(p_first_name, '')), 60);
  v_last  text := left(btrim(coalesce(p_last_name, '')), 60);
  v_old   public.players;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  perform 1 from public.accounts a where a.id = auth.uid() for update;
  select * into v_old from public.players p
   where p.id = p_child and p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
   for update;
  if not found then
    raise exception 'not_your_child' using errcode = '42501';
  end if;
  if v_first = '' or v_last = '' then
    raise exception 'name_required' using errcode = 'P0001';
  end if;
  if p_date_of_birth is null or p_date_of_birth > current_date then
    raise exception 'invalid_birthday' using errcode = '22023';
  end if;
  -- M3: once Tara has decided a program for this child, or a waiver has
  -- been signed for them, who the child is stays as it was: Tara corrects it.
  if (v_first, v_last, p_date_of_birth) is distinct from (v_old.first_name, v_old.last_name, v_old.date_of_birth)
     and (exists (select 1 from public.program_approvals a
                   where a.player_id = p_child and a.status in ('approved', 'declined'))
          or exists (select 1 from public.junior_waiver_acceptances w where w.player_id = p_child)) then
    raise exception 'child_locked' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.players p
              where p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
                and p.id <> p_child
                and lower(p.first_name) = lower(v_first) and lower(p.last_name) = lower(v_last)
                and p.date_of_birth = p_date_of_birth) then
    raise exception 'child_exists' using errcode = 'P0001';
  end if;

  update public.players p
     set first_name = v_first, last_name = v_last, date_of_birth = p_date_of_birth
   where p.id = p_child;

  return query select p.id, p.first_name, p.last_name, p.date_of_birth
                 from public.players p where p.id = p_child;
end;
$$;

create or replace function public.remove_my_child(p_child uuid)
returns void
language plpgsql security definer set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  perform 1 from public.players p
   where p.id = p_child and p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
   for update;
  if not found then
    raise exception 'not_your_child' using errcode = '42501';
  end if;
  -- A spot still to come, or a late request Tara has not answered, is on
  -- her side: the parent cancels it first.
  if exists (select 1 from public.registrations r
               join public.clinics c on c.id = r.clinic_id
              where r.player_id = p_child and c.starts_at > now()
                and r.status in ('in', 'pool', 'response_needed'))
     or exists (select 1 from public.late_requests l
                 where l.player_id = p_child and l.status = 'pending') then
    raise exception 'child_has_upcoming' using errcode = 'P0001';
  end if;
  update public.players p set is_active = false
   where p.id = p_child and p.is_active;
end;
$$;

create or replace function public.accept_child_waiver(p_child uuid, p_version text, p_legal_name text, p_app_version text default null)
returns table (player_id uuid, version text, accepted_at timestamptz)
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_name    text := btrim(coalesce(p_legal_name, ''));
  v_current text := public.junior_waiver_version();
  v_email   text;
  v_child   public.players;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select * into v_child from public.players p
   where p.id = p_child and p.account_id = auth.uid() and p.kind = 'junior' and p.is_active
   for share;
  if not found then
    raise exception 'not_your_child' using errcode = '42501';
  end if;
  if v_current is null then
    raise exception 'junior_waiver_not_available' using errcode = 'P0001';
  end if;
  if p_version is distinct from v_current then
    raise exception 'waiver_version_stale' using errcode = 'P0001';
  end if;
  if length(v_name) < 3 or position(' ' in v_name) = 0 then
    raise exception 'legal_name_required' using errcode = 'P0001';
  end if;
  select a.email into v_email from public.accounts a
   where a.id = auth.uid() and a.deleted_at is null;
  if v_email is null then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;

  insert into public.junior_waiver_acceptances (player_id, account_id, version, legal_name, email, app_version,
      child_first_name, child_last_name, child_date_of_birth)
  values (p_child, auth.uid(), p_version, left(v_name, 120), v_email, left(p_app_version, 40),
          v_child.first_name, v_child.last_name, v_child.date_of_birth)
  on conflict on constraint junior_waiver_acceptances_player_id_version_key do nothing;

  return query select a.player_id, a.version, a.accepted_at
                 from public.junior_waiver_acceptances a
                where a.player_id = p_child and a.version = p_version;
end;
$$;

-- L5: the old apps' two reads ------------------------------------------------
create or replace view public.my_news as
 SELECT n.id,
    n.title,
    n.body,
    n.audience,
    n.published_at,
    nr.read_at IS NOT NULL AS is_read
   FROM news_posts n
     LEFT JOIN news_reads nr ON nr.news_id = n.id AND nr.account_id = auth.uid()
  WHERE n.status = 'published'::news_status AND n.archived_at IS NULL AND (n.audience = 'everyone'::news_audience OR n.audience = 'adults'::news_audience AND (EXISTS ( SELECT 1
           FROM players p
          WHERE p.account_id = auth.uid() AND p.kind = 'adult'::player_kind)) OR n.audience = 'juniors'::news_audience AND (EXISTS ( SELECT 1
           FROM players p
          WHERE p.account_id = auth.uid() AND p.kind = 'junior'::player_kind AND p.is_active)));

revoke all on public.my_news from public, anon, authenticated;
grant select on public.my_news to authenticated;

-- A message about a child's clinic is the family's to read through the new
-- apps (phase 2); the apps already on phones read the adult's clinics only.
create or replace view public.my_clinic_messages as
 SELECT id,
    clinic_id,
    body,
    audience,
    sent_at
   FROM clinic_messages m
  WHERE audience = 'everyone'::message_audience AND (EXISTS ( SELECT 1
           FROM registrations r
             JOIN players p ON p.id = r.player_id
          WHERE r.clinic_id = m.clinic_id AND p.account_id = auth.uid() AND p.kind = 'adult'::player_kind
            AND r.status <> 'canceled'::registration_status)) OR (EXISTS ( SELECT 1
           FROM clinic_message_recipients cr
             JOIN players p ON p.id = cr.player_id
          WHERE cr.message_id = m.id AND p.account_id = auth.uid() AND p.kind = 'adult'::player_kind));

revoke all on public.my_clinic_messages from public, anon, authenticated;
grant select on public.my_clinic_messages to authenticated;

-- H1, M2, M4, L6, L7: the existing functions, their latest bodies with only
-- the marked lines added ----------------------------------------------------
CREATE OR REPLACE FUNCTION public.register_for_clinic(p_clinic uuid, p_player uuid, p_note text DEFAULT NULL::text)
 RETURNS registrations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_note   text;
  v_kind   public.player_kind;
begin
  if not (public.owns_player(p_player) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  -- The note for Tara (decision 0039), checked before anything else so a
  -- note that is too long refuses cleanly instead of after the clinic lock.
  -- Only the player's own words: Tara registering someone cannot put a
  -- sentence in their mouth that they then read back as theirs.
  v_note := case when public.owns_player(p_player) then public.clean_player_note(p_note) end;

  select * into c from public.clinics
   where id = p_clinic and status = 'published'
   for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;

  if c.closes_at is not null and now() >= c.closes_at then
    raise exception 'registration_closed' using errcode = 'P0001';
  end if;

  -- An archived player (a child the parent removed) holds nothing
  -- (20261118000002). FOR SHARE: remove_my_child takes the row FOR UPDATE,
  -- so a removal and a registration are one after the other. Tara is not
  -- refused here, as before: placing anyone is hers.
  select is_member, account_id, kind into v_member, v_account, v_kind
    from public.players
   where id = p_player and (is_active or public.is_admin())
   for share;
  if v_member is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;
  -- A child in an adult clinic, or an adult in a juniors one, hears that
  -- first: guard_player_kind's answer (20261115000001), before any waiver
  -- or card question that would not apply anyway.
  if not public.is_admin() and (v_kind = 'junior') <> (c.audience = 'juniors') then
    raise exception 'wrong_player_kind' using errcode = 'P0001';
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
  -- An adult signs the adult waiver; a child needs the parent's signature
  -- on the junior waiver for that child (decision 0061, 20261118000002),
  -- and while no junior text is published a child holds no spot at all,
  -- with its own error so the gap is never mistaken for the parent's.
  if not public.is_admin() then
    if v_kind = 'junior' then
      if public.junior_waiver_version() is null then
        raise exception 'junior_waiver_not_available' using errcode = 'P0001';
      elsif not public.junior_waiver_signed(p_player) then
        raise exception 'junior_waiver_required' using errcode = 'P0001';
      end if;
    elsif not public.waiver_accepted(v_account) then
      raise exception 'waiver_required' using errcode = 'P0001';
    end if;
  end if;

  if now() < c.member_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif not v_member and now() < c.public_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif v_member and now() < c.public_opens_at then
    -- Decision 0050, Tara 2026-11-06: a member is in automatically only from
    -- the member open (Thursday 8am) to the public open (Friday noon), while
    -- there is room. From the public open on, the Waitlist, like everyone.
    -- You're In! and Tara's guests (20261107000003).
    v_taken := public.clinic_taken(p_clinic);
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
      price_cents_charged, was_member, duration_minutes, player_note)
  values (p_clinic, p_player, v_status,
          case when public.owns_player(p_player) then 'self'::registration_source
                                                 else 'admin'::registration_source end,
          case when v_member then c.member_price_cents else c.nonmember_price_cents end,
          v_member,
          c.duration_minutes,
          v_note)
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
$function$
;

CREATE OR REPLACE FUNCTION public.request_late_spot(p_clinic uuid, p_player uuid, p_message text DEFAULT NULL::text)
 RETURNS late_requests
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c        public.clinics;
  v_req    public.late_requests;
  v_taken  int;
  v_name   text;
  v_admin  uuid;
  v_kind   public.player_kind;
begin
  if not public.owns_player(p_player) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  -- 20261118000002: an archived player asks for nothing (FOR SHARE, against
  -- remove_my_child's FOR UPDATE), and a child only with a signature on the
  -- current junior waiver, as register_for_clinic.
  select kind into v_kind from public.players where id = p_player and is_active for share;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  select * into c from public.clinics where id = p_clinic;
  if not found or c.status <> 'published' then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if c.canceled_at is not null then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  -- As register_for_clinic: the kind first, then the child's waiver.
  if (v_kind = 'junior') <> (c.audience = 'juniors') then
    raise exception 'wrong_player_kind' using errcode = 'P0001';
  end if;
  if v_kind = 'junior' then
    if public.junior_waiver_version() is null then
      raise exception 'junior_waiver_not_available' using errcode = 'P0001';
    elsif not public.junior_waiver_signed(p_player) then
      raise exception 'junior_waiver_required' using errcode = 'P0001';
    end if;
  end if;

  -- This path exists only INSIDE the closed window. Before it, the player
  -- registers normally, and offering both would be two doors to one room.
  if c.closes_at is null or now() < c.closes_at then
    raise exception 'registration_still_open' using errcode = 'P0001';
  end if;
  if now() >= c.starts_at then
    raise exception 'clinic_already_started' using errcode = 'P0001';
  end if;

  -- Already in, pooled, or invited: nothing to ask for.
  if exists (select 1 from public.registrations r
              where r.clinic_id = p_clinic and r.player_id = p_player
                and r.status <> 'canceled') then
    raise exception 'already_registered' using errcode = 'P0001';
  end if;

  -- Her condition, verbatim: "assuming there is space and it isn't full".
  -- You're In! and Tara's guests (20261107000003).
  v_taken := public.clinic_taken(p_clinic);
  if v_taken >= c.internal_capacity then
    raise exception 'clinic_full' using errcode = 'P0001';
  end if;

  insert into public.late_requests (clinic_id, player_id, message)
  values (p_clinic, p_player, nullif(btrim(coalesce(p_message, '')), ''))
  returning * into v_req;

  -- Tell every admin. This is the "direct message" from her side.
  select p.first_name || ' ' || p.last_name into v_name
    from public.players p where p.id = p_player;

  -- admin_account_ids() returns SETOF uuid, so it is selected FROM, not
  -- unnested. Matches how respond_to_invitation already fans out to admins.
  for v_admin in select public.admin_account_ids() loop
    perform public.notify_account(
      v_admin, 'LATE_REQUEST', 'clinic', p_clinic,
      v_name || ' is asking to join ' || c.name || '.'
      || coalesce(' "' || v_req.message || '"', ''));
  end loop;

  return v_req;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.respond_to_invitation(p_registration uuid, p_accept boolean)
 RETURNS registrations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
  v_kind   public.player_kind;
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

  -- 20261118000002: an Accept by an archived player takes nothing, and a
  -- child accepts only with a signature on the current junior waiver.
  -- Declining stays open to everyone: it takes nothing.
  if p_accept and not public.is_admin() then
    select kind into v_kind from public.players
     where id = v_row.player_id and is_active
     for share;
    if not found then
      raise exception 'player_not_found' using errcode = 'P0002';
    end if;
    if v_kind = 'junior' then
      if public.junior_waiver_version() is null then
        raise exception 'junior_waiver_not_available' using errcode = 'P0001';
      elsif not public.junior_waiver_signed(v_row.player_id) then
        raise exception 'junior_waiver_required' using errcode = 'P0001';
      end if;
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
$function$
;

CREATE OR REPLACE FUNCTION public.pro_week()
 RETURNS TABLE(clinic_id uuid, clinic_name text, starts_at timestamp with time zone, ends_at timestamp with time zone, registration_id uuid, first_name text, last_name text, court_number smallint, no_show boolean, late_cancel boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.require_pro();
  -- pro_today's columns exactly (decision 0025: the column list is the
  -- contract), for today and the six New York days after it.
  return query
    select c.id, c.name, c.starts_at, c.ends_at,
           r.id, p.first_name, p.last_name, r.court_number, r.no_show, r.late_cancel
      from public.clinics c
      -- No child for a pro until phase 3 (decision 0061, 20261118000002):
      -- a juniors clinic shows, its children do not.
      left join (public.registrations r
                 join public.players p on p.id = r.player_id and p.kind = 'adult')
             on r.clinic_id = c.id and r.status = 'in'
     where c.status = 'published'
       and public.new_york_date(c.starts_at) between public.new_york_date(now())
                                                 and public.new_york_date(now()) + 6
     order by c.starts_at, c.id, r.court_number nulls last, p.last_name, p.first_name, r.id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.pro_today()
 RETURNS TABLE(clinic_id uuid, clinic_name text, starts_at timestamp with time zone, ends_at timestamp with time zone, registration_id uuid, first_name text, last_name text, court_number smallint, no_show boolean, late_cancel boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  perform public.require_pro();
  return query
    select c.id, c.name, c.starts_at, c.ends_at,
           r.id, p.first_name, p.last_name, r.court_number, r.no_show, r.late_cancel
      from public.clinics c
      -- No child for a pro until phase 3 (decision 0061, 20261118000002):
      -- a juniors clinic shows, its children do not.
      left join (public.registrations r
                 join public.players p on p.id = r.player_id and p.kind = 'adult')
             on r.clinic_id = c.id and r.status = 'in'
     where c.status = 'published'
       and public.new_york_date(c.starts_at) = public.new_york_date(now())
     order by c.starts_at, c.id, r.court_number nulls last, p.last_name, p.first_name, r.id;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.clinic_round_people(p_clinic uuid)
 RETURNS TABLE(person_id uuid, first_name text, last_name text, is_guest boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  c public.clinics;
begin
  if not public.is_admin() then
    perform public.require_pro();
    select * into c from public.clinics where id = p_clinic;
    -- One answer for anything outside the week, as clinic_rounds.
    if not found or c.status <> 'published'
       or public.new_york_date(c.starts_at) not between public.new_york_date(now())
                                                    and public.new_york_date(now()) + 6 then
      raise exception 'not_this_week' using errcode = 'P0001';
    end if;
    -- Rounds are a 105 thing: a pro's other clinics already show their
    -- players (pro_week), never their guests, so this is no wider than that.
    if not public.is_105(c.name, c.category) then
      raise exception 'not_105' using errcode = 'P0001';
    end if;
  end if;
  return query
    select r.id, p.first_name, p.last_name, false
      from public.registrations r
      join public.players p on p.id = r.player_id
     where r.clinic_id = p_clinic and r.status = 'in'
       -- No child for a pro until phase 3 (20261118000002); Tara sees all.
       and (p.kind = 'adult' or public.is_admin())
    union all
    select g.id, g.first_name, g.last_name, true
      from public.clinic_guests g
     where g.clinic_id = p_clinic and g.removed_at is null
    order by 3, 2, 1;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.set_my_gender(p_player uuid, p_gender player_gender)
 RETURNS players
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v public.players;
begin
  if p_gender is null then
    raise exception 'gender_required' using errcode = '22023';
  end if;
  if not public.owns_player(p_player) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  -- The Ladies / Men answer is the adult's (20261115000001 reads only the
  -- adult's); a child has none to give (20261118000002).
  if exists (select 1 from public.players where id = p_player and kind <> 'adult') then
    raise exception 'wrong_player_kind' using errcode = 'P0001';
  end if;
  -- Conditional (hard rule 3): only an unanswered row. A second answer, or
  -- the same answer twice, changes nothing and says so.
  update public.players set gender = p_gender
   where id = p_player and gender is null
  returning * into v;
  if not found then
    select * into v from public.players where id = p_player;
    if v.gender is distinct from p_gender then
      raise exception 'gender_already_set' using errcode = 'P0001';
    end if;
  end if;
  return v;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.request_level_approval(p_player uuid, p_level numeric)
 RETURNS level_approvals
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_player public.players;
  v        public.level_approvals;
  v_admin  uuid;
begin
  if not public.owns_player(p_player) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
  -- Levels are the adult clinics' (decision 0048); a child's program is
  -- chosen by hand and approved per program (20261118000002).
  if exists (select 1 from public.players where id = p_player and kind <> 'adult') then
    raise exception 'wrong_player_kind' using errcode = 'P0001';
  end if;
  if p_level is null or p_level < 2.5 or p_level > 5.0 or p_level * 2 <> trunc(p_level * 2) then
    raise exception 'invalid_level' using errcode = '22023';
  end if;
  select * into v_player from public.players where id = p_player;
  if public.level_ok(p_player, p_level) then
    raise exception 'approval_not_needed' using errcode = 'P0001';
  end if;

  -- Conditional (hard rule 3): a second tap, or a request after Tara already
  -- approved, changes nothing and tells nobody.
  insert into public.level_approvals (player_id, level, status, requested_at)
  values (p_player, p_level::numeric(2,1), 'requested', now())
  on conflict (player_id, level) do nothing
  returning * into v;

  if found then
    for v_admin in select public.admin_account_ids() loop
      perform public.notify_account(v_admin, 'level_request', 'player', p_player,
        v_player.first_name || ' ' || v_player.last_name
        || ' (' || to_char(v_player.adult_rating, 'FM9.0') || ') asked to attend '
        || to_char(p_level, 'FM9.0') || '+ clinics.');
    end loop;
  else
    select * into v from public.level_approvals
     where player_id = p_player and level = p_level;
  end if;
  return v;
end;
$function$
;

CREATE OR REPLACE FUNCTION public.waiver_version()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  -- Adult text only (20261118000002), as junior_waiver_version reads junior.
  select w.version
    from public.app_settings s
    join public.waivers w on w.version = s.value and w.kind = 'adult'
   where s.key = 'waiver_version';
$function$
;

CREATE OR REPLACE FUNCTION public.current_waiver()
 RETURNS TABLE(version text, title text, organizer text, body text, published_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  select w.version, w.title, w.organizer, w.body, w.published_at
    from public.waivers w
   where w.kind = 'adult' and w.version = public.waiver_version();
$function$
;
