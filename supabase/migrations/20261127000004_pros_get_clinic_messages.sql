-- 20261127000004_pros_get_clinic_messages.sql
--
-- Tara, via John, 2026-11-27: "every pro sees every clinic message".
-- No table links a pro to the clinics they coach, so every pro (accounts with
-- role 'pro', not deleted) is told of every message Tara sends to a clinic:
--
--   * send_clinic_message: after the players its audience names, every pro,
--     once, whatever the audience; a pro already told as a player on the
--     clinic is not told twice. One player's message (admin_message_player)
--     stays between Tara and that player.
--   * cancel_clinic: the cancel notice, with her message when she wrote one,
--     goes to every pro as well (a clinic that was never published still
--     tells nobody).
--
-- Bodies copied from 20261107000002 (send_clinic_message) and 20261125000002
-- (cancel_clinic); only the marked lines differ. Pinned by
-- tests/sql/pros_get_clinic_messages.sql.

create or replace function public.send_clinic_message(p_clinic uuid, p_audience message_audience, p_body text)
 returns clinic_messages
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare m public.clinic_messages; r record; v_told uuid[] := '{}';
begin
  perform public.require_admin();
  if p_audience::text = 'player' then
    raise exception 'invalid_audience' using errcode = 'P0001';
  end if;

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
    v_told := v_told || r.account_id;
  end loop;

  -- 20261127000004: every pro gets every clinic message (Tara, via John,
  -- 2026-11-27: "every pro sees every clinic message"), whatever its
  -- audience, once per account; a pro already told as a player is not told
  -- twice. A deleted account is not told.
  for r in
    select a.id as account_id
      from public.accounts a
     where a.role::text = 'pro' and a.deleted_at is null
       and not (a.id = any (v_told))
  loop
    perform public.notify_account(r.account_id, 'clinic_message', 'clinic', p_clinic, p_body);
  end loop;

  return m;
end;
$function$;

revoke all on function public.send_clinic_message(uuid, message_audience, text) from public, anon;
grant execute on function public.send_clinic_message(uuid, message_audience, text) to authenticated;

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
      -- 20261127000004: every pro, with her message (the same notice).
      union
      select a.id
        from public.accounts a
       where a.role::text = 'pro' and a.deleted_at is null
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
