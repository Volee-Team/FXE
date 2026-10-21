---
name: feedback-how-alex-works
description: "How Alex wants sessions run: keep building without reminders, verify on simulator/browser the first time, explain concepts, numbered replies, he does not review PRs, he relays Tara"
metadata:
  type: feedback
---

Collected from 2026-08-13 through 2026-09-13.

- "just keep building" (2026-09-10) and "anything you need my info on?" He is often on autopilot; do not wait for him between tasks, and put the things only he can do in one short list at the end, with exact clicks or commands.
- "make sure things are being built super thoroughly the first time" (2026-09-01): simulator screenshots and browser walks before claiming done; probes red-first; a claim comes with its command (hard rule 12).
- He does not review PRs; CI is the gate and I merge. He made the repo public for that.
- He wants to learn: name the concept and the rejected option in two sentences (CLAUDE.md, "What this project is FOR").
- He relays Tara; anything policy-shaped goes to `docs/questions-for-tara.md` first (hard rule 14) and he sends her a short plain-language list, not the whole doc.
- He asks "are you sure you remember everything?" and "audit everything": run the mechanisms (`scripts/check-doc-*.sh`), then parallel read-only agents, and write findings into the repo, never only into chat.
- Replies: numbered to match his numbered asks, honest about what was not verified, a plain "what I need from you" block at the end.

**Why:** these are the instructions he has repeated most. **How to apply:** default to autonomy on engineering, zero autonomy on Tara's product rules, and end every long turn with the two-line list of what only he can do. Related: [[feedback-take-more-control]], [[feedback-ask-tara-first]], [[project-accounts-and-tooling]].

**One conclusion, at the end (Alex, 2026-10-21: "u need to stop doing your summaries halfway thru then u keep going...").** While working, say only what you are doing in a line. When the work is done, give one final answer: the problems found, then what needs doing and by whom. Never a summary followed by more work followed by another summary.
