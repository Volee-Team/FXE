-- Let Tara create and edit her own schedule.
--
-- Tara, 2026-08-16: "You'll need to show me how I can easily change the
-- schedule within the app as the 'super' admin of course."
--
-- She could already RUN a clinic (invite from the Player Pool, mark paid,
-- message players) and could not CREATE or EDIT one from any client. The only
-- writer was `create_clinic_from_template`, which needs a `clinic_templates`
-- row, and `clinic_templates` had no write path at all: revoked from
-- `authenticated`, no RPC, no UI. So her own weekly schedule was reachable only
-- by hand-written SQL as service role, which is the exact "no path exists yet"
-- case CLAUDE.md says to build rather than work around.
--
-- WHAT THIS ADDS
--   admin_upsert_clinic   create or edit one clinic
--   admin_upsert_template create or edit one template
--   admin_delete_template remove an unused template
--
-- DESIGN NOTES, in the order they will matter to whoever reads this next
--
-- 1. UPSERT, not separate create and update. The web admin form is the same
--    form either way, and two RPCs would drift.
--
-- 2. Registration windows are DERIVED, never typed. `member_opens_at` and
--    `public_opens_at` come from `member_opens_at(starts_at)` and
--    `public_opens_at(starts_at)`, which encode decision 0001: the window is
--    per SERVICE WEEK, not per clinic, so every clinic in one week shares one
--    pair of open moments. Tara never has to work out "the Thursday before".
--    An override is accepted for the case her own guide anticipated ("if a
--    clinic ever needs a different date"), and passing null keeps the rule.
--
-- 3. `closes_at` defaults to the clinic's START. This is the smallest honest
--    answer to a real bug: nothing has ever populated it, so registration never
--    closed and a clinic that finished nine days ago was still bookable, which
--    put real Player Pool rows in Tara's queue for events that had happened.
--    It is open question 5 in docs/whats-next.md; when she answers, change this
--    one `coalesce` and nothing else.
--
-- 4. Prices are NOT parameters. `apply_default_clinic_pricing` derives
--    member/non-member cents from clinic length (decision: 60/90 min = $18/$22
--    member, $23/$28 non-member). Letting a form overwrite that would let a
--    typo silently undercharge the club, and decision 0002 already snapshots
--    the price onto each registration so past revenue is safe either way.
--
-- 5. Editing a clinic does NOT touch its registrations. Hard rule 7 is about
--    templates snapshotting rather than referencing; this is the same instinct
--    one level down. Moving a clinic's time does not re-open its window or
--    re-price anyone already registered.
--
-- 6. Status is not settable here. `publish_clinic` and `cancel_clinic` already
--    own those transitions and both are probe-covered. A second path to
--    'canceled' that skips `cancel_clinic` would skip its notifications.

create or replace function public.admin_upsert_clinic(
  p_id                uuid          default null,
  p_name              text          default null,
  p_audience          text          default null,
  p_starts_at         timestamptz   default null,
  p_duration_minutes  int           default null,
  p_internal_capacity int           default null,
  p_category          text          default null,
  p_description       text          default null,
  p_member_opens_at   timestamptz   default null,
  p_public_opens_at   timestamptz   default null,
  p_closes_at         timestamptz   default null
) returns public.clinics
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v public.clinics;
  v_ends timestamptz;
begin
  perform public.require_admin();

  if p_id is null then
    -- CREATE. Everything the table needs and cannot invent.
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
      coalesce(p_closes_at, p_starts_at),
      p_internal_capacity, 'draft')
    returning * into v;

    return v;
  end if;

  -- EDIT. Every parameter is optional; null means "leave it alone", so the
  -- caller can change one field without resending the whole row.
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
    ends_at           = coalesce(p_starts_at, starts_at)
                        + make_interval(mins => coalesce(p_duration_minutes, duration_minutes)),
    -- Moving a clinic moves its window with it, unless the caller pins one.
    -- Silently keeping last week's open time on a rescheduled clinic is how a
    -- registration window ends up in the past.
    member_opens_at   = coalesce(p_member_opens_at,
                                 case when p_starts_at is null then member_opens_at
                                      else public.member_opens_at(p_starts_at) end),
    public_opens_at   = coalesce(p_public_opens_at,
                                 case when p_starts_at is null then public_opens_at
                                      else public.public_opens_at(p_starts_at) end),
    closes_at         = coalesce(p_closes_at,
                                 case when p_starts_at is null then closes_at
                                      else p_starts_at end),
    internal_capacity = coalesce(p_internal_capacity, internal_capacity)
  where id = p_id
  returning * into v;

  return v;
