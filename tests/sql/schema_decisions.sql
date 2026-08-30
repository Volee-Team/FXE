-- schema_decisions.sql
--
-- Tara's answered decisions of 2026-08-02, pinned in the schema.
--
-- These are not invariants the database would enforce on its own. They are
-- product decisions that a well-meaning future session could reverse in a
-- single line, each time believing it was tidying up: dropping the unused
-- 'juniors' enum value, adding an index to the category column "since we filter
-- on it", restoring a notifications-off flag because a design doc still
-- mentions one, correcting Tara's lower-case "zelle".
--
-- Every check here exists because the reversal is plausible.
--
-- Expected: every row of the final result reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;

-- ----------------------------------------------------- decision 8: audience --
--
-- v1 UI offers ladies / men / coed. 'juniors' stays in the enum because juniors
-- return in the fall and Postgres has no DROP VALUE: removing it means a full
-- type rewrite, twice.
insert into _probe_result
select 'audience_enum_still_has_juniors', '1', count(*)::text
  from pg_enum e join pg_type t on t.oid = e.enumtypid
 where t.typname = 'clinic_audience' and e.enumlabel = 'juniors';

insert into _probe_result
select 'audience_enum_has_the_three_v1_values', '3', count(*)::text
  from pg_enum e join pg_type t on t.oid = e.enumtypid
 where t.typname = 'clinic_audience' and e.enumlabel in ('ladies', 'men', 'coed');

-- ----------------------------------------------------- decision 8: category --
--
-- Nullable free text, kept for later, with no filtering built on it. An index
-- is the tell: nobody indexes a column they only display.
insert into _probe_result
select 'category_is_nullable_free_text', 'text|YES', data_type || '|' || is_nullable
  from information_schema.columns
 where table_schema = 'public' and table_name = 'clinics' and column_name = 'category';

insert into _probe_result
select 'no_index_promises_category_filtering', '0', count(*)::text
  from pg_indexes
 where schemaname = 'public' and indexdef ~* 'category';

-- ------------------------------------------- decision 13: notifications off --
--
-- Tara does not want to manage or monitor who has notifications turned off, so
-- the column that would feed an admin indicator is gone. The replacement is a
-- client-side disclosure, recorded in CLAUDE.md, not a schema object.
insert into _probe_result
select 'accounts_has_no_push_enabled_column', '0', count(*)::text
  from information_schema.columns
 where table_schema = 'public' and table_name = 'accounts' and column_name = 'push_enabled';

insert into _probe_result
select 'no_notifications_off_flag_anywhere', '0', count(*)::text
  from information_schema.columns
 where table_schema = 'public'
   and column_name ~* '(push_enabled|notifications_off|push_opt|notify_disabled)';

-- ------------------------------------------------- decision 11: payment copy --
--
-- Character for character. Lower-case "zelle" and the missing terminal period
-- are hers, and "correcting" them means shipping a string she did not write.
insert into _probe_result
select 'payment_string_is_exact', 'MATCH',
       case when value = 'Payment can be made via zelle to fersctennispro@gmail.com (preferred) or Venmo FXE Tennis'
            then 'MATCH' else 'DIFFERS: ' || value end
  from public.app_settings where key = 'payment_instructions';

insert into _probe_result
select 'payment_accessor_returns_same_string', 'MATCH',
       case when public.payment_instructions() =
                 'Payment can be made via zelle to fersctennispro@gmail.com (preferred) or Venmo FXE Tennis'
            then 'MATCH' else 'DIFFERS' end;

insert into _probe_result
select 'app_settings_write_is_admin_only', '1', count(*)::text
  from pg_policies
 where schemaname = 'public' and tablename = 'app_settings'
   and policyname = 'app_settings_admin_write' and qual ~ 'is_admin';

-- ------------------------------------------ decisions 6 and 7: NTRP rating --
--
-- Same scale and same chart as Volee, stored the same way Volee stores it, so a
-- rating crosses between the apps with no translation. "5.0+" is a display
-- label, never a stored value.
insert into _probe_result
select 'adult_rating_is_numeric_like_volee', 'numeric', data_type
  from information_schema.columns
 where table_schema = 'public' and table_name = 'players' and column_name = 'adult_rating';

do $$
declare
  MARIA constant uuid := 'a0000000-0000-0000-0000-000000000001';
begin
  -- A legal bucket.
  begin
    update public.players set adult_rating = 4.5 where id = MARIA;
    insert into _probe_result values ('ntrp_accepts_a_half_step_bucket', 'accepted', 'accepted');
  exception when others then
    insert into _probe_result values ('ntrp_accepts_a_half_step_bucket', 'accepted', sqlerrm);
  end;

  -- Above the 5.0 ceiling. Volee collapses these to the 5.0+ bucket on read;
  -- storing 5.5 would render as a blank row, so it is refused.
  begin
    update public.players set adult_rating = 5.5 where id = MARIA;
    insert into _probe_result values ('ntrp_refuses_above_ceiling', 'rejected', 'ACCEPTED 5.5');
  exception when check_violation then
    insert into _probe_result values ('ntrp_refuses_above_ceiling', 'rejected', 'rejected');
  end;

  -- Not a half step. There is no copy for 3.7, so there is no 3.7.
  begin
    update public.players set adult_rating = 3.7 where id = MARIA;
    insert into _probe_result values ('ntrp_refuses_off_scale_value', 'rejected', 'ACCEPTED 3.7');
  exception when check_violation then
    insert into _probe_result values ('ntrp_refuses_off_scale_value', 'rejected', 'rejected');
  end;

  -- Below the published list.
  begin
    update public.players set adult_rating = 1.5 where id = MARIA;
    insert into _probe_result values ('ntrp_refuses_below_published_scale', 'rejected', 'ACCEPTED 1.5');
  exception when check_violation then
    insert into _probe_result values ('ntrp_refuses_below_published_scale', 'rejected', 'rejected');
  end;

  -- Juniors carry no adult rating, and an adult may not have self-rated yet.
  begin
    update public.players set adult_rating = null where id = MARIA;
    insert into _probe_result values ('ntrp_allows_null', 'accepted', 'accepted');
  exception when others then
    insert into _probe_result values ('ntrp_allows_null', 'accepted', sqlerrm);
  end;
