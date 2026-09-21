-- 20260921000002_waiver.sql
--
-- Decision 0013 §4. Tara sent "FXE_Adult_Tennis_Participation_Waiver.docx"
-- (version date September 2026) on 2026-09-21. Its last page specifies the
-- mechanism, so nothing here is invented:
--
--   Required checkbox: "I have read and agree to the Adult Tennis
--     Participation Waiver and Release."
--   Electronic signature: participant enters full legal name.
--   Participant email: captured from the signed-in account.
--   Date and time: recorded automatically by the app.
--   Agreement record: store the waiver version and acceptance record.
--
-- So: waivers (one row per version, her text verbatim), waiver_acceptances
-- (who, which version, the typed name, the account email, when, which app
-- build), accept_waiver() as the only writer, my_waiver_status() for the
-- app, and register_for_clinic refusing with waiver_required until the
-- current version is accepted. Section 8 of her text says a current waiver
-- may be required before future activities, which is why the check is per
-- version, not once per account.

create table public.waivers (
  version      text primary key,
  title        text not null,
  organizer    text not null,
  body         text not null,
  published_at timestamptz not null default now()
);
comment on table public.waivers is 'Tara''s waiver text, one row per version (decision 0013). Read-only for players.';

create table public.waiver_acceptances (
  id          uuid primary key default gen_random_uuid(),
  account_id  uuid not null references public.accounts(id) on delete cascade,
  version     text not null references public.waivers(version),
  legal_name  text not null,
  email       text not null,
  accepted_at timestamptz not null default now(),
  app_version text,
  unique (account_id, version)
);
comment on table public.waiver_acceptances is 'Electronic signatures (decision 0013). Written only by accept_waiver(); no client reads it.';

-- Hard rule 11: enumerate, then grant. Default privileges were revoked in
-- 20260813000001, but a revoke that is written down is the one that is
-- verified by grants_are_explicit.sql.
revoke all on public.waivers, public.waiver_acceptances from public, anon, authenticated;
alter table public.waivers enable row level security;
alter table public.waiver_acceptances enable row level security;
-- No policies on purpose: every access goes through the two functions.

insert into public.app_settings (key, value) values ('waiver_version', '2026-09')
on conflict (key) do update set value = excluded.value;

insert into public.waivers (version, title, organizer, body) values (
  '2026-09',
  'Adult Tennis Participation Waiver and Release',
  'FXE Tennis LLC and Foxcroft East Racquet and Swim Club',
  $w$Please read carefully. This agreement affects your legal rights. By signing electronically, you agree to its terms for adult participation in tennis clinics, lessons, matches, events, and related activities organized, hosted, or provided by FXE Tennis, LLC or Foxcroft East Racquet and Swim Club.

IMPORTANT NOTICE: This agreement includes an assumption of risk and a release of claims, including claims based on ordinary negligence, to the fullest extent permitted by North Carolina law.

1  Activities and Released Parties

I wish to participate in adult tennis and related activities, including clinics, lessons, drills, games, matches, tournaments, social events, fitness or conditioning activities, and use of tennis courts, facilities, equipment, parking areas, walkways, and surrounding premises (collectively, the Activities). In this agreement, the Released Parties are FXE Tennis, LLC; Foxcroft East Racquet and Swim Club; and each of their respective owners, officers, directors, board members, employees, tennis professionals, coaches, agents, independent contractors, volunteers, members, affiliates, successors, assigns, and premises owners or lessors.

2  Acknowledgment of Risks

I understand that tennis and related activities involve inherent and other risks that can cause property damage, illness, serious injury, disability, or death. Risks include, without limitation, strenuous physical exertion; rapid movement, twisting, falls, overuse, and loss of balance; contact with racquets, balls, nets, fences, court fixtures, equipment, other participants, instructors, spectators, or objects; uneven, wet, slippery, cracked, hot, or otherwise hazardous surfaces; weather, heat, humidity, lightning, and other environmental conditions; equipment failure or misuse; acts or omissions of other participants; and delayed access to medical care. I understand that this list is not complete and that unexpected risks may arise.

3  Voluntary Participation and Fitness

I am at least 18 years old and voluntarily choose to participate. I am responsible for deciding whether I am physically and medically able to participate and for seeking medical advice when appropriate. I will stop participating and notify a tennis professional if I experience pain, dizziness, breathing difficulty, or another concerning symptom. I will follow reasonable safety rules and instructions, use appropriate footwear and equipment, and avoid participating while impaired by alcohol, drugs, illness, or medication that makes participation unsafe.

4  Assumption of Risk

I knowingly and voluntarily accept and assume all known and unknown risks of the Activities, whether inherent or arising from the condition of the premises, equipment, weather, the conduct of participants or others, or the ordinary negligence of any Released Party, to the fullest extent permitted by law.

5  Release and Waiver of Claims

To the fullest extent permitted by law, I release, waive, and discharge the Released Parties from claims, demands, causes of action, liabilities, damages, losses, or expenses arising out of or related to my participation in the Activities, including claims for personal injury, illness, death, or property damage caused in whole or in part by the ordinary negligence of a Released Party. This release does not apply to gross negligence, willful or wanton misconduct, intentional wrongdoing, or any liability that cannot legally be released.

6  Responsibility for My Conduct

I am responsible for my own conduct and property. To the fullest extent permitted by law, I agree to indemnify and hold the Released Parties harmless from third-party claims, liabilities, damages, or expenses, including reasonable attorneys' fees, caused by my negligent or intentional conduct, my violation of safety rules or instructions, or my material breach of this agreement. This provision does not require me to indemnify a Released Party for that party's gross negligence, willful or wanton misconduct, or intentional wrongdoing.

7  Emergency Care

If I become injured or ill and cannot make decisions for myself, I authorize the Released Parties to contact emergency services and arrange reasonably necessary emergency assistance. I understand that the Released Parties are not required to provide medical care and that I am responsible for costs charged by medical providers, emergency responders, or transportation services.

8  Duration and Revocation

This agreement begins when I sign it and remains effective until I revoke it in writing by delivering notice to FXE Tennis, LLC. Revocation applies only to Activities occurring after the revocation is received and does not affect the agreement's application to Activities that occurred before then. I understand that I may be required to accept a current waiver before participating in future Activities.

9  North Carolina Law and Severability

This agreement is governed by North Carolina law. Any provision found unenforceable will be enforced to the maximum extent permitted, and the remaining provisions will continue in effect. This agreement is intended to be as broad as North Carolina law permits.

10  Electronic Agreement

I consent to using an electronic record and electronic signature. By checking the required box and entering my legal name, I intend to sign this agreement electronically. I understand that my electronic acceptance may be stored with the agreement version, date and time, account information, and available technical records.

Participant Acknowledgment

BY SIGNING, I CONFIRM THAT I HAVE READ AND UNDERSTAND THIS AGREEMENT, HAVE HAD THE OPPORTUNITY TO ASK QUESTIONS, AND VOLUNTARILY AGREE TO ALL OF ITS TERMS.$w$
);

