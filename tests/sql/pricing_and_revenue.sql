-- pricing_and_revenue.sql
--
-- Tara's locked price table, and the guarantee her reconciliation depends on:
-- once a registration exists, what it cost NEVER changes.
--
--                 60 min    90 min
--   Member         $18       $22
--   Non-member     $23       $28
--
-- Expected values below are transcribed from Tara's own words on the
-- 2026-08-02 call, not read back out of the code. Per CLAUDE.md: write the
-- probe from the rule, never from the implementation.
--
-- Expected: every row reads PASS.

begin;

create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
-- The probe switches into the `authenticated` role to exercise real policies,
-- so that role needs to be able to write its own scratch results.
grant all on _probe_result to authenticated;

do $$
declare
  MARIA     constant uuid := 'a0000000-0000-0000-0000-000000000001'; -- member
  ROB       constant uuid := 'a0000000-0000-0000-0000-000000000003'; -- NON-member
  KEN       constant uuid := 'a0000000-0000-0000-0000-000000000002'; -- member
  MARIA_ACC constant uuid := '22222222-2222-2222-2222-222222222222';
  ROB_ACC   constant uuid := '44444444-4444-4444-4444-444444444444';
  TARA_ACC  constant uuid := '11111111-1111-1111-1111-111111111111';
  c60 uuid; c90 uuid;
  r public.registrations;
  v text;
