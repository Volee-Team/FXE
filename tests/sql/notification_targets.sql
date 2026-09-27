-- notification_targets.sql
--
-- A notification is only useful if tapping it opens the thing it is about.
-- Every row names that thing in two columns, entity_type and entity_id, and
-- the app opens exactly two kinds (FXETennis/App/NotificationRouter.swift):
--
--   'clinic'        a clinic id
--   'registration'  a registration id, resolved with the RECIPIENT's grants:
--                   a player through my_registrations, Tara through
--                   registrations_admin (her rows are about other people)
--
-- Earned 2026-09-27 (MVP audit item 12). invite_from_pool has written
-- 'registration' since July; the bell opened only 'clinic', so "A spot opened
-- in ... Accept or decline." opened nothing. seed.sql typed that invitation as
-- 'clinic', so the one invitation any test could see hid the bug. Expected
-- values below come from the rule, worked out by hand, not from the code.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  SEED_C  constant uuid := 'd0000000-0000-0000-0000-000000000005';
  pc uuid; reg uuid; ent uuid; n int; v text;
begin
  -- Fixture: a clinic three weeks out, open to everyone, and Ken in its Pool.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Targets', 'coed', 'Clinic', 'probe', now() + interval '20 days', now() + interval '20 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into pc;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (pc, KEN_P, 'pool', 'self', 1800, true, 60) returning id into reg;

  -- ------------------------------------------------ 1. Tara invites Ken
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.invite_from_pool(reg);
  perform set_config('role', 'postgres', true);

  select count(*) into n from public.notifications where account_id = KEN and type = 'invitation_received';
  insert into _probe_result values ('invite_notifies_the_invited_player_once', '1', n::text);
  select entity_type, entity_id into v, ent from public.notifications
   where account_id = KEN and type = 'invitation_received';
  insert into _probe_result values ('invite_names_a_registration', 'registration', coalesce(v, 'null'));
  insert into _probe_result values ('invite_names_the_registration_itself', reg::text, coalesce(ent::text, 'null'));

  -- Ken opens it with his own grants: his registration, then the clinic.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  select clinic_id::text into v from public.my_registrations where id = ent;
  insert into _probe_result values ('invite_resolves_for_the_player', pc::text, coalesce(v, 'no row'));
  select count(*) into n from public.clinics_public where id = pc;
  insert into _probe_result values ('invited_clinic_is_open_to_the_player', '1', n::text);

  -- Hard rule 1: nobody else can turn Ken's registration into a clinic.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  select count(*) into n from public.my_registrations where id = ent;
  insert into _probe_result values ('another_player_cannot_resolve_it', '0', n::text);

  -- --------------------------------------------- 2. Ken accepts: Tara's row
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform public.respond_to_invitation(reg, true);
  perform set_config('role', 'postgres', true);

  select type || ' ' || entity_type || ' ' || entity_id into v from public.notifications
   where account_id = TARA and type = 'invitation_accepted' and entity_id = reg;
  insert into _probe_result values ('accept_names_the_registration_to_tara',
    'invitation_accepted registration ' || reg, coalesce(v, 'no row'));

  -- Tara's rows are about other people, so her own registrations cannot
  -- open them; her roster can. This is why the app has a second branch.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select count(*) into n from public.my_registrations where id = reg;
  insert into _probe_result values ('tara_cannot_open_it_as_her_own', '0', n::text);
  select clinic_id::text into v from public.registrations_admin where id = reg;
  insert into _probe_result values ('tara_resolves_it_through_her_roster', pc::text, coalesce(v, 'no row'));
  select count(*) into n from public.clinics_admin where id = pc;
  insert into _probe_result values ('tara_reads_the_clinic', '1', n::text);

  -- -------------------------------- 3. Ken cancels: still a registration
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform public.cancel_registration(reg, null);
  perform set_config('role', 'postgres', true);
  select type || ' ' || entity_type || ' ' || entity_id into v from public.notifications
   where account_id = TARA and type = 'player_canceled' and entity_id = reg;
  insert into _probe_result values ('cancel_names_the_registration_to_tara',
    'player_canceled registration ' || reg, coalesce(v, 'no row'));
  -- Archive, never delete (hard rule 4): the canceled row still opens.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  select clinic_id::text into v from public.registrations_admin where id = reg;
  insert into _probe_result values ('a_canceled_registration_still_resolves', pc::text, coalesce(v, 'no row'));
  perform set_config('role', 'postgres', true);

  -- ------------------------- 4. the seed's invitation is the producer's own
  select entity_type || ' ' || entity_id into v from public.notifications
   where account_id = MARIA and type = 'invitation_received';
  insert into _probe_result values ('seed_invitation_is_a_registration',
    'registration e0000000-0000-0000-0000-000000000001', coalesce(v, 'no row'));
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  select r.clinic_id::text into v
    from public.notifications nt join public.my_registrations r on r.id = nt.entity_id
   where nt.type = 'invitation_received';
  insert into _probe_result values ('seed_invitation_resolves_for_maria', SEED_C::text, coalesce(v, 'no row'));
  perform set_config('role', 'postgres', true);

  -- ----------------- 5. every row points at something its recipient may open
  -- Counted after the producers above ran, so their rows are included.
  select count(*) into n from public.notifications nt
   where not (
         (nt.entity_type = 'clinic' and exists (select 1 from public.clinics c where c.id = nt.entity_id))
      or (nt.entity_type = 'registration' and exists (
            select 1 from public.registrations r join public.players p on p.id = r.player_id
             where r.id = nt.entity_id
               and (p.account_id = nt.account_id
                    or exists (select 1 from public.accounts a where a.id = nt.account_id and a.role = 'admin')))));
  insert into _probe_result values ('every_row_points_at_something_its_recipient_may_open', '0', n::text);
