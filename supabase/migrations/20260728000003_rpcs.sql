-- FXE Tennis v1: RPCs.
--
-- Two rules run through all of this:
--
--  1. Member priority is the ONLY place software decides capacity. It is done
--     inside one transaction with the clinic row locked, because two members
--     tapping Register in the same second must not both land in You're In!.
--
--  2. Every state transition is a CONDITIONAL update that reports whether it
--     actually did anything. Tara cancelling an invitation at the same moment
--     the player accepts is a real race; the loser gets a friendly message
--     instead of silently clobbering the winner.
--
-- Nothing here ever invites the next player automatically. The app manages
-- information; Tara manages tennis.

-- ------------------------------------------------------------- utilities ----

create or replace function public.notify_account(
  p_account uuid, p_type text, p_entity_type text, p_entity_id uuid, p_body text)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.notifications (account_id, type, entity_type, entity_id, body)
  values (p_account, p_type, p_entity_type, p_entity_id, p_body);
$$;

create or replace function public.admin_account_ids()
returns setof uuid
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select id from public.accounts where role = 'admin';
$$;

create or replace function public.require_admin()
returns void
language plpgsql
stable
as $$
begin
  if not public.is_admin() then
    raise exception 'not_authorized' using errcode = '42501';
  end if;
end;
$$;

-- ---------------------------------------------------------- registration ----

