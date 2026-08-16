-- create_my_account: the missing half of sign-up.
--
-- THE BUG THIS FIXES
-- ------------------
-- Sign-up produced a permanently broken account. `SessionStore.signUp` called
-- `supabase.auth.signUp`, then `loadProfile()`, then set `phase = .signedIn`
-- unconditionally. Nothing ever created the `public.accounts` row, and nothing
-- could: `authenticated` has no INSERT on `accounts` (correctly revoked by
-- 20260802000003), there is no trigger on `auth.users`, and the Swift client
-- contains zero table writes.
--
-- The result for a real person: an orphan `auth.users` row, no `accounts` row,
-- no `players` row. `loadProfile` swallowed the failure and left
-- `activePlayer = nil`. Home greeted them "Good Evening, there!", they were
-- treated as a NON-member so every price was wrong, and the Register button was
-- a silent no-op at `ClinicDetailView.swift:213`
-- (`guard let playerId = session.activePlayer?.id else { return }`). On relaunch
-- `bootstrap` sent them back to signed-out with no explanation, and signing up
-- again with the same email failed because the auth user already existed.
--
-- Found 2026-08-13. It is the reason a TestFlight build would have been a demo
-- rather than a test: Tara installs it, signs up, and can do nothing at all.
--
-- WHY AN RPC AND NOT A TRIGGER ON auth.users
-- ------------------------------------------
-- A trigger is the common Supabase pattern and it is wrong here.
-- `accounts.first_name` and `last_name` are NOT NULL, and sign-up collects only
-- an email and a password (`AuthView.swift:61-84`). A trigger would have to
-- invent names or read them out of `raw_user_meta_data`, which means trusting
-- client-supplied metadata for a NOT NULL column and silently writing junk when
-- it is absent. An explicit RPC lets the app collect a real name on a real
-- screen and fail loudly if it is missing.
--
-- It also keeps every write to `accounts` in one auditable place, which is the
-- pattern the rest of this schema already uses.
--
-- SECURITY NOTES, in the order they matter
-- ----------------------------------------
-- * The row id is `auth.uid()`, never a parameter. You cannot create an account
--   for anyone but yourself, and there is no argument that would let you try.
-- * `role` is hard-coded to 'member'. It is NOT a parameter and never will be.
--   Hard rule 8: a privilege column is never writable by the role it grants
--   privilege to. `guard_account_privilege_columns` would reject it anyway;
--   this is the belt to that trigger's braces.
-- * `email` is read from `auth.users`, not accepted from the caller. A client
--   that could name its own email could impersonate one.
-- * `search_path` is pinned, as on all 23 other SECURITY DEFINER functions.
-- * Revoke precedes grant (hard rule 11). `revoke ... from public` matters:
--   PUBLIC holds EXECUTE on new functions by default, so revoking from `anon`
--   alone would be a no-op.
-- * Idempotent. Calling it twice returns the existing player instead of
--   raising, because a retry after a dropped connection must not be an error.

create or replace function public.create_my_account(
  p_first_name   text,
  p_last_name    text,
  p_phone        text    default null,
  p_is_member    boolean default false,
  p_adult_rating numeric default null
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
  insert into public.players (account_id, kind, first_name, last_name, adult_rating, is_member, is_active)
  values (v_uid, 'adult', v_first, v_last, p_adult_rating, coalesce(p_is_member, false), true)
  returning id into v_player_id;

  return v_player_id;
end;
$$;

comment on function public.create_my_account(text, text, text, boolean, numeric) is
  'Creates the caller''s own accounts + adult players row after auth sign-up. '
  'id is auth.uid() and role is hard-coded to member, so it cannot be used to '
  'create another person''s account or to grant privilege. Idempotent.';

revoke all on function public.create_my_account(text, text, text, boolean, numeric)
  from public, anon, authenticated;
grant execute on function public.create_my_account(text, text, text, boolean, numeric)
  to authenticated;
