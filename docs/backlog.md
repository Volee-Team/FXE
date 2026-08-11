# Backlog

Bugs, chores, and small things that are not worth a roadmap entry. **Anything
noticed and not fixed goes here in the same breath**, or it is forgotten.

Priority: 🔴 blocks a person · 🟡 should fix · 🟢 whenever

## Open

| | Item | Found | Note |
|---|---|---|---|
| 🟡 | Notification triggers with no producer | 2026-08-02 | `REGISTRATION IS OPEN` needs a scheduler that does not exist. Copy is written, nothing fires it |
| 🟡 | Four "high" findings from the completeness review | 2026-08-02 | Docs drifted from code; probes asserting less than their comments claim |
| 🟢 | Six "medium" / seven "low" findings from the same review | 2026-08-02 | Not security. Worth one focused pass |
| 🟢 | `clinics.price_cents` is dead | 2026-08-10 | Superseded by the two price columns. Drop once the Swift client and web admin are both off it |
| 🟢 | Supabase CLI is v2.90, current is v2.113 | 2026-08-10 | Works fine, just stale |

## Fixed

| | Item | Found | Fix |
|---|---|---|---|
| 🔴 | **Any player could make themselves admin** with one UPDATE, then read every roster, court and payment, demote Tara, and reassign other players to their own account | 2026-08-02 | Column grants + `WITH CHECK` + trigger. `tests/sql/privilege_escalation.sql` attacks it, verified red first |
| 🔴 | Registration window rule was wrong on Fridays and Saturdays | 2026-08-02 | See decision 0001 |
| 🔴 | **Probe harness reported SQL errors as passes.** It matched `^ERROR`, psql writes `psql:<stdin>:138: ERROR:`. Five probes were aborting and the suite said green | 2026-08-10 | Match `ERROR:` anywhere |
| 🔴 | **A probe running zero assertions reported as a pass** | 2026-08-10 | Zero checks is now red |
| 🟡 | Probe pass condition used substring matching, so an actual of `105` passed an expected of `0` | 2026-08-02 | Substring only when the expected value contains a letter |