end $$;

-- ------------------------------- decisions 3 and 4: Tara places by hand, and --
--                                 capacity never blocks her                   --
do $$
declare
  MARIA constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  DANA  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  TARA_ACC constant uuid := '11111111-1111-1111-1111-111111111111';
  c uuid;
  r public.registrations;
  n int;
begin
  perform set_config('request.jwt.claims', json_build_object('sub', TARA_ACC)::text, true);

  -- Capacity ONE. Deliberately the tightest possible clinic.
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status)
  values ('Placement Probe', 'coed', now() + interval '3 days', now() + interval '3 days 1 hour',
      now() - interval '1 hour', now() + interval '12 hours', 1, 'published')
  returning id into c;

  -- Tara puts three players into a clinic that seats one. Every one lands in
  -- You're In!. She sees counts; she is never stopped by them.
  r := public.place_player(c, MARIA, 'in');
  r := public.place_player(c, KEN,   'in');
  r := public.place_player(c, DANA,  'in');

  select count(*) into n from public.registrations where clinic_id = c and status = 'in';
  insert into _probe_result values ('capacity_never_blocks_admin_placement', '3', n::text);

  -- And she can move someone between You're In! and Player Pool by hand, in
  -- both directions, without cancelling and re-registering them.
  r := public.place_player(c, KEN, 'pool');
  insert into _probe_result values ('admin_moves_in_to_pool', 'pool', r.status::text);

  r := public.place_player(c, KEN, 'in');
  insert into _probe_result values ('admin_moves_pool_back_to_in', 'in', r.status::text);

  -- One live row per player throughout. Moving is not re-registering.
  select count(*) into n from public.registrations
   where clinic_id = c and player_id = KEN and status <> 'canceled';
  insert into _probe_result values ('placement_leaves_one_live_row', '1', n::text);
end $$;

-- ------------------------------------ decision 5: member status self-reported --
--
-- The owning account writes it, an admin overrides it. Both branches live in
-- one policy, and losing either one silently breaks a different half of the
-- decision: drop the uid branch and self-report dies, drop the admin branch and
-- Tara can no longer correct a wrong claim.
insert into _probe_result
select 'is_member_self_writable', '1', count(*)::text
  from pg_policies
 where schemaname = 'public' and tablename = 'players'
   and policyname = 'players_update_own' and qual ~ 'auth\.uid';

insert into _probe_result
select 'is_member_admin_overridable', '1', count(*)::text
  from pg_policies
 where schemaname = 'public' and tablename = 'players'
   and policyname = 'players_update_own' and qual ~ 'is_admin';


-- ---------------------------------------------- Tara's answers, 2026-08-27 --
-- Pinned here so a later "simplification" cannot quietly undo a decision she
-- made. Each row names the person and the date, because the whole point of this
-- probe is that these are HER calls and not ours.
do $$
declare n int; v numeric;
begin
  -- Q5: registration closes 3 hours before the clinic starts.
  select round(extract(epoch from ('2026-10-06 09:00:00-04'::timestamptz
         - public.default_closes_at('2026-10-06 09:00:00-04'::timestamptz))) / 3600, 1)
    into v;
  insert into _probe_result values ('tara_close_window_is_3h', '3.0', v::text);

  -- Every clinic in the future must have one. Null meant "never closes", which
  -- left finished clinics bookable.
  select count(*) into n from public.clinics where starts_at > now() and closes_at is null;
  insert into _probe_result values ('no_future_clinic_without_a_close', '0', n::text);

  -- Q2: members get the same schedule 24 hours earlier. Asserted as the GAP so
  -- it holds for any clinic, rather than pinning two literal timestamps.
  select round(extract(epoch from (public.public_opens_at('2026-10-06 09:00:00-04'::timestamptz)
         - public.member_opens_at('2026-10-06 09:00:00-04'::timestamptz))) / 3600, 1)
    into v;
  insert into _probe_result values ('tara_member_head_start_is_24h', '24.0', v::text);

  -- Q6: juniors are deferred to November or the spring session. The enum value
  -- must survive so re-enabling is UI work, not a migration against live data.
  select count(*) into n from pg_enum e join pg_type t on t.oid = e.enumtypid
   where t.typname = 'clinic_audience' and e.enumlabel = 'juniors';
  insert into _probe_result values ('juniors_enum_still_present', '1', n::text);
end $$;

select
  check_name,
  expected,
  actual,
  case
    when actual = expected then 'PASS'
    -- Substring matching exists for checks whose `actual` is a server error
    -- message wrapping the expected error name. It is deliberately NOT allowed
    -- for numeric expectations. The original comparison used
    -- `actual like '%' || expected || '%'`, under which an actual count of 105
    -- PASSED against an expected 0, because "105" contains "0". That silently
    -- greened a real assertion failure. LIKE also treated `_` in an expected
    -- error name as a wildcard, so strpos is used instead.
    when expected ~ '[A-Za-z]' and strpos(actual, expected) > 0 then 'PASS'
    else 'FAIL'
  end as result
from _probe_result
order by check_name;

rollback;
