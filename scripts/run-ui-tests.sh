#!/usr/bin/env bash
# run-ui-tests.sh: the one way to run the app's unit and UI tests on this Mac.
#
# Every rule in here was a manual step that was once forgotten:
#   - ONE RUN AT A TIME. Two xcodebuild test runs at once crashed the
#     simulator's SpringBoard four times on 2026-09-27/28 (every crash report
#     was inside XCTAutomationSupport). A lock directory refuses a second run.
#   - A FRESH DATABASE. The suite assumes the seed; a dirty database fails
#     tests for reasons that are not regressions (2026-09-12).
#   - NO SILENT SKIPS. The declined-card test skips itself without the local
#     service key, and a skip reads as green (2026-09-29). The key is passed
#     here, never printed, and any skipped test fails the run.
#   - A RECORD OF WHAT PASSED. On a full green run, one line goes into
#     docs/ui-test-runs.log: the fingerprint of the app's code, the device and
#     iOS version. CI (check-ui-test-record.sh) fails a PR whose app code has
#     no green line, because UI tests cannot run in CI (no CI database,
#     launch checklist F) and "I ran them" is otherwise only a claim.
#
# CI requires a green record on iOS 26, 18 and 17 for the same code
# (check-ui-test-record.sh), so a change to the app means all three:
#   bash scripts/run-ui-tests.sh                                       # iOS 26
#   RUNTIME=18 DEVICE="iPhone SE (3rd generation)" bash scripts/run-ui-tests.sh
#   RUNTIME=17 DEVICE="iPhone 15" bash scripts/run-ui-tests.sh
#
#   bash scripts/run-ui-tests.sh                      # everything, iPhone 17 Pro
#   DEVICE="iPhone 16e" bash scripts/run-ui-tests.sh   # another simulator
#   RUNTIME=18 DEVICE="iPhone 16" bash scripts/run-ui-tests.sh   # iOS 18
#   bash scripts/run-ui-tests.sh -only-testing:FXETennisUITests/PlayerFlowUITests
#
# A run with -only-testing arguments is never recorded: the record means the
# whole suite passed.
set -uo pipefail
cd "$(dirname "$0")/.."

LOCK=/tmp/fxe-ui-tests.lock
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "Another UI test run holds $LOCK (pid $(cat "$LOCK/pid" 2>/dev/null || echo '?'))."
  echo "Two runs at once crash the simulator. Wait for it, or remove the lock if that process is gone."
  exit 2
fi
echo $$ > "$LOCK/pid"
trap 'rm -rf "$LOCK"' EXIT

DEVICE="${DEVICE:-iPhone 17 Pro}"
RUNTIME="${RUNTIME:-}"
DD="${DERIVED_DATA:-/tmp/fxe-ui-dd}"
LOG="${LOG:-/tmp/fxe-ui-tests.log}"

