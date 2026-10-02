# 0034: No middle dots between words

**Date:** 2026-10-01 · **Status:** Active · **Source:** Alex, 2026-10-01, with a
screenshot of Home ("Sun, Oct 4 · 2:14 PM"): *"we should not have those
little dots it looks super AI"*.

## What we chose

The middle dot (`·`) is gone from every line a person reads, in the app and
on the admin site. What replaces it depends on what it was joining:

| Was | Now | Where |
|---|---|---|
| a date and a time | `Sun, Oct 4 at 2:14 PM` | Home, Clinics, Tara's Clinics |
| a date and a time range | `Tuesday, Oct 6, 7:00 PM to 8:30 PM` | a clinic on Tara's phone, the court sheet |
| items in a list | commas: `60 min, $18`; `12 played, 1 no-show`; `3.5, Member` | clinic cards, a player's history, Players |
| a clinic and its date | `Tuesday Ladies on Tue, Sep 29` | declined cards, disputes, the ledger |
| a reason or a note after that | a colon: `...: Insufficient funds (NSF)` | the same rows |
| a state tacked on the end | parentheses: `(archived)`, `(resolved)`, `(not opened yet)` | the admin site |
| a page's tab title | a space: `FXE Tennis Admin` | browser tabs |

## Rejected

- **A vertical bar (`|`) or an en dash.** The same "generated" look with a
  different glyph.
- **Two lines everywhere.** Right for one place (a clinic card on the admin
  site, where the date line already holds commas), too tall for a list row.

## How we would know we were wrong

Tara or a member reads a comma list as one phrase ("60 min, $18" as a price
for 60 minutes is the intended reading). Nothing found so far.

## Enforced

`scripts/check-no-dots.sh`, a step in the copy-gate CI job: any `·` outside a
comment line in the app's Swift, the admin site or Tara's review page builder
fails the build. Shown red on a planted line before it went in. The copy gate
alone could not do this: it sees literal strings, and most of these lines are
built from data.
