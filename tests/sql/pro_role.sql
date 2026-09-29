-- pro_role.sql
--
-- The pro role (decision 0025, migration 20260928600001). Written FROM THE
-- RULE, Tara's words, not from the functions:
--
--   2026-09-28 (decision 0024): "For right now, I'm going to be the only one
--   that sees everything. Let the pros see who is coming to the clinics that
--   day. I don't want the pros to invite people from the player pool. See
--   anything financial at all."
--   2026-09-22 (decision 0016): the pros "are not allowed to have capabilities
--   to charge people but can label them as no show, late cancellation, and
--   see the clinic list."
--
-- THE RULE, as checked below (check names start with the rule's number):
--   r1  Tara is the only admin. A pro is not an admin.
--   r2  A pro sees today's clinics (the New York date), published and not
--       canceled, and who is You're In! in each: first and last name and
--       court, the no-show and late-cancel flags, and the ids to act on.
--       Nothing else: never the Player Pool, Response Needed or a canceled
--       row, never another day, a draft or a canceled clinic, and no price,
--       paid, charge, card, note, phone, email, rating, membership or
--       capacity. A clinic nobody is in yet is still seen.
--   r3  A pro marks Came / No-show and a late cancellation, on today's
--       clinics only, under Tara's own guards, and is never told who was
--       charged: once Tara has charged a clinic, every row of it answers a
--       pro alike (clinic_locked), charged or not.
--   r4  A pro never invites, places, removes, messages, sets a court, edits a
--       clinic, reads the directory or sees money: every admin RPC refuses a
--       pro, every admin view is empty to one, and a pro reads exactly what a
--       member reads from every table and view a client can read.
--   r5  Only Tara changes a role, only between member and pro, never an
--       admin's, a deleted account's or her own. No other path can change a
--       role, and a pro cannot change anyone's, their own included.
--   r6  A deleted pro is no longer a pro.
--   r7  A member gets none of the pro's three functions.
--   r8  Tara keeps everything she had: no-show and late cancel on any day,
--       with her refusal words unchanged, and she is not a pro.
--   r9  anon holds nothing new, and no client can call the internal helpers.
--
-- This probe ATTACKS (hard rule 9): every refusal is followed by a read of the
-- resulting state as the owner, because a blocked UPDATE can affect zero rows
-- and raise nothing. It enumerates the admin surface from the catalog rather
-- than listing it, so an admin function or view added next month is attacked
-- before anyone remembers to add it here.
--
-- Time of day: every fixture clinic is placed relative to now() or to New
-- York's calendar date, so the checks mean the same thing at any hour, and
-- two sit at 22:30 New York (tonight, last night), when the UTC date has
-- already turned, so a "today" computed in the wrong zone is caught at every
-- hour, not only after 20:00 (the sql-auditor, 2026-09-28). The seed's
-- Today Drill is moved to today inside the transaction, so the seed checks do
-- not depend on the day of the last reset, and the seeded pro is made a pro
-- again inside it, so a committed change to her role fails one row (r0)
-- instead of aborting the file.
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;
-- What one account can read from every client-readable relation, as a pro and
-- then as a member (r4).
create temporary table _reads (relname text, pass text, n text) on commit drop;
grant all on _reads to authenticated;

-- Runs one statement as the current role; 'ok', or the error's own words.
create function pg_temp.try(p_sql text) returns text language plpgsql as $$
begin
  execute p_sql;
  return 'ok';
exception when others then
  return sqlerrm;
end $$;

-- Row count of one relation as the current role, or the error's words.
create function pg_temp.rows_in(p_rel text) returns text language plpgsql as $$
declare n bigint;
begin
  execute format('select count(*) from public.%I', p_rel) into n;
  return n::text;
exception when others then
  return 'ERROR ' || sqlerrm;
end $$;

create function pg_temp.act_as(p_account uuid) returns void language plpgsql as $$
begin
  perform set_config('request.jwt.claims', json_build_object('sub', p_account)::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

create function pg_temp.as_owner() returns void language plpgsql as $$
begin
  perform set_config('role', 'postgres', true);
end $$;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  CASEY   constant uuid := '77777777-7777-7777-7777-777777777777';   -- the seeded pro
  THEO    constant uuid := '99999999-9999-9999-9999-999999999999';
  ADMIN2  constant uuid := '12121212-1212-1212-1212-121212121212';   -- a second admin, made here
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  LENA_P  constant uuid := 'a0000000-0000-0000-0000-000000000007';
  THEO_P  constant uuid := 'a0000000-0000-0000-0000-000000000008';
  TODAY_DRILL constant uuid := 'd0000000-0000-0000-0000-000000000006';
  ny      constant text := 'America/New_York';
  today   date := (now() at time zone 'America/New_York')::date;
  c_today uuid; c_tomorrow uuid; c_yesterday uuid; c_draft uuid; c_canceled uuid;
  c_empty uuid; c_soon uuid; c_charged uuid; c_tonight uuid; c_last_night uuid;
  r_priya_charged uuid; r_rob_tonight uuid; r_maria_last_night uuid;
  r_maria uuid; r_ken uuid; r_lena uuid; r_dana_pool uuid; r_rob_rn uuid; r_priya_gone uuid;
  r_maria_tomorrow uuid; r_ken_yesterday uuid; r_dana_draft uuid; r_rob_canceled uuid;
  r_theo_pool uuid; r_dana_soon uuid;
  f record; v text; n int; n_fns int := 0; n_views int := 0;
begin
  -- ------------------------------------------------------------ r0, the seed
  -- What the seed committed, read as the owner: this row can fail without
  -- stopping the file. Then the pro is made a pro again inside this
  -- transaction, through Tara's own switch, and the Today Drill moved to
  -- today, so everything below reads the same whatever happened since the
  -- last reset.
  select role::text into v from public.accounts where id = CASEY;
  insert into _probe_result values ('r0_seed_made_casey_a_pro', 'pro', coalesce(v, 'NO ROW'));
  perform pg_temp.act_as(TARA);
  perform public.admin_set_pro(CASEY, true);
  perform pg_temp.as_owner();
  update public.clinics
     set starts_at = (today + time '00:30') at time zone ny,
         ends_at   = (today + time '01:30') at time zone ny
   where id = TODAY_DRILL;

  -- ------------------------------------------------------------ fixtures
  -- Today's clinic starts at now(), which is today in New York by definition,
  -- and is inside the 3-hour cutoff, so a late cancel is allowed on it.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Today', 'coed', 'Clinic', 'probe', now(), now() + interval '1 hour',
          now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
  returning id into c_today;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Tomorrow', 'coed', 'Clinic', 'probe',
          (today + 1 + time '12:00') at time zone ny, (today + 1 + time '13:00') at time zone ny,
          now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
  returning id into c_tomorrow;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Yesterday', 'coed', 'Clinic', 'probe',
          (today - 1 + time '12:00') at time zone ny, (today - 1 + time '13:00') at time zone ny,
          now() - interval '4 days', now() - interval '3 days', 8, 'published', 60)
  returning id into c_yesterday;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Draft', 'coed', 'Clinic', 'probe', now(), now() + interval '1 hour',
          now() - interval '3 days', now() - interval '2 days', 8, 'draft', 60)
  returning id into c_draft;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, canceled_at)
  values ('Probe Pro Rained Out', 'coed', 'Clinic', 'probe', now(), now() + interval '1 hour',
          now() - interval '3 days', now() - interval '2 days', 8, 'canceled', 60, now())
  returning id into c_canceled;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Nobody Yet', 'coed', 'Clinic', 'probe', now(), now() + interval '1 hour',
          now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
  returning id into c_empty;
  -- A clinic Tara has charged: Lena's fee went through, Priya has none.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Charged', 'coed', 'Clinic', 'probe', now(), now() + interval '1 hour',
          now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
  returning id into c_charged;
  -- 22:30 New York tonight and last night: the UTC date has already turned
  -- at both, so only the New York date puts them on the right side of today.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Tonight', 'coed', 'Clinic', 'probe',
          (today + time '22:30') at time zone ny, (today + time '23:30') at time zone ny,
          now() - interval '4 days', now() - interval '3 days', 8, 'published', 60)
  returning id into c_tonight;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Last Night', 'coed', 'Clinic', 'probe',
          (today - 1 + time '22:30') at time zone ny, (today - 1 + time '23:30') at time zone ny,
          now() - interval '4 days', now() - interval '3 days', 8, 'published', 60)
  returning id into c_last_night;

  -- Probe Pro Today: Maria court 3, Ken no court; Dana in the Player Pool,
  -- Rob invited, Priya already canceled.
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, court_number)
  values (c_today, MARIA_P, 'in', 'self', 1800, true, 60, 3) returning id into r_maria;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_today, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_today, DANA_P, 'pool', 'self', 1800, true, 60) returning id into r_dana_pool;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, invited_at)
  values (c_today, ROB_P, 'response_needed', 'self', 2300, false, 60, now()) returning id into r_rob_rn;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, canceled_at)
  values (c_today, PRIYA_P, 'canceled', 'self', 2300, false, 60, now()) returning id into r_priya_gone;
  -- Probe Pro Charged: Lena court 1 with a fee that went through, Priya
  -- court 2 with none (no card, say).
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, court_number)
  values (c_charged, LENA_P, 'in', 'self', 1800, true, 60, 1) returning id into r_lena;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, court_number)
  values (c_charged, PRIYA_P, 'in', 'self', 2300, false, 60, 2) returning id into r_priya_charged;
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, livemode, stripe_payment_intent_id)
  values (r_lena, '88888888-8888-8888-8888-888888888888', 'clinic_fee', 1800, 'succeeded', true, 'pi_probe_pro_role');
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_tonight, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_rob_tonight;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_last_night, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r_maria_last_night;

  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_tomorrow, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r_maria_tomorrow;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_yesterday, KEN_P, 'in', 'self', 1800, true, 60) returning id into r_ken_yesterday;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_draft, DANA_P, 'in', 'self', 1800, true, 60) returning id into r_dana_draft;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_canceled, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_rob_canceled;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_empty, THEO_P, 'pool', 'self', 2300, false, 60) returning id into r_theo_pool;

  -- A second admin, for r5.
  insert into auth.users (id, email, instance_id, aud, role)
  values (ADMIN2, 'admin2@probe.test', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated');
  insert into public.accounts (id, first_name, last_name, email, role)
  values (ADMIN2, 'Second', 'Admin', 'admin2@probe.test', 'admin');

  -- ------------------------------------------------------ r1, identity
  perform pg_temp.act_as(CASEY);
  insert into _probe_result values ('r1_pro_is_a_pro', 'true', public.is_pro()::text);
  insert into _probe_result values ('r1_pro_is_not_an_admin', 'false', public.is_admin()::text);

  -- --------------------------------------------------- r2, what a pro sees
  -- The contract is the column list. Allowlist, exact and in order.
  perform pg_temp.as_owner();
  select string_agg(a.n, ',' order by a.i) into v
    from unnest((select p.proargnames from pg_proc p where p.oid = 'public.pro_today()'::regprocedure))
         with ordinality as a(n, i);
  insert into _probe_result values ('r2_pro_today_columns_exactly',
    'clinic_id,clinic_name,starts_at,ends_at,registration_id,first_name,last_name,court_number,no_show,late_cancel', v);
  -- The same list read the other way: nothing named like a hidden fact.
  select coalesce(string_agg(a.n, ','), '') into v
    from unnest((select p.proargnames from pg_proc p where p.oid = 'public.pro_today()'::regprocedure)) a(n)
   where a.n ~ '(price|paid|charge|cent|card|stripe|note|phone|email|member|pool|capacity|rating|level|location|address|source|courtesy)';
  insert into _probe_result values ('r2_pro_today_names_no_hidden_fact', '', v);

  perform pg_temp.act_as(CASEY);
  select (count(*) filter (where clinic_id = c_today) > 0)::text || '|'
         || (count(*) filter (where clinic_id = c_empty) > 0)::text || '|'
         || (count(*) filter (where clinic_id = c_charged) > 0)::text
    into v from public.pro_today();
  insert into _probe_result values ('r2_pro_today_lists_todays_published_clinics', 'true|true|true', v);
  select (count(*) filter (where clinic_id = c_tonight) > 0)::text || '|'
         || (count(*) filter (where clinic_id = c_last_night) > 0)::text
    into v from public.pro_today();
  insert into _probe_result values ('r2_today_is_new_yorks_date_tonight_yes_last_night_no', 'true|false', v);
  select count(*)::text into v from public.pro_today()
   where clinic_id in (c_tomorrow, c_yesterday, c_draft, c_canceled, c_last_night);
  insert into _probe_result values ('r2_pro_today_omits_other_days_drafts_and_canceled', '0', v);
  -- You're In! only, in court order (no court last): Maria 3, then Ken.
  select string_agg(first_name || ' ' || last_name || '|' || coalesce(court_number::text, ''), ','
                    order by court_number nulls last, last_name)
    into v from public.pro_today() where clinic_id = c_today;
  insert into _probe_result values ('r2_pro_today_youre_in_only_by_court',
    'Maria Alvarez|3,Ken Whitfield|', v);
  select count(*)::text into v from public.pro_today()
   where registration_id in (r_dana_pool, r_rob_rn, r_priya_gone, r_theo_pool);
  insert into _probe_result values ('r2_pro_today_never_pool_invited_or_canceled_rows', '0', v);
  select (registration_id = r_maria)::text || '|' || court_number || '|' || no_show || '|' || late_cancel
    into v from public.pro_today() where registration_id = r_maria;
  insert into _probe_result values ('r2_pro_today_row_values', 'true|3|false|false', v);
  -- A clinic with only a Pool entry is one row with nobody in it.
  select count(*)::text || '|' || coalesce(max(registration_id::text), '')
    into v from public.pro_today() where clinic_id = c_empty;
  insert into _probe_result values ('r2_pro_today_clinic_nobody_is_in_yet', '1|', v);
  -- Belt and braces on values: no email or phone anywhere in any row.
  select count(*)::text into v from public.pro_today() t where row_to_json(t)::text ~ '(@|704-555)';
  insert into _probe_result values ('r2_pro_today_carries_no_email_or_phone', '0', v);
  -- The seed's Today Drill, which ProFlowUITests reads (on the reset's day).
  select coalesce(string_agg(first_name || ' ' || last_name || '|' || coalesce(court_number::text, ''), ','
                    order by court_number nulls last, last_name), '')
    into v from public.pro_today() where clinic_id = TODAY_DRILL;
  insert into _probe_result values ('r2_seed_today_drill_on_pro_today', 'Lena Brooks|1,Theo Grant|', v);

  -- ---------------------------------- r3, the pro's two marks, today only
  insert into _probe_result values ('r3_pro_marks_no_show_call', 'ok',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_maria)));
  perform pg_temp.as_owner();
  select no_show::text into v from public.registrations where id = r_maria;
  insert into _probe_result values ('r3_pro_marks_no_show_today', 'true', v);
  perform pg_temp.act_as(CASEY);
  select no_show::text into v from public.pro_today() where registration_id = r_maria;
  insert into _probe_result values ('r3_pro_today_shows_the_no_show', 'true', v);
  perform public.pro_set_no_show(r_maria, false);
  perform pg_temp.as_owner();
  select no_show::text into v from public.registrations where id = r_maria;
  insert into _probe_result values ('r3_pro_marks_came_today', 'false', v);

  perform pg_temp.act_as(CASEY);
  insert into _probe_result values ('r3_pro_late_cancel_call', 'ok',
    pg_temp.try(format('select public.pro_mark_late_cancel(%L, %L)', r_ken, 'Texted the pro')));
  perform pg_temp.as_owner();
  select status::text || '|' || late_cancel || '|' || canceled_by || '|' || coalesce(cancel_note, '')
    into v from public.registrations where id = r_ken;
  insert into _probe_result values ('r3_pro_late_cancel_today_recorded',
    'canceled|true|77777777-7777-7777-7777-777777777777|Texted the pro', v);
  perform pg_temp.act_as(CASEY);
  select string_agg(first_name || ' ' || last_name, ',' order by court_number nulls last, last_name)
    into v from public.pro_today() where clinic_id = c_today;
  insert into _probe_result values ('r3_late_cancel_leaves_youre_in', 'Maria Alvarez', v);
  -- Tonight's 22:30 clinic is markable; last night's is not.
  insert into _probe_result values ('r3_pro_marks_tonight', 'ok',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_rob_tonight)));
  insert into _probe_result values ('r3_pro_refused_last_night', 'not_today',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_maria_last_night)));

  -- Any other day, a draft, a canceled clinic, a row that is not You're In!,
  -- an id that does not exist: refused, and nothing moved.
  insert into _probe_result values ('r3_pro_no_show_tomorrow_refused', 'not_today',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_maria_tomorrow)));
  insert into _probe_result values ('r3_pro_late_cancel_yesterday_refused', 'not_today',
    pg_temp.try(format('select public.pro_mark_late_cancel(%L, null)', r_ken_yesterday)));
  insert into _probe_result values ('r3_pro_no_show_draft_refused', 'not_today',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_dana_draft)));
  insert into _probe_result values ('r3_pro_no_show_canceled_clinic_refused', 'clinic_canceled',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_rob_canceled)));
  insert into _probe_result values ('r3_pro_no_show_pool_row_refused', 'registration_not_in',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_dana_pool)));
  insert into _probe_result values ('r3_pro_late_cancel_invited_row_refused', 'registration_not_in',
    pg_temp.try(format('select public.pro_mark_late_cancel(%L, null)', r_rob_rn)));
  insert into _probe_result values ('r3_pro_unknown_registration_refused', 'not_today',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', gen_random_uuid())));
  perform pg_temp.as_owner();
  select string_agg(r.status::text || ':' || r.no_show, ',' order by r.id = r_maria_tomorrow desc, r.id = r_ken_yesterday desc,
                    r.id = r_dana_draft desc, r.id = r_rob_canceled desc, r.id = r_dana_pool desc)
    into v from public.registrations r
   where r.id in (r_maria_tomorrow, r_ken_yesterday, r_dana_draft, r_rob_canceled, r_dana_pool, r_rob_rn);
  insert into _probe_result values ('r3_refusals_moved_nothing',
    'in:false,in:false,in:false,in:false,pool:false,response_needed:false', v);

  -- A clinic Tara has charged: every row answers alike, so no answer tells a
  -- pro who was charged. The first version refused only Lena's row (under
  -- another name), which was the leak (the sql-auditor, 2026-09-28). The
  -- property is the check: Lena's answer equals Priya's, re-saving the value
  -- each already shows (Came), which changes nothing either way.
  perform pg_temp.act_as(CASEY);
  select pg_temp.try(format('select public.pro_set_no_show(%L, false)', r_lena)) = pg_temp.try(format('select public.pro_set_no_show(%L, false)', r_priya_charged))
    into v;
  insert into _probe_result values ('r3_charged_and_uncharged_rows_answer_alike', 'true', v);
  insert into _probe_result values ('r3_charged_clinic_refuses_an_uncharged_row', 'clinic_locked',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_priya_charged)));
  insert into _probe_result values ('r3_charged_clinic_refuses_the_charged_row', 'clinic_locked',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_lena)));
  insert into _probe_result values ('r3_charged_clinic_refuses_late_cancels', 'clinic_locked|clinic_locked',
    pg_temp.try(format('select public.pro_mark_late_cancel(%L, null)', r_lena)) || '|'
    || pg_temp.try(format('select public.pro_mark_late_cancel(%L, null)', r_priya_charged)));
  perform pg_temp.as_owner();
  select string_agg(status::text || ':' || no_show, ',' order by id = r_lena desc) into v
    from public.registrations where id in (r_lena, r_priya_charged);
  insert into _probe_result values ('r3_charged_clinic_unchanged', 'in:false,in:false', v);

  -- Tara's guard comes with it: with her cutoff at 0 hours, a clinic starting
  -- a microsecond from now is not late yet (the setting rolls back).
  update public.app_settings set value = '0' where key = 'cancel_cutoff_hours';
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Pro Soon', 'coed', 'Clinic', 'probe', now() + interval '1 microsecond', now() + interval '1 hour',
          now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
  returning id into c_soon;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_soon, DANA_P, 'in', 'self', 1800, true, 60) returning id into r_dana_soon;
  perform pg_temp.act_as(CASEY);
  insert into _probe_result values ('r3_pro_late_cancel_not_late_yet', 'not_late_yet',
    pg_temp.try(format('select public.pro_mark_late_cancel(%L, null)', r_dana_soon)));
  perform pg_temp.as_owner();
  update public.app_settings set value = '3' where key = 'cancel_cutoff_hours';

  -- ------------------------------------ r4, the admin surface, enumerated
  -- Every function a client may call whose body asks is_admin() or
  -- require_admin(), called by the pro with null arguments. The gate comes
  -- first in each, so the refusal is the only possible answer; anything else
  -- is a hole or a guard in the wrong place, and both are worth a red row.
  -- Keyed on is_admin() as well as require_admin(), so an admin function
  -- rewritten as "if not (is_admin() or is_pro())" stays in the list and
  -- goes red, instead of quietly leaving it. The exceptions are the five a
  -- member may call that merely have an admin branch; each has its own
  -- outcome check below, and a sixth added later turns this red until it is
  -- named here (the same forcing function as grants_are_explicit's list).
  for f in
    select p.oid, p.proname,
           format('select * from public.%I(%s)', p.proname,
                  coalesce((select string_agg('null::' || format_type(t, null), ', ' order by o)
                              from unnest(p.proargtypes::oid[]) with ordinality as a(t, o)), '')) as call
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.prokind = 'f'
       and p.prosrc ~ '(require_admin|is_admin)\(\)'
       and p.proname not in ('require_admin', 'cancel_registration', 'register_for_clinic',
                             'respond_to_invitation', 'my_courtesy_available', 'revenue_summary')
       and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     order by p.proname
  loop
    n_fns := n_fns + 1;
    perform pg_temp.act_as(CASEY);
    v := pg_temp.try(f.call);
    perform pg_temp.as_owner();
    insert into _probe_result values ('r4_pro_refused_by_' || f.proname, 'not_authorized', v);
  end loop;
  insert into _probe_result values ('r4_admin_functions_enumerated', 'true', (n_fns >= 30)::text);

  -- Every view that filters on is_admin() is empty to a pro.
  for f in
    select c.relname from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public' and c.relkind in ('v', 'm')
       and pg_get_viewdef(c.oid) ~ 'is_admin\(\)'
     order by c.relname
  loop
    n_views := n_views + 1;
    perform pg_temp.act_as(CASEY);
    v := pg_temp.rows_in(f.relname);
    perform pg_temp.as_owner();
    insert into _probe_result values ('r4_pro_sees_nothing_in_' || f.relname, '0', v);
  end loop;
  insert into _probe_result values ('r4_admin_views_enumerated', 'true', (n_views >= 6)::text);
  -- Not vacuous: Tara sees rows in the two views a roster is built from.
  perform pg_temp.act_as(TARA);
  select ((select count(*) from public.clinics_admin) > 0 and (select count(*) from public.registrations_admin) > 0)::text
    into v;
  insert into _probe_result values ('r4_tara_sees_rows_in_the_admin_views', 'true', v);

  -- Member-callable functions with an admin branch: a pro is a member there.
  perform pg_temp.act_as(CASEY);
  select expected_cents::text || '|' || total_players into v from public.revenue_summary();
  insert into _probe_result values ('r4_pro_revenue_summary_is_zero', '0|0', v);
  v := pg_temp.try(format('select public.cancel_registration(%L)', r_maria));
  v := pg_temp.try(format('select public.register_for_clinic(%L, %L)', c_empty, MARIA_P));
  v := pg_temp.try(format('select public.respond_to_invitation(%L, true)', r_rob_rn));
  perform pg_temp.as_owner();
  select (select status::text from public.registrations where id = r_maria) || '|'
      || (select count(*) from public.registrations where clinic_id = c_empty and player_id = MARIA_P) || '|'
      || (select status::text from public.registrations where id = r_rob_rn)
    into v;
  insert into _probe_result values ('r4_pro_cannot_remove_place_or_accept_for_others', 'in|0|response_needed', v);
  perform pg_temp.act_as(CASEY);
  insert into _probe_result values ('r4_pro_refused_another_players_courtesy', 'not_authorized',
    pg_temp.try(format('select public.my_courtesy_available(%L)', MARIA_P)));
  perform pg_temp.as_owner();

  -- The other direction: a pro's power can only come from something that
  -- asks is_pro() (or require_pro, or compares a role to 'pro'). Those are
  -- exactly the declared functions, and no policy or view at all. A new one
  -- anywhere turns this red until someone decides, in this file, that it
  -- belongs.
  select coalesce(string_agg(x, ', ' order by x), '') into v from (
    select 'function ' || p.proname as x
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public'
       and p.prosrc ~ '(is_pro\(|require_pro|''pro'')'
       and p.proname not in ('is_pro', 'require_pro', 'require_pro_today', 'pro_today',
                             'pro_set_no_show', 'pro_mark_late_cancel', 'admin_set_pro',
                             'guard_account_privilege_columns')
    union all
    select 'policy ' || pol.tablename || '.' || pol.policyname
      from pg_policies pol
     where pol.schemaname = 'public'
       and (coalesce(pol.qual, '') || ' ' || coalesce(pol.with_check, '')) ~ '(is_pro|''pro'')'
    union all
    select 'view ' || c.relname
      from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public' and c.relkind in ('v', 'm')
       and pg_get_viewdef(c.oid) ~ '(is_pro|''pro'')'
  ) offenders;
  insert into _probe_result values ('r4_pro_power_only_in_the_declared_functions', '', v);
  -- The two-value habit: "role <> 'member'" meant admin while there were two
  -- roles, and now lets a pro in without naming one. Nothing may read it so.
  select coalesce(string_agg(x, ', ' order by x), '') into v from (
    select 'function ' || p.proname as x
      from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
     where ns.nspname = 'public' and p.prosrc ~* 'role(::text)?\s*(<>|!=)\s*''member'''
    union all
    select 'policy ' || pol.tablename || '.' || pol.policyname
      from pg_policies pol
     where pol.schemaname = 'public'
       and (coalesce(pol.qual, '') || ' ' || coalesce(pol.with_check, '')) ~* 'role(::text)?\s*(<>|!=)\s*''member'''
    union all
    select 'view ' || c.relname
      from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public' and c.relkind in ('v', 'm')
       and pg_get_viewdef(c.oid) ~* 'role(::text)?\s*(<>|!=)\s*''member'''
  ) offenders;
  insert into _probe_result values ('r4_no_code_reads_role_as_two_values', '', v);

  -- A pro reads exactly what a member reads. Every relation a client may
  -- SELECT, counted as Casey the pro, then as Casey the member (Tara flips
  -- her), then compared. A policy or view that ever grants pros a row more
  -- turns this red.
  -- has_any_column_privilege, not has_table_privilege: notifications is
  -- readable through column grants only (20260923000001), and the first
  -- version of this check never counted it. Found red-first, 2026-09-28: a
  -- policy letting pros read every notification left this check green.
  perform pg_temp.act_as(CASEY);
  for f in
    select c.relname from pg_class c join pg_namespace ns on ns.oid = c.relnamespace
     where ns.nspname = 'public' and c.relkind in ('r', 'v', 'm', 'p', 'f')
       and has_any_column_privilege('authenticated', c.oid, 'SELECT')
     order by c.relname
  loop
    insert into _reads values (f.relname, 'pro', pg_temp.rows_in(f.relname));
  end loop;
  perform pg_temp.act_as(TARA);
  perform public.admin_set_pro(CASEY, false);
  perform pg_temp.act_as(CASEY);
  for f in select distinct relname from _reads loop
    insert into _reads values (f.relname, 'member', pg_temp.rows_in(f.relname));
  end loop;
  perform pg_temp.act_as(TARA);
  perform public.admin_set_pro(CASEY, true);
  perform pg_temp.as_owner();
  select coalesce(string_agg(a.relname || ' ' || a.n || '/' || b.n, ', ' order by a.relname), '') into v
    from _reads a join _reads b on b.relname = a.relname and b.pass = 'member'
   where a.pass = 'pro' and a.n is distinct from b.n;
  insert into _probe_result values ('r4_pro_reads_exactly_what_a_member_reads', '', v);
  select (count(distinct relname) >= 15)::text into v from _reads;
  insert into _probe_result values ('r4_client_readable_relations_enumerated', 'true', v);

  -- ------------------------------------------------ r5, who changes a role
  -- A pro, at the table and through the RPC.
  perform pg_temp.act_as(CASEY);
  v := pg_temp.try(format('update public.accounts set role = %L where id = %L', 'admin', CASEY));
  v := pg_temp.try(format('update public.accounts set role = %L where id = %L', 'member', CASEY));
  v := pg_temp.try(format('update public.accounts set role = %L where id = %L', 'pro', MARIA));
  v := pg_temp.try(format('update public.accounts set role = %L where id = %L', 'member', TARA));
  insert into _probe_result values ('r5_pro_cannot_unmake_self_by_rpc', 'not_authorized',
    pg_temp.try(format('select public.admin_set_pro(%L, false)', CASEY)));
  insert into _probe_result values ('r5_pro_cannot_make_a_member_pro', 'not_authorized',
    pg_temp.try(format('select public.admin_set_pro(%L, true)', MARIA)));
  perform pg_temp.as_owner();
  select string_agg(role::text, ',' order by id = CASEY desc, id = MARIA desc) into v
    from public.accounts where id in (CASEY, MARIA, TARA);
  insert into _probe_result values ('r5_pro_attacks_changed_no_role', 'pro,member,admin', v);

  -- A member, at the table and through the RPC.
  perform pg_temp.act_as(MARIA);
  v := pg_temp.try(format('update public.accounts set role = %L where id = %L', 'pro', MARIA));
  insert into _probe_result values ('r5_member_cannot_make_self_pro', 'not_authorized',
    pg_temp.try(format('select public.admin_set_pro(%L, true)', MARIA)));
  perform pg_temp.as_owner();
  select role::text into v from public.accounts where id = MARIA;
  insert into _probe_result values ('r5_member_attacks_changed_no_role', 'member', v);
  insert into _probe_result values ('r5_role_column_not_client_writable', 'false',
    has_column_privilege('authenticated', 'public.accounts', 'role', 'UPDATE')::text);

  -- Tara: member <-> pro, and nothing else.
  perform pg_temp.act_as(TARA);
  insert into _probe_result values ('r5_tara_makes_a_member_pro', 'pro',
    (select public.admin_set_pro(MARIA, true)));
  perform pg_temp.act_as(MARIA);
  select public.is_pro()::text || '|' || (select count(*) > 0 from public.pro_today()) into v;
  insert into _probe_result values ('r5_new_pro_gets_the_today_read', 'true|true', v);
  perform pg_temp.act_as(TARA);
  insert into _probe_result values ('r5_tara_makes_a_pro_member_again', 'member',
    (select public.admin_set_pro(MARIA, false)));
  perform pg_temp.act_as(MARIA);
  insert into _probe_result values ('r5_former_pro_refused', 'not_authorized',
    pg_temp.try('select * from public.pro_today()'));
  perform pg_temp.act_as(TARA);
  insert into _probe_result values ('r5_setting_the_same_state_again_is_fine', 'pro',
    (select public.admin_set_pro(CASEY, true)));
  insert into _probe_result values ('r5_tara_cannot_change_herself', 'cannot_change_own_role',
    pg_temp.try(format('select public.admin_set_pro(%L, false)', TARA)));
  insert into _probe_result values ('r5_tara_cannot_make_herself_pro', 'cannot_change_own_role',
    pg_temp.try(format('select public.admin_set_pro(%L, true)', TARA)));
  insert into _probe_result values ('r5_tara_cannot_demote_an_admin', 'cannot_change_an_admin',
    pg_temp.try(format('select public.admin_set_pro(%L, false)', ADMIN2)));
  insert into _probe_result values ('r5_tara_cannot_make_an_admin_pro', 'cannot_change_an_admin',
    pg_temp.try(format('select public.admin_set_pro(%L, true)', ADMIN2)));
  insert into _probe_result values ('r5_unknown_account_refused', 'account_not_found',
    pg_temp.try(format('select public.admin_set_pro(%L, true)', gen_random_uuid())));
  insert into _probe_result values ('r5_null_choice_refused', 'invalid_argument',
    pg_temp.try(format('select public.admin_set_pro(%L, null)', THEO)));
  perform pg_temp.as_owner();
  update public.accounts set deleted_at = now() where id = THEO;
  perform pg_temp.act_as(TARA);
  insert into _probe_result values ('r5_deleted_account_refused', 'account_deleted',
    pg_temp.try(format('select public.admin_set_pro(%L, true)', THEO)));
  perform pg_temp.as_owner();
  select string_agg(role::text, ',' order by id = TARA desc, id = ADMIN2 desc) into v
    from public.accounts where id in (TARA, ADMIN2, THEO);
  insert into _probe_result values ('r5_refusals_changed_no_role', 'admin,admin,member', v);

  -- The trigger, for the code path nobody has written yet: even running as
  -- the owner with Tara's identity (what a future SECURITY DEFINER function
  -- would be), a role moves only between member and pro.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  insert into _probe_result values ('r5_backstop_refuses_pro_to_admin', 'only_member_and_pro_may_change',
    pg_temp.try(format('update public.accounts set role = %L where id = %L', 'admin', CASEY)));
  insert into _probe_result values ('r5_backstop_refuses_admin_to_member', 'only_member_and_pro_may_change',
    pg_temp.try(format('update public.accounts set role = %L where id = %L', 'member', ADMIN2)));
  insert into _probe_result values ('r5_backstop_refuses_demoting_tara', 'only_member_and_pro_may_change',
    pg_temp.try(format('update public.accounts set role = %L where id = %L', 'pro', TARA)));
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  insert into _probe_result values ('r5_backstop_still_refuses_non_admins', 'only_an_admin_may_change_a_role',
    pg_temp.try(format('update public.accounts set role = %L where id = %L', 'pro', MARIA)));
  select string_agg(role::text, ',' order by id = CASEY desc, id = ADMIN2 desc, id = TARA desc) into v
    from public.accounts where id in (CASEY, ADMIN2, TARA, MARIA);
  insert into _probe_result values ('r5_backstop_changed_no_role', 'pro,admin,admin,member', v);

  -- ------------------------------------------------------------ r7, a member
  perform pg_temp.act_as(MARIA);
  insert into _probe_result values ('r7_member_is_not_a_pro', 'false', public.is_pro()::text);
  insert into _probe_result values ('r7_member_refused_pro_today', 'not_authorized',
    pg_temp.try('select * from public.pro_today()'));
  insert into _probe_result values ('r7_member_cannot_mark_own_no_show', 'not_authorized',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_maria)));
  insert into _probe_result values ('r7_member_cannot_mark_own_late_cancel', 'not_authorized',
    pg_temp.try(format('select public.pro_mark_late_cancel(%L, null)', r_maria)));
  perform pg_temp.as_owner();
  select status::text || ':' || no_show into v from public.registrations where id = r_maria;
  insert into _probe_result values ('r7_member_attempts_moved_nothing', 'in:false', v);

  -- ------------------------------------------- r8, Tara keeps everything
  perform pg_temp.act_as(TARA);
  insert into _probe_result values ('r8_tara_no_show_on_another_day', 'ok',
    pg_temp.try(format('select public.admin_set_no_show(%L, true)', r_maria_tomorrow)));
  insert into _probe_result values ('r8_tara_late_cancel_on_another_day', 'ok',
    pg_temp.try(format('select public.admin_mark_late_cancel(%L, %L)', r_ken_yesterday, 'Called Tara')));
  insert into _probe_result values ('r8_tara_still_told_charged_refund_first', 'charged_refund_first',
    pg_temp.try(format('select public.admin_set_no_show(%L, true)', r_lena)));
  insert into _probe_result values ('r8_tara_is_not_a_pro', 'false', public.is_pro()::text);
  insert into _probe_result values ('r8_tara_does_not_need_today', 'not_authorized',
    pg_temp.try('select * from public.pro_today()'));
  perform pg_temp.as_owner();
  select (select no_show::text from public.registrations where id = r_maria_tomorrow) || '|'
      || (select status::text || ':' || late_cancel || ':' || canceled_by from public.registrations where id = r_ken_yesterday)
    into v;
  insert into _probe_result values ('r8_tara_changes_landed',
    'true|canceled:true:11111111-1111-1111-1111-111111111111', v);

  -- ------------------------------------------------ r6, a deleted pro, last
  update public.accounts set deleted_at = now() where id = CASEY;
  perform pg_temp.act_as(CASEY);
  insert into _probe_result values ('r6_deleted_pro_is_not_a_pro', 'false', public.is_pro()::text);
  insert into _probe_result values ('r6_deleted_pro_refused_pro_today', 'not_authorized',
    pg_temp.try('select * from public.pro_today()'));
  insert into _probe_result values ('r6_deleted_pro_refused_no_show', 'not_authorized',
    pg_temp.try(format('select public.pro_set_no_show(%L, true)', r_maria)));
  perform pg_temp.as_owner();
  select no_show::text into v from public.registrations where id = r_maria;
  insert into _probe_result values ('r6_deleted_pro_moved_nothing', 'false', v);

  -- ------------------------------------------------------------ r9, grants
  select coalesce(string_agg(p.proname, ', ' order by p.proname), '') into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('new_york_date', 'is_pro', 'require_pro', 'require_pro_today', 'pro_today',
                       'pro_set_no_show', 'pro_mark_late_cancel', 'admin_set_pro',
                       'registration_set_no_show', 'registration_mark_late_cancel', 'pro_clinic_locked')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('r9_anon_executes_none_of_it', '', v);
  select coalesce(string_agg(p.proname, ', ' order by p.proname), '') into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('require_pro_today', 'registration_set_no_show', 'registration_mark_late_cancel', 'pro_clinic_locked')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE');
  insert into _probe_result values ('r9_no_client_calls_the_internal_helpers', '', v);
  select coalesce(string_agg(p.proname, ', ' order by p.proname), '') into v
    from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public'
     and p.proname in ('is_pro', 'pro_today', 'pro_set_no_show', 'pro_mark_late_cancel', 'admin_set_pro')
     and not has_function_privilege('authenticated', p.oid, 'EXECUTE');
  insert into _probe_result values ('r9_signed_in_clients_can_call_the_rpcs', '', v);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
