-- Templates can be archived, and brought back.
--
-- `clinic_templates.archived_at` has existed since 2026-08-28 and nothing
-- wrote it; the only way to retire a template was admin_delete_template,
-- which is a delete, and hard rule 4 says archive, never delete. The picker
-- grows with every season otherwise (review 09-02).
--
-- The view now carries archived_at and no longer hides archived rows: the
-- web admin filters, so a "Show archived" toggle needs no second view and a
-- restore is one click. A non-admin still sees zero rows.

create or replace view public.templates_admin as
  select id, name, audience, category, description,
         default_start_time, duration_minutes, internal_capacity,
         member_price_cents, nonmember_price_cents, created_at,
         archived_at
  from public.clinic_templates
  where public.is_admin();

comment on view public.templates_admin is
  'Clinic templates, admins only; zero rows for a non-admin. Columns listed '
  'explicitly (never select *). archived_at is present since 2026-09-10 so the '
  'client can offer Show archived and Restore; price_cents (deprecated) stays out.';

revoke all on public.templates_admin from public, anon, authenticated;
grant select on public.templates_admin to authenticated;

create or replace function public.admin_set_template_archived(p_id uuid, p_archived boolean)
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  update public.clinic_templates
     set archived_at = case when p_archived then coalesce(archived_at, now()) else null end
   where id = p_id;
  if not found then
    raise exception 'template_not_found' using errcode = 'P0002';
  end if;
end;
$$;

comment on function public.admin_set_template_archived(uuid, boolean) is
  'Admin-only. Archive (stamps archived_at once; a second archive keeps the first stamp) or restore a template.';

revoke all on function public.admin_set_template_archived(uuid, boolean) from public, anon, authenticated;
grant execute on function public.admin_set_template_archived(uuid, boolean) to authenticated;
