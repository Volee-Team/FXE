#!/usr/bin/env bash
# check-ui-test-record.sh (CI): a pull request's app code must have passed the
# whole UI suite. Since 2026-11-21 GitHub runs it against the fxe-ci project
# (scripts/ci-ui-tests.sh; CI_PASSED below). Otherwise it runs on a Mac through
# scripts/run-ui-tests.sh, which records each full green run in
# docs/ui-test-runs.log with a fingerprint of the code it tested. This fails
# when the code in this commit has no green record: app, tests, project or
# database changed since the suite last passed on them.
#
# REQUIRED_IOS lists the iOS majors that must each have a green run of this
# exact code: the newest (26) and the smallest current screen on 18 (the
# iPhone SE). On 2026-10-01 the first runs on 18 and 17 found five things no
# iOS 26 run could: a prompt cutting its own sentence off, navy page titles on
# the navy banner, a dark search box, a clipped card title, and a tap landing
# under the home bar.
#
# iOS 17 was required until 2026-10-30 (John): the current Xcode can no
# longer download an iOS 17 simulator ("iOS 17.5 is not available for
# download", likewise 17.0 to 17.4), so no Mac on the team could record it.
# The app still supports iOS 17.0; it is just not re-run on it before each
# merge. REQUIRED_IOS="26 18 17" restores the old rule on a Mac that has it.
set -euo pipefail
cd "$(dirname "$0")/.."
REQUIRED_IOS="${REQUIRED_IOS:-26 18}"
fp=$(bash scripts/app-fingerprint.sh)
# Since 2026-11-21 the suite also runs on GitHub (scripts/ci-ui-tests.sh,
# against the fxe-ci project). Its pass on this commit is the record.
if [ "${CI_PASSED:-}" = "true" ]; then
  echo "UI tests green on iOS 26 and 18 for this code ($fp): the CI project run on this commit."
  exit 0
fi
# Code the UI tests exercise is unchanged from the base branch, which was
# gated by this same check when it merged.
if [ -n "${BASE_SHA:-}" ]; then
  tmp=$(mktemp -d); trap 'git worktree remove --force "$tmp" >/dev/null 2>&1' EXIT
  if git worktree add -q --detach "$tmp" "$BASE_SHA" 2>/dev/null; then
    base_fp=$(bash "$tmp/scripts/app-fingerprint.sh" 2>/dev/null || true)
    if [ "$base_fp" = "$fp" ]; then
      echo "The app, its tests and the database are unchanged from the base branch ($fp); nothing new to test."
      exit 0
    fi
  fi
fi
bad=0
for v in $REQUIRED_IOS; do
  if grep -qE "^${fp}	PASS	[^	]+	iOS ${v}\." docs/ui-test-runs.log 2>/dev/null; then
    echo "UI tests green on iOS $v for this code ($fp): $(grep -E "^${fp}	PASS	[^	]+	iOS ${v}\." docs/ui-test-runs.log | tail -1 | cut -f3,5)"
  else
    echo "::error::No green UI test run on iOS $v for this code (fingerprint $fp)."
    bad=1
  fi
done
if [ "$bad" -ne 0 ]; then
  echo "Run on a Mac: bash scripts/run-ui-tests.sh   (and RUNTIME=<major> for each other iOS)"
  echo "then commit docs/ui-test-runs.log with the change."
  exit 1
fi
