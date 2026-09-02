-- Every function in public was executable by anon. Not one of them was meant to be.
--
-- WHAT WAS WRONG
-- --------------
-- Postgres grants EXECUTE on every new function to PUBLIC, the pseudo-role every
-- other role belongs to. Several migrations here revoked "from anon", which
-- reads as if it closes the door but is a no-op while PUBLIC still holds the
-- privilege (20260815000001 says exactly this about create_my_account, and got
-- it right for that one function). On 2026-09-01 the count was 30 of 41
-- functions executable by anon, including assign_court, cancel_clinic,
-- set_paid, publish_clinic, place_player and send_clinic_message.
--
-- WHY IT DID NOT LEAK
-- -------------------
-- Every one of those functions begins with require_admin() or an auth.uid()
-- check, so an anonymous caller gets 42501 at runtime. Nothing was exposed.
-- But hard rule 11 exists because "the function checks" is one line of code
-- away from not being true, and the grant surface is the layer that holds when
-- the code does not. The probe suite asserted the surface for tables and views
-- since 2026-08-16 and never asked the same question of functions.
--
-- WHAT THIS DOES
-- --------------
-- For every function in public, in the order hard rule 11 requires:
--   1. revoke ALL from PUBLIC and anon (PUBLIC is the one that matters);
--   2. grant EXECUTE to authenticated on every function a signed-in client may
--      call, which is every non-trigger function except the two internal
--      helpers (admin_account_ids, notify_account) that only run inside other
--      SECURITY DEFINER functions.
-- Trigger functions get no grant at all: Postgres checks EXECUTE at CREATE
-- TRIGGER time, not when the trigger fires, and the full probe suite inserting
-- as authenticated is the proof.
--
-- Statements are written out, not looped, so the surface can be read here.
-- The probe in tests/sql/grants_are_explicit.sql enumerates pg_proc, so a
-- function added next month is caught before anyone remembers this file.

revoke all on function public.admin_account_ids() from public, anon;

revoke all on function public.admin_delete_template(p_id uuid) from public, anon;
grant execute on function public.admin_delete_template(p_id uuid) to authenticated;

revoke all on function public.admin_upsert_clinic(p_id uuid, p_name text, p_audience text, p_starts_at timestamp with time zone, p_duration_minutes integer, p_internal_capacity integer, p_category text, p_description text, p_member_opens_at timestamp with time zone, p_public_opens_at timestamp with time zone, p_closes_at timestamp with time zone) from public, anon;
grant execute on function public.admin_upsert_clinic(p_id uuid, p_name text, p_audience text, p_starts_at timestamp with time zone, p_duration_minutes integer, p_internal_capacity integer, p_category text, p_description text, p_member_opens_at timestamp with time zone, p_public_opens_at timestamp with time zone, p_closes_at timestamp with time zone) to authenticated;

revoke all on function public.admin_upsert_template(p_id uuid, p_name text, p_audience text, p_duration_minutes integer, p_internal_capacity integer, p_category text, p_description text) from public, anon;
grant execute on function public.admin_upsert_template(p_id uuid, p_name text, p_audience text, p_duration_minutes integer, p_internal_capacity integer, p_category text, p_description text) to authenticated;

revoke all on function public.apply_default_clinic_close() from public, anon;

revoke all on function public.apply_default_clinic_pricing() from public, anon;

revoke all on function public.assign_court(p_registration uuid, p_court smallint) from public, anon;
grant execute on function public.assign_court(p_registration uuid, p_court smallint) to authenticated;

revoke all on function public.bootstrap_first_admin() from public, anon;

revoke all on function public.cancel_clinic(p_clinic uuid) from public, anon;
grant execute on function public.cancel_clinic(p_clinic uuid) to authenticated;

revoke all on function public.cancel_invitation(p_registration uuid) from public, anon;
grant execute on function public.cancel_invitation(p_registration uuid) to authenticated;

revoke all on function public.cancel_registration(p_registration uuid) from public, anon;
grant execute on function public.cancel_registration(p_registration uuid) to authenticated;

revoke all on function public.create_clinic_from_template(p_template uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone) from public, anon;
grant execute on function public.create_clinic_from_template(p_template uuid, p_starts_at timestamp with time zone, p_ends_at timestamp with time zone) to authenticated;

revoke all on function public.create_my_account(p_first_name text, p_last_name text, p_phone text, p_is_member boolean, p_adult_rating numeric) from public, anon;
grant execute on function public.create_my_account(p_first_name text, p_last_name text, p_phone text, p_is_member boolean, p_adult_rating numeric) to authenticated;

