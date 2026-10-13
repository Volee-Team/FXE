-- 20261013000001_audit_fixes.sql
--
-- Two full error audits of 2026-10-12 (player side; Tara and money), the
-- fixes with a database half:
--
--   1. A clinic's length changed on the laptop kept the old length's price,
--      so Charge took $18 for a 90-minute clinic (critical). admin_upsert_clinic
--      reprices from default_price_cents when the length changes, the rule the
--      template editor already follows. Registrations keep their snapshot
--      until Tara answers question 113.
--   2. cancel_clinic left charges queued for the clinic, which the next
--      stripe-charge run sent. It now cancels the clinic's pending charges
--      that have not reached Stripe; refunds still go.
--   3. my_past_clinics listed Player Pool spots never picked and invitations
--      never answered as played. Only You're In! and canceled rows now, and
--      a clinic Tara canceled says so (clinic_canceled).

create or replace function public.admin_upsert_clinic(p_id uuid DEFAULT NULL::uuid, p_name text DEFAULT NULL::text, p_audience text DEFAULT NULL::text, p_starts_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_duration_minutes integer DEFAULT NULL::integer, p_internal_capacity integer DEFAULT NULL::integer, p_category text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_member_opens_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_public_opens_at timestamp with time zone DEFAULT NULL::timestamp with time zone, p_closes_at timestamp with time zone DEFAULT NULL::timestamp with time zone)
 RETURNS clinics
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare
  v public.clinics;
  v_ends timestamptz;
begin
  perform public.require_admin();

  if p_id is null then
    if p_name is null or btrim(p_name) = '' then
      raise exception 'name_required' using errcode = '22023';
    end if;
    if p_audience is null or p_starts_at is null
       or p_duration_minutes is null or p_internal_capacity is null then
      raise exception 'missing_required_field' using errcode = '22023';
    end if;
    if p_duration_minutes <= 0 then
      raise exception 'duration_must_be_positive' using errcode = '22023';
    end if;
    if p_internal_capacity <= 0 then
      raise exception 'capacity_must_be_positive' using errcode = '22023';
    end if;

    v_ends := p_starts_at + make_interval(mins => p_duration_minutes);

    insert into public.clinics (
      name, audience, category, description,
      starts_at, ends_at, duration_minutes,
      member_opens_at, public_opens_at, closes_at,
      internal_capacity, status)
    values (
      btrim(p_name), p_audience::public.clinic_audience,
      nullif(btrim(coalesce(p_category, '')), ''),
      nullif(btrim(coalesce(p_description, '')), ''),
      p_starts_at, v_ends, p_duration_minutes,
      coalesce(p_member_opens_at, public.member_opens_at(p_starts_at)),
      coalesce(p_public_opens_at, public.public_opens_at(p_starts_at)),
      coalesce(p_closes_at, public.default_closes_at(p_starts_at)),
      p_internal_capacity, 'draft')
    returning * into v;

    return v;
  end if;

  select * into v from public.clinics where id = p_id;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;

  if p_duration_minutes is not null and p_duration_minutes <= 0 then
    raise exception 'duration_must_be_positive' using errcode = '22023';
  end if;
  if p_internal_capacity is not null and p_internal_capacity <= 0 then
    raise exception 'capacity_must_be_positive' using errcode = '22023';
  end if;

  update public.clinics set
    name              = coalesce(nullif(btrim(coalesce(p_name, '')), ''), name),
    audience          = coalesce(p_audience::public.clinic_audience, audience),
    category          = case when p_category is null then category
                             else nullif(btrim(p_category), '') end,
    description       = case when p_description is null then description
                             else nullif(btrim(p_description), '') end,
    starts_at         = coalesce(p_starts_at, starts_at),
    duration_minutes  = coalesce(p_duration_minutes, duration_minutes),
    -- A new length takes the price for that length from her table, as the
    -- template editor already does (audit 2026-10-12: a 60 edited to 90 kept
    -- $18 and Charge took $18). People already in keep the price they signed
    -- up at (registrations snapshot it) until Tara answers question 113.
    member_price_cents    = case when p_duration_minutes is not null and p_duration_minutes <> duration_minutes
                                 then public.default_price_cents(p_duration_minutes, true) else member_price_cents end,
    nonmember_price_cents = case when p_duration_minutes is not null and p_duration_minutes <> duration_minutes
                                 then public.default_price_cents(p_duration_minutes, false) else nonmember_price_cents end,
    ends_at           = coalesce(p_starts_at, starts_at)
                        + make_interval(mins => coalesce(p_duration_minutes, duration_minutes)),
    member_opens_at   = coalesce(p_member_opens_at,
                                 case when p_starts_at is null then member_opens_at
                                      else public.member_opens_at(p_starts_at) end),
    public_opens_at   = coalesce(p_public_opens_at,
                                 case when p_starts_at is null then public_opens_at
                                      else public.public_opens_at(p_starts_at) end),
    -- Rescheduling moves the close with the clinic, same as the open windows.
    closes_at         = coalesce(p_closes_at,
                                 case when p_starts_at is null then closes_at
                                      else public.default_closes_at(p_starts_at) end),
    internal_capacity = coalesce(p_internal_capacity, internal_capacity)
  where id = p_id
  returning * into v;

  return v;