# The simulator by name, on the newest runtime unless RUNTIME picks a major
# version ("18" -> the newest iOS 18.x runtime installed).
UDID=$(xcrun simctl list devices available -j | python3 -c '
import json, sys, re
want, major = sys.argv[1], sys.argv[2]
best = None
for rt, devs in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    if not m or (major and m.group(1) != major): continue
    ver = (int(m.group(1)), int(m.group(2)))
    for d in devs:
        if d["name"] == want and (best is None or ver > best[0]):
            best = (ver, d["udid"])
print(best[1] if best else "")' "$DEVICE" "$RUNTIME")
if [ -z "$UDID" ]; then
  echo "No available simulator named \"$DEVICE\"${RUNTIME:+ on iOS $RUNTIME}. Create one: xcrun simctl create \"$DEVICE\" \"$DEVICE\" <runtime>"
  exit 2
fi
OS=$(xcrun simctl list devices -j | python3 -c '
import json, sys, re
for rt, devs in json.load(sys.stdin)["devices"].items():
    for d in devs:
        if d["udid"] == sys.argv[1]:
            m = re.search(r"iOS-(\d+)-(\d+)", rt); print(f"{m.group(1)}.{m.group(2)}")' "$UDID")
echo "Device: $DEVICE, iOS $OS ($UDID)"

# One simulator at a time: shut down every other booted one first. Several
# left running ate memory and confused whoever was watching (Alex,
# 2026-10-01: "why do u keep opening 2 sims?").
for other in $(xcrun simctl list devices booted -j | python3 -c '
import json, sys
for devs in json.load(sys.stdin)["devices"].values():
    for d in devs:
        if d["state"] == "Booted" and d["udid"] != sys.argv[1]: print(d["udid"])' "$UDID"); do
  xcrun simctl shutdown "$other" 2>/dev/null
done

echo "Resetting the local database..."
supabase db reset >/tmp/fxe-ui-reset.log 2>&1 || { echo "supabase db reset failed; see /tmp/fxe-ui-reset.log"; exit 1; }
# Sign-in 504s for minutes after a reset unless auth is restarted (backlog).
docker restart supabase_auth_FXE-Tennis >/dev/null 2>&1 && sleep 3

KEY=$(supabase status -o env 2>/dev/null | grep -E '^SERVICE_ROLE_KEY=' | cut -d= -f2- | tr -d '"')
[ -n "$KEY" ] || { echo "No local service key from supabase status; is the stack running?"; exit 1; }

# The fingerprint of the code being tested, taken BEFORE the build. Taken
# at the end, it recorded code edited during a 20-minute run as having
# passed (2026-10-01, the first iOS 26 record after the darker-green edit).
fp_start=$(bash scripts/app-fingerprint.sh)

xcodegen generate -q
echo "Running the tests (about 15 minutes for the whole suite)..."
# The Mac must stay awake: on 2026-10-01 it slept twice mid-run (the lid
# closed on battery) and every tap after that timed out, which reads exactly
# like a broken app. caffeinate stops idle sleep for the run; a closed lid
# still sleeps, so the run also checks afterwards whether the Mac slept.
started_at=$(date '+%Y-%m-%d %H:%M:%S')
TEST_RUNNER_FXE_SUPABASE_SERVICE_KEY="$KEY" caffeinate -dimsu xcodebuild test \
  -project FXETennis.xcodeproj -scheme FXETennis \
  -destination "id=$UDID" -derivedDataPath "$DD" "$@" >"$LOG" 2>&1
status=$?

grep -E "Executed [0-9]+ tests?, with" "$LOG" | sort -u | sed 's/^[[:space:]]*/  /'
skipped=$(grep -cE "Test Case .* skipped \(" "$LOG")
failed=$(grep -cE "Test Case .* failed \(" "$LOG")
grep -E "Test Case .* (failed|skipped) \(" "$LOG" | sed 's/^/  /'
echo "Failed: $failed, skipped: $skipped (full log: $LOG)"

slept=$(pmset -g log 2>/dev/null | awk -v t="$started_at" '$0 >= t && /Entering Sleep/' | head -3)
if [ -n "$slept" ]; then
  echo "$slept" | sed 's/^/  /'
  echo "UNRELIABLE: the Mac slept during this run, so failures above may be timeouts, not the app. Keep the lid open and run again."
  exit 1
fi

if [ "$status" -ne 0 ] || [ "$failed" -ne 0 ]; then echo "RED"; exit 1; fi
if [ "$skipped" -ne 0 ]; then echo "RED: a skipped test is not a passing test"; exit 1; fi

if [ "$#" -eq 0 ]; then
  fp=$(bash scripts/app-fingerprint.sh)
  if [ "$fp" != "$fp_start" ]; then
    echo "GREEN, but NOT recorded: the code changed during the run ($fp_start -> $fp). Run again."
    exit 1
  fi
  n() { grep -A1 -E "Test Suite '$1\.xctest' passed" "$LOG" | grep -oE "Executed [0-9]+" | grep -oE "[0-9]+" | tail -1; }
  unit=$(n FXETennisTests); ui=$(n FXETennisUITests)
  [ -n "$unit" ] && [ -n "$ui" ] || { echo "RED: could not read both test bundles' totals from $LOG"; exit 1; }
  printf '%s\tPASS\t%s\tiOS %s\t%s\t%s unit, %s UI\n' "$fp" "$DEVICE" "$OS" "$(date -u +%Y-%m-%dT%H:%MZ)" "$unit" "$ui" >> docs/ui-test-runs.log
  echo "GREEN. Recorded in docs/ui-test-runs.log: $fp, $DEVICE, iOS $OS"
else
  echo "GREEN (partial run, not recorded)"
fi
