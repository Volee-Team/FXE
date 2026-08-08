-- FXE Tennis v1: helper functions, player-facing views, grants, RLS.
--
-- THE CENTRAL SECURITY RULE OF THIS APP:
--
--   Nine things are hidden from players: clinic capacity, number registered,
--   spots remaining, Player Pool size, other players' names, court assignments,
--   other players' payment status, private coaching notes, and clinic location.
--
-- None of that can be enforced in SwiftUI. Anyone with a network proxy reads
-- the raw JSON. So the hiding is done here, by revoking table access outright
-- and exposing narrow views instead. RLS is enabled as well, as defence in
-- depth, but the grants are the primary control: a policy bug cannot leak a
-- column the client was never granted.
--
-- Verified by tests/sql/information_hiding.sql.

-- ------------------------------------------------------- helper functions ----

-- SECURITY DEFINER so policies can call it without recursing into the table
-- they protect. search_path is pinned: without it a SECURITY DEFINER function
-- is vulnerable to search-path hijacking.
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.accounts
    where id = auth.uid() and role = 'admin'
  );
$$;

create or replace function public.owns_player(p_player uuid)
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.players
    where id = p_player and account_id = auth.uid()
  );
$$;

-- Age derived from date_of_birth, never stored. Volee learned this the hard
-- way with a stored age_group column that had to be deprecated.
create or replace function public.player_age(p_dob date)
returns integer
language sql
immutable
as $$
  select case when p_dob is null then null
              else extract(year from age(current_date, p_dob))::int end;
$$;

-- Member priority opens at 8:00 AM on the most recent Thursday STRICTLY BEFORE
-- the clinic date, in Charlotte local time. Non-members open 24 hours later.
--
-- The offset formula: isodow is 1=Mon .. 7=Sun, Thursday is 4.
--   ((isodow - 4 + 6) % 7) + 1  gives days to subtract, always >= 1.
-- Verified for all seven weekdays in tests/sql/registration_window_dates.sql.
-- Naming the zone rather than using a fixed offset is what makes DST a
-- non-issue: 8 AM stays 8 AM across both transitions.
create or replace function public.member_opens_at(p_starts_at timestamptz)
returns timestamptz
language sql
stable
as $$
  select (
    (
      (p_starts_at at time zone 'America/New_York')::date
      - ((((extract(isodow from p_starts_at at time zone 'America/New_York')::int - 4 + 6) % 7) + 1))
    )::timestamp + time '08:00'
  ) at time zone 'America/New_York';
$$;

create or replace function public.public_opens_at(p_starts_at timestamptz)
returns timestamptz
language sql
stable
as $$
  select public.member_opens_at(p_starts_at) + interval '1 day';
$$;

-- ------------------------------------------------------------- lock down ----

revoke all on public.clinics                  from anon, authenticated;
revoke all on public.registrations            from anon, authenticated;
revoke all on public.player_notes             from anon, authenticated;
revoke all on public.clinic_templates         from anon, authenticated;
revoke all on public.clinic_message_recipients from anon, authenticated;
revoke all on public.clinic_messages          from anon, authenticated;
revoke all on public.news_posts               from anon, authenticated;

-- ------------------------------------------------- player-facing surfaces ----

-- What a player is allowed to know about a clinic. internal_capacity is absent.
-- So is location, which the guide hides (every clinic is at FXE; question 10
-- to Tara). Draft clinics are invisible.
create view public.clinics_public as
  select id, name, audience, category, description, price_cents,
         starts_at, ends_at,
         member_opens_at, public_opens_at, closes_at,
         status, canceled_at
  from public.clinics
  where status in ('published', 'canceled');

-- Admin sees everything, but only if they are an admin. Non-admins get zero
-- rows rather than an error, which keeps client code simple.
create view public.clinics_admin as
  select * from public.clinics where public.is_admin();

-- A player sees their own registrations and nothing else. court_number,
-- canceled_by and source are absent: courts are admin-only by the guide, and
-- the other two are operational metadata.
create view public.my_registrations as
  select r.id, r.clinic_id, r.player_id, r.status, r.paid,
         r.registered_at, r.invited_at, r.responded_at, r.canceled_at
  from public.registrations r
  where public.owns_player(r.player_id);