begin
  -- Two open clinics, one of each length. Prices are left NULL deliberately so
  -- the default trigger has to supply them from Tara's table.
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Hour Clinic', 'coed', now() + interval '3 days', now() + interval '3 days 1 hour',
      now() - interval '2 days', now() - interval '1 day', 20, 'published', 60)
  returning id into c60;

  -- The 90-minute clinic sits INSIDE the member priority window (public opening
  -- is still 12 hours out). That matters: past the public opening every
  -- registration goes to the Player Pool, and a Player Pool entry owes nothing,
  -- so the revenue assertions below would all be zero for reasons that have
  -- nothing to do with pricing.
  insert into public.clinics (name, audience, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Ninety Clinic', 'coed', now() + interval '3 days', now() + interval '3 days 90 minutes',
      now() - interval '1 hour', now() + interval '12 hours', 20, 'published', 90)
  returning id into c90;

  -- ── the locked table, applied by the default trigger ─────────────────────
  select member_price_cents::text into v from public.clinics where id = c60;
  insert into _probe_result values ('default_member_60_is_1800', '1800', v);
  select nonmember_price_cents::text into v from public.clinics where id = c60;
  insert into _probe_result values ('default_nonmember_60_is_2300', '2300', v);
  select member_price_cents::text into v from public.clinics where id = c90;
  insert into _probe_result values ('default_member_90_is_2200', '2200', v);
  select nonmember_price_cents::text into v from public.clinics where id = c90;
  insert into _probe_result values ('default_nonmember_90_is_2800', '2800', v);

  -- ── what each player is actually charged ─────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  r := public.register_for_clinic(c60, MARIA);
  insert into _probe_result values ('member_charged_1800_for_60', '1800', r.price_cents_charged::text);
  insert into _probe_result values ('member_snapshot_was_member', 'true', r.was_member::text);
  insert into _probe_result values ('snapshot_duration_60', '60', r.duration_minutes::text);

  r := public.register_for_clinic(c90, MARIA);
  insert into _probe_result values ('member_charged_2200_for_90', '2200', r.price_cents_charged::text);

  perform set_config('request.jwt.claims', json_build_object('sub', ROB_ACC)::text, true);
  r := public.register_for_clinic(c60, ROB);
  insert into _probe_result values ('nonmember_charged_2300_for_60', '2300', r.price_cents_charged::text);
  insert into _probe_result values ('nonmember_snapshot_was_member', 'false', r.was_member::text);

  -- Rob cannot self-register for the 90 yet: it is still the member-only
  -- window. Tara places him, which is exactly the real-world case she
  -- described, and it must still charge the non-member rate.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA_ACC)::text, true);
  r := public.place_player(c90, ROB, 'in');
  insert into _probe_result values ('nonmember_charged_2800_for_90', '2800', r.price_cents_charged::text);

  -- ── THE GUARANTEE: history does not move ─────────────────────────────────
  -- This is the whole reason the price is snapshotted. Tara reconciles real
  -- money against these numbers; if editing a clinic rewrote what August
  -- earned, her books and the club's would silently disagree.
  perform set_config('role', 'postgres', true);
  update public.clinics set member_price_cents = 9900, nonmember_price_cents = 9900
   where id = c60;

  select price_cents_charged::text into v from public.registrations
   where clinic_id = c60 and player_id = MARIA;
  insert into _probe_result values ('price_edit_does_not_rewrite_history', '1800', v);

  -- Same for a membership correction. Tara fixes a wrong is_member flag when
  -- she notices; that must not change what the person already owed.
  update public.players set is_member = true where id = ROB;
  select price_cents_charged::text into v from public.registrations
   where clinic_id = c60 and player_id = ROB;
  insert into _probe_result values ('membership_fix_does_not_rewrite_history', '2300', v);
  select was_member::text into v from public.registrations
   where clinic_id = c60 and player_id = ROB;
  insert into _probe_result values ('was_member_snapshot_frozen', 'false', v);
  update public.players set is_member = false where id = ROB;  -- restore

  -- ── Tara adding somebody herself still counts toward the total ───────────
  -- Her words: "it will count as normal and counted to the payment total".
  perform set_config('request.jwt.claims', json_build_object('sub', TARA_ACC)::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.place_player(c90, KEN, 'in');
  insert into _probe_result values ('placed_player_is_charged', '2200', r.price_cents_charged::text);
  insert into _probe_result values ('placed_player_snapshot_member', 'true', r.was_member::text);

  -- ── the reconciliation numbers ───────────────────────────────────────────
  -- 90-minute clinic: Maria $22 (member) + Rob $28 (non-member) + Ken $22
  -- placed by Tara = $72 expected, nothing marked paid yet.
  select expected_cents::text into v from public.revenue_by_clinic where clinic_id = c90;
  insert into _probe_result values ('revenue_90_expected_7200', '7200', v);
  select outstanding_cents::text into v from public.revenue_by_clinic where clinic_id = c90;
  insert into _probe_result values ('revenue_90_all_outstanding', '7200', v);
  select member_players::text into v from public.revenue_by_clinic where clinic_id = c90;
  insert into _probe_result values ('revenue_90_two_members', '2', v);
  select nonmember_players::text into v from public.revenue_by_clinic where clinic_id = c90;
  insert into _probe_result values ('revenue_90_one_nonmember', '1', v);

  -- Tick one payment off; expected stays put, collected moves.
  perform set_config('role', 'postgres', true);
  update public.registrations set paid = true
   where clinic_id = c90 and player_id = MARIA;
  perform set_config('role', 'authenticated', true);

  select collected_cents::text into v from public.revenue_by_clinic where clinic_id = c90;
  insert into _probe_result values ('revenue_90_collected_2200', '2200', v);
  select outstanding_cents::text into v from public.revenue_by_clinic where clinic_id = c90;
  insert into _probe_result values ('revenue_90_outstanding_5000', '5000', v);
  select expected_cents::text into v from public.revenue_by_clinic where clinic_id = c90;
  insert into _probe_result values ('expected_unchanged_by_payment', '7200', v);

  -- A Player Pool entry owes nothing until Tara gives them a spot.
  perform set_config('role', 'postgres', true);
  insert into public.registrations (clinic_id, player_id, status, source,
      price_cents_charged, was_member, duration_minutes)
  values (c90, 'a0000000-0000-0000-0000-000000000004', 'pool', 'self', 2200, true, 90);
  perform set_config('role', 'authenticated', true);
  select expected_cents::text into v from public.revenue_by_clinic where clinic_id = c90;
  insert into _probe_result values ('pool_entry_owes_nothing', '7200', v);

  -- ── players must never see the money ─────────────────────────────────────
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA_ACC)::text, true);
  select count(*)::text into v from public.revenue_by_clinic;
  insert into _probe_result values ('player_sees_no_revenue_rows', '0', v);
  select count(*)::text into v from public.revenue_by_segment;
  insert into _probe_result values ('player_sees_no_segment_rows', '0', v);

  perform set_config('role', 'postgres', true);
end $$;

select
  check_name,
  expected,
  actual,
  case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result
order by check_name;

rollback;
