-- Reset links Tara makes for a member (decision 0017).
--
-- WHY: the hosted project sends email through Supabase's built-in sender,
-- which delivers only to the project's own team, two an hour. Until custom
-- SMTP is set (launch checklist D1), "Forgot password?" reaches no member.
-- The admin-reset-link edge function lets Tara make a one-time reset link for
-- a member and text it to them: no email involved.
--
-- A reset link is a way to sign in as someone. Whoever makes one could use it
-- themselves, so every link made is recorded here: whose account, who made
-- it, when. Nobody reads this table from a client; it exists so the question
-- "did anyone ever make a link for my account?" has an answer.
--
-- Written only by the edge function (service_role). No client verb on it,
-- by revoke-before-grant (hard rule 11): the table is born with INSERT,
-- UPDATE, DELETE and TRUNCATE for anon and authenticated.

create table if not exists public.reset_links_issued (
  id          uuid primary key default gen_random_uuid(),
  account_id  uuid not null references public.accounts(id) on delete restrict,
  issued_by   uuid not null references public.accounts(id) on delete restrict,
  -- clock_timestamp(): two links in one transaction keep their order.
  issued_at   timestamptz not null default clock_timestamp()
);

create index if not exists reset_links_issued_account_idx
  on public.reset_links_issued (account_id, issued_at desc);

comment on table public.reset_links_issued is
  'One row per password-reset link an admin made for a member (admin-reset-link, decision 0017). Audit only: written by service_role, readable by no client.';

alter table public.reset_links_issued enable row level security;

revoke all on public.reset_links_issued from public, anon, authenticated;
-- Full DML, like every table (grants_are_explicit.sql asserts it): the
-- server role is trusted, and an append-only rule against it would be
-- decoration, since it can also bypass RLS.
grant select, insert, update, delete on public.reset_links_issued to service_role;
