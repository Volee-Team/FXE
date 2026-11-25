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
--   * A message of only spaces is no message: the notice reads exactly as
--     before and nothing is posted.
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
  v_msg text := nullif(btrim(coalesce(p_message, '')), '');
begin
  perform public.require_admin();

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