revoke all on function public.default_closes_at(p_starts_at timestamp with time zone) from public, anon;
grant execute on function public.default_closes_at(p_starts_at timestamp with time zone) to authenticated;

revoke all on function public.default_price_cents(p_duration_minutes integer, p_is_member boolean) from public, anon;
grant execute on function public.default_price_cents(p_duration_minutes integer, p_is_member boolean) to authenticated;

revoke all on function public.guard_account_privilege_columns() from public, anon;

revoke all on function public.guard_player_owner_column() from public, anon;

revoke all on function public.invite_from_pool(p_registration uuid) from public, anon;
grant execute on function public.invite_from_pool(p_registration uuid) to authenticated;

revoke all on function public.is_admin() from public, anon;
grant execute on function public.is_admin() to authenticated;

revoke all on function public.leave_pool(p_registration uuid) from public, anon;
grant execute on function public.leave_pool(p_registration uuid) to authenticated;

revoke all on function public.mark_news_read(p_news uuid) from public, anon;
grant execute on function public.mark_news_read(p_news uuid) to authenticated;

revoke all on function public.member_opens_at(p_starts_at timestamp with time zone) from public, anon;
grant execute on function public.member_opens_at(p_starts_at timestamp with time zone) to authenticated;

revoke all on function public.notify_account(p_account uuid, p_type text, p_entity_type text, p_entity_id uuid, p_body text) from public, anon;

revoke all on function public.owns_player(p_player uuid) from public, anon;
grant execute on function public.owns_player(p_player uuid) to authenticated;

revoke all on function public.payment_instructions() from public, anon;
grant execute on function public.payment_instructions() to authenticated;

revoke all on function public.place_player(p_clinic uuid, p_player uuid, p_status registration_status) from public, anon;
grant execute on function public.place_player(p_clinic uuid, p_player uuid, p_status registration_status) to authenticated;

revoke all on function public.player_age(p_dob date) from public, anon;
grant execute on function public.player_age(p_dob date) to authenticated;

revoke all on function public.public_opens_at(p_starts_at timestamp with time zone) from public, anon;
grant execute on function public.public_opens_at(p_starts_at timestamp with time zone) to authenticated;

revoke all on function public.publish_clinic(p_clinic uuid) from public, anon;
grant execute on function public.publish_clinic(p_clinic uuid) to authenticated;

revoke all on function public.publish_news(p_news uuid) from public, anon;
grant execute on function public.publish_news(p_news uuid) to authenticated;

revoke all on function public.register_for_clinic(p_clinic uuid, p_player uuid) from public, anon;
grant execute on function public.register_for_clinic(p_clinic uuid, p_player uuid) to authenticated;

revoke all on function public.request_late_spot(p_clinic uuid, p_player uuid, p_message text) from public, anon;
grant execute on function public.request_late_spot(p_clinic uuid, p_player uuid, p_message text) to authenticated;

revoke all on function public.require_admin() from public, anon;
grant execute on function public.require_admin() to authenticated;

revoke all on function public.resolve_late_request(p_request uuid, p_approve boolean) from public, anon;
grant execute on function public.resolve_late_request(p_request uuid, p_approve boolean) to authenticated;

revoke all on function public.respond_to_invitation(p_registration uuid, p_accept boolean) from public, anon;
grant execute on function public.respond_to_invitation(p_registration uuid, p_accept boolean) to authenticated;

revoke all on function public.revenue_summary(p_from timestamp with time zone, p_to timestamp with time zone) from public, anon;
grant execute on function public.revenue_summary(p_from timestamp with time zone, p_to timestamp with time zone) to authenticated;

revoke all on function public.search_players(p_query text, p_include_inactive boolean) from public, anon;
grant execute on function public.search_players(p_query text, p_include_inactive boolean) to authenticated;

revoke all on function public.send_clinic_message(p_clinic uuid, p_audience message_audience, p_body text) from public, anon;
grant execute on function public.send_clinic_message(p_clinic uuid, p_audience message_audience, p_body text) to authenticated;

revoke all on function public.service_week_start(p_starts_at timestamp with time zone) from public, anon;
grant execute on function public.service_week_start(p_starts_at timestamp with time zone) to authenticated;

revoke all on function public.set_paid(p_registration uuid, p_paid boolean) from public, anon;
grant execute on function public.set_paid(p_registration uuid, p_paid boolean) to authenticated;

revoke all on function public.set_player_active(p_player uuid, p_active boolean) from public, anon;
grant execute on function public.set_player_active(p_player uuid, p_active boolean) to authenticated;