-- The one capacity decision in the app. See rule 1 above.
--
-- Branches, straight from the guide's registration table:
--   member, inside the priority window  -> You're In! if room, else Player Pool
--   member, after the priority window   -> Player Pool
--   non-member, after public opening    -> Player Pool
--   anyone, before member opening       -> rejected
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
begin
  if not (public.owns_player(p_player) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  -- FOR UPDATE is what serialises concurrent registrations on this clinic.
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

  if now() < c.member_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif not v_member and now() < c.public_opens_at then
    -- Non-members cannot queue during the member-only window. The guide only
    -- says their opening is Friday 8 AM, but Tara sees Player Pool in
    -- registration order, so letting non-members join on Thursday would put
    -- them ahead of members in her list and quietly subvert the priority.
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif v_member and now() < c.public_opens_at then
    select count(*) into v_taken
      from public.registrations
     where clinic_id = p_clinic and status = 'in';
    v_status := case when v_taken < c.internal_capacity then 'in' else 'pool' end;
  else
    v_status := 'pool';
  end if;

  insert into public.registrations (clinic_id, player_id, status, source)
  values (p_clinic, p_player, v_status,
          case when public.owns_player(p_player) then 'self'::registration_source
                                                 else 'admin'::registration_source end)
  returning * into v_row;

  return v_row;
exception
  -- The partial unique index makes a retried request safe rather than a double
  -- booking. The client renders this as the guide's copy.
  when unique_violation then
    raise exception 'already_registered' using errcode = 'P0001';
end;
$$;

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
begin
  select * into v_row from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not public.owns_player(v_row.player_id) then
    raise exception 'not_authorized' using errcode = '42501';
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
  for v_admin in select public.admin_account_ids() loop
    perform public.notify_account(
      v_admin, case when p_accept then 'invitation_accepted' else 'invitation_declined' end,
      'registration', v_row.id,
      v_player.first_name || ' ' || v_player.last_name
        || case when p_accept then ' accepted.' else ' declined.' end);
  end loop;

  return v_row;
end;
$$;

create or replace function public.cancel_registration(p_registration uuid)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row    public.registrations;
  v_player public.players;
  v_admin  uuid;
begin
  select * into v_row from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not (public.owns_player(v_row.player_id) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  update public.registrations
     set status = 'canceled', canceled_at = now(), canceled_by = auth.uid()
   where id = p_registration
     and status in ('in', 'pool', 'response_needed')
  returning * into v_row;

  if not found then
    raise exception 'already_canceled' using errcode = 'P0001';
  end if;

  select * into v_player from public.players where id = v_row.player_id;
  for v_admin in select public.admin_account_ids() loop
    perform public.notify_account(v_admin, 'player_canceled', 'registration', v_row.id,
      v_player.first_name || ' ' || v_player.last_name || ' canceled.');
  end loop;

  return v_row;
end;
$$;

-- Leaving the Pool removes the row outright: the guide treats it as withdrawing
-- interest, not as a cancellation Tara needs to see in Action Needed.
create or replace function public.leave_pool(p_registration uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_player uuid;
begin
  select player_id into v_player from public.registrations where id = p_registration;
  if v_player is null then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not public.owns_player(v_player) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  delete from public.registrations where id = p_registration and status = 'pool';
  if not found then
    raise exception 'not_in_pool' using errcode = 'P0001';
  end if;
  return true;
end;
$$;

create or replace function public.mark_news_read(p_news uuid)
returns void
language sql
security definer
set search_path = public, pg_temp
as $$
  insert into public.news_reads (news_id, account_id)
  values (p_news, auth.uid())
  on conflict (news_id, account_id) do nothing;
$$;

-- ----------------------------------------------------------------- admin ----

-- Copy-on-create, never by reference. Editing a template in October must not
-- rewrite the clinics published in September.
create or replace function public.create_clinic_from_template(
  p_template uuid, p_starts_at timestamptz, p_ends_at timestamptz default null)
returns public.clinics
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare t public.clinic_templates; v public.clinics;
begin
  perform public.require_admin();

  select * into t from public.clinic_templates where id = p_template;
  if not found then
    raise exception 'template_not_found' using errcode = 'P0002';
  end if;

  insert into public.clinics (
    template_id, name, audience, category, description, price_cents,
    starts_at, ends_at, member_opens_at, public_opens_at,
    internal_capacity, status)
  values (
    t.id, t.name, t.audience, t.category, t.description, t.price_cents,
    p_starts_at,
    coalesce(p_ends_at, p_starts_at + make_interval(mins => t.duration_minutes)),
    public.member_opens_at(p_starts_at),
    public.public_opens_at(p_starts_at),
    t.internal_capacity, 'draft')
  returning * into v;

  return v;
end;
$$;

create or replace function public.publish_clinic(p_clinic uuid)
returns public.clinics
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.clinics;
begin
  perform public.require_admin();
  update public.clinics set status = 'published'
   where id = p_clinic and status = 'draft'
  returning * into v;
  if not found then
    raise exception 'not_draft' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

-- Cancelling notifies everyone in a live status, and preserves the record.
create or replace function public.cancel_clinic(p_clinic uuid)
returns public.clinics
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.clinics; r record;
begin
  perform public.require_admin();

  update public.clinics set status = 'canceled', canceled_at = now()
   where id = p_clinic and status <> 'canceled'
  returning * into v;
  if not found then
    raise exception 'already_canceled' using errcode = 'P0001';
  end if;

  for r in
    select distinct p.account_id
      from public.registrations reg
      join public.players p on p.id = reg.player_id
     where reg.clinic_id = p_clinic
       and reg.status in ('in', 'pool', 'response_needed')
  loop
    perform public.notify_account(r.account_id, 'clinic_canceled', 'clinic', p_clinic,
      v.name || ' has been canceled.');
  end loop;

  return v;
end;
$$;

create or replace function public.invite_from_pool(p_registration uuid)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.registrations; v_player public.players; v_clinic public.clinics;
begin
  perform public.require_admin();

  update public.registrations
     set status = 'response_needed', invited_at = now()
   where id = p_registration and status = 'pool'
  returning * into v;
  if not found then
    raise exception 'not_in_pool' using errcode = 'P0001';
  end if;

  select * into v_player from public.players where id = v.player_id;
  select * into v_clinic from public.clinics where id = v.clinic_id;
  perform public.notify_account(v_player.account_id, 'invitation_received',
    'registration', v.id,
    'A spot opened in ' || v_clinic.name || '. Accept or decline.');

  return v;
end;
$$;

create or replace function public.cancel_invitation(p_registration uuid)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.registrations;
begin
  perform public.require_admin();
  update public.registrations
     set status = 'pool', invited_at = null
   where id = p_registration and status = 'response_needed'
  returning * into v;
  if not found then
    -- The player accepted or declined first. Not an error worth alarming
    -- about, but the caller must know it did not happen.
    raise exception 'invitation_already_answered' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

-- The walk-up path. Someone calls Tara or grabs her at the club and she just
-- wants them in. Not in the guide; she will want it in week one.
create or replace function public.place_player(
  p_clinic uuid, p_player uuid, p_status registration_status default 'in')
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.registrations;
begin
  perform public.require_admin();
  if p_status not in ('in', 'pool', 'response_needed') then
    raise exception 'invalid_status' using errcode = 'P0001';
  end if;

  insert into public.registrations (clinic_id, player_id, status, source)
  values (p_clinic, p_player, p_status, 'admin')
  on conflict (clinic_id, player_id) where status in ('in','pool','response_needed')
  do update set status = excluded.status
  returning * into v;

  return v;
end;
$$;

create or replace function public.set_paid(p_registration uuid, p_paid boolean)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.registrations;
begin
  perform public.require_admin();
  update public.registrations set paid = p_paid where id = p_registration
  returning * into v;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  return v;
end;
$$;

create or replace function public.assign_court(p_registration uuid, p_court smallint)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.registrations;
begin
  perform public.require_admin();
  update public.registrations set court_number = p_court where id = p_registration
  returning * into v;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  return v;
end;
$$;

-- Recipients are resolved server-side and snapshotted, so who can read the
-- message later is deterministic and does not drift as statuses change.
create or replace function public.send_clinic_message(
  p_clinic uuid, p_audience message_audience, p_body text)
returns public.clinic_messages
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare m public.clinic_messages; r record;
begin
  perform public.require_admin();

  insert into public.clinic_messages (clinic_id, audience, body)
  values (p_clinic, p_audience, p_body)
  returning * into m;

  for r in
    select reg.player_id, p.account_id
      from public.registrations reg
      join public.players p on p.id = reg.player_id
     where reg.clinic_id = p_clinic
       and reg.status <> 'canceled'
       and (
         p_audience = 'everyone'
         or (p_audience = 'in'              and reg.status = 'in')
         or (p_audience = 'pool'            and reg.status = 'pool')
         or (p_audience = 'response_needed' and reg.status = 'response_needed')
         or (p_audience = 'unpaid'          and reg.paid = false and reg.status = 'in')
       )
  loop
    if p_audience <> 'everyone' then
      insert into public.clinic_message_recipients (message_id, player_id)
      values (m.id, r.player_id) on conflict do nothing;
    end if;
    perform public.notify_account(r.account_id, 'clinic_message', 'clinic', p_clinic, p_body);
  end loop;

  return m;
end;
$$;

create or replace function public.publish_news(p_news uuid)
returns public.news_posts
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.news_posts;
begin
  perform public.require_admin();
  update public.news_posts set status = 'published', published_at = now()
   where id = p_news and status = 'draft'
  returning * into v;
  if not found then
    raise exception 'not_draft' using errcode = 'P0001';
  end if;
  return v;
end;
$$;

create or replace function public.set_player_active(p_player uuid, p_active boolean)
returns public.players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.players;
begin
  perform public.require_admin();
  update public.players set is_active = p_active where id = p_player
  returning * into v;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;
  return v;
end;
$$;

-- Forgiving name search. "Ann" returns Anna, Ann, Annette and Joann, per the
-- guide's example.
create or replace function public.search_players(p_query text, p_include_inactive boolean default false)
returns table (
  id uuid, first_name text, last_name text, kind player_kind,
  age integer, adult_rating text, is_member boolean, is_active boolean,
  has_notes boolean)
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
    select p.id, p.first_name, p.last_name, p.kind,
           public.player_age(p.date_of_birth), p.adult_rating,
           p.is_member, p.is_active,
           exists (select 1 from public.player_notes n
                    where n.player_id = p.id and n.body <> '')
      from public.players p
     where (p_include_inactive or p.is_active)
       and (
         p_query is null or p_query = ''
         or p.first_name ilike '%' || p_query || '%'
         or p.last_name  ilike '%' || p_query || '%'
       )
     order by p.last_name, p.first_name;
end;
$$;

-- ---------------------------------------------------------------- grants ----

revoke all on function public.register_for_clinic(uuid, uuid) from public;
grant execute on function
  public.register_for_clinic(uuid, uuid),
  public.respond_to_invitation(uuid, boolean),
  public.cancel_registration(uuid),
  public.leave_pool(uuid),
  public.mark_news_read(uuid),
  public.create_clinic_from_template(uuid, timestamptz, timestamptz),
  public.publish_clinic(uuid),
  public.cancel_clinic(uuid),
  public.invite_from_pool(uuid),
  public.cancel_invitation(uuid),
  public.place_player(uuid, uuid, registration_status),
  public.set_paid(uuid, boolean),
  public.assign_court(uuid, smallint),
  public.send_clinic_message(uuid, message_audience, text),
  public.publish_news(uuid),
  public.set_player_active(uuid, boolean),
  public.search_players(text, boolean),
  public.player_age(date),
  public.member_opens_at(timestamptz),
  public.public_opens_at(timestamptz),
  public.is_admin(),
  public.owns_player(uuid)
to authenticated;

-- notify_account and admin_account_ids are internal plumbing for the RPCs
-- above. A client must never be able to fabricate a notification.
revoke execute on function public.notify_account(uuid, text, text, uuid, text) from public, anon, authenticated;
revoke execute on function public.admin_account_ids() from public, anon, authenticated;
