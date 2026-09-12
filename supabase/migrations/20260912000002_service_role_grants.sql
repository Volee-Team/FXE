-- service_role could not read or write any table.
--
-- Found 2026-09-12 by the first edge function that needed it:
-- stripe-setup-intent, using the platform's service key, got "permission
-- denied for table accounts". information_schema showed service_role holding
-- only TRUNCATE, TRIGGER and REFERENCES on every table: the 2026-08-13 /
-- 2026-08-17 grant lockdowns revoked SELECT/INSERT/UPDATE/DELETE with
-- "from public", and on this stack service_role's DML had come through that
-- pseudo-role rather than a direct grant. Nothing noticed for a month
-- because no server-side code existed: the app and the web admin are
-- clients, the backup runs as postgres.
--
-- service_role is the platform's trusted role, the one edge functions use to
-- write what no client may write (ledger status, card summaries, later push
-- delivery). It bypasses RLS by design. Grant it DML explicitly, on every
-- table and sequence, and as a default for tables created later, so a future
-- lockdown of PUBLIC cannot take it away again. The grants probe pins it.

grant usage on schema public to service_role;
grant select, insert, update, delete on all tables in schema public to service_role;
grant usage, select on all sequences in schema public to service_role;
grant execute on all functions in schema public to service_role;

alter default privileges in schema public grant select, insert, update, delete on tables to service_role;
alter default privileges in schema public grant usage, select on sequences to service_role;
alter default privileges in schema public grant execute on functions to service_role;
