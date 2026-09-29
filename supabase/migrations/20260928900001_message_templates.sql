-- 20260928900001_message_templates.sql
--
-- TARA'S SAVED MESSAGES (decision 0030). Roadmap, "Tara's tools" (2026-09-28):
-- "Her saved messages: sentences she sends often, kept in her words, sent in
-- one tap."
--
-- The app stores what she typed and offers it back. It never suggests,
-- completes or writes one (hard rule 13): there is no seed row, no default
-- and no server-side text anywhere in this file. Sending is unchanged: a
-- saved message only fills the box, and the send still goes through
-- send_clinic_message with the audience she picks, resolved by the database.
--
-- WHAT IS STORED. The text as she typed it, minus the whitespace at its two
-- ends (spaces, tabs, newlines), so "See you at 9 " and "See you at 9" are one
-- saved message rather than two that look identical in the list. Nothing
-- inside the text is touched: not case, not punctuation, not a double space.
--
-- KEPT ONCE, WITHOUT A RACE. A unique index on md5(body) over the live rows
-- decides "the same text twice", so two saves at the same moment (the phone
-- and the laptop, or a double click) cannot both insert: the second waits for
-- the first to commit and then finds its row. md5 rather than the text itself
-- because a btree entry is capped near 2.7 kB and 1000 characters of accented
-- or emoji text can be 4 kB. Pinned by message_template_race.sh, which is red
-- with a check-then-insert in place of the index.
--
-- REMOVE ARCHIVES (hard rule 4). archived_at is stamped once, by a conditional
-- update: a second Remove (another tab, the phone) changes nothing and answers
-- false. The row stays. Saving the same words again later is a new live row,
-- because the index covers live rows only.
--
-- WHO. Tara only: every function opens with require_admin(), so a member is
-- refused, and so is a pro (the pro role on branch pro-role keeps is_admin()
-- false for a pro; message_templates.sql loops over every non-admin value of
-- account_role, so the pro is attacked the day that branch merges). No client
-- role holds anything on the table (hard rule 11: revoke before grant); the
-- functions are the only door.

-- ----------------------------------------------------------------- table ----

create table public.message_templates (
  id          uuid        primary key default gen_random_uuid(),
  body        text        not null,
  created_at  timestamptz not null default now(),
  archived_at timestamptz,
  -- The spec's check was length(trim(body)) between 1 and 1000. trim() strips
  -- spaces only, so a body of one newline passed it. This is the stricter
  -- form: what is stored is already trimmed of all ASCII whitespace at both
  -- ends, and is 1 to 1000 characters (characters, not bytes: length() on
  -- text). It is also the backstop for any writer that is not the function.
  constraint message_templates_body_trimmed_1_to_1000
    check (body = btrim(body, E' \t\n\r') and length(body) between 1 and 1000)
);

comment on table public.message_templates is
  'Tara''s saved messages (decision 0030): text she typed, kept to fill the clinic '
  'message box again. Admin-only through admin_message_templates, '
  'admin_save_message_template and admin_archive_message_template; no client role '
  'holds a privilege. Remove stamps archived_at (hard rule 4).';

-- One live copy of any text. Partial, so a removed message never blocks
-- saving the same words again.
create unique index message_templates_one_live_copy
  on public.message_templates (md5(body))
  where archived_at is null;

alter table public.message_templates enable row level security;
-- No policy on purpose: no client role reaches the table, and the three
-- SECURITY DEFINER functions below run as the owner, whom RLS does not bind
-- (it is not forced). A policy would be a second door with nothing behind it.

-- Hard rule 11: revoke before grant, then grant exactly what is needed.
revoke all on public.message_templates from public, anon, authenticated;
-- The platform's trusted role holds DML on every table (20260912000002;
-- grants_are_explicit.sql asserts it). The default privilege already gives
-- it; written here because a grant nobody wrote can be taken away (2026-08-19).
grant select, insert, update, delete on public.message_templates to service_role;

-- ------------------------------------------------------------- functions ----

-- The live saved messages, newest first. created_at is now() of the saving
-- transaction, so two saved in one transaction tie; id breaks the tie so the
-- order is the same on every read.
create or replace function public.admin_message_templates()
returns setof public.message_templates
language plpgsql
stable
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
    select t.*
      from public.message_templates t
     where t.archived_at is null
     order by t.created_at desc, t.id desc;
end;
$$;

comment on function public.admin_message_templates() is
  'Admin-only. Tara''s live saved messages, newest first (decision 0030).';

-- Keep the text for next time. Returns the live row for that text: the new
-- one, or the one already there (the same text twice is kept once).
create or replace function public.admin_save_message_template(p_body text)
returns public.message_templates
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_body text := btrim(coalesce(p_body, ''), E' \t\n\r');
  v_row  public.message_templates;
begin
  perform public.require_admin();

  if v_body = '' then
    raise exception 'message_empty' using errcode = '22023';
  end if;
  if length(v_body) > 1000 then
    raise exception 'message_too_long' using errcode = '22001';
  end if;

  -- The index decides. A concurrent save of the same text makes this insert
  -- wait for that transaction, then do nothing and read the row it made. The
  -- only way the read can miss is a Remove of that live copy between the two
  -- statements; then the next pass inserts. Bounded, so a case nobody
  -- foresaw (an md5 collision between two different texts) raises instead of
  -- spinning.
  for i in 1..3 loop
    insert into public.message_templates (body) values (v_body)
      on conflict (md5(body)) where archived_at is null do nothing
      returning * into v_row;
    if found then
      return v_row;
    end if;

    select * into v_row
      from public.message_templates t
     where md5(t.body) = md5(v_body) and t.body = v_body and t.archived_at is null;
    if found then
      return v_row;
    end if;
  end loop;

  raise exception 'message_save_conflict' using errcode = '40001';
end;
$$;

comment on function public.admin_save_message_template(text) is
  'Admin-only. Saves the text (trimmed at both ends, 1 to 1000 characters) as a '
  'saved message, or returns the live row already holding it (decision 0030). '
  'message_empty (22023), message_too_long (22001).';

-- Remove: stamp archived_at once. True when this call removed it, false when
-- it was already removed (someone got there first, hard rule 3: the list is
-- reloaded and it is gone, which is the truth). An id that was never a saved
-- message is message_template_not_found, because that is a bug in the caller.
create or replace function public.admin_archive_message_template(p_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();

  update public.message_templates
     set archived_at = now()
   where id = p_id
     and archived_at is null;
  if found then
    return true;
  end if;

  if not exists (select 1 from public.message_templates where id = p_id) then
    raise exception 'message_template_not_found' using errcode = 'P0002';
  end if;
  return false;
end;
$$;

comment on function public.admin_archive_message_template(uuid) is
  'Admin-only. Remove a saved message: stamps archived_at once (conditional '
  'update); false when it was already removed; the row is kept (hard rule 4).';

-- Every new function is born with PUBLIC EXECUTE, and anon inherits it:
-- revoke from public and anon, not anon alone (hard rule 11, 20260902000001).
revoke all on function public.admin_message_templates()                from public, anon, authenticated;
revoke all on function public.admin_save_message_template(text)        from public, anon, authenticated;
revoke all on function public.admin_archive_message_template(uuid)     from public, anon, authenticated;
grant execute on function public.admin_message_templates()             to authenticated;
grant execute on function public.admin_save_message_template(text)     to authenticated;
grant execute on function public.admin_archive_message_template(uuid)  to authenticated;
