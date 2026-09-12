-- Cancellation is a 4-hour honor system (decision 0010, Tara 2026-09-12).
--
-- Her words, relayed by Alex: "honor system for canceling, unless it's an
-- emergency, someone sick in your household, etc ... very concise message -
-- the threshold will be 4 hours, so before 4 hours anything can be cancelled
-- but after that you have to say it's an emergency to cancel."
--
-- So: the cutoff setting becomes 4; a You're In! player canceling inside it
-- must send a short note or the cancellation is refused; the row remembers
-- that it was late and what they said; nothing is charged by the app. Tara
-- sees the note on the roster and charging stays her tap (0009).

update public.app_settings set value = '4' where key = 'cancel_cutoff_hours';

alter table public.registrations
  add column if not exists late_cancel boolean not null default false,
  add column if not exists cancel_note text;

comment on column public.registrations.late_cancel is
  'True when a You''re In! player canceled inside cancel_cutoff_hours. Set only by cancel_registration.';
comment on column public.registrations.cancel_note is
  'The player''s own concise message on a late cancellation. Their words, never generated.';

create or replace function public.cancel_cutoff_hours()
returns integer
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select coalesce((select value::integer from public.app_settings where key = 'cancel_cutoff_hours'), 4);
$$;

-- The old one-argument signature is dropped on purpose. Leaving it beside a
-- two-argument version with a default makes cancel_registration(uuid)
-- ambiguous to Postgres, and every client would start failing with
-- "function is not unique".
drop function if exists public.cancel_registration(uuid);

create or replace function public.cancel_registration(p_registration uuid, p_note text default null)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_row    public.registrations;
  v_player public.players;
  v_admin  uuid;
  v_starts timestamptz;
  v_late   boolean := false;
  v_note   text := nullif(btrim(coalesce(p_note, '')), '');
begin
  select * into v_row from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not (public.owns_player(v_row.player_id) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  -- Late means: the player (not Tara) drops a held spot inside the cutoff.
  -- Pool and Response Needed hold nothing; Tara removing someone is not the
  -- player's late cancel.
  select starts_at into v_starts from public.clinics where id = v_row.clinic_id;
  if v_row.status = 'in' and not public.is_admin()
     and v_starts - now() < make_interval(hours => public.cancel_cutoff_hours()) then
    v_late := true;
    if v_note is null then
      raise exception 'late_cancel_needs_note' using errcode = 'P0001';
    end if;
  end if;

  update public.registrations
     set status = 'canceled', canceled_at = now(), canceled_by = auth.uid(),
         late_cancel = v_late,
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
      || case when v_late then ' Note: "' || v_row.cancel_note || '"' else '' end);
  end loop;

  return v_row;
end;
$$;

-- Hard rule 11: revoke before grant, from PUBLIC too.
revoke all on function public.cancel_cutoff_hours() from public, anon;
grant execute on function public.cancel_cutoff_hours() to authenticated;
revoke all on function public.cancel_registration(uuid, text) from public, anon;
grant execute on function public.cancel_registration(uuid, text) to authenticated;

-- Tara's roster needs the note and whether a card exists to charge; the
-- player's own view needs to know the cancel was late. Columns appended at
-- the end so `create or replace` keeps the existing shape.
create or replace view public.registrations_admin as
  select id, clinic_id, player_id, status, paid, court_number, source,
         registered_at, invited_at, responded_at, canceled_at, canceled_by,
         late_cancel, cancel_note,
         exists (select 1 from public.players p join public.accounts a on a.id = p.account_id
                  where p.id = r.player_id and a.stripe_customer_id is not null) as has_card,
         -- The latest fee on this registration, so the roster shows "Processing"
         -- or "Paid" instead of offering the Charge button a second time.
         (select x.status::text from public.payments x
           where x.registration_id = r.id and x.kind <> 'refund'
           order by x.created_at desc limit 1) as charge_status
    from public.registrations r
   where public.is_admin();

create or replace view public.my_registrations as
  select id, clinic_id, player_id, status, paid, registered_at, invited_at, responded_at, canceled_at,
         late_cancel
    from public.registrations r
   where public.owns_player(player_id);