end $$;

-- ------------------------------------------------ 6. every producer, enumerated
-- Enumerate, never list: every function that calls notify_account() must name
-- one of the two entity types the app opens, as a literal. A new producer with
-- a third kind turns this red, which is the moment to teach NotificationRouter
-- to open it.
--
-- The actual is the list of OTHER kinds, expected empty, so the comparison is
-- exact. It used to be the list of all kinds against 'clinic,registration',
-- and the harness's substring rule (expected has a letter) then passed any
-- superset whose extra kind sorted outside the pair: a producer naming
-- 'account' or 'waiver' read 'account,clinic,registration', which contains
-- the expected text. Only a kind sorting between the two, like 'payment',
-- went red (verify, 2026-09-27). An empty list is not vacuous: the next
-- check goes red if this pattern stops matching the calls.
with calls as (
  select p.proname, m[1] as entity
    from pg_proc p, regexp_matches(p.prosrc, 'notify_account\s*\(\s*[^,]+,\s*[^,]+,\s*''([^'']*)''', 'g') m
   where p.pronamespace = 'public'::regnamespace
)
insert into _probe_result
select 'every_producer_names_clinic_or_registration', '',
       coalesce(string_agg(distinct entity, ',' order by entity)
                  filter (where entity not in ('clinic', 'registration')), '')
  from calls;

with every_call as (
  select p.proname
    from pg_proc p, regexp_matches(p.prosrc, 'notify_account\s*\(', 'g') m
   where p.pronamespace = 'public'::regnamespace and p.proname <> 'notify_account'
), literal_calls as (
  select p.proname
    from pg_proc p, regexp_matches(p.prosrc, 'notify_account\s*\(\s*[^,]+,\s*[^,]+,\s*''([^'']*)''', 'g') m
   where p.pronamespace = 'public'::regnamespace
)
insert into _probe_result
select 'every_producer_passes_its_entity_as_a_literal', '0',
       ((select count(*) from every_call) - (select count(*) from literal_calls))::text;

-- Not vacuous: the seven producers that exist today are the ones found.
insert into _probe_result
select 'the_seven_known_producers_are_found', '7', count(*)::text
  from unnest(array['cancel_clinic', 'cancel_registration', 'invite_from_pool', 'request_late_spot',
                    'resolve_late_request', 'respond_to_invitation', 'send_clinic_message']) k
 where exists (select 1 from pg_proc p
                where p.pronamespace = 'public'::regnamespace and p.proname = k
                  and p.prosrc ~ 'notify_account\s*\(');

select check_name, expected, actual,
       case when actual = expected
              or (expected ~ '[a-z]' and actual like '%' || expected || '%')
            then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
