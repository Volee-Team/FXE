# 0003 — Zelle plus a report for v1, Stripe in v1.1

**Date:** 2026-08-10 · **Status:** Active

## Decision

v1 moves no money. Tara keeps taking Zelle (preferred) and Venmo, and the app
gives her `revenue_summary()`: how many members and non-members played 60- and
90-minute clinics, and the total. Stripe is v1.1.

## Why

Her actual pain today is not collection, it is **reconciliation** — she keeps a
handwritten list, ticks off who paid, and works out what to tell the club. A
report solves that this month.

What she asked for is the harder half of Stripe: cards on file that she charges
later. That is Customers, SetupIntents, off-session PaymentIntents, and handling
a decline on a card charged days after the clinic. It is real work with real
money risk, and shipping it badly is worse than not shipping it.

## The Apple question, since it comes up

Apple does **not** require in-app purchase for real-world services, and tennis
clinics qualify. Stripe direct is allowed. This is genuinely different from
Volee, where subscriptions to app functionality do require IAP. Nobody needs to
argue about this again.

## Rejected

**Stripe in v1.** Delays everything else for the piece she is least blocked on.

**Apple Pay / IAP.** Not required, and Apple's cut on a $23 clinic fee is real
money out of a small program.

## Pinned by

Nothing in code — this is a scheduling decision. The v1 half is pinned by the
`revenue_summary` checks in `tests/sql/pricing_and_revenue.sql`.