create or replace function public.waiver_version()
returns text
language sql stable security definer set search_path = public, pg_temp
as $$
  select value from public.app_settings where key = 'waiver_version';
$$;

-- The current waiver, for the sheet the app shows.
create or replace function public.current_waiver()
returns table (version text, title text, organizer text, body text, published_at timestamptz)
language sql stable security definer set search_path = public, pg_temp
as $$
  select w.version, w.title, w.organizer, w.body, w.published_at
    from public.waivers w
   where w.version = public.waiver_version();
$$;

-- True when the signed-in account has accepted the current version.
create or replace function public.my_waiver_accepted()
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.waiver_acceptances a
     where a.account_id = auth.uid() and a.version = public.waiver_version()
  );
$$;

-- Internal: any account, used by register_for_clinic and search_players.
create or replace function public.waiver_accepted(p_account uuid)
returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.waiver_acceptances a
     where a.account_id = p_account and a.version = public.waiver_version()
  );
$$;

-- The signature. The email comes from the account row, never from the
-- client (her spec: "captured from the signed-in account"). Accepting the
-- same version twice keeps the first record: a signature is not overwritten.
create or replace function public.accept_waiver(p_version text, p_legal_name text, p_app_version text default null)
returns public.waiver_acceptances
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  v_name  text := btrim(coalesce(p_legal_name, ''));
  v_email text;
  v_row   public.waiver_acceptances;
begin
  if auth.uid() is null then
    raise exception 'not_authenticated' using errcode = '42501';
  end if;
  if p_version is distinct from public.waiver_version() then
    raise exception 'waiver_version_stale' using errcode = 'P0001';
  end if;
  if length(v_name) < 3 or position(' ' in v_name) = 0 then
    raise exception 'legal_name_required' using errcode = 'P0001';
  end if;
  select email into v_email from public.accounts where id = auth.uid();
  if v_email is null then
    raise exception 'account_not_found' using errcode = 'P0002';
  end if;

  insert into public.waiver_acceptances (account_id, version, legal_name, email, app_version)
  values (auth.uid(), p_version, left(v_name, 120), v_email, left(p_app_version, 40))
  on conflict (account_id, version) do nothing
  returning * into v_row;
  if v_row.id is null then
    select * into v_row from public.waiver_acceptances
     where account_id = auth.uid() and version = p_version;
  end if;
  return v_row;
end;
$$;

