-- 20260921000003_account_deletion.sql
--
-- Decision 0013 §5. App Store guideline 5.1.1(v) requires that an app with
-- account creation lets the person delete the account from inside the app.
-- Tara, 2026-09-21, asked what stays: "Keep their history."
--
-- So deletion is two steps, and this migration is the first:
--
--   1. delete_my_account(): the signed-in account scrubs its own personal
--      data in OUR tables (name, phone, email, card summary, the note only
--      Tara reads, push tokens, notifications) and stamps deleted_at. The
--      registrations, payments ledger and Tara's private notes stay, under
--      a player now called "Deleted Player", so Money still adds up and a
--      roster from March still has the right count.
--   2. The sign-in itself is removed by the delete-account edge function
--      through Supabase's admin API (soft delete), which is the supported
--      path. Nothing here touches the auth schema: accounts.id cascades
--      from auth.users, and players and registrations cascade from there,
--      so a hard delete would erase exactly the history she said to keep.
--
-- The admin cannot delete herself from the app (admin_cannot_delete): the
-- club would lose its only administrator with one tap.

alter table public.accounts add column if not exists deleted_at timestamptz;

create or replace function public.delete_my_account()
returns uuid
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_id   uuid := auth.uid();
  v_role text;
begin
  if v_id is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  select role into v_role from public.accounts where id = v_id;
  if v_role is null then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;
  if v_role = 'admin' then
    raise exception 'admin_cannot_delete' using errcode = 'P0001';
  end if;

  -- Personal data goes; the account row and its id stay so history keeps
  -- its foreign keys. The email is replaced with a value that can never be
  -- signed in with or mailed (RFC 2606 reserves .invalid).
  update public.accounts
     set first_name = 'Deleted', last_name = 'Account',
         email      = 'deleted-' || v_id || '@deleted.invalid',
         phone      = null,
         card_brand = null, card_last4 = null, card_added_at = null,
         deleted_at = coalesce(deleted_at, now())
   where id = v_id;

  update public.players
     set first_name = 'Deleted', last_name = 'Player',
         date_of_birth = null, level_note = null, is_active = false
   where account_id = v_id;

  -- A push token is a device, not history; a notification is personal.
  delete from public.devices       where account_id = v_id;
  delete from public.notifications where account_id = v_id;

  -- Spots in clinics still to come are given back; their rows stay as
  -- canceled (hard rule 4). A clinic already played is history and keeps
  -- its "in": that is the record she said to keep, and the row Money reads.
  update public.registrations r
     set status = 'canceled', canceled_at = now(), canceled_by = v_id
    from public.players p, public.clinics c
   where p.id = r.player_id and p.account_id = v_id
     and c.id = r.clinic_id and c.starts_at > now()
     and r.status in ('in', 'pool', 'response_needed');

  return v_id;
end;
$$;
revoke all on function public.delete_my_account() from public, anon;
grant execute on function public.delete_my_account() to authenticated;

-- A deleted account is never an admin, whatever a stale row says, and
-- cannot come back through the profile screen.
create or replace function public.is_admin()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.accounts
     where id = auth.uid() and role = 'admin' and deleted_at is null
  );
$$;
