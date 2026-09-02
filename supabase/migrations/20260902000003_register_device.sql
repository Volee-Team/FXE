-- Device registration: the first half of push notifications.
--
-- `devices` has existed since the first migration (account_id, apns_token,
-- platform, updated_at) with an owner-only RLS policy and, since 2026-08-17,
-- no client privilege at all. Nothing could write to it. This adds the two
-- RPCs the app needs and nothing else: the sending side (an edge function
-- reading `notifications` and talking to APNs) is decision 0008 and a later
-- migration, because it cannot be exercised until Apple issues the signing
-- key that only a paid developer account holds.
--
-- SECURITY NOTES
-- * The account is auth.uid(), never a parameter: you register your own
--   phone, nobody else's, and a token can only ever be tied to its caller.
-- * Upsert on (account_id, apns_token): APNs tokens rotate, and the app
--   re-registers on every launch, so the same token must be a no-op and a
--   new one an extra row. Old tokens are pruned by APNs feedback later.
-- * The player's push permission state is NOT recorded anywhere Tara can see
--   (her decision 13, 2026-08-02: she does not want to monitor who has
--   notifications off). The app nags the player instead.
-- * Hard rule 11: revoke from PUBLIC, not just anon, before granting.

create or replace function public.register_device(p_token text, p_platform text default 'ios')
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v_uid uuid := auth.uid(); v_token text := btrim(coalesce(p_token, ''));
begin
  if v_uid is null then
    raise exception 'register_device: not authenticated' using errcode = '42501';
  end if;
  if v_token = '' then
    raise exception 'register_device: token required' using errcode = '22023';
  end if;
  if not exists (select 1 from public.accounts a where a.id = v_uid) then
    raise exception 'register_device: no account' using errcode = '42501';
  end if;
  insert into public.devices (account_id, apns_token, platform, updated_at)
  values (v_uid, v_token, coalesce(nullif(btrim(p_platform), ''), 'ios'), now())
  on conflict (account_id, apns_token) do update set updated_at = now(), platform = excluded.platform;
end;
$$;

-- Sign-out and "notifications off" both call this so a phone that no longer
-- wants pushes stops getting them, and a shared phone never leaks one
-- player's invitations to the next person who signs in on it.
create or replace function public.unregister_device(p_token text)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if auth.uid() is null then
    raise exception 'unregister_device: not authenticated' using errcode = '42501';
  end if;
  delete from public.devices where account_id = auth.uid() and apns_token = btrim(coalesce(p_token, ''));
end;
$$;

comment on function public.register_device(text, text) is
  'Ties an APNs token to the calling account. Upsert; account is auth.uid(), never a parameter.';
comment on function public.unregister_device(text) is
  'Removes one of the caller''s own tokens. Called on sign-out.';

revoke all on function public.register_device(text, text) from public, anon, authenticated;
revoke all on function public.unregister_device(text) from public, anon, authenticated;
grant execute on function public.register_device(text, text) to authenticated;
grant execute on function public.unregister_device(text) to authenticated;

-- Belt to the braces: the table itself stays unreadable and unwritable by
-- clients, so a token can never be read back by anyone but the sender.
revoke all on public.devices from public, anon, authenticated;
