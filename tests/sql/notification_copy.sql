-- notification_copy.sql
--
-- Tara's own notification words (her catalogue, docs/notifications.md,
-- 2026-08-02), wired into the producers by 20260928000001:
--
--   #1  You're In            register_for_clinic lands in You're In!, or Tara
--                            puts someone in with place_player
--   #3  Invitation Accepted  respond_to_invitation, accept, to the player
--   #5  Added to Player Pool register_for_clinic lands in the Player Pool
--   #6  Removed from Pool    Tara removes a pooled player (cancel_registration)
--   #13 #14 #15              the admin rows, in the catalogue's wording
--
-- For every event this probe asserts exactly which rows the event wrote, one
-- line per row, as recipient:type:entity=what-it-points-at:body. "ref" means
-- the row points at the registration (or clinic) the event was about. The
-- rows are compared whole and exactly, never by substring, so an extra row
-- or a changed character is a FAIL.
--
-- Expected bodies are copied from her catalogue, not from the SQL. Day and
-- time were worked out by hand from how each clinic below is built:
--
--   Probe Copy Thursday  Monday of this week (New York) + 10 days + 9:00
--                        = next week's Thursday, 9:00 AM New York.
--   Probe Copy Friday    Monday of this week (New York) + 11 days + 20:30
--                        = next week's Friday, 8:30 PM New York. Chosen
--                        because 8:30 PM in New York is already Saturday in
--                        UTC (00:30 in summer, 01:30 in winter): a body built
--                        from the UTC value reads "Saturday at 12:30 AM" or
--                        "1:30 AM" and fails here, as would a padded weekday
--                        ("Friday   "), a leading zero ("08:30 PM") or a
--                        24-hour clock ("20:30").
--
-- The clinics are built from the wall clock and converted back, so the day
-- and time hold in summer and winter alike, and the probe cannot expire.
-- (date_trunc('week') is fine HERE: it only finds a Monday to count from. It
-- is never how a service week is anchored; that is service_week_start.)
--
-- Negatives, each its own check: accepting an invitation sends #3, not #1
-- (finding (e)); a decline and a withdrawn invitation send no #5 (finding
-- (i)); Tara placing someone into the Pool sends nothing; a player's own
-- cancel sends no #6; Tara's removal from You're In! sends nothing (there are
-- no words for it); an approved late request still sends one row, its own,
-- while a late request approved on an earlier day does not silence #1; a
-- clinic the player cannot see yet (draft), has already started, or is
-- canceled gets no "You're all set" from Tara's placement; accepting after
-- Tara canceled the clinic is refused outright (20260928300001), so nothing
-- moves and nobody is told; and a Pool removal from a draft or a canceled
-- clinic sends no #6.
--
-- The payments switch is set off inside the transaction: this probe is about
-- words, and register_for_clinic's card check would stop it with
-- card_required the day payments go on (the sql-auditor, 2026-09-28).
--
-- Expected: every row reads PASS.

begin;
create temporary table _probe_result (check_name text, expected text, actual text) on commit drop;
grant all on _probe_result to authenticated, anon;
update public.app_settings set value = 'false' where key = 'payments_enabled';

-- Every notification that existed before a step. delta() returns the rows
-- written since the last call, and marks them seen.
create temporary table _seen (id uuid primary key) on commit drop;
insert into _seen select id from public.notifications;

create function pg_temp.delta(p_ref uuid, p_body boolean default true) returns text
language sql as $$
  with fresh as (
    select n.* from public.notifications n
     where not exists (select 1 from _seen s where s.id = n.id)
  ), mark as (
    insert into _seen select id from fresh returning 1
  )
  select coalesce(string_agg(
           case f.account_id
             when '11111111-1111-1111-1111-111111111111' then 'tara'
             when '22222222-2222-2222-2222-222222222222' then 'maria'
             when '33333333-3333-3333-3333-333333333333' then 'ken'
             when '44444444-4444-4444-4444-444444444444' then 'rob'
             when '55555555-5555-5555-5555-555555555555' then 'priya'
             when '66666666-6666-6666-6666-666666666666' then 'dana'
             else 'other' end
           || ':' || f.type || ':' || coalesce(f.entity_type, 'null') || '='
           || case when f.entity_id = p_ref then 'ref' else coalesce(f.entity_id::text, 'null') end
           || case when p_body then ':' || f.body else '' end,
           ' || ' order by f.account_id, f.type), '')
    from fresh f;
$$;

