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

`tests/sql/clinic_messaging.sql` (2026-09-21, 14 checks): Tara sends to In,
Pool and everyone; Maria (In), Ken (Pool), Rob (canceled) and Dana (not
registered) each read the view and the whole list they see is asserted in
brackets, so a longer list cannot pass by containing the expected one; the
recipients table and the messages table are unreadable to players; each
recipient is notified once and non-recipients not at all. Proven red on
three checks under a view that shows every message to any registered player.
(Until 2026-09-12 this section claimed `information_hiding.sql` pinned it;
that probe has no message check. From then until 2026-09-21 nothing did.)
