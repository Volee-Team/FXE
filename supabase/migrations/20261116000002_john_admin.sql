-- John is an admin, as Tara is (2026-11-16).
--
-- John: "Every permission alex and tara have, I should have." On the live
-- server that is one row: Tara's account has role 'admin'; Alex has no admin
-- account there (his Stripe access is outside the database). This makes
-- John's own account (the id below, nothing else about him; the repo is
-- public) an admin, which gives him, exactly as it gives Tara:
--
--   - the Manage tab in the app and the whole laptop admin site, court
--     reservations included (so he can be a court tester while courts are
--     off, decision 0058, without a member switch);
--   - every admin_* function (require_admin / is_admin);
--   - the admin notifications: 13 Player Accepted, 14 Player Declined,
--     15 Player Canceled, and LATE_REQUEST (docs/notifications.md, "Every
--     admin account"). Those arrive on his phone as they do on Tara's.
--
-- guard_account_privilege_columns (20260928600001) refuses every role change
-- that is not member <-> pro, and any role change by a non-admin; a
-- migration runs with no signed-in user, so it would refuse this too. It is
-- switched off for this one statement and on again in the same transaction,
-- as a migration is the one path John approves (hard rule: hosted writes only
-- via `supabase db push`).
--
-- Guarded: where this account does not exist (a local stack, CI, a fresh
-- reset) nothing changes, and the trigger is back on either way.

alter table public.accounts disable trigger guard_account_privilege_columns;

update public.accounts
   set role = 'admin'
 where id = '0be0bdcc-177d-4fc0-8282-a50953021133'
   and deleted_at is null
   and role::text <> 'admin';

alter table public.accounts enable trigger guard_account_privilege_columns;
