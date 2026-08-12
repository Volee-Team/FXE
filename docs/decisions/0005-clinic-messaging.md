# 0005 — Clinic messaging is a broadcast with three audiences

**Date:** 2026-08-12 · **Status:** Active

## Decision

Each clinic has a message thread. Tara composes; players read. The composer
offers exactly **three** audiences:

1. **You're In!** — the confirmed players
2. **Player Pool** — the people waiting on her
3. **Both**

The unpaid reminder stays a separate button on the roster, not a fourth option
in this picker. `response_needed` and `unpaid` remain in the `message_audience`
enum, unused by this screen.

## Why

Tara, 2026-08-12: *"she really wants to be able to basically have a group chat
for each clinic where she can send out a message to anyone and say 'sorry a pro
is sick, etc.' - also make there an option to either message the people who are
confirmed, the people in the pool, OR both - so 3 options"*

The example is the whole spec: a pro calls in sick an hour before a clinic and
she needs to reach exactly the right people, fast, from her phone. Five options
in a picker is a decision she does not want to make in that moment.

"Group chat" describes how it should *feel* — one place per clinic, history
visible — not that players can post. All messaging is still Tara outward.
Player-initiated messaging has never been asked for and is not in v1.

## Rejected

**Five audiences, matching the enum.** More precise, slower to use, and two of
the five have no moment where she would reach for them.

**Removing the unused enum values.** They cost nothing sitting there, and
`unpaid` is genuinely used by the reminder button. Archive, never delete.

## How we would know this was wrong

If she asks for a fourth option, or if players start replying to her by text
because they cannot reply in the app.

## Pinned by

`tests/sql/information_hiding.sql` — a targeted message stays visible only to
its audience (decision 12 of the 2026-08-02 set).
