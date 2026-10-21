---
name: reference-tara-review-page
description: "How Tara reviews the app's words and answers questions: web/review.html on the admin site saves her answers to hosted; review-watch.yml opens a tara-answers issue when she does; round four (2026-09-27) is only what changed"
metadata:
  node_type: memory
  type: reference
  originSessionId: 9072dbe0-404d-42e8-9fee-5349a35247ad
  modified: 2026-09-27T21:00:30.363Z
---

**The live channel (since 2026-09-21):** `https://fxe-tennis-admin.vercel.app/review.html?t=<token>`. Alex mints a link on the web admin (the small grey **Testing** link at the foot of the page → Review links → Make link) and texts it to her. Her answers save to `review_responses` on hosted as she types (edge function `review-submit`), keyed by link and `page_version`, and are read back on the same Testing panel → Responses.

**Never miss them again (2026-09-27):** her round-two answers saved on 2026-09-22 and nobody read them for five days; round three nearly re-asked her everything (decision 0016). Now `.github/workflows/review-watch.yml` checks hosted every two hours and opens a GitHub issue labelled `tara-answers` (label and time only; the repo is public), and the session-start hook prints every open one. Close the issue once her answers are recorded as a dated decision.

**Round rule:** each round shows only what is new or changed since her last answers, plus the questions still open (Alex, 2026-09-27: "why tf are we giving her so many if she did this like last week"). Page version 4 = 15 strings, questions 69 to 79, three tasks. Bump `PAGE_VERSION` in `scripts/build-tara-review.py` when items are inserted, removed or reordered; appending at the end keeps saved answers aligned.

**Source:** `scripts/build-tara-review.py` writes both `web/review.html` (deploy with `bash scripts/deploy-web.sh`) and `docs/tara-review/index.html`. The older claude.ai artifact (https://claude.ai/artifact/1H3fCuvG7pkc9scTAJmfkL, 2026-09-18, answers kept in her browser and texted back) is superseded; do not send it.

Related: [[feedback-ask-tara-first]], [[feedback-how-alex-works]], [[project-tara-vision-and-cancel-policy]].
