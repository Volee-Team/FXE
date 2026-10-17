-- 20261014000003_card_payment_method.sql
--
-- WHICH CARD IS ON FILE, exactly. The card-removed webhook
-- (payment_method.detached, 2026-10-13) cleared the summary when the removed
-- card's brand and last four matched the one on file. A review the same night
-- found the hole: PaymentSheet makes a new PaymentMethod every time a card is
-- saved, even the same physical card, so a player who re-saves their card and
-- then removes the old copy had the summary cleared while the new copy was
-- still there. Register then refused (card_required) and Tara's Charge said
-- no_card_on_file.
--
-- accounts.card_payment_method_id: the Stripe PaymentMethod the summary
-- describes, written by stripe-webhook on setup_intent.succeeded alongside
-- brand and last four. The detach clears only when the removed PaymentMethod
-- IS that one. A summary from before this column (null id) falls back to the
-- brand-and-last-four match.
--
-- Readable by its owner through accounts' table-level SELECT, like the rest
-- of the summary. Accepted: a PaymentMethod id is useless without the secret
-- key. Written only by service_role (no client holds UPDATE on it).
--
-- Every path that clears the summary (stripe_cutover_to_live,
-- delete_my_account, stripe-setup-intent and stripe-charge on a customer
-- Stripe does not have, delete-account, the detach itself) sets card_last4 to
-- null. A trigger nulls the id with it, so none of those functions is
-- redefined here: redefining an older function from a later migration is how
-- a later fix gets silently undone.

alter table public.accounts add column card_payment_method_id text;

comment on column public.accounts.card_payment_method_id is
  'The Stripe PaymentMethod the card summary describes (stripe-webhook, '
  'setup_intent.succeeded). Cleared with the summary by '
  'accounts_card_pm_follows_summary. 20261014000003.';

create or replace function public.accounts_card_pm_follows_summary()
returns trigger
language plpgsql
set search_path = public, pg_temp
as $$
begin
  if new.card_last4 is null then
    new.card_payment_method_id := null;
  end if;
  return new;
end
$$;

comment on function public.accounts_card_pm_follows_summary() is
  'Internal trigger: a cleared card summary clears its PaymentMethod id. 20261014000003.';

-- Hard rule 11: PUBLIC first. Trigger functions need no EXECUTE to fire.
revoke all on function public.accounts_card_pm_follows_summary() from public, anon, authenticated;

create trigger accounts_card_pm_follows_summary
  before insert or update of card_last4, card_payment_method_id on public.accounts
  for each row execute function public.accounts_card_pm_follows_summary();
