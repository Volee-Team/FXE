-- SECURITY FIX: player could promote themselves to admin.
--
-- Found 2026-08-02 by adversarial review, reproduced end to end.
--
-- THE HOLE
--   public.accounts carried Supabase's default table-level grants to
--   `authenticated`, and the accounts_update_self policy had USING but no
--   WITH CHECK and no column scoping. An ordinary player could run:
--
--       update public.accounts set role = 'admin' where id = <their own id>;
--
--   USING passed (it is their own row), nothing constrained the NEW row, and
--   is_admin() then returned true. That defeats the entire information-hiding
--   model in one statement: clinic capacity, every registration in the club,
--   other players' names, court assignments and payment status all became
--   readable, plus every admin RPC became callable.
--
-- WHY THE EXISTING PROBE MISSED IT
--   information_hiding.sql asserted `maria_is_not_admin = false` and then
--   tested what a non-admin can read. It never attempted the escalation. A
--   probe that only tests the state you expect cannot find a transition you
--   did not think of. The probe now attacks.
--
-- THE FIX, three independent layers. Any one of them alone would close it;
-- all three are cheap and the failure mode is severe.
--
--   1. Column-level privileges. `authenticated` may update only the three
--      contact columns. Note the ORDER: a table-level UPDATE grant covers
--      every column, so the table grant must be revoked BEFORE the column
--      grant is issued, or the column grant is meaningless.
--   2. WITH CHECK on the RLS policy, pinning the identity and privilege
--      columns so the new row cannot differ from the old one.
--   3. A trigger, so the invariant holds even for a future code path that
--      arrives with different grants (a service-role script, a new RPC).
--
-- Pinned by tests/sql/privilege_escalation.sql, which performs the actual
-- attack and asserts it fails.

-- ── Layer 1: column-level privileges ────────────────────────────────────────

revoke update on public.accounts from anon, authenticated;
grant  update (first_name, last_name, phone) on public.accounts to authenticated;

revoke insert, delete on public.accounts from anon, authenticated;

-- players: a player may edit their own name and rating. account_id must never
-- move (that would reassign a person to another household) and, per Tara's
-- decision 5, is_member stays self-reported so it is deliberately writable.
revoke update on public.players from anon, authenticated;
grant  update (first_name, last_name, date_of_birth, adult_rating, is_member)
  on public.players to authenticated;

revoke delete on public.players from anon, authenticated;

-- ── Layer 2: WITH CHECK on the policies ─────────────────────────────────────

drop policy if exists accounts_update_self on public.accounts;
create policy accounts_update_self on public.accounts
  for update
  using       (id = auth.uid() or public.is_admin())
  with check  (id = auth.uid() or public.is_admin());

drop policy if exists players_update_own on public.players;
create policy players_update_own on public.players
  for update
  using      (account_id = auth.uid() or public.is_admin())
  with check (account_id = auth.uid() or public.is_admin());

drop policy if exists players_insert_own on public.players;
create policy players_insert_own on public.players
  for insert
  with check (account_id = auth.uid() or public.is_admin());

-- ── Layer 3: trigger backstop ───────────────────────────────────────────────

-- Belt and braces for any future path that bypasses the grants above: a
-- service-role migration, a new SECURITY DEFINER RPC, a direct psql session
-- from an admin tool. Only an actual admin may change a role, and nobody may
-- change an account's id.
create or replace function public.guard_account_privilege_columns()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'account_id_is_immutable' using errcode = '42501';
  end if;
  if new.role is distinct from old.role and not public.is_admin() then
    raise exception 'only_an_admin_may_change_a_role' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_account_privilege_columns on public.accounts;
create trigger guard_account_privilege_columns
  before update on public.accounts
  for each row execute function public.guard_account_privilege_columns();

create or replace function public.guard_player_owner_column()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  if new.account_id is distinct from old.account_id and not public.is_admin() then
    raise exception 'player_owner_is_immutable' using errcode = '42501';
  end if;
  return new;
end;
$$;

drop trigger if exists guard_player_owner_column on public.players;
create trigger guard_player_owner_column
  before update on public.players
  for each row execute function public.guard_player_owner_column();
