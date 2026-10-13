-- 20261012000001_tara_answers_1012.sql
--
-- Tara's answers of 2026-10-12 (decision 0040), the ones with a database
-- consequence:
--
--   106 "Yes": a button to waive a late cancel's fee (a real emergency).
--       registrations.fee_waived_at; admin_set_fee_waived turns it on or off
--       on a late cancel that holds no live charge; money_rows owes nothing
--       for a waived row, so the Charge button, the Money tab and Action
--       Needed all drop it at once (one rule, 20261002000001).
--   107 "Yes": Accept needs a saved card, as Register does, while payments
--       are on and cards are required. respond_to_invitation refuses
--       card_required before anything moves.
--   105 "Yes": the Pool's history line counts every cancel, "12 played,
--       5 canceled (2 late), 1 no-show". admin_player_history gains
--       `canceled`: every row she canceled herself (You're In! or the Pool),
--       plus every late cancel whoever marked it. Tara's plain Remove is not
--       the player's cancel and does not count.
--
-- Answers with no database change (81's red flag, 96 pros skip the waiver
-- and card, the rest as built) are in decision 0040.

-- --------------------------------------------------------- 106: waive --
alter table public.registrations add column fee_waived_at timestamptz;

comment on column public.registrations.fee_waived_at is
  'Tara waived this late cancel''s fee (question 106, decision 0040). '
  'money_rows owes nothing for it. Written only by admin_set_fee_waived.';

create or replace function public.money_rows(p_clinic uuid DEFAULT NULL::uuid)
 RETURNS TABLE(registration_id uuid, clinic_id uuid, player_id uuid, account_id uuid, owed_kind payment_kind, amount_cents integer, state text, has_card boolean, attempted_cents integer, failure_code text, failure_reason text, failed_at timestamp with time zone, failed_payment_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
  with since as (select public.payments_enabled_at() as t),
  owing as (
    select r.id, r.clinic_id, r.player_id, p.account_id, r.price_cents_charged, r.paid,
           case when r.status = 'in' and not r.no_show then 'clinic_fee'::public.payment_kind
                when r.status = 'in' and r.no_show     then 'no_show'::public.payment_kind
                when r.status = 'canceled' and r.late_cancel and not r.courtesy_used
                     -- Waived by Tara (question 106, decision 0040): owes nothing.
                     and r.fee_waived_at is null
                     and not exists (select 1 from public.registrations o
                                      where o.clinic_id = r.clinic_id
                                        and o.player_id = r.player_id
                                        and o.status = 'in')
                     -- One late fee per person per clinic: only the newest
                     -- late cancel owes (cancel, approved back in, cancel
                     -- again left two owing rows, two Charge buttons).
                     and not exists (select 1 from public.registrations l
                                      where l.clinic_id = r.clinic_id
                                        and l.player_id = r.player_id
                                        and l.status = 'canceled' and l.late_cancel and not l.courtesy_used
                                        and (l.canceled_at, l.id) > (r.canceled_at, r.id))
                  then 'late_cancel'::public.payment_kind
           end as owed_kind
      from public.registrations r
      join public.clinics c on c.id = r.clinic_id
      join public.players p on p.id = r.player_id
      cross join since s
     -- Published only: a draft Tara never published was never shown to a
     -- player and owes nothing (sql-auditor, 2026-10-04; a Copy-to-next-week
     -- draft left unpublished was chargeable once its end time passed).
     where c.status = 'published'
       and (p_clinic is null or r.clinic_id = p_clinic)
       and c.ends_at <= now()
       and s.t is not null
       and c.ends_at >= s.t
  ),
  judged as (
    select w.*,
           case
             when w.owed_kind is null then null
             when public.player_has_live_fee(w.player_id, w.clinic_id) then 'charged'
             when w.paid then 'settled'
             when exists (select 1 from public.payments x
                           where x.registration_id = w.id and x.kind = w.owed_kind
                             and x.status = 'succeeded'
                             and public.payment_is_real(x.livemode)) then 'refunded'
             when exists (select 1 from public.payments x
                           where x.registration_id = w.id and x.kind = w.owed_kind
                             and x.status = 'failed'
                             and public.payment_is_real(x.livemode)) then 'declined'
             else 'not_charged'
           end as state
      from owing w
  )
  select j.id, j.clinic_id, j.player_id, j.account_id, j.owed_kind, j.price_cents_charged,
         -- Tara's Resolved on the failed charge shown (20260928700001).
         case when j.state = 'declined' and f.resolved_at is not null then 'resolved' else j.state end,
         exists (select 1 from public.accounts a
                  where a.id = j.account_id
                    and a.stripe_customer_id is not null
                    and a.card_last4 is not null),
         f.amount_cents, f.failure_code, f.failure_reason, f.updated_at, f.id
    from judged j
    left join lateral (
      select x.id, x.amount_cents, x.failure_code, x.failure_reason, x.updated_at, x.resolved_at
        from public.payments x
       where j.state = 'declined'
         and x.registration_id = j.id and x.kind = j.owed_kind and x.status = 'failed'
         and public.payment_is_real(x.livemode)
       order by x.updated_at desc, x.created_at desc, x.id desc
       limit 1
    ) f on true;
$function$;

revoke all on function public.money_rows(uuid) from public, anon, authenticated;

create or replace function public.admin_set_fee_waived(p_registration uuid, p_waived boolean)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_clinic uuid;
  v_player uuid;
  r        public.registrations;
  v_at     timestamptz;
begin
  perform public.require_admin();
  select clinic_id, player_id into v_clinic, v_player from public.registrations where id = p_registration;
  if not found then
    raise exception 'not_waivable' using errcode = 'P0001';
  end if;
  -- The order admin_charge_player locks in: the clinic FOR SHARE, then the
  -- registration FOR UPDATE. A Charge and a Waive at the same instant are
  -- serialized, and the check below is a new statement, so it sees a charge
  -- that committed while this waited (sql-auditor, 2026-10-12: as a single
  -- UPDATE both could commit, charged and "waived").
  perform 1 from public.clinics where id = v_clinic for share;
  select * into r from public.registrations where id = p_registration for update;
  -- A late cancel, not under the old courtesy, the newest late cancel for
  -- this player and clinic (the only one money_rows can owe), and no charge
  -- pending, processing or taken for this player in this clinic (refund it
  -- first), the per-player rule money_rows uses.
  if r.status <> 'canceled' or not r.late_cancel or r.courtesy_used
     or public.player_has_live_fee(v_player, v_clinic)
     or exists (select 1 from public.registrations l
                 where l.clinic_id = v_clinic and l.player_id = v_player
                   and l.status = 'canceled' and l.late_cancel and not l.courtesy_used
                   and (l.canceled_at, l.id) > (r.canceled_at, r.id)) then
    raise exception 'not_waivable' using errcode = 'P0001';
  end if;
  update public.registrations
     set fee_waived_at = case when p_waived then coalesce(fee_waived_at, now()) end
   where id = p_registration
  returning fee_waived_at into v_at;
  return jsonb_build_object('registration_id', p_registration, 'fee_waived', v_at is not null);
end;
$$;

comment on function public.admin_set_fee_waived(uuid, boolean) is
  'Admin only. Waives (true) or restores (false) a player''s newest late cancel '
  'fee in a clinic while the player holds no live charge there (question 106, '
  'decision 0040). Locks as admin_charge_player does.';

revoke all on function public.admin_set_fee_waived(uuid, boolean) from public, anon;
grant execute on function public.admin_set_fee_waived(uuid, boolean) to authenticated;

-- admin_charge_clinic had its own copy of the owing rule, which drifted from
-- money_rows (it charged a waived fee, a draft clinic, and every late cancel
-- rather than the newest; sql-auditor, 2026-10-12). No screen calls it since
-- decision 0037, but it is granted and the Swift wrapper exists, so it now
-- charges exactly what money_rows says is owed, as admin_charge_player does.
-- Same refusals, same answer shape.
create or replace function public.admin_charge_clinic(p_clinic uuid)
returns jsonb
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  c        public.clinics;
  m        record;
  v_since  timestamptz;
  n_total  int;
  n_charged int := 0; n_already int := 0; n_no_card int := 0;
begin
  perform public.require_admin();
  if not public.payments_enabled() then
    raise exception 'payments_disabled' using errcode = 'P0001';
  end if;
  -- The clinic FOR SHARE, then its registrations FOR UPDATE: the order
  -- admin_charge_player and admin_set_fee_waived lock in.
  select * into c from public.clinics where id = p_clinic for share;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;
  if c.status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  if c.status <> 'published' then
    raise exception 'clinic_not_published' using errcode = 'P0001';
  end if;
  if c.ends_at > now() then
    raise exception 'clinic_not_over' using errcode = 'P0001';
  end if;
  v_since := public.payments_enabled_at();
  if v_since is null or c.ends_at < v_since then
    raise exception 'clinic_before_payments' using errcode = 'P0001';
  end if;

  perform 1 from public.registrations where clinic_id = p_clinic order by id for update;
  select count(*) into n_total from public.registrations where clinic_id = p_clinic;

  for m in select * from public.money_rows(p_clinic) x
            where x.owed_kind is not null and x.state in ('not_charged', 'declined', 'charged')
            order by x.registration_id
  loop
    if m.state = 'charged' then
      n_already := n_already + 1;
      continue;
    end if;
    begin
      perform public.admin_charge_registration(m.registration_id, m.owed_kind);
      n_charged := n_charged + 1;
    exception
      when others then
        if sqlerrm = 'already_charged' then n_already := n_already + 1;
        elsif sqlerrm = 'no_card_on_file' then n_no_card := n_no_card + 1;
        else raise;
        end if;
    end;
  end loop;

  return jsonb_build_object('charged', n_charged, 'already', n_already,
                            'no_card', n_no_card,
                            'not_owed', n_total - n_charged - n_already - n_no_card);
end;
$$;

revoke all on function public.admin_charge_clinic(uuid) from public, anon;
grant execute on function public.admin_charge_clinic(uuid) to authenticated;

create or replace view public.registrations_admin as
SELECT id,
    clinic_id,
    player_id,
    status,
    paid,
    court_number,
    source,
    registered_at,
    invited_at,
    responded_at,
    canceled_at,
    canceled_by,
    late_cancel,
    cancel_note,
    (EXISTS ( SELECT 1
           FROM (players p
             JOIN accounts a ON ((a.id = p.account_id)))
          WHERE ((p.id = r.player_id) AND (a.stripe_customer_id IS NOT NULL) AND (a.card_last4 IS NOT NULL)))) AS has_card,
    ( SELECT (x.status)::text AS status
           FROM payments x
          WHERE ((x.registration_id = r.id) AND (x.kind <> 'refund'::payment_kind) AND ((x.livemode IS NOT FALSE) OR (NOT (EXISTS ( SELECT 1
                   FROM app_settings s
                  WHERE (s.key = 'stripe_live_since'::text))))))
          ORDER BY x.created_at DESC
         LIMIT 1) AS charge_status,
    courtesy_used,
    no_show,
    player_note,
    fee_waived_at
   FROM registrations r
  WHERE is_admin();

revoke all on public.registrations_admin from public, anon, authenticated;
grant select on public.registrations_admin to authenticated;

-- ------------------------------------------------ 107: Accept needs a card --
create or replace function public.respond_to_invitation(p_registration uuid, p_accept boolean)
 RETURNS registrations
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v_row    public.registrations;
  v_player public.players;
  v_admin  uuid;
  v_clinic text;
  v_clinic_status clinic_status;
  v_ends  timestamptz;
  v_declined boolean;
  v_decline_code text;
  v_card   boolean;
begin
  select * into v_row from public.registrations where id = p_registration;
  if not found then
    raise exception 'registration_not_found' using errcode = 'P0002';
  end if;
  if not public.owns_player(v_row.player_id) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  -- Accepting a canceled clinic put a player in You're In! of a clinic that
  -- is not happening (backlog, 2026-09-28): the invitation's own Accept
  -- button on the lock screen never sees the clinic page's canceled banner.
  -- The clinic row is locked FOR SHARE first, so cancel_clinic (an UPDATE of
  -- that row) and this answer are serialized: whichever commits first, the
  -- other sees it. Declining a canceled clinic stays allowed; it changes
  -- nothing that matters.
  select status, ends_at into v_clinic_status, v_ends
    from public.clinics where id = v_row.clinic_id
     for share;
  if p_accept and v_clinic_status = 'canceled' then
    raise exception 'clinic_canceled' using errcode = 'P0001';
  end if;
  -- A finished clinic cannot be joined (20260928400001). Invitations never
  -- expire (hard rule 2), and since decision 0023 the Accept sits on a push
  -- that can be tapped days later: without this the player landed in You're
  -- In! of a clinic that was over and was charged at Tara's next tap. The
  -- line is the END, which nobody can argue with; whether it should be the
  -- start is question 91.
  if p_accept and v_ends <= now() then
    raise exception 'clinic_ended' using errcode = 'P0001';
  end if;
  -- Decision 0024, Tara's question 78: a declined card takes no spot, by
  -- Register or by Accept, while cards are required (the switches
  -- register_for_clinic reads). Decline stays allowed: it takes nothing.
  -- Checked before the conditional UPDATE, so nothing moves (20260928700001).
  if p_accept and not public.is_admin()
     and public.payments_enabled() and public.card_required() then
    -- Tara's question 107 (2026-10-12): "Yes", Accept needs a saved card,
    -- the same summary register_for_clinic reads (card_last4, decision 0015
    -- §5). Checked before the conditional UPDATE, so nothing moves.
    select a.stripe_customer_id is not null and a.card_last4 is not null into v_card
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = v_row.player_id;
    if not coalesce(v_card, false) then
      raise exception 'card_required' using errcode = 'P0001';
    end if;
    select a.card_declined_at is not null, a.card_decline_code into v_declined, v_decline_code
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = v_row.player_id;
    if coalesce(v_declined, false) then
      raise exception 'card_declined' using errcode = 'P0001', hint = coalesce(v_decline_code, '');
    end if;
  end if;

  update public.registrations
     set status = case when p_accept then 'in'::registration_status
                                     else 'pool'::registration_status end,
         responded_at = now()
   where id = p_registration
     and status = 'response_needed'
  returning * into v_row;

  if not found then
    raise exception 'invitation_no_longer_available' using errcode = 'P0001';
  end if;

  select * into v_player from public.players where id = v_row.player_id;
  select name, status into v_clinic, v_clinic_status from public.clinics where id = v_row.clinic_id;
  -- #13 and #14, the catalogue's wording, to every admin.
  for v_admin in select public.admin_account_ids() loop
    perform public.notify_account(
      v_admin, case when p_accept then 'invitation_accepted' else 'invitation_declined' end,
      'registration', v_row.id,
      v_player.first_name || ' ' || v_player.last_name
        || case when p_accept then ' accepted their spot in ' || v_clinic || '.'
                else ' declined ' || v_clinic || ' and is back in the Player Pool.' end);
  end loop;

  -- #3 Invitation Accepted, hers, to the player who accepted. Not #1 as well:
  -- one tap, one push (finding (e)). Not when Tara has canceled the clinic:
  -- "Your spot is confirmed" would be false (#13 still tells her). A decline
  -- sends the player nothing: it is not a first registration, so not #5
  -- (finding (i)).
  if p_accept and v_clinic_status <> 'canceled' then
    perform public.notify_account(v_player.account_id, 'invitation_accepted_player', 'registration', v_row.id,
      'Awesome! Your spot is confirmed. See you soon!');
  end if;

  -- What goes back to a player carries no court (hard rule 1, fact 6).
  if not public.is_admin() then
    v_row.court_number := null;
    v_row.canceled_by  := null;
  end if;

  return v_row;
end;
$function$;

revoke all on function public.respond_to_invitation(uuid, boolean) from public, anon;
grant execute on function public.respond_to_invitation(uuid, boolean) to authenticated;

-- ---------------------------------------------- 105: every cancel counted --
-- A new column changes the return type, so drop and create.
drop function public.admin_player_history(uuid);

create function public.admin_player_history(p_player uuid default null)
 RETURNS TABLE(player_id uuid, played integer, no_shows integer, late_cancels integer, last_played_at timestamp with time zone, canceled integer)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
-- Every column reference below is qualified: in plpgsql the RETURNS TABLE
-- names are variables, and an unqualified column of the same name would be
-- ambiguous (the board report's note, 20260926000010).
begin
  perform public.require_admin();

  return query
  with facts as (
    select r.player_id as pid,
           case
             when r.status = 'in' and c.ends_at <= now() and not r.no_show then 'played'
             when r.status = 'in' and c.ends_at <= now() and r.no_show     then 'no_show'
             when r.status = 'canceled' and r.late_cancel                   then 'late_cancel'
             -- A cancel she made herself, from You're In! or the Player Pool
             -- (question 105, decision 0040). Tara's own Remove is not hers.
             when r.status = 'canceled' and r.canceled_by = pl0.account_id   then 'canceled'
           end as kind,
           c.starts_at as clinic_starts_at
      from public.registrations r
      join public.clinics c on c.id = r.clinic_id
      join public.players pl0 on pl0.id = r.player_id
     where c.status <> 'canceled'
       and (p_player is null or r.player_id = p_player)
  )
  select pl.id,
         (count(*) filter (where f.kind = 'played'))::integer,
         (count(*) filter (where f.kind = 'no_show'))::integer,
         (count(*) filter (where f.kind = 'late_cancel'))::integer,
         max(f.clinic_starts_at) filter (where f.kind = 'played'),
         -- Every cancel, late ones included: "5 canceled (2 late)".
         (count(*) filter (where f.kind in ('canceled', 'late_cancel')))::integer
    from public.players pl
    left join facts f on f.pid = pl.id
   where p_player is null or pl.id = p_player
   group by pl.id
   order by pl.id;
end;
$function$;

revoke all on function public.admin_player_history(uuid) from public, anon;
grant execute on function public.admin_player_history(uuid) to authenticated;

comment on function public.admin_player_history(uuid) is
  'Admin only (decision 0027 §1). Per player: clinics played (the board report''s '
  'attended: You''re In!, not a no-show, clinic ended and not canceled), no-shows '
  '(the same rows, flagged), late cancellations (in a clinic not canceled), the '
  'start of the last clinic played, and every cancel (her own, from You''re In! or '
  'the Pool, plus every late cancel; decision 0040). Every player when p_player is null.';