end;
$function$;

revoke all on function public.admin_upsert_clinic(uuid, text, text, timestamptz, integer, integer, text, text, timestamptz, timestamptz, timestamptz) from public, anon;
grant execute on function public.admin_upsert_clinic(uuid, text, text, timestamptz, integer, integer, text, text, timestamptz, timestamptz, timestamptz) to authenticated;

create or replace function public.cancel_clinic(p_clinic uuid)
 RETURNS clinics
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
declare v public.clinics; r record;
begin
  perform public.require_admin();

  update public.clinics set status = 'canceled', canceled_at = now()
   where id = p_clinic and status <> 'canceled'
  returning * into v;
  if not found then
    raise exception 'already_canceled' using errcode = 'P0001';
  end if;

  -- A rained-out clinic owes nothing: charges queued for it and not yet
  -- sent to Stripe are canceled with it (audit 2026-10-12: the next Charge
  -- tap anywhere, or opening the Money tab, would have sent them). A refund
  -- still goes through; a charge already with Stripe is refunded by hand.
  update public.payments p
     set status = 'canceled', failure_reason = 'clinic_canceled', updated_at = now()
    from public.registrations reg
   where reg.id = p.registration_id and reg.clinic_id = p_clinic
     and p.status = 'pending' and p.kind <> 'refund'
     and p.stripe_payment_intent_id is null;

  -- Nobody is told about a clinic that was never published.
  if v.published_at is not null then
    for r in
      select distinct p.account_id
        from public.registrations reg
        join public.players p on p.id = reg.player_id
       where reg.clinic_id = p_clinic
         and reg.status in ('in', 'pool', 'response_needed')
    loop
      perform public.notify_account(r.account_id, 'clinic_canceled', 'clinic', p_clinic,
        v.name || ' has been canceled.');
    end loop;
  end if;

  return v;
end; $function$;

revoke all on function public.cancel_clinic(uuid) from public, anon;
grant execute on function public.cancel_clinic(uuid) to authenticated;

create or replace view public.my_past_clinics as
SELECT r.id AS registration_id,
    c.id AS clinic_id,
    c.name,
    c.starts_at,
    c.ends_at,
    c.duration_minutes,
    c.category,
    c.audience,
    r.status,
    r.no_show,
    r.late_cancel,
    r.canceled_at,
    r.price_cents_charged,
    r.paid,
    (c.status = 'canceled'::clinic_status) AS clinic_canceled
   FROM (registrations r
     JOIN clinics c ON ((c.id = r.clinic_id)))
  WHERE (owns_player(r.player_id)
     -- Only spots she held or gave up: a Player Pool spot never picked or an
     -- invitation never answered is not a clinic she played (audit 2026-10-12:
     -- it read "Played, $18").
     AND r.status IN ('in'::registration_status, 'canceled'::registration_status) AND ((c.status = 'published'::clinic_status) OR ((c.status = 'canceled'::clinic_status) AND (c.published_at IS NOT NULL))) AND (c.ends_at <= now()));

revoke all on public.my_past_clinics from public, anon, authenticated;
grant select on public.my_past_clinics to authenticated;
