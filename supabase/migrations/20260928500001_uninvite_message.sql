-- 20260928500001_uninvite_message.sql
--
-- Tara's words when she takes an invitation back (question 79, answered
-- 2026-09-28, decision 0024), verbatim with her curly apostrophes:
--
--   "Yes if I “uninvited them” it’s
--    The levels didn’t line up for this clinic, so we’ve released your spot.
--    We keep each court close in level so everyone gets a great practice.
--    We’ll catch you at the next clinic!"
--
-- cancel_invitation now sends that to the player whose invitation she
-- withdraws. Until today it sent nothing (tests/sql/notification_copy.sql
-- step 13 asserted exactly that, and now asserts her message instead).
--
-- What does not change: the player goes back to the Player Pool, as Cancel
-- Invite always did. Her message ends "We’ll catch you at the next clinic!",
-- which reads as if they are off this clinic; whether they should be is
-- question 94, and until she answers, the button keeps doing what she has
-- been using it for. Taking someone out of You're In! sends nothing yet
-- (question 92): these words are for an uninvite, and would be wrong for a
-- player who asked her to drop them.
--
-- Body otherwise unchanged from 20260728000003 (grants from
-- 20260902000001, restated).

create or replace function public.cancel_invitation(p_registration uuid)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare v public.registrations; v_account uuid;
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

  select account_id into v_account from public.players where id = v.player_id;
  if v_account is not null then
    perform public.notify_account(v_account, 'invitation_withdrawn', 'registration', v.id,
      'The levels didn’t line up for this clinic, so we’ve released your spot. We keep each court close in level so everyone gets a great practice. We’ll catch you at the next clinic!');
  end if;
  return v;
end;
$$;

revoke all on function public.cancel_invitation(uuid) from public, anon;
grant execute on function public.cancel_invitation(uuid) to authenticated;
