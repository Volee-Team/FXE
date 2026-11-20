-- A canceled clinic shows only to the players who were on it.
--
-- Tara, 2026-11-20: "I can't see the canceled coed 105 from my desktop, but I
-- can see it on my phone, and so can everybody else. Is there a way to get rid
-- of that? It's just confusing because it's not supposed to be canceled, but
-- there is another one that they can sign up for at the same time, also
-- called coed Black Friday 105." Hosted: two "COED Black Friday 105" clinics
-- on 11-27 at 9:00; she canceled the duplicate on 11-18 and nobody had ever
-- registered for it, yet clinics_public listed it, wearing Canceled, to every
-- player until it ends, because since 20260929000001 the view shows every
-- canceled clinic that was once published. The laptop hides canceled clinics
-- behind Show canceled (2026-09-10); players had no such filter.
--
-- Now a canceled clinic is listed only for an account with a player who has
-- a registration on it, in any state: someone who held a spot, was on the
-- Waitlist or was invited still sees "Canceled" and knows. Everyone else does
-- not see it at all. Published clinics and drafts are unchanged.
-- Pinned by tests/sql/canceled_drafts.sql (canceled_clinic_nobody_was_on_is_gone,
-- canceled_clinic_gone_for_who_was_not red before this;
-- canceled_clinic_still_shown_to_who_was_on_it green before and after).
--
-- The view keeps its columns, owner rights and grants exactly as
-- 20261115000001 left them; only the canceled branch of the WHERE changes.

create or replace view public.clinics_public as
  select id, name, audience, category, description, price_cents,
         starts_at, ends_at, member_opens_at, public_opens_at, closes_at,
         status, canceled_at, member_price_cents, nonmember_price_cents,
         duration_minutes,
         (case when public.level_check_enabled() then min_rating end)::numeric(2,1) as min_rating
    from public.clinics c
   where (c.status = 'published'
          or (c.status = 'canceled' and c.published_at is not null
              and exists (select 1 from public.registrations r
                            join public.players p on p.id = r.player_id
                           where r.clinic_id = c.id and p.account_id = auth.uid())))
     and c.ends_at > now()
     -- Juniors clinics are read through the family functions (phase 1 and
     -- 2): an app that cannot register a child would only show a Register
     -- button that wrong_player_kind refuses.
     and c.audience <> 'juniors'
     and (
       c.audience not in ('ladies', 'men')
       or not exists (select 1 from public.players p
                       where p.account_id = auth.uid() and p.kind = 'adult')
       or exists (select 1 from public.players p
                   where p.account_id = auth.uid() and p.kind = 'adult'
                     and public.audience_open_to(c.audience, p.gender))
       or exists (select 1 from public.registrations r
                    join public.players p on p.id = r.player_id
                   where r.clinic_id = c.id and p.account_id = auth.uid() and p.kind = 'adult')
     );

revoke all on public.clinics_public from public, anon, authenticated;
grant select on public.clinics_public to authenticated;
