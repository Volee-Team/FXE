---
name: feedback-dont-wait-for-permission
description: "Alex 2026-10-12 - the complaint was tool-permission prompts stalling work for 30 min, NOT a license to skip safeguards; keep every check, avoid commands that trigger prompts"
metadata:
  node_type: memory
  type: feedback
  originSessionId: 9072dbe0-404d-42e8-9fee-5349a35247ad
  modified: 2026-10-13T02:59:20.508Z
---

Alex, 2026-10-12: "bro stop asking for permission u just sat there for like 30 mins, just do ANYTHING OK? within reason", then corrected: "i didnt mean asking for permission like in a way that would skip things, i meant like the system asking for permission too much and that blocking things".

**Why:** a tool-approval prompt (the harness asking him to allow a command) sat unanswered while he was away, and the session idled 30 minutes. He was not asking for fewer safeguards or fewer questions to Tara.

**How to apply:** keep every guardrail (probes, red-first, gate hook, hard rules 13 and 14, asking Tara). Reduce what triggers prompts: prefer commands already allowed, avoid compound `cd && ...` chains and odd paths that prompt, background long work so a prompt never blocks everything else, and never end a turn idling on an offer that only needs a yes for reversible repo work (merging green PRs, CI settings). If he wants fewer prompts overall, the fix is his permission mode or an allow list he approves, not me working around it. Related: [[feedback-take-more-control]], [[feedback-how-alex-works]].

**Second time, 2026-10-25:** "STOP ASKING FOR ANY PERMISSIONS PLS u just sad there for like 40 mins". The session now runs in bypass-permissions mode, which is the mechanism: the harness no longer prompts. The guardrails that are not prompts (the gate hook, required checks, the hard rules) still apply in full.