do $$
declare
  TARA    constant uuid := '11111111-1111-1111-1111-111111111111';
  MARIA   constant uuid := '22222222-2222-2222-2222-222222222222';
  KEN     constant uuid := '33333333-3333-3333-3333-333333333333';
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  PRIYA   constant uuid := '55555555-5555-5555-5555-555555555555';
  DANA    constant uuid := '66666666-6666-6666-6666-666666666666';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  -- Her sentences, verbatim from the catalogue (#1 with the day and time
  -- worked out by hand above; #5 has no closing period, as she wrote it).
  YOURE_IN_THU constant text := 'You''re all set for Probe Copy Thursday on Thursday at 9:00 AM. Looking forward to seeing you on court!';
  YOURE_IN_FRI constant text := 'You''re all set for Probe Copy Friday on Friday at 8:30 PM. Looking forward to seeing you on court!';
  ACCEPTED     constant text := 'Awesome! Your spot is confirmed. See you soon!';
  POOLED       constant text := 'Thanks for registering! I personally create each clinic based on playing levels and will send confirmations once lineups are set ASAP';
  REMOVED_FRI  constant text := 'You''ve been removed from the Player Pool for Probe Copy Friday. Hope to see you at another clinic soon!';
  monday timestamp := date_trunc('week', now() at time zone 'America/New_York');
  thu uuid; pool_c uuid; fri uuid; soon uuid; draft_c uuid; started uuid; rained uuid; washout uuid;
  reg_rob_wash uuid; reg_priya_wash uuid;
  r public.registrations; lr public.late_requests;
  reg_maria_thu uuid; reg_ken_thu uuid; reg_rob_pool uuid; reg_dana_fri uuid; reg_priya_fri uuid;
  reg_ken_pool uuid; reg_maria_soon uuid; n int; v text; err text;
begin
  -- ------------------------------------------------------------ fixtures
  -- Thursday: the members' head start is open now, one spot.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Copy Thursday', 'coed', 'Clinic', 'probe',
          (monday + interval '10 days 9 hours') at time zone 'America/New_York',
          (monday + interval '10 days 10 hours') at time zone 'America/New_York',
          now() - interval '1 day', now() + interval '1 day', 1, 'published', 60)
  returning id into thu;
  -- Pool: open to everyone, so every registration lands in the Player Pool.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Copy Pool', 'coed', 'Clinic', 'probe', now() + interval '10 days', now() + interval '10 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into pool_c;
  -- Friday 8:30 PM: Tara's placements.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Copy Friday', 'coed', 'Clinic', 'probe',
          (monday + interval '11 days 20 hours 30 minutes') at time zone 'America/New_York',
          (monday + interval '11 days 21 hours 30 minutes') at time zone 'America/New_York',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into fri;
  -- Two hours out: inside the cancel cutoff, and closed to registration.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Copy Soon', 'coed', 'Clinic', 'probe', now() + interval '2 hours', now() + interval '3 hours',
          now() - interval '3 days', now() - interval '2 days', 8, 'published', 60)
  returning id into soon;
  -- Three clinics a player cannot be told about.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Copy Draft', 'coed', 'Clinic', 'probe', now() + interval '12 days', now() + interval '12 days 1 hour',
          now() + interval '8 days', now() + interval '9 days', 8, 'draft', 60)
  returning id into draft_c;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Copy Started', 'coed', 'Clinic', 'probe', now() - interval '30 minutes', now() + interval '30 minutes',
          now() - interval '4 days', now() - interval '3 days', 8, 'published', 60)
  returning id into started;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, canceled_at, duration_minutes)
  values ('Probe Copy Rained', 'coed', 'Clinic', 'probe', now() + interval '5 days', now() + interval '5 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'canceled', now(), 60)
  returning id into rained;
  -- Washout: published now, canceled by Tara in step 24.
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Copy Washout', 'coed', 'Clinic', 'probe', now() + interval '6 days', now() + interval '6 days 1 hour',
          now() - interval '2 days', now() - interval '1 day', 8, 'published', 60)
  returning id into washout;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (soon, MARIA_P, 'in', 'self', 1800, true, 60) returning id into reg_maria_soon;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (washout, ROB_P, 'pool', 'self', 2300, false, 60) returning id into reg_rob_wash;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (washout, PRIYA_P, 'pool', 'self', 2300, false, 60) returning id into reg_priya_wash;
  perform pg_temp.delta(null);

  -- Hand-derivation check on the fixture itself, so a wrong fixture cannot
  -- pass as a right body: the two clinics are what the header says they are.
  select to_char(starts_at at time zone 'America/New_York', 'FMDay HH24:MI') into v from public.clinics where id = thu;
  insert into _probe_result values ('fixture_thursday_is_thursday_0900_new_york', 'Thursday 09:00', v);
  select to_char(starts_at at time zone 'America/New_York', 'FMDay HH24:MI') into v from public.clinics where id = fri;
  insert into _probe_result values ('fixture_friday_is_friday_2030_new_york', 'Friday 20:30', v);
  select to_char(starts_at at time zone 'UTC', 'FMDay') into v from public.clinics where id = fri;
  insert into _probe_result values ('fixture_friday_is_saturday_in_utc', 'Saturday', v);

  -- =============================================== #1 and #5: registering
  -- 1. Maria, a member, inside the head start, room: You're In!, #1.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.register_for_clinic(thu, MARIA_P);
  reg_maria_thu := r.id;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('register_in_status', 'in', r.status::text);
  insert into _probe_result values ('register_in_sends_1_to_the_player',
    'maria:youre_in:registration=ref:' || YOURE_IN_THU, pg_temp.delta(reg_maria_thu));

  -- 2. Ken, a member, the one spot gone: Player Pool, #5.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.register_for_clinic(thu, KEN_P);
  reg_ken_thu := r.id;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('register_full_status', 'pool', r.status::text);
  insert into _probe_result values ('register_full_sends_5_to_the_player',
    'ken:added_to_pool:registration=ref:' || POOLED, pg_temp.delta(reg_ken_thu));

  -- 3. Rob, a non-member, after the public opening: Player Pool, #5.
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);
  r := public.register_for_clinic(pool_c, ROB_P);
  reg_rob_pool := r.id;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('register_pool_status', 'pool', r.status::text);
  insert into _probe_result values ('register_pool_sends_5_to_the_player',
    'rob:added_to_pool:registration=ref:' || POOLED, pg_temp.delta(reg_rob_pool));

  -- ================================================= #1: Tara places by hand
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  -- 4. Dana, no row yet, straight into You're In!: #1, at 8:30 PM on Friday.
  r := public.place_player(fri, DANA_P, 'in');
  reg_dana_fri := r.id;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('place_in_sends_1_to_the_player',
    'dana:youre_in:registration=ref:' || YOURE_IN_FRI, pg_temp.delta(reg_dana_fri));

  -- 5. The same placement again: she was already in, nothing is sent.
  perform set_config('role', 'authenticated', true);
  perform public.place_player(fri, DANA_P, 'in');
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('place_when_already_in_sends_nothing', '', pg_temp.delta(reg_dana_fri));

  -- 6. Ken, Player Pool to You're In! by hand: #1, on his existing row.
  perform set_config('role', 'authenticated', true);
  r := public.place_player(thu, KEN_P, 'in');
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('place_moves_the_same_row', reg_ken_thu::text, r.id::text);
  insert into _probe_result values ('place_from_pool_to_in_sends_1',
    'ken:youre_in:registration=ref:' || YOURE_IN_THU, pg_temp.delta(reg_ken_thu));

  -- 7. Priya into the Player Pool by hand: nothing (#5 is for registering).
  perform set_config('role', 'authenticated', true);
  r := public.place_player(fri, PRIYA_P, 'pool');
  reg_priya_fri := r.id;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('place_into_pool_sends_nothing', '', pg_temp.delta(reg_priya_fri));

  -- ====================================== #3, #13, #14: invitations answered
  -- 8. Tara invites Rob. #2 is not rewired here (contradiction (a) waits on
  --    her), so this row keeps our words; pinned so this change is seen not
  --    to have touched it.
  perform set_config('role', 'authenticated', true);
  perform public.invite_from_pool(reg_rob_pool);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('invitation_body_untouched',
    'rob:invitation_received:registration=ref:A spot opened in Probe Copy Pool. Accept or decline.',
    pg_temp.delta(reg_rob_pool));

  -- 9. Rob accepts: #3 to him, #13 to Tara, and no #1 (finding (e)).
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.respond_to_invitation(reg_rob_pool, true);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('accept_sends_3_to_the_player_and_13_to_tara',
    'tara:invitation_accepted:registration=ref:Rob Delgado accepted their spot in Probe Copy Pool.'
    || ' || rob:invitation_accepted_player:registration=ref:' || ACCEPTED,
    pg_temp.delta(reg_rob_pool));
  select count(*) into n from public.notifications where entity_id = reg_rob_pool and type = 'youre_in';
  insert into _probe_result values ('accept_sends_no_1', '0', n::text);

  -- 10. Tara invites Priya; 11. Priya declines: #14 to Tara, nothing to her.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.invite_from_pool(reg_priya_fri);
  perform set_config('role', 'postgres', true);
  perform pg_temp.delta(reg_priya_fri);
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.respond_to_invitation(reg_priya_fri, false);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('decline_sends_14_to_tara_only',
    'tara:invitation_declined:registration=ref:Priya Raman declined Probe Copy Friday and is back in the Player Pool.',
    pg_temp.delta(reg_priya_fri));
  select count(*) into n from public.notifications where entity_id = reg_priya_fri and type = 'added_to_pool';
  insert into _probe_result values ('decline_sends_no_5', '0', n::text);

  -- 12. Tara invites Priya again, then 13. takes the invitation back: no #5.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.invite_from_pool(reg_priya_fri);
  perform set_config('role', 'postgres', true);
  perform pg_temp.delta(reg_priya_fri);
  perform set_config('role', 'authenticated', true);
  perform public.cancel_invitation(reg_priya_fri);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('withdrawn_invitation_sends_nothing', '', pg_temp.delta(reg_priya_fri));
  select count(*) into n from public.notifications where entity_id = reg_priya_fri and type = 'added_to_pool';
  insert into _probe_result values ('withdrawn_invitation_sends_no_5', '0', n::text);

  -- ============================================ #6 and #15: cancellations
  -- 14. Tara removes Priya from the Player Pool: #6 to Priya, nothing to Tara.
  perform set_config('role', 'authenticated', true);
  perform public.cancel_registration(reg_priya_fri);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('pool_removal_sends_6_to_the_player',
    'priya:removed_from_pool:registration=ref:' || REMOVED_FRI, pg_temp.delta(reg_priya_fri));

  -- 15. Tara removes Dana from You're In!: no words exist for it, nothing.
  perform set_config('role', 'authenticated', true);
  perform public.cancel_registration(reg_dana_fri);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('removal_from_youre_in_sends_nothing', '', pg_temp.delta(reg_dana_fri));

  -- 16. Ken cancels his own You're In! spot, days out: #15 to Tara, no #6.
  perform set_config('request.jwt.claims', json_build_object('sub', KEN)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.cancel_registration(reg_ken_thu);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('own_cancel_sends_15_to_tara',
    'tara:player_canceled:registration=ref:Ken Whitfield canceled Probe Copy Thursday.', pg_temp.delta(reg_ken_thu));

  -- 17. Ken registers into the Pool (#5), then cancels that himself: #15 to
  --     Tara and no #6, because #6 is Tara removing him, not his own tap.
  perform set_config('role', 'authenticated', true);
  r := public.register_for_clinic(pool_c, KEN_P);
  reg_ken_pool := r.id;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('second_registration_sends_5',
    'ken:added_to_pool:registration=ref:' || POOLED, pg_temp.delta(reg_ken_pool));
  perform set_config('role', 'authenticated', true);
  perform public.cancel_registration(reg_ken_pool);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('own_pool_cancel_sends_15_and_no_6',
    'tara:player_canceled:registration=ref:Ken Whitfield canceled Probe Copy Pool.', pg_temp.delta(reg_ken_pool));

  -- 18. Maria's own late cancel with a note: #15 keeps today's suffixes.
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.cancel_registration(reg_maria_soon, '  Kid has a fever.  ');
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('late_cancel_sends_15_with_fee_and_note',
    'tara:player_canceled:registration=ref:Maria Alvarez canceled Probe Copy Soon. Late, fee applies. Note: "Kid has a fever."',
    pg_temp.delta(reg_maria_soon));

  -- ========================= an approved late request: one event, one row
  -- 19. Priya asks for a late spot in the soon clinic; Tara approves. The
  --     approval places her through place_player and tells her itself, so
  --     she gets exactly one row, the late-request answer, and no #1 on top.
  perform set_config('request.jwt.claims', json_build_object('sub', PRIYA)::text, true);
  perform set_config('role', 'authenticated', true);
  lr := public.request_late_spot(soon, PRIYA_P, null);
  perform set_config('role', 'postgres', true);
  perform pg_temp.delta(soon);
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.resolve_late_request(lr.id, true);
  perform set_config('role', 'postgres', true);
  select status::text into v from public.registrations where clinic_id = soon and player_id = PRIYA_P and status <> 'canceled';
  insert into _probe_result values ('late_approval_places_her', 'in', coalesce(v, 'NOT PLACED'));
  insert into _probe_result values ('late_approval_sends_one_row_not_1',
    'priya:LATE_REQUEST_APPROVED:clinic=ref', pg_temp.delta(soon, false));

  -- ======================= clinics a player cannot be told "all set" about
  perform set_config('role', 'authenticated', true);
  -- 20. A draft: she cannot see it yet.
  perform public.place_player(draft_c, KEN_P, 'in');
  -- 21. Already started: the walk-up is standing on the court.
  perform public.place_player(started, ROB_P, 'in');
  -- 22. Canceled: "all set" would be false.
  perform public.place_player(rained, DANA_P, 'in');
  perform set_config('role', 'postgres', true);
  select string_agg(c.name || ' ' || r2.status, ', ' order by c.name) into v
    from public.registrations r2 join public.clinics c on c.id = r2.clinic_id
   where r2.clinic_id in (draft_c, started, rained);
  insert into _probe_result values ('hidden_clinic_placements_happened',
    'Probe Copy Draft in, Probe Copy Rained in, Probe Copy Started in', coalesce(v, 'none'));
  insert into _probe_result values ('placement_into_draft_started_or_canceled_sends_nothing', '', pg_temp.delta(null));

  -- 23. A Pool removal from a draft: she was never told she was in it.
  perform set_config('role', 'authenticated', true);
  r := public.place_player(draft_c, PRIYA_P, 'pool');
  perform public.cancel_registration(r.id);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('draft_pool_removal_sends_nothing', '', pg_temp.delta(r.id));

  -- ======================================= after Tara cancels the clinic
  -- 24. Tara invites Rob, then cancels the clinic (rain) before he answers;
  --     the invitation's Accept (the clinic page opened from the push, or
  --     the lock screen's own button) is refused since 20260928300001: a
  --     canceled clinic has no spots. 24a: the refusal. 24b: nothing moved
  --     and nobody was told anything (a refused answer writes no row).
  --     Before that migration the accept went through and Rob sat in
  --     You're In! of a clinic that was not happening.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.invite_from_pool(reg_rob_wash);
  perform public.cancel_clinic(washout);
  perform set_config('role', 'postgres', true);
  perform pg_temp.delta(null);
  perform set_config('request.jwt.claims', json_build_object('sub', ROB)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.respond_to_invitation(reg_rob_wash, true);
    err := 'accepted';
  exception when others then
    err := sqlerrm;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('accept_after_cancel_is_refused', 'clinic_canceled', err);
  insert into _probe_result values ('accept_after_cancel_moves_and_sends_nothing',
    'response_needed|',
    (select status::text from public.registrations where id = reg_rob_wash) || '|' || pg_temp.delta(reg_rob_wash));

  -- 25. Tara then clears Priya out of the canceled clinic's Pool: she was
  --     already told it was canceled, so no #6 on top.
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);
  perform public.cancel_registration(reg_priya_wash);
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('canceled_clinic_pool_removal_sends_nothing', '', pg_temp.delta(reg_priya_wash));

  -- 26. A late request Tara approved on an earlier day does not silence #1
  --     for a placement today: only the approval in the same transaction is
  --     the late request's own answer.
  insert into public.late_requests (clinic_id, player_id, status, resolved_at, resolved_by)
  values (thu, DANA_P, 'approved', now() - interval '1 day', TARA);
  perform set_config('role', 'authenticated', true);
  r := public.place_player(thu, DANA_P, 'in');
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('earlier_late_approval_does_not_silence_1',
    'dana:youre_in:registration=ref:' || YOURE_IN_THU, pg_temp.delta(r.id));

  -- ============================== hard rule 1: nothing hidden in her rows
  -- Every player-facing row of the four new types, whole: none carries a
  -- court number, a count, a location or another player's name. (The bodies
  -- above are exact, so this is belt and braces against a future producer.)
  -- "Your spot is confirmed" and "on court!" are hers and are not counts, so
  -- the pattern asks for a number next to the word.
  select count(*) into n from public.notifications x
   where x.type in ('youre_in', 'invitation_accepted_player', 'added_to_pool', 'removed_from_pool')
     and (x.body ~* '(court [0-9]|[0-9]+ (spots?|players?|people)|spots? (left|remaining)|capacity|address|location)'
          or x.body ~ '(Maria|Ken|Rob|Dana|Priya|Alvarez|Whitfield|Delgado|Okonkwo|Raman)');
  insert into _probe_result values ('player_rows_carry_no_hidden_fact', '0', n::text);
end $$;

-- Exact comparison for every row, including those with letters: the
-- harness's substring rule would pass a delta with an extra row appended.
select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result;
rollback;
