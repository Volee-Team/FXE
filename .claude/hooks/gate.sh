#!/bin/bash
# gate.sh: a PreToolUse hook on Bash that refuses two commands outright
# (exit 2: the command does not run and the model is told why).
#
#   1. `gh pr merge` while any check on that PR is not green. "CI is the
#      gate" was a claim until now: PR #9 merged red through a `;` chain
#      (2026-09-01), and only 2 of ~30 checks are required by GitHub.
#   2. `supabase db reset` (and psql against the main local database) while
#      a UI test run holds /tmp/fxe-ui-tests.lock: a reset wipes the run's
#      data mid-test (the run-probes.sh and browser-suite guards, 10-01 and
#      10-12, never covered the hand-typed command).
#
# Workflow audit, 2026-10-12: "mechanism over discipline".
input=$(cat)
cmd=$(printf '%s' "$input" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("tool_input",{}).get("command",""))' 2>/dev/null)
[ -n "$cmd" ] || exit 0

# Only where a command starts (the line's start, or after &&, ||, ; or |),
# never inside text: the first version refused a commit whose message
# merely mentioned the command.
if printf '%s' "$cmd" | grep -qE '(^|&&|\|\||;|\|)[[:space:]]*gh pr merge'; then
  pr=$(printf '%s' "$cmd" | grep -oE 'gh pr merge[[:space:]]+[0-9]+' | grep -oE '[0-9]+$' | head -1)
  if [ -z "$pr" ]; then
    echo "gate: name the PR number in gh pr merge so its checks can be read first." >&2; exit 2
  fi
  states=$(gh pr checks "$pr" --json bucket -q '.[].bucket' 2>/dev/null)
  if [ -z "$states" ]; then
    echo "gate: could not read the checks of PR #$pr; not merging blind." >&2; exit 2
  fi
  bad=$(printf '%s\n' "$states" | grep -vcE '^(pass|skipping)$')
  if [ "$bad" -gt 0 ]; then
    echo "gate: PR #$pr has $bad check(s) not green (pending or failing). Merge only when every check passes." >&2; exit 2
  fi
fi

if printf '%s' "$cmd" | grep -qE '(^|&&|\|\||;|\|)[[:space:]]*(supabase db reset|docker exec[^|;]*supabase_db_FXE-Tennis[^|;]*psql)'; then
  if [ -d /tmp/fxe-ui-tests.lock ] && kill -0 "$(cat /tmp/fxe-ui-tests.lock/pid 2>/dev/null)" 2>/dev/null; then
    case "$cmd" in *run-ui-tests.sh*) exit 0;; esac
    echo "gate: a UI test run holds the local database (/tmp/fxe-ui-tests.lock). Wait for it to finish." >&2; exit 2
  fi
fi
exit 0
