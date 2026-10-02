#!/usr/bin/env bash
# check-ui-test-record.sh (CI): the app's UI tests cannot run on GitHub (no CI
# database, launch checklist F), so they run on a Mac through
# scripts/run-ui-tests.sh, which records each full green run in
# docs/ui-test-runs.log with a fingerprint of the code it tested. This fails
# when the code in this commit has no green record: app, tests, project or
# database changed since the suite last passed on them.
#
# REQUIRED_IOS lists the iOS majors that must each have a green run of this
# exact code: the newest (26), the smallest current screen on 18 (the iPhone
# SE), and the oldest the app supports (17). On 2026-10-01 the first runs on
# 18 and 17 found five things no iOS 26 run could: a prompt cutting its own
# sentence off, navy page titles on the navy banner, a dark search box, a
# clipped card title, and a tap landing under the home bar.
set -euo pipefail
cd "$(dirname "$0")/.."
REQUIRED_IOS="${REQUIRED_IOS:-26 18 17}"
fp=$(bash scripts/app-fingerprint.sh)
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
