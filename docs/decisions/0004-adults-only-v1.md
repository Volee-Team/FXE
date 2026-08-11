# 0004 — Adults only in v1, juniors stay in the schema

**Date:** 2026-08-02 · **Status:** Active

## Decision

v1 ships adults only. The `juniors` audience, the `junior` player kind, and the
junior-specific columns stay in the database, unused.

## Why

Tara, on the 2026-08-02 call: *"also btw only adults no kids"*, and earlier
*"we will address juniors before winter time"*.

Juniors touch roughly a third of onboarding: parent accounts, children under a
parent, date-of-birth requirements, age groups, a separate news audience.
Cutting them from v1 removes all of it.

Keeping the enum values costs nothing and means the fall re-enable is UI work
rather than a migration against a live database with real players in it.

## Rejected

**Strip juniors from the schema entirely.** Cleaner today, but re-adding an enum
value and a set of columns to a production database is a migration with
downtime risk, to undo something we chose.

**Build juniors anyway since it is specified.** The Developer Guide has the full
junior flow, but Tara superseded it verbally. The most recent instruction wins.

## Pinned by

`tests/sql/schema_decisions.sql` — `audience_enum_still_has_juniors` asserts the
enum value survives, so a future cleanup cannot quietly delete it.
