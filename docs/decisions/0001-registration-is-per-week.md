# 0001 — Registration opens per service week, not per clinic

**Date:** 2026-08-02 · **Status:** Active

## Decision

A clinic belongs to the **service week** containing it: Sunday 00:00 through
Saturday 23:59, America/New_York. Registration for every clinic in that week
opens at one pair of moments derived only from the week's anchor Sunday:

* Members: 08:00 local on `anchor_sunday - 3 days` (the Thursday before)
* Public: 08:00 local on `anchor_sunday - 2 days` (the Friday before)

A clinic's own weekday has no effect on when it opens.

## Why

Tara: *"Registration opens on Thursday, September 3rd for dates of Sunday,
September 6th - Friday, September 11th. Registration opens on Friday, September
4th for dates of Sunday, September 6th - Friday, September 11th."*

Two different open dates for one identical range. That is only coherent if the
**week** is the registrable unit and the two dates are the two audiences.

## What this replaced, and why it mattered

The original implementation read "the most recent Thursday before the clinic
date," per clinic. It agrees with the real rule Sunday through Thursday and
breaks on **Friday and Saturday** — the two days seats are scarcest.

Worse, its public-side counterpart would open non-members on Friday
2026-09-04 for a Friday 2026-09-11 clinic, while members opened Thursday
2026-09-10. Non-members would get in **six days before** members: the exact
inversion of the priority the rule exists to protect.

It was wrong on the specific date Tara spelled out, and its test was green the
whole time, because the test had been written by reading the code.

## Open

Her example ran Sunday–Friday and never mentioned Saturday. We extended the week
to Saturday so every calendar date belongs to a week; otherwise `week_of(date)`
is undefined for Saturdays. If she runs Saturday clinics, the two readings are a
full week apart. **Ask her.**

## Pinned by

`tests/sql/registration_window_rule.sql` — 45 checks, values transcribed from
Tara's sentence by hand, verified to go red against the old implementation.
