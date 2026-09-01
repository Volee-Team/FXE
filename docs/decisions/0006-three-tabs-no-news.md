# 0006 — Three tabs, no News tab, no Community tab

**Date:** 2026-08-12 · **Status:** Active

## Decision

The player app has exactly **three** tabs: **Home, Clinics, Profile**.

News is **deferred**. Its model (`NewsPost`) and repository (`NewsRepository`)
stay in the code, unused and unreachable, the same way the `juniors` enum stays
in the schema under decision 0004. There is no News screen in v1.

Two more from the same call, recorded here because they had no numbered file:

* **Court number is never shown to a player** (decision 17). Confirms hard rule 1.
  Tara reads court assignments off her own screen.
* **Capacity is never shown to a player** (decision 18). The wireframe's
  "Max: 12 Players" is not built.

## Why

Tara, on the 2026-08-12 call: three tabs, no Community tab. News is real program
communication she wants eventually, but clinic messages already carry everything
tied to a specific clinic, which is the case that actually blocks her week. A
News tab with nothing in it teaches a new player that a tab can be empty.

Fewer tabs also matches the stated visual direction: player screens must never
feel like long blocks of writing, and a four-tab bar on a phone used outdoors is
one more thing to mis-tap.

## What this supersedes

Two higher-authority-looking sources now disagree with reality, and both lose:

* **The Developer Guide** specifies four tabs (Home, Clinics, News, Profile) at
  Screen 7, and a full News surface at Screen 11. Superseded.
* **The wireframe mockups** show a **Community** tab. Never built, never
  specified anywhere else, and explicitly cut on the call.

This is the ordering in CLAUDE.md's "Which source wins" working: the most recent
thing Tara said beats the spec she approved in June, which beats the Developer
Guide, which beats the mockups.

## Rejected

**Ship News as a tab with the two most recent posts.** The repository layer
already exists so it looked nearly free. It is not: posting News needs an admin
surface that does not exist either, so the tab would be permanently empty in
Tara's hands.

**Fold News into Home as a third section.** Plausible, and it is what the
Developer Guide's Home screen does. Deferred rather than rejected: revisit when
there is an admin path to publish a post. Do not build it before then.

**Delete the News model and repository.** Same reasoning as decision 0004: dead
code that costs nothing beats a re-add later. Hard rule 6 also forbids removing
it without asking.

## How we would know we were wrong

Tara starts sending program-wide announcements by text again because the app has
nowhere to put them. That is the signal News has become load-bearing, and it
should then arrive with its admin half, not before.

## Pinned by

Nothing mechanical yet. `MainTabView.swift` has three tabs and a comment saying
admin is a separate surface. **Gap:** no test asserts the tab count, so a future
session could add a fourth without anything going red.
