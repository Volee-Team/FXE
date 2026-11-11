-- 20261111000001_membership_reprices.sql
--
-- Tara, 2026-11-11: "[a player] is a member and getting charged nonmember
-- prices. Can you check on this?" The player signed up as a non-member and
-- registered for six clinics; Tara made her a member three days later.
-- Every registration keeps the price and was_member it was made with, and
-- admin_set_membership changed players.is_member alone, so four clinics were
-- charged the non-member price after she was a member and a fifth was about
-- to be.
--
-- THE RULE (decision 0055): Tara's membership answer is the price basis for
-- every clinic not yet over. admin_set_membership now moves the player's
-- registrations that can still owe (not canceled, or a late cancel), on a
-- clinic not canceled that has not ended, not marked Paid and holding no
-- live fee, to the new answer:
-- was_member, and the price the clinic gives that answer (clinic_price_for:
-- the rain half and a no-show included). A price she typed by hand
-- (price_set_by_admin, decision 0054) keeps its amount; its was_member still
-- follows, so null puts back the right clinic price. Money already taken is
-- a refund, not a reprice: those rows are left alone, both ways.
--
-- Both ways: a player made a non-member owes the non-member price for what
-- is still to come, as one who had answered "non-member" would.
--
-- A clinic that has ended keeps what it was, charged or not (decision 0002:
-- "A player who joins the club in October still owed the non-member rate in
-- September"); the board's and Tara's reports for a closed period never move
-- (the sql-auditor, 2026-11-11, found the first draft rewrote them). Tara
-- changes one past row by hand with Set price (0054).
--
-- Locks: the clinics, in id order, then the rows, the order reprice_clinic
-- and the charges take (20261109000001).
--
-- Backfill: the registrations that already differ from their player's
-- answer, under the same conditions, as if the rule had been there. On
-- 2026-11-11 hosted had one such row on a clinic not yet over (a real
-- player's, on 11-13: $28 for a member, $22 owed).

create or replace function public.admin_set_membership(p_player uuid, p_is_member boolean)
returns public.players
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v public.players;
begin
  perform public.require_admin();
  update public.players set is_member = p_is_member where id = p_player
  returning * into v;
  if not found then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;
  perform public.follow_membership(p_player);
  return v;
end;
$$;

comment on function public.admin_set_membership(uuid, boolean) is
  'Admin-only. Corrects self-reported membership (for-tara.md question 5); the player''s registrations not yet charged follow it (20261111000001).';

-- Internal: one player's registrations that can still owe, to the player's
-- membership now. Returns how many changed.
create or replace function public.follow_membership(p_player uuid)
returns integer
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  m boolean;
  n integer;
begin
  select is_member into m from public.players where id = p_player;
  perform 1 from public.clinics c
   where c.id in (select r.clinic_id from public.registrations r where r.player_id = p_player)
   order by c.id for update;
  perform 1 from public.registrations r where r.player_id = p_player order by r.id for update;
  update public.registrations r
     set was_member = m,
         price_cents_charged = case when r.price_set_by_admin then r.price_cents_charged
                                    else public.clinic_price_for(c, m, r.status, r.no_show) end
    from public.clinics c
   where c.id = r.clinic_id
     and r.player_id = p_player
     and r.was_member is distinct from m
     and (r.status <> 'canceled' or r.late_cancel)
     and c.status <> 'canceled'
     and c.ends_at > now()
     and not r.paid
     and not public.registration_has_live_fee(r.id);
  get diagnostics n = row_count;
  return n;
end;
$$;
revoke all on function public.follow_membership(uuid) from public, anon, authenticated;

comment on column public.registrations.was_member is
  'Whether the player was a member when this was made; the price basis. Tara''s membership correction moves it on clinics not yet over and not charged (20261111000001, decision 0055); an ended clinic keeps it (decision 0002).';

-- Hard rule 11: revoke before grant, and from PUBLIC, not just anon.
revoke all on function public.admin_set_membership(uuid, boolean) from public, anon, authenticated;
grant execute on function public.admin_set_membership(uuid, boolean) to authenticated;

-- Backfill.
do $$
declare p uuid;
begin
  for p in
    select distinct r.player_id
      from public.registrations r
      join public.players pl on pl.id = r.player_id
      join public.clinics c on c.id = r.clinic_id
     where r.was_member is distinct from pl.is_member
       and (r.status <> 'canceled' or r.late_cancel)
       and c.status <> 'canceled'
       and c.ends_at > now()
       and not r.paid
     order by 1
  loop
    perform public.follow_membership(p);
  end loop;
end $$;