revoke all on function public.waiver_version()      from public, anon;
revoke all on function public.current_waiver()      from public, anon;
revoke all on function public.my_waiver_accepted()  from public, anon;
revoke all on function public.waiver_accepted(uuid) from public, anon, authenticated;
revoke all on function public.accept_waiver(text, text, text) from public, anon;
grant execute on function public.waiver_version()     to authenticated;
grant execute on function public.current_waiver()     to authenticated;
grant execute on function public.my_waiver_accepted() to authenticated;
grant execute on function public.accept_waiver(text, text, text) to authenticated;

-- ------------------------------- register_for_clinic: waiver before a spot
-- Same body as 20260916000001 plus the waiver check, placed after the card
-- check so the error a player sees first is the one they can fix first.
-- Tara placing someone by hand is not blocked (capacity never blocks Tara,
-- and neither does paperwork she can chase in person).
create or replace function public.register_for_clinic(p_clinic uuid, p_player uuid)
returns public.registrations
language plpgsql security definer set search_path = public, pg_temp
as $$
declare
  c        public.clinics;
  v_member boolean;
  v_taken  integer;
  v_status registration_status;
  v_row    public.registrations;
  v_card   boolean;
  v_account uuid;
begin
  if not (public.owns_player(p_player) or public.is_admin()) then
    raise exception 'not_authorized' using errcode = '42501';
  end if;

  select * into c from public.clinics
   where id = p_clinic and status = 'published'
   for update;
  if not found then
    raise exception 'clinic_not_found' using errcode = 'P0002';
  end if;

  if c.closes_at is not null and now() >= c.closes_at then
    raise exception 'registration_closed' using errcode = 'P0001';
  end if;

  select is_member, account_id into v_member, v_account from public.players where id = p_player;
  if v_member is null then
    raise exception 'player_not_found' using errcode = 'P0002';
  end if;

  -- Decision 0012: "Gosh I say yes." A player cannot hold a spot without a
  -- card once payments are on. Tara placing someone by hand is not blocked.
  if public.payments_enabled() and public.card_required() and not public.is_admin() then
    select a.stripe_customer_id is not null into v_card
      from public.players p join public.accounts a on a.id = p.account_id
     where p.id = p_player;
    if not coalesce(v_card, false) then
      raise exception 'card_required' using errcode = 'P0001';
    end if;
  end if;

  -- Decision 0013 §4: the waiver is signed before the first spot is held.
  if not public.is_admin() and not public.waiver_accepted(v_account) then
    raise exception 'waiver_required' using errcode = 'P0001';
  end if;

  if now() < c.member_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif not v_member and now() < c.public_opens_at then
    raise exception 'registration_not_open' using errcode = 'P0001';
  elsif v_member and now() < c.public_opens_at then
    select count(*) into v_taken
      from public.registrations
     where clinic_id = p_clinic and status = 'in';
    v_status := case when v_taken < c.internal_capacity then 'in' else 'pool' end;
  else
    v_status := 'pool';
  end if;

  insert into public.registrations (
      clinic_id, player_id, status, source,
      price_cents_charged, was_member, duration_minutes)
  values (p_clinic, p_player, v_status,
          case when public.owns_player(p_player) then 'self'::registration_source
                                                 else 'admin'::registration_source end,
          case when v_member then c.member_price_cents else c.nonmember_price_cents end,
          v_member,
          c.duration_minutes)
  returning * into v_row;

  return v_row;
exception
  when unique_violation then
    raise exception 'already_registered' using errcode = 'P0001';
end;
$$;

-- --------------------------- search_players: level note and the signature
-- Decision 0013 §6 ("Both"): the note only Tara sees shows on the roster and
-- on the player's page. And she can see who has not signed the waiver.
drop function public.search_players(text, boolean);
create function public.search_players(p_query text, p_include_inactive boolean default false)
returns table (
  id uuid, first_name text, last_name text, kind public.player_kind,
  age integer, adult_rating numeric, is_member boolean, is_active boolean,
  has_notes boolean, level_note text, waiver_accepted boolean
)
language plpgsql stable security definer set search_path = public, pg_temp
as $$
begin
  perform public.require_admin();
  return query
    select p.id, p.first_name, p.last_name, p.kind,
           public.player_age(p.date_of_birth), p.adult_rating,
           p.is_member, p.is_active,
           exists (select 1 from public.player_notes n
                    where n.player_id = p.id and n.body <> ''),
           p.level_note,
           public.waiver_accepted(p.account_id)
      from public.players p
     where (p_include_inactive or p.is_active)
       and (
         p_query is null or p_query = ''
         or p.first_name ilike '%' || p_query || '%'
         or p.last_name  ilike '%' || p_query || '%'
       )
     order by p.last_name, p.first_name;
end;
$$;
revoke all on function public.search_players(text, boolean) from public, anon;
grant execute on function public.search_players(text, boolean) to authenticated;