end;
$$;

comment on function public.admin_upsert_clinic is
  'Create (p_id null) or edit one clinic, admin only. Registration windows are '
  'derived from starts_at per decision 0001 unless explicitly overridden. '
  'Prices are not settable: apply_default_clinic_pricing derives them from '
  'length. Status is not settable: publish_clinic and cancel_clinic own it.';

create or replace function public.admin_upsert_template(
  p_id                uuid default null,
  p_name              text default null,
  p_audience          text default null,
  p_duration_minutes  int  default null,
  p_internal_capacity int  default null,
  p_category          text default null,
  p_description       text default null
) returns public.clinic_templates
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare t public.clinic_templates;
begin
  perform public.require_admin();

  if p_id is null then
    if p_name is null or btrim(p_name) = '' then
      raise exception 'name_required' using errcode = '22023';
    end if;
    if p_audience is null or p_duration_minutes is null or p_internal_capacity is null then
      raise exception 'missing_required_field' using errcode = '22023';
    end if;

    -- Prices computed explicitly rather than by trigger. `clinics` has
    -- apply_default_clinic_pricing; `clinic_templates` never got it, and both
    -- price columns are NOT NULL with no default. That gap was invisible for a
    -- month because NOTHING could insert a template from any client, so the
    -- first insert ever attempted was this one, and it failed. A column nobody
    -- can reach cannot prove it works.
    insert into public.clinic_templates
      (name, audience, category, description, duration_minutes, internal_capacity,
       member_price_cents, nonmember_price_cents)
    values (btrim(p_name), p_audience::public.clinic_audience,
            nullif(btrim(coalesce(p_category, '')), ''),
            nullif(btrim(coalesce(p_description, '')), ''),
            p_duration_minutes, p_internal_capacity,
            public.default_price_cents(p_duration_minutes, true),
            public.default_price_cents(p_duration_minutes, false))
    returning * into t;
    return t;
  end if;

  update public.clinic_templates set
    name              = coalesce(nullif(btrim(coalesce(p_name, '')), ''), name),
    audience          = coalesce(p_audience::public.clinic_audience, audience),
    category          = case when p_category is null then category else nullif(btrim(p_category), '') end,
    description       = case when p_description is null then description else nullif(btrim(p_description), '') end,
    duration_minutes  = coalesce(p_duration_minutes, duration_minutes),
    internal_capacity = coalesce(p_internal_capacity, internal_capacity),
    -- Price follows length. Changing a 60-minute template to 90 minutes and
    -- leaving the 60-minute price on it would quietly undercharge every clinic
    -- created from it afterwards.
    member_price_cents    = case when p_duration_minutes is null then member_price_cents
                                 else public.default_price_cents(p_duration_minutes, true) end,
    nonmember_price_cents = case when p_duration_minutes is null then nonmember_price_cents
                                 else public.default_price_cents(p_duration_minutes, false) end
  where id = p_id
  returning * into t;

  if not found then
    raise exception 'template_not_found' using errcode = 'P0002';
  end if;
  return t;
end;
$$;

-- Templates are the one thing here that may be genuinely DELETED rather than
-- archived. Hard rule 4 protects players, clinics and registrations, which are
-- records of something that happened to a person. A template is a blank form.
-- Clinics created from it keep their snapshotted values (hard rule 7), and
-- clinics.template_id is ON DELETE SET NULL, so removing one cannot orphan or
-- alter history.
create or replace function public.admin_delete_template(p_id uuid)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  delete from public.clinic_templates where id = p_id;
  if not found then
    raise exception 'template_not_found' using errcode = 'P0002';
  end if;
end;
$$;

-- Hard rule 11: revoke before grant, and from PUBLIC as well as anon. PUBLIC
-- holds EXECUTE on a new function by default, so revoking from anon alone is a
-- no-op. require_admin() is the real control; these grants are the outer door.
revoke all on function public.admin_upsert_clinic(uuid, text, text, timestamptz, int, int, text, text, timestamptz, timestamptz, timestamptz) from public, anon, authenticated;
revoke all on function public.admin_upsert_template(uuid, text, text, int, int, text, text) from public, anon, authenticated;
revoke all on function public.admin_delete_template(uuid) from public, anon, authenticated;

grant execute on function public.admin_upsert_clinic(uuid, text, text, timestamptz, int, int, text, text, timestamptz, timestamptz, timestamptz) to authenticated;
grant execute on function public.admin_upsert_template(uuid, text, text, int, int, text, text) to authenticated;
grant execute on function public.admin_delete_template(uuid) to authenticated;
