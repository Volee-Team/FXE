---
description: Run every FXE probe against the local database and report red/green
---

Run `bash tests/run-probes.sh` and report the result table.

If the local stack is not running, start it with `supabase start` first. If a
probe is red, show the failing rows, not just the count. Do not fix anything in
this command: report only.
