---
name: project-tara-vision-and-cancel-policy
description: "Tara's cancellation and payment policy as of 2026-09-21 (3-hour cutoff, full fee, no courtesy, card only, her tap charges) and her long-term vision (whole-club app, court reservations, white-label to other clubs)"
metadata: 
  node_type: memory
  type: project
  originSessionId: 9072dbe0-404d-42e8-9fee-5349a35247ad
  modified: 2026-09-21T19:02:37.796Z
---

Exact words are in the repo: `docs/decisions/0010`, `0012`, `0013` and `docs/roadmap.md` ("The dream, in Tara's words"). This file is the shape, not the source.

- **Cancellation (2026-09-21, decision 0013):** cutoff 3 hours before the clinic (same as the registration close). Inside it the cancel goes through, is late, and the full fee applies every time. **No courtesy** ("NOT DOING THIS ANYMORE"); the 90-day window is a setting at 0, kept so it is reversible. The note is optional. No-shows: full fee.
- **Money:** the card is the only way to pay ("Everyone using the app has to input a credit card"); Zelle/Venmo controls hidden behind `zelle_allowed = false`. Every attendee's card is charged after the clinic by **her tap** on Charge clinic ("app does nothing automatically w payments"). No refunds because nothing is charged before a clinic ends. Card required to register once payments are on.
- **Final Updates (2026-09-26, decision 0015):** a card with a permission box ("I give permission for my card to be charged") is part of onboarding while payments are on; consent kept 90 days after deletion; a "card on file" means a saved card, not a Stripe customer. Non-members may not hold two 105s the same day until two days before the earlier start (clock time). Board report: members/non-members attended, collected, 10% (base is her question 58). Home lists your clinics then what is open to you; Zelle wording is gone.
- **Waiver:** her Adult Tennis Participation Waiver (Sept 2026) is signed in the app before the first spot; account deletion keeps history.
- **Courts:** the club pays $500/yr for reservemycourt.com and keeps it for now. Integration is a v2 wish.
- **The dream:** everything on the app: pay for treats, a barcode at the pool entrance, merch, cabana bookings, "truly comprehensive", then white-label to other clubs.
- **Stripe:** Alex, 2026-09-12: "we REALLY want this implemented in v1"; keys still not set (he said "remind me later" on 2026-09-18).

**Why:** These shape what the schema should grow into (club-level, not tennis-only) and what must never be hard-coded to FXE. Related: [[feedback-ask-tara-first]], [[feedback-take-more-control]], [[reference-tara-review-page]].

**How to apply:** Treat clinics as one product line of a club app; keep FXE-specific strings in settings; never reintroduce the courtesy or Zelle path without her word; do not build court reservations, pool, merch, or cabanas until asked, but do not design them out.
