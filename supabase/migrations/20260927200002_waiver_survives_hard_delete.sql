-- 20260927200002_waiver_survives_hard_delete.sql
--
-- A signed waiver is the club's legal record (decision 0013 §4), and it was
-- one click from gone. waiver_acceptances.account_id was ON DELETE CASCADE
-- (20260921000002), and accounts cascade from auth.users, so the dashboard's
-- "Delete user" (a hard delete) would have erased the signature with the
-- person. card_consents was switched to RESTRICT for exactly this reason on
-- 2026-09-26 (20260926000001, audit); the waiver, the older and weightier
-- record, was missed (MVP audit, 2026-09-27, build-now item 11).
--
-- Now RESTRICT: a hard delete of anyone who has signed fails loudly, and the
-- only supported way out stays the soft one (delete_my_account(), then the
-- delete-account edge function's soft delete of the sign-in, which keeps the
-- auth row and so everything that hangs off it). Nothing deletes a signature.
-- Pinned by tests/sql/waiver.sql ("a hard delete cannot take a signature"),
-- red on the CASCADE definition.
--
-- The constraint name is Postgres's default for the column
-- (<table>_<column>_fkey), the same on every database that ran 20260921000002.

alter table public.waiver_acceptances
  drop constraint if exists waiver_acceptances_account_id_fkey;

alter table public.waiver_acceptances
  add constraint waiver_acceptances_account_id_fkey
  foreign key (account_id) references public.accounts(id) on delete restrict;

comment on column public.waiver_acceptances.account_id is
  'Who signed. ON DELETE RESTRICT (20260927200002): a hard delete of a signer '
  'fails, so the signature cannot leave with the account.';
