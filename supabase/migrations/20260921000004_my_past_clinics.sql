-- 20260921000004_my_past_clinics.sql
--
-- Feature review 2026-09-02 ("soon"): finished clinics vanish from every
-- player list by design (clinics_public keeps ends_at > now(), 20260828), so
-- a player checking what they played, or what they will be charged for, had
-- nowhere to look. Tara confirmed the shape on 2026-09-16 (decision 0012
-- §10: "it drops off the players' list; Past is on her side" is HER list;
-- this is the player's own history).
--
-- my_past_clinics: the signed-in player's own registrations in clinics that
-- have ended, with the clinic's name and time and the player's own outcome
-- (You're In! or canceled, no-show, what it cost them). Nothing about anyone
-- else and none of the nine hidden facts (hard rule 1): no capacity, no
-- count, no court, no location. Owner-run like the other player views
-- (hard rule 11: revoke before grant, and never security_invoker).

create view public.my_past_clinics as
  select r.id as registration_id, c.id as clinic_id, c.name, c.starts_at, c.ends_at,
         c.duration_minutes, c.category, c.audience,
         r.status, r.no_show, r.late_cancel, r.canceled_at, r.price_cents_charged, r.paid
    from public.registrations r
    join public.clinics c on c.id = r.clinic_id
   where public.owns_player(r.player_id)
     and c.status in ('published', 'canceled')
     and c.ends_at <= now();

comment on view public.my_past_clinics is
  'A player''s own finished clinics (decision 0012 §10, feature review 09-02). Own rows only; no hidden fact.';

revoke all on public.my_past_clinics from public, anon, authenticated;
grant select on public.my_past_clinics to authenticated;
