-- 20261104000001_waitlist_move_in.sql
--
-- Tara, 2026-11-04, by text through John: "Making sure that when someone is
-- on the waitlist - when I move them to the clinic they automatically are
-- moved and get notification they're in, UNLESS it's the same day of clinic
-- in which case they have to accept the invitiation." Decision 0047.
--
-- Her one button on a Waitlist row (Invite) now does one of two things,
-- decided by the clinic's day in New York, not by elapsed hours:
--
--   clinic day is after today  -> You're In! at once, and #1 in her words
--                                 ("You're all set for ..."), the sentence
--                                 place_player sends
--   clinic day is today, or    -> an invitation, as before: Response Needed,
--   already past                  #2, and the player Accepts or Declines
--
-- A move-in also needs the cancel cutoff (3 hours) still ahead: a clinic at
-- 12:30 AM is "tomorrow" at 10 PM, and a spot the player never said yes to
-- must not start inside the late-cancel window. Inside it, an invitation.
--
-- A clinic whose day has passed keeps the invitation path on purpose: moving
-- someone straight into a clinic that has ended would put them on the charge
-- list (the accept after the end is refused since 20260928400001; this keeps
-- that refusal meaningful).
--
-- Hard rule 2 changes with it: Tara confirming someone off the Waitlist before
-- clinic day no longer needs their acceptance. Nothing is still ever moved
-- without her tap.
--
-- Copied from the live definition (20260928400001), with the transition and
-- the notification chosen by the day. CREATE OR REPLACE keeps owner and grants.

create or replace function public.invite_from_pool(p_registration uuid)
returns public.registrations
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v public.registrations; v_player public.players; v_clinic public.clinics; v_clinic_id uuid;
  v_move_in boolean;
begin
  perform public.require_admin();

  -- The clinic first, locked FOR SHARE so cancel_clinic and this invitation
  -- are serialized; then the conditional transition (hard rule 3).
  select clinic_id into v_clinic_id from public.registrations where id = p_registration;
  select * into v_clinic from public.clinics where id = v_clinic_id for share;
  if found and v_clinic.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;

  -- Before clinic day she places them; on the day they must still say yes.
  -- And only while the player can still cancel without a fee: a 12:30 AM
  -- clinic is "tomorrow" at 10 PM, and a spot they never said yes to must
  -- not make their first chance to cancel a late cancel (the sql-auditor,
  -- 2026-11-04). Inside the cutoff it is an invitation.
  v_move_in := (v_clinic.starts_at at time zone 'America/New_York')::date
             > (now() at time zone 'America/New_York')::date
           and v_clinic.starts_at - now() >= make_interval(hours => public.cancel_cutoff_hours());

  update public.registrations
     set status     = case when v_move_in then 'in'::registration_status else 'response_needed'::registration_status end,
         invited_at = case when v_move_in then invited_at else now() end
   where id = p_registration and status = 'pool'
  returning * into v;
  if not found then
    raise exception 'not_in_pool' using errcode = 'P0001';
  end if;

  select * into v_player from public.players where id = v.player_id;
  if v_move_in then
    -- #1, the same sentence and the same conditions as place_player: only for
    -- a clinic the player can open (a draft is invisible to them).
    if v_clinic.status = 'published' then
      perform public.notify_account(v_player.account_id, 'youre_in', 'registration', v.id,
        'You''re all set for ' || v_clinic.name || ' on '
        || to_char(v_clinic.starts_at at time zone 'America/New_York', 'FMDay') || ' at '
        || to_char(v_clinic.starts_at at time zone 'America/New_York', 'FMHH12:MI AM')
        || '. Looking forward to seeing you on court!');
    end if;
  else
    perform public.notify_account(v_player.account_id, 'invitation_received',
      'registration', v.id,
      'A spot opened in ' || v_clinic.name || '. Accept or decline.');
  end if;

  return v;
end;
$$;

-- Restated by convention, as 20260928400001 did; CREATE OR REPLACE kept them.
revoke all on function public.invite_from_pool(uuid) from public, anon;
grant execute on function public.invite_from_pool(uuid) to authenticated;