create view public.registrations_admin as
  select * from public.registrations where public.is_admin();

-- Message visibility. 'everyone' reaches anyone with a live registration on the
-- clinic, including players who joined after it was sent. Targeted messages
-- reach exactly the snapshotted recipients.
create view public.my_clinic_messages as
  select m.id, m.clinic_id, m.body, m.audience, m.sent_at
  from public.clinic_messages m
  where (
    m.audience = 'everyone'
    and exists (
      select 1 from public.registrations r
      join public.players p on p.id = r.player_id
      where r.clinic_id = m.clinic_id
        and p.account_id = auth.uid()
        and r.status <> 'canceled'
    )
  )
  or exists (
    select 1 from public.clinic_message_recipients cr
    join public.players p on p.id = cr.player_id
    where cr.message_id = m.id and p.account_id = auth.uid()
  );

-- News filtered to the audiences this account can see. A parent sees junior
-- news because they receive everything for their children (guide, section 2).
create view public.my_news as
  select n.id, n.title, n.body, n.audience, n.published_at,
         (nr.read_at is not null) as is_read
  from public.news_posts n
  left join public.news_reads nr
         on nr.news_id = n.id and nr.account_id = auth.uid()
  where n.status = 'published'
    and n.archived_at is null
    and (
      n.audience = 'everyone'
      or (n.audience = 'adults' and exists (
            select 1 from public.players p
            where p.account_id = auth.uid() and p.kind = 'adult'))
      or (n.audience = 'juniors' and exists (
            select 1 from public.players p
            where p.account_id = auth.uid() and p.kind = 'junior'))
    );

grant select on public.clinics_public       to authenticated;
grant select on public.clinics_admin        to authenticated;
grant select on public.my_registrations     to authenticated;
grant select on public.registrations_admin  to authenticated;
grant select on public.my_clinic_messages   to authenticated;
grant select on public.my_news              to authenticated;

-- --------------------------------------------------- RLS (defence in depth) ----

alter table public.accounts       enable row level security;
alter table public.players        enable row level security;
alter table public.player_notes   enable row level security;
alter table public.clinics        enable row level security;
alter table public.registrations  enable row level security;
alter table public.news_reads     enable row level security;
alter table public.notifications  enable row level security;
alter table public.devices        enable row level security;
alter table public.clinic_messages enable row level security;
alter table public.clinic_templates enable row level security;
alter table public.news_posts     enable row level security;
alter table public.clinic_message_recipients enable row level security;

create policy accounts_self on public.accounts
  for select using (id = auth.uid() or public.is_admin());
create policy accounts_update_self on public.accounts
  for update using (id = auth.uid() or public.is_admin());

create policy players_own on public.players
  for select using (account_id = auth.uid() or public.is_admin());
create policy players_insert_own on public.players
  for insert with check (account_id = auth.uid() or public.is_admin());
create policy players_update_own on public.players
  for update using (account_id = auth.uid() or public.is_admin());

-- Notes are admin-only, full stop. No player policy exists.
create policy notes_admin on public.player_notes
  for all using (public.is_admin()) with check (public.is_admin());

create policy clinics_admin_all on public.clinics
  for all using (public.is_admin()) with check (public.is_admin());

create policy registrations_own on public.registrations
  for select using (public.owns_player(player_id) or public.is_admin());

create policy news_reads_own on public.news_reads
  for all using (account_id = auth.uid()) with check (account_id = auth.uid());

create policy notifications_own on public.notifications
  for select using (account_id = auth.uid());
create policy notifications_update_own on public.notifications
  for update using (account_id = auth.uid());

create policy devices_own on public.devices
  for all using (account_id = auth.uid()) with check (account_id = auth.uid());

create policy templates_admin on public.clinic_templates
  for all using (public.is_admin()) with check (public.is_admin());
create policy messages_admin on public.clinic_messages
  for all using (public.is_admin()) with check (public.is_admin());
create policy recipients_admin on public.clinic_message_recipients
  for all using (public.is_admin()) with check (public.is_admin());
create policy news_admin on public.news_posts
  for all using (public.is_admin()) with check (public.is_admin());
