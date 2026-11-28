-- 20261127000002_level_check_on.sql — decision 0048, the switch back on.
--
-- 20261106000002 turned the level check off: the 1.0.1 app in the store had
-- no Request Approval button and read level_approval_required as "Sorry,
-- someone beat you to the punch". Every app since 1.0.2 has the button, and
-- Tara's next-update note (2026-11-23) asks for it again: "only 4.0's or
-- higher get in to 4.0+ clinic". John, 2026-11-27: on, as built.
--
-- With it on: a player rated below a clinic's level (the number in its name)
-- sees "Request Approval" instead of Register; Tara approves or declines on
-- Manage. A player with no rating, Tara's own placements and invitations, and
-- approvals she already gave are unchanged. The seed has had it on since
-- 20261106000002, so every test already runs this way.

update public.app_settings set value = 'true' where key = 'level_check_enabled';
