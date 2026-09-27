-- money_reports.sql
--
-- The board report, the decline code, and the one-live-row indexes
-- (20260926000010). Written FROM THE RULE in that migration's header, not
-- from its SQL: every expected number is worked out by hand from the fixture
-- and written as a literal, with the arithmetic beside it.
--
-- THE RULE: attended = status 'in', not a no-show, clinic not canceled and
-- ended, clinic start on a New York date in [from, to]. Member by the
-- registration's was_member snapshot (null = non-member), never
-- players.is_member. Fees due = sum of price_cents_charged over attended
-- (null adds nothing). Collected = succeeded clinic_fee / late_cancel /
-- no_show payments whose clinic starts in the period, minus succeeded refunds
-- of those payments. Board share = 10% of each, half up (floor(x + 0.5)).
--
-- FIXTURE (New York times; "S" succeeded)
--   A  Mon 2026-08-10 09:00, 60 min
--      Maria in  t 1800   P1 fee 1800 S; R2 refund of P1 FAILED; R3 refund of P1 PENDING;
--                         P12 fee 1800 CANCELED
--      Rob   in  f 2300   P2 fee 2300 S; R1 refund of P2 2300 S
--      Ken   in  t 1800   no-show; P3 no_show 1800 S
--      Priya pool f 2300  (never attended)
--      Dana  canceled late 1800; P4 late_cancel 1800 S
--   D  Sat 2026-08-15 09:00, CANCELED clinic
--      Rob   in  f 2300   P10 fee 2300 S  (the fee was taken, then she canceled)
--   E  Thu 2026-08-20 09:00
--      Dana  in  t 1800   no-show; P9 no_show 1805 S (odd on purpose: rounding)
--   B  Mon 2026-08-31 21:00 (= 2026-09-01 01:00 UTC), 90 min
--      Maria in  t 2200   P5 fee FAILED insufficient_funds; P11 fee 2200 PROCESSING
--      Priya in  f 2800   P6 fee 2800 S
--      Ken   in  t 2200   PK fee 2200 FAILED expired_card (added 2026-09-27 for
--                         the Money tab; a failed fee is never collected, so
--                         no board number below moves)
--      Rob   in  f 2800   P7 fee 2800 PENDING
--      Dana  in  NULL snapshot, NULL price
--   C  Fri 2026-07-31 22:00 (= 2026-08-01 02:00 UTC): July in New York
--      Maria in  t 1800   P8 fee 1800 S
--   W  Sat 2026-01-31 23:30 (= 2026-02-01 04:30 UTC): January in New York
--      Maria in  t 1800   PW fee 1800 S
--   Relative to now(): "Probe ended" (-3h..-2h), "Probe in progress"
--      (-30m..+30m), "Probe later today" (+2h..+3h); Maria in t 1800 each.
--   AFTER registering: Rob and Priya flipped to members, Ken to non-member.
--
-- EXPECTED, August:
--   attended: A Maria t, A Rob f, B Maria t, B Priya f, B Ken t, B Rob f, B Dana null
--   members 3 (A Maria, B Maria, B Ken); non-members 4 (A Rob, B Priya, B Rob, B Dana)
--   member players {Maria, Ken} 2; non-member players {Rob, Priya, Dana} 3; clinics {A, B} 2
--   due = 1800+2300+2200+2800+2200+2800+0 = 14100
--   collected = P1 1800 + P2 2300 + P3 1800 + P4 1800 + P6 2800 + P9 1805 + P10 2300
--             = 14605, minus R1 2300 = 12305
--             (P5 failed, P7 pending, P11 processing, P12 canceled, R2 failed,
--              R3 pending, P8 July: none count)
--   10% of 12305 = 1230.5, half up 1231; 10% of 14100 = 1410
--   rows by start: A 1|1|4100|(1800+2300+1800+1800-2300=)5400 ; D 0|0|0|2300 ;
--                  E 0|0|0|1805 ; B 2|3|10000|2800
--   row sums: 3 | 4 | 14100 | 5400+2300+1805+2800 = 12305
--
-- THE MONEY TAB (20260927100003), same fixture, all time. THE RULE: charged =
-- succeeded fees minus their succeeded refunds, every clinic (the board's
-- collected without dates). Owing rows = ended, not canceled clinics: in owes
-- the clinic fee, a no-show the no-show fee, a late cancel (no courtesy, no
-- You're In! row beside it) the late fee. Each owing row is charged (the
-- player holds a live fee there), refunded (that exact fee went through and
-- came back), declined (a charge of it failed) or not charged.
--   charged = 18205 (the nine succeeded fees, July and January included)
--             - R1 2300 = 15905
--   owing rows: A Maria charged (R2 failed, R3 pending: nothing came back);
--     A Rob refunded (P2 back in full by R1); A Ken charged; A Dana charged;
--     E Dana charged; B Maria charged (P11 processing is live, P5 is history);
--     B Priya charged; B Ken DECLINED 2200 expired_card; B Rob charged (P7);
--     B Dana NOT CHARGED (null price: counts 1, adds 0); C and W Maria
--     charged; "Probe ended" Maria NOT CHARGED 1800. D is canceled: owes
--     nothing, but its 2300 was taken. In progress and later today: not over.
--   summary: 15905 | declined 1, 2200 | not charged 2, 1800, 2 clinics
--   clinic rows, newest first, name|canceled|charged|declined|not|not cents|
--   with a card (Maria's card is added first, Dana has none):
--     Probe ended|f|0|0|1|1800|1 ; Probe Aug 31 late|f|2800|1|1|0|0 ;
--     Probe Aug 20 all no-show|f|1805|0|0|0|0 ; Probe Aug 15 canceled|t|2300|0|0|0|0 ;
--     Probe Aug 10|f|5400|0|0|0|0 ; Probe Jul 31 late|f|1800|0|0|0|0 ;
--     Probe Jan 31 late|f|1800|0|0|0|0
--   row sums: 15905 | 1 | 2 | 1800, the summary's.
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
  ROB     constant uuid := '44444444-4444-4444-4444-444444444444';
  PRIYA   constant uuid := '55555555-5555-5555-5555-555555555555';
  DANA    constant uuid := '66666666-6666-6666-6666-666666666666';
  MARIA_P constant uuid := 'a0000000-0000-0000-0000-000000000001';
  KEN_P   constant uuid := 'a0000000-0000-0000-0000-000000000002';
  ROB_P   constant uuid := 'a0000000-0000-0000-0000-000000000003';
  DANA_P  constant uuid := 'a0000000-0000-0000-0000-000000000004';
  PRIYA_P constant uuid := 'a0000000-0000-0000-0000-000000000005';
  ny      constant text := 'America/New_York';
  ca uuid; cb uuid; cc uuid; cd uuid; ce uuid; cw uuid; c_end uuid; c_now uuid; c_later uuid;
  r_am uuid; r_ar uuid; r_ak uuid; r_ad uuid; r_ed uuid; r_dr uuid;
  r_bm uuid; r_bp uuid; r_br uuid; r_cm uuid; r_wm uuid; r_bk uuid;
  p1 uuid; p2 uuid; p5 uuid; p9 uuid;
  s record; v text; n int; n2 int; x text; per record; bad text;
begin
  -- ------------------------------------------------------------ clinics
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Aug 10', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-10 09:00' at time zone ny, timestamp '2026-08-10 10:00' at time zone ny,
          timestamp '2026-08-06 08:00' at time zone ny, timestamp '2026-08-07 08:00' at time zone ny, 8, 'published', 60)
  returning id into ca;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes, canceled_at)
  values ('Probe Aug 15 canceled', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-15 09:00' at time zone ny, timestamp '2026-08-15 10:00' at time zone ny,
          timestamp '2026-08-06 08:00' at time zone ny, timestamp '2026-08-07 08:00' at time zone ny, 8, 'canceled', 60,
          timestamp '2026-08-14 12:00' at time zone ny)
  returning id into cd;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Aug 20 all no-show', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-20 09:00' at time zone ny, timestamp '2026-08-20 10:00' at time zone ny,
          timestamp '2026-08-13 08:00' at time zone ny, timestamp '2026-08-14 08:00' at time zone ny, 8, 'published', 60)
  returning id into ce;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Aug 31 late', 'coed', 'Clinic', 'probe',
          timestamp '2026-08-31 21:00' at time zone ny, timestamp '2026-08-31 22:30' at time zone ny,
          timestamp '2026-08-27 08:00' at time zone ny, timestamp '2026-08-28 08:00' at time zone ny, 8, 'published', 90)
  returning id into cb;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Jul 31 late', 'coed', 'Clinic', 'probe',
          timestamp '2026-07-31 22:00' at time zone ny, timestamp '2026-07-31 23:00' at time zone ny,
          timestamp '2026-07-23 08:00' at time zone ny, timestamp '2026-07-24 08:00' at time zone ny, 8, 'published', 60)
  returning id into cc;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe Jan 31 late', 'coed', 'Clinic', 'probe',
          timestamp '2026-01-31 23:30' at time zone ny, timestamp '2026-02-01 00:30' at time zone ny,
          timestamp '2026-01-22 08:00' at time zone ny, timestamp '2026-01-23 08:00' at time zone ny, 8, 'published', 60)
  returning id into cw;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe ended', 'coed', 'Clinic', 'probe', now() - interval '3 hours', now() - interval '2 hours',
          now() - interval '5 days', now() - interval '4 days', 8, 'published', 60)
  returning id into c_end;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe in progress', 'coed', 'Clinic', 'probe', now() - interval '30 minutes', now() + interval '30 minutes',
          now() - interval '5 days', now() - interval '4 days', 8, 'published', 60)
  returning id into c_now;
  insert into public.clinics (name, audience, category, description, starts_at, ends_at,
      member_opens_at, public_opens_at, internal_capacity, status, duration_minutes)
  values ('Probe later today', 'coed', 'Clinic', 'probe', now() + interval '2 hours', now() + interval '3 hours',
          now() - interval '5 days', now() - interval '4 days', 8, 'published', 60)
  returning id into c_later;

  -- ------------------------------------------------------ registrations
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ca, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r_am;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ca, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_ar;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, no_show)
  values (ca, KEN_P, 'in', 'self', 1800, true, 60, true) returning id into r_ak;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (ca, PRIYA_P, 'pool', 'self', 2300, false, 60);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes,
                                    late_cancel, canceled_at, canceled_by)
  values (ca, DANA_P, 'canceled', 'self', 1800, true, 60, true, timestamp '2026-08-10 08:00' at time zone ny, DANA)
  returning id into r_ad;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cd, ROB_P, 'in', 'self', 2300, false, 60) returning id into r_dr;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes, no_show)
  values (ce, DANA_P, 'in', 'self', 1800, true, 60, true) returning id into r_ed;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cb, MARIA_P, 'in', 'self', 2200, true, 90) returning id into r_bm;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cb, PRIYA_P, 'in', 'self', 2800, false, 90) returning id into r_bp;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cb, KEN_P, 'in', 'self', 2200, true, 90) returning id into r_bk;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cb, ROB_P, 'in', 'self', 2800, false, 90) returning id into r_br;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cb, DANA_P, 'in', 'admin', null, null, 90);
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cc, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r_cm;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (cw, MARIA_P, 'in', 'self', 1800, true, 60) returning id into r_wm;
  insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes)
  values (c_end, MARIA_P, 'in', 'self', 1800, true, 60),
         (c_now, MARIA_P, 'in', 'self', 1800, true, 60),
         (c_later, MARIA_P, 'in', 'self', 1800, true, 60);

  -- ------------------------------------------------------------ ledger
  -- As the edge functions would leave it (they run as service_role; this is
  -- postgres standing in for them).
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_am, MARIA, 'clinic_fee', 1800, 'succeeded') returning id into p1;              -- P1
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_ar, ROB, 'clinic_fee', 2300, 'succeeded') returning id into p2;                -- P2
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, refunds_payment_id)
  values (r_ar, ROB, 'refund', 2300, 'succeeded', p2);                                     -- R1
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, refunds_payment_id)
  values (r_am, MARIA, 'refund', 1800, 'failed', p1);                                      -- R2
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, refunds_payment_id)
  values (r_am, MARIA, 'refund', 1800, 'pending', p1);                                     -- R3
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_am, MARIA, 'clinic_fee', 1800, 'canceled');                                    -- P12
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_ak, KEN, 'no_show', 1800, 'succeeded');                                        -- P3
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_ad, DANA, 'late_cancel', 1800, 'succeeded');                                   -- P4
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_dr, ROB, 'clinic_fee', 2300, 'succeeded');                                     -- P10
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_ed, DANA, 'no_show', 1805, 'succeeded') returning id into p9;                  -- P9
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, failure_reason, failure_code)
  values (r_bm, MARIA, 'clinic_fee', 2200, 'failed', 'Your card has insufficient funds.', 'insufficient_funds')
  returning id into p5;                                                                    -- P5
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_bm, MARIA, 'clinic_fee', 2200, 'processing');                                  -- P11
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_bp, PRIYA, 'clinic_fee', 2800, 'succeeded');                                   -- P6
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_br, ROB, 'clinic_fee', 2800, 'pending');                                       -- P7
  insert into public.payments (registration_id, account_id, kind, amount_cents, status, failure_reason, failure_code)
  values (r_bk, KEN, 'clinic_fee', 2200, 'failed', 'Your card has expired.', 'expired_card');  -- PK
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_cm, MARIA, 'clinic_fee', 1800, 'succeeded');                                   -- P8
  insert into public.payments (registration_id, account_id, kind, amount_cents, status)
  values (r_wm, MARIA, 'clinic_fee', 1800, 'succeeded');                                   -- PW

  -- Tara corrects membership AFTER they registered. A past report must not move.
  update public.players set is_member = true  where id in (ROB_P, PRIYA_P);
  update public.players set is_member = false where id = KEN_P;

  -- ---------------------------------------------- STRUCTURE (as postgres)
  -- Assert the resulting state, not the error (hard rule 9).
  -- A second live clinic fee for Rob in A, as the double-tap race would make.
  begin
    insert into public.payments (registration_id, account_id, kind, amount_cents, status)
    values (r_ar, ROB, 'clinic_fee', 2300, 'pending');
  exception when others then null;
  end;
  select count(*) into n from public.payments
   where registration_id = r_ar and kind = 'clinic_fee' and status in ('pending', 'processing', 'succeeded');
  insert into _probe_result values ('second_live_charge_blocked', '1', n::text);

  -- A second app refund of P1 while R3 is still pending (the refund race).
  begin
    insert into public.payments (registration_id, account_id, kind, amount_cents, status, refunds_payment_id)
    values (r_am, MARIA, 'refund', 1800, 'pending', p1);
  exception when others then null;
  end;
  select count(*) into n from public.payments
   where refunds_payment_id = p1 and status in ('pending', 'processing', 'succeeded');
  insert into _probe_result values ('second_live_app_refund_blocked', '1', n::text);

  -- Two refunds Stripe recorded (dashboard partials carry their Stripe id) are
  -- both kept, and a net below zero still rounds half up. Done inside a block
  -- that is rolled back on purpose, so the numbers below never see them.
  -- plpgsql variables survive the rollback; the rows do not.
  begin
    insert into public.payments (registration_id, account_id, kind, amount_cents, status, refunds_payment_id, stripe_refund_id)
    values (r_ed, DANA, 'refund', 1000, 'succeeded', p9, 're_probe_a'),
           (r_ed, DANA, 'refund', 810,  'succeeded', p9, 're_probe_b');
    select count(*) into n2 from public.payments where refunds_payment_id = p9 and status = 'succeeded';
    perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
    perform set_config('role', 'authenticated', true);
    -- Aug 20 alone: P9 1805 - 1000 - 810 = -5; 10% = -0.5, half up = 0
    -- (Postgres round() would say -1).
    select collected_cents || '|' || board_share_cents into x from public.admin_board_report('2026-08-20', '2026-08-20');
    raise exception 'probe_rollback';
  exception when others then
    if sqlerrm <> 'probe_rollback' then raise; end if;
  end;
  perform set_config('role', 'postgres', true);
  insert into _probe_result values ('stripe_recorded_partial_refunds_both_kept', '2', n2::text);
  insert into _probe_result values ('negative_half_cent_rounds_up', '-5|0', coalesce(x, 'NULL'));

  -- ------------------------------------------------------------ as Tara
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  select * into s from public.admin_board_report('2026-08-01', '2026-08-31');
  insert into _probe_result values
    ('aug_period_echoed',             '2026-08-01..2026-08-31', s.period_from || '..' || s.period_to),
    ('aug_member_attendances',        '3',     s.member_attendances::text),
    ('aug_nonmember_attendances',     '4',     s.nonmember_attendances::text),
    ('aug_member_players',            '2',     s.member_players::text),
    ('aug_nonmember_players',         '3',     s.nonmember_players::text),
    ('aug_clinics',                   '2',     s.clinics::text),
    ('aug_fees_due_cents',            '14100', s.fees_due_cents::text),
    ('aug_collected_cents',           '12305', s.collected_cents::text),
    ('aug_board_share_half_up',       '1231',  s.board_share_cents::text),
    ('aug_board_share_of_due',        '1410',  s.board_share_of_due_cents::text);

  select string_agg(c.clinic_name || '|' || c.member_attendances || '|' || c.nonmember_attendances
                    || '|' || c.fees_due_cents || '|' || c.collected_cents, ' ; ' order by c.starts_at)
    into v from public.admin_board_report_clinics('2026-08-01', '2026-08-31') c;
  insert into _probe_result values ('aug_clinic_rows',
    'Probe Aug 10|1|1|4100|5400 ; Probe Aug 15 canceled|0|0|0|2300 ; Probe Aug 20 all no-show|0|0|0|1805 ; Probe Aug 31 late|2|3|10000|2800',
    coalesce(v, 'NO ROWS'));

  -- The function's own order is the page's order (by start).
  select string_agg(c.clinic_name, ' ; ') into v from public.admin_board_report_clinics('2026-08-01', '2026-08-31') c;
  insert into _probe_result values ('aug_clinic_rows_in_start_order',
    'Probe Aug 10 ; Probe Aug 15 canceled ; Probe Aug 20 all no-show ; Probe Aug 31 late', coalesce(v, 'NO ROWS'));

  -- A alone: P1 1800 + P2 2300 + P3 1800 + P4 1800 - R1 2300 = 5400. The
  -- failed (R2) and pending (R3) refunds of P1 and the canceled fee P12 are
  -- not money that moved.
  select s2.member_attendances || '|' || s2.nonmember_attendances || '|' || s2.clinics || '|' || s2.fees_due_cents || '|' || s2.collected_cents
    into v from public.admin_board_report('2026-08-10', '2026-08-10') s2;
  insert into _probe_result values ('aug10_failed_pending_refunds_and_canceled_fee_ignored', '1|1|1|4100|5400', v);

  -- B alone, on the New York date (inclusive upper bound): Maria, Ken members;
  -- Priya, Rob and Dana (no snapshot) non-members; due 2200+2800+2200+2800+0;
  -- collected P6 2800 only (P5 failed, P11 processing, P7 pending).
  select * into s from public.admin_board_report('2026-08-31', '2026-08-31');
  insert into _probe_result values ('aug31_only', '2|3|1|10000|2800|280|1000',
    s.member_attendances || '|' || s.nonmember_attendances || '|' || s.clinics || '|' || s.fees_due_cents
    || '|' || s.collected_cents || '|' || s.board_share_cents || '|' || s.board_share_of_due_cents);
  select c.nonmember_attendances || '|' || c.fees_due_cents into v
    from public.admin_board_report_clinics('2026-08-31', '2026-08-31') c;
  insert into _probe_result values ('null_snapshot_is_nonmember_null_price_adds_nothing', '3|10000', coalesce(v, 'NO ROW'));

  -- D alone: canceled, so nobody attended, but the 2300 was taken.
  select * into s from public.admin_board_report('2026-08-15', '2026-08-15');
  insert into _probe_result values ('canceled_clinic_fee_is_income_not_attendance', '0|0|0|0|2300|230',
    s.member_attendances || '|' || s.nonmember_attendances || '|' || s.clinics || '|' || s.fees_due_cents
    || '|' || s.collected_cents || '|' || s.board_share_cents);
  select string_agg(c.clinic_name || '|' || c.member_attendances || '|' || c.nonmember_attendances
                    || '|' || c.fees_due_cents || '|' || c.collected_cents, ' ; ')
    into v from public.admin_board_report_clinics('2026-08-15', '2026-08-15') c;
  insert into _probe_result values ('canceled_clinic_fee_gets_its_own_row', 'Probe Aug 15 canceled|0|0|0|2300', coalesce(v, 'NO ROWS'));

  -- September 1 in New York holds nothing: B is August 31 there.
  select * into s from public.admin_board_report('2026-09-01', '2026-09-01');
  insert into _probe_result values ('sep1_is_empty', '0|0|0|0|0|0|0|0|0',
    s.member_attendances || '|' || s.nonmember_attendances || '|' || s.member_players || '|' || s.nonmember_players
    || '|' || s.clinics || '|' || s.fees_due_cents || '|' || s.collected_cents || '|' || s.board_share_cents
    || '|' || s.board_share_of_due_cents);
  select count(*) into n from public.admin_board_report_clinics('2026-09-01', '2026-09-01');
  insert into _probe_result values ('sep1_has_no_clinic_rows', '0', n::text);

  -- July 31 at 10 pm is July in New York (August 1 in UTC).
  select * into s from public.admin_board_report('2026-07-01', '2026-07-31');
  insert into _probe_result values ('jul_catches_the_late_clinic', '1|0|1800|1800',
    s.member_attendances || '|' || s.nonmember_attendances || '|' || s.fees_due_cents || '|' || s.collected_cents);

  -- Winter (EST, UTC-5): January 31 at 11:30 pm is February 1 04:30 UTC.
  select * into s from public.admin_board_report('2026-01-01', '2026-01-31');
  insert into _probe_result values ('jan_catches_the_winter_late_clinic', '1|0|1|1800|1800',
    s.member_attendances || '|' || s.nonmember_attendances || '|' || s.clinics || '|' || s.fees_due_cents || '|' || s.collected_cents);
  select * into s from public.admin_board_report('2026-02-01', '2026-02-28');
  select count(*) into n from public.admin_board_report_clinics('2026-02-01', '2026-02-28');
  insert into _probe_result values ('feb_does_not', '0|0|0|0|0|rows 0',
    s.member_attendances || '|' || s.nonmember_attendances || '|' || s.clinics || '|' || s.fees_due_cents
    || '|' || s.collected_cents || '|rows ' || n);

  -- "Has ended" is ends_at <= now(), decided against the three clinics made
  -- relative to now(), not against whatever the seed happens to hold.
  select coalesce(string_agg(c.clinic_name, ' ; ' order by c.starts_at), 'NONE') into v
    from public.admin_board_report_clinics(((now() at time zone ny) - interval '1 day')::date,
                                           ((now() at time zone ny) + interval '1 day')::date) c
   where c.clinic_id in (c_end, c_now, c_later);
  insert into _probe_result values ('only_the_ended_clinic_counts', 'Probe ended', v);

  -- Every period used above: the clinic rows add up to the summary, column by
  -- column. A mismatch names the period.
  bad := null;
  for per in
    select * from (values ('2026-08-01'::date, '2026-08-31'::date), ('2026-08-10', '2026-08-10'),
                          ('2026-08-15', '2026-08-15'), ('2026-08-20', '2026-08-20'),
                          ('2026-08-31', '2026-08-31'), ('2026-09-01', '2026-09-01'),
                          ('2026-07-01', '2026-07-31'), ('2026-01-01', '2026-01-31'),
                          ('2026-02-01', '2026-02-28'),
                          (((now() at time zone ny) - interval '1 day')::date, ((now() at time zone ny) + interval '1 day')::date)
                  ) t(f, t2)
  loop
    select s3.member_attendances || '|' || s3.nonmember_attendances || '|' || s3.fees_due_cents || '|' || s3.collected_cents
      into v from public.admin_board_report(per.f, per.t2) s3;
    select coalesce(sum(c.member_attendances), 0) || '|' || coalesce(sum(c.nonmember_attendances), 0) || '|'
           || coalesce(sum(c.fees_due_cents), 0) || '|' || coalesce(sum(c.collected_cents), 0)
      into x from public.admin_board_report_clinics(per.f, per.t2) c;
    if v is distinct from x then
      bad := coalesce(bad || ', ', '') || per.f || '..' || per.t2 || ' (' || v || ' vs ' || x || ')';
    end if;
  end loop;
  insert into _probe_result values ('totals_equal_clinic_rows_every_period', 'none', coalesce(bad, 'none'));

  -- invalid_period: backwards, or either end missing.
  begin
    perform public.admin_board_report('2026-08-31', '2026-08-01');
    insert into _probe_result values ('backwards_period_rejected', 'invalid_period', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('backwards_period_rejected', 'invalid_period', sqlerrm);
  end;
  begin
    perform public.admin_board_report(null, '2026-08-31');
    insert into _probe_result values ('null_from_rejected', 'invalid_period', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('null_from_rejected', 'invalid_period', sqlerrm);
  end;
  begin
    perform public.admin_board_report_clinics('2026-08-01', null);
    insert into _probe_result values ('clinics_null_to_rejected', 'invalid_period', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('clinics_null_to_rejected', 'invalid_period', sqlerrm);
  end;

  -- The ledger names the decline for Tara.
  select coalesce(l.failure_code, 'NULL') || ' | ' || l.first_name || ' ' || l.last_name || ' | ' || l.status
    into v from public.payments_ledger l where l.id = p5;
  insert into _probe_result values ('ledger_shows_decline_code_to_admin',
    'insufficient_funds | Maria Alvarez | failed', coalesce(v, 'NO ROW'));
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------ THE MONEY TAB (20260927100003)
  -- Maria's card, so "with a card" has one yes (the webhook's job; postgres
  -- stands in). Dana, the other not-charged row, has none.
  update public.accounts set stripe_customer_id = 'cus_probe_maria', card_brand = 'visa', card_last4 = '4242' where id = MARIA;
  perform set_config('request.jwt.claims', json_build_object('sub', TARA)::text, true);
  perform set_config('role', 'authenticated', true);

  select m.charged_cents || '|' || m.declined_count || '|' || m.declined_cents || '|' || m.not_charged_count
         || '|' || m.not_charged_cents || '|' || m.not_charged_clinics
    into v from public.admin_money_summary() m;
  insert into _probe_result values ('money_summary_from_the_ledger', '15905|1|2200|2|1800|2', coalesce(v, 'NO ROW'));

  -- Charged is the board's collected with no dates: the two cannot disagree.
  select s2.collected_cents || '|' || (select m.charged_cents from public.admin_money_summary() m)
    into v from public.admin_board_report('2000-01-01', '2099-12-31') s2;
  insert into _probe_result values ('money_charged_equals_board_collected', '15905|15905', v);

  select string_agg(c.clinic_name || '|' || case when c.canceled then 't' else 'f' end || '|' || c.charged_cents
                    || '|' || c.declined_count || '|' || c.not_charged_count || '|' || c.not_charged_cents
                    || '|' || c.chargeable_count, ' ; ')
    into v from public.admin_money_clinics() c;
  insert into _probe_result values ('money_clinic_rows_newest_first',
    'Probe ended|f|0|0|1|1800|1 ; Probe Aug 31 late|f|2800|1|1|0|0 ; Probe Aug 20 all no-show|f|1805|0|0|0|0 ; '
    || 'Probe Aug 15 canceled|t|2300|0|0|0|0 ; Probe Aug 10|f|5400|0|0|0|0 ; Probe Jul 31 late|f|1800|0|0|0|0 ; '
    || 'Probe Jan 31 late|f|1800|0|0|0|0',
    coalesce(v, 'NO ROWS'));

  select sum(c.charged_cents) || '|' || sum(c.declined_count) || '|' || sum(c.not_charged_count) || '|' || sum(c.not_charged_cents)
    into v from public.admin_money_clinics() c;
  insert into _probe_result values ('money_clinic_rows_add_up', '15905|1|2|1800', coalesce(v, 'NO ROWS'));

  select string_agg(d.first_name || ' ' || d.last_name || '|' || d.clinic_name || '|' || d.amount_cents
                    || '|' || coalesce(d.failure_code, 'NULL'), ' ; ')
    into v from public.admin_money_declined() d;
  insert into _probe_result values ('money_declined_names_the_cardholder', 'Ken Whitfield|Probe Aug 31 late|2200|expired_card',
    coalesce(v, 'NO ROWS'));
  perform set_config('role', 'postgres', true);

  -- ------------------------------------------------------ ATTACK: Maria
  -- A member asking for the report is refused outright: counts of anything
  -- are never returned to a player (hard rule 1).
  perform set_config('request.jwt.claims', json_build_object('sub', MARIA)::text, true);
  perform set_config('role', 'authenticated', true);
  begin
    perform public.admin_board_report('2026-08-01', '2026-08-31');
    insert into _probe_result values ('member_cannot_run_board_report', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_run_board_report', 'not_authorized', sqlerrm);
  end;
  begin
    perform public.admin_board_report_clinics('2026-08-01', '2026-08-31');
    insert into _probe_result values ('member_cannot_run_clinic_rows', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_run_clinic_rows', 'not_authorized', sqlerrm);
  end;
  -- Her own declined payment is not readable through the admin ledger.
  select count(*) into n from public.payments_ledger;
  insert into _probe_result values ('member_sees_nothing_in_ledger', '0', n::text);
  -- Nor through the Money tab's three functions: refused, not zeroes.
  begin
    perform public.admin_money_summary();
    insert into _probe_result values ('member_cannot_run_money_summary', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_run_money_summary', 'not_authorized', sqlerrm);
  end;
  begin
    perform public.admin_money_clinics();
    insert into _probe_result values ('member_cannot_run_money_clinics', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_run_money_clinics', 'not_authorized', sqlerrm);
  end;
  begin
    perform public.admin_money_declined();
    insert into _probe_result values ('member_cannot_run_money_declined', 'not_authorized', 'CALL SUCCEEDED');
  exception when others then
    insert into _probe_result values ('member_cannot_run_money_declined', 'not_authorized', sqlerrm);
  end;
  perform set_config('role', 'postgres', true);
  perform set_config('request.jwt.claims', null, true);

  -- --------------------------------------------------------- grant surface
  -- anon is asserted by privilege, not by calling: the local image segfaults
  -- the backend when a role without EXECUTE calls a function (CLAUDE.md,
  -- "Known local-environment defect").
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('admin_board_report', 'admin_board_report_clinics')
     and has_function_privilege('anon', p.oid, 'EXECUTE');
  insert into _probe_result values ('anon_cannot_execute_report', '0', n::text);

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('admin_board_report', 'admin_board_report_clinics')
     and (p.proacl is null or exists (select 1 from aclexplode(p.proacl) a
                                      where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  insert into _probe_result values ('public_cannot_execute_report', '0', n::text);

  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('admin_board_report', 'admin_board_report_clinics')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and p.prosecdef
     and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
  insert into _probe_result values ('report_is_definer_pinned_and_callable_signed_in', '2', n::text);

  -- failure_code reaches Tara through the view, and the view is still select-only.
  insert into _probe_result values ('ledger_has_failure_code_column', 'true',
    exists (select 1 from information_schema.columns
             where table_schema = 'public' and table_name = 'payments_ledger' and column_name = 'failure_code')::text);
  select count(*) into n from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'payments_ledger'
     and grantee in ('anon', 'authenticated', 'PUBLIC')
     and privilege_type <> 'SELECT';
  insert into _probe_result values ('ledger_still_select_only', '0', n::text);
  insert into _probe_result values ('anon_cannot_select_ledger', 'false',
    has_table_privilege('anon', 'public.payments_ledger', 'SELECT')::text);

  -- No client writes failure_code: payments stays read-only to authenticated.
  insert into _probe_result values ('client_cannot_write_failure_code', 'false',
    has_column_privilege('authenticated', 'public.payments', 'failure_code', 'UPDATE')::text);

  -- The Money tab's functions: anon and PUBLIC hold nothing, the signed-in
  -- may call the three (each refuses a member inside), and money_rows is
  -- internal to them.
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('admin_money_summary', 'admin_money_clinics', 'admin_money_declined', 'money_rows')
     and (has_function_privilege('anon', p.oid, 'EXECUTE')
          or p.proacl is null
          or exists (select 1 from aclexplode(p.proacl) a where a.grantee = 0 and a.privilege_type = 'EXECUTE'));
  insert into _probe_result values ('money_tab_functions_closed_to_anon_and_public', '0', n::text);
  select count(*) into n from pg_proc p join pg_namespace ns on ns.oid = p.pronamespace
   where ns.nspname = 'public' and p.proname in ('admin_money_summary', 'admin_money_clinics', 'admin_money_declined')
     and has_function_privilege('authenticated', p.oid, 'EXECUTE')
     and p.prosecdef
     and exists (select 1 from unnest(p.proconfig) c where c like 'search_path=%');
  insert into _probe_result values ('money_tab_functions_definer_pinned_callable', '3', n::text);
  insert into _probe_result values ('money_rows_is_internal', 'false',
    has_function_privilege('authenticated', 'public.money_rows()', 'EXECUTE')::text);
end $$;

select check_name, expected, actual,
       case when actual = expected then 'PASS' else 'FAIL' end as result
from _probe_result order by check_name;

rollback;
