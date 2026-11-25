-- 20261125000002_cancel_with_message.sql
--
-- Tara's next-update list (2026-11-23):
--   "when canceling, allow me to send a message when I cancel"
--   "when somebody requests to be added to a clinic, the day of and they
--    don't accept the invite, that person should still get notification if
--    the clinic is canceled"
--
-- cancel_clinic gains p_message (default null), so the one-argument call the
-- 1.0.4 app and the website make resolves to it unchanged. The old
-- one-argument function is dropped: two overloads would make that call
-- ambiguous.
--
--   * Her message follows the usual notice in the same notification ("<name>
--     has been canceled. <her message>"), so a player gets one push, not two,
--     and it is kept on the clinic's message board as a message to everyone.
--   * A player whose late request is still waiting is told as well, and the
--     request is closed as declined: the clinic it asked for is gone, so it
--     leaves Action Needed on the phone and the laptop.
--   * A message of only spaces or line breaks is no message: the notice reads
--     exactly as before and nothing is posted. Over 500 characters is refused
--     (message_too_long), as the laptop's box allows: the push carries it.
--   * A deleted account is not told (as send_player_message).
--   * request_late_spot now takes the clinic row FOR SHARE, so a request
--     filed while the cancel is in flight is seen by it (below).
--   * Unchanged: a never-published clinic tells nobody, pending charges are
--     canceled, and the clinic must not already be canceled.
--
-- Pinned by tests/sql/cancel_with_message.sql.

drop function if exists public.cancel_clinic(uuid);

create or replace function public.cancel_clinic(p_clinic uuid, p_message text default null)
 returns public.clinics
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v     public.clinics;
  r     record;
  v_msg text := nullif(btrim(coalesce(p_message, ''), E' \t\r\n'), '');
begin
  perform public.require_admin();
  if length(v_msg) > 500 then
    raise exception 'message_too_long' using errcode = 'P0001';
  end if;

  update public.clinics set status = 'canceled', canceled_at = now()
   where id = p_clinic and status <> 'canceled'
  returning * into v;
  if not found then
    raise exception 'already_canceled' using errcode = 'P0001';
  end if;

  -- A rained-out clinic owes nothing: charges queued for it and not yet
  -- sent to Stripe are canceled with it (audit 2026-10-12). A refund still
  -- goes through; a charge already with Stripe is refunded by hand.
  update public.payments p
     set status = 'canceled', failure_reason = 'clinic_canceled', updated_at = now()
    from public.registrations reg
   where reg.id = p.registration_id and reg.clinic_id = p_clinic
     and p.status = 'pending' and p.kind <> 'refund'
     and p.stripe_payment_intent_id is null;

  -- Nobody is told about a clinic that was never published.
  if v.published_at is not null then
    if v_msg is not null then
      insert into public.clinic_messages (clinic_id, audience, body)
      values (p_clinic, 'everyone', v_msg);
    end if;

    for r in
      select p.account_id
        from public.registrations reg
        join public.players p on p.id = reg.player_id
       where reg.clinic_id = p_clinic
         and reg.status in ('in', 'pool', 'response_needed')
      union
      select p.account_id
        from public.late_requests lr
        join public.players p on p.id = lr.player_id
        join public.accounts a on a.id = p.account_id and a.deleted_at is null
       where lr.clinic_id = p_clinic
         and lr.status = 'pending'
    loop
      perform public.notify_account(r.account_id, 'clinic_canceled', 'clinic', p_clinic,
        v.name || ' has been canceled.' || coalesce(' ' || v_msg, ''));
    end loop;
  end if;

  -- After the notices, which read the waiting requests.
  update public.late_requests
     set status = 'declined', resolved_at = now(), resolved_by = auth.uid()
   where clinic_id = p_clinic and status = 'pending';

  return v;
end; $function$;

revoke all on function public.cancel_clinic(uuid, text) from public, anon;
grant execute on function public.cancel_clinic(uuid, text) to authenticated;

create or replace function public.request_late_spot(p_clinic uuid, p_player uuid, p_message text DEFAULT NULL::text)
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
  -- 20261118000002: an archived child asks for nothing (FOR KEY SHARE,
  -- against remove_my_child's FOR UPDATE), and a child only with a
  -- signature on the current junior waiver, as register_for_clinic. An
  -- adult is unchanged.
  select kind into v_kind from public.players
   where id = p_player and (is_active or kind = 'adult')
   for key share;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  -- 20261125000002: FOR SHARE, as respond_to_invitation. A cancel in flight
  -- (an UPDATE of this row) makes the request wait and then see 'canceled';
  -- a request in flight makes the cancel wait, and the cancel's own
  -- statements then see it, tell the player and close it. Without it a
  -- request filed while Tara canceled stayed pending, untold
  -- (tests/sql/late_request_cancel_race.sh).
  select * into c from public.clinics where id = p_clinic for share;
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
$function$;

revoke all on function public.request_late_spot(uuid, uuid, text) from public, anon;
grant execute on function public.request_late_spot(uuid, uuid, text) to authenticated;
