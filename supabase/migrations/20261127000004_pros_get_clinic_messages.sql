-- 20261127000004_pros_get_clinic_messages.sql
--
-- Tara, via John, 2026-11-27: "every pro sees every clinic message".
-- No table links a pro to the clinics they coach, so every pro (accounts with
-- role 'pro', not deleted) is told of every message Tara sends to a clinic:
--
--   * send_clinic_message: after the players its audience names, every pro,
--     once; a pro already told as a player on the clinic is not told twice.
--     Not an Unpaid message: decision 0025, a pro never sees money, and
--     "hasn't been paid yet" names the clinic. Not a clinic that was never
--     published (as cancel_clinic: nobody is told about a draft). Private
--     clinics included: Tara's "every" (decision 0062 amended).
--     One player's message (admin_message_player) stays between Tara and
--     that player.
--   * Each account is told once per message (20261127000004): a parent with
--     two children on a clinic got two notices; the recipient rows stay one
--     per player.
--   * Not the cancel notice: John, 2026-11-27, "drop" (pros see a canceled
--     clinic in their week; cancel_clinic is unchanged).
--
-- Body copied from 20261107000002; only the marked lines differ. Pinned by
-- tests/sql/pros_get_clinic_messages.sql.

create or replace function public.send_clinic_message(p_clinic uuid, p_audience message_audience, p_body text)
 returns clinic_messages
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare m public.clinic_messages; r record;
  v_told uuid[] := '{}';  -- 20261127000004: accounts already told
  v_published boolean;    -- 20261127000004
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
    -- 20261127000004: one notice per account, not per player.
    if not (r.account_id = any (v_told)) then
      perform public.notify_account(r.account_id, 'clinic_message', 'clinic', p_clinic, p_body);
      v_told := v_told || r.account_id;
    end if;
  end loop;

  -- 20261127000004: every pro gets every clinic message (Tara, via John,
  -- 2026-11-27: "every pro sees every clinic message"), once per account; a
  -- pro already told as a player is not told twice. Not Unpaid (a pro never
  -- sees money, decision 0025), not a draft, not a deleted account.
  select published_at is not null into v_published from public.clinics where id = p_clinic;
  if coalesce(v_published, false) and p_audience <> 'unpaid' then
    for r in
      select a.id as account_id
        from public.accounts a
       where a.role::text = 'pro' and a.deleted_at is null
         and not (a.id = any (v_told))
    loop
      perform public.notify_account(r.account_id, 'clinic_message', 'clinic', p_clinic, p_body);
    end loop;
  end if;

  return m;
end;
$function$;

revoke all on function public.send_clinic_message(uuid, message_audience, text) from public, anon;
grant execute on function public.send_clinic_message(uuid, message_audience, text) to authenticated;
