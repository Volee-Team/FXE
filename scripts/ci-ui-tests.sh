#!/usr/bin/env bash
# ci-ui-tests.sh (CI): the whole unit and UI suite on GitHub's Mac, against the
# throwaway fxe-ci Supabase project, on the two iOS versions
# check-ui-test-record.sh requires: iOS 26 on an iPhone 17 Pro and iOS 18 on
# the iPhone SE (3rd generation), the same pair run-ui-tests.sh runs on a Mac.
# One job runs both, one after the other, because both reset the one project.
#
# Same rules as run-ui-tests.sh: a fresh database before each run (reset to
# every migration plus the seed), the service key passed and never printed,
# and a skipped test fails the run. Unlike the Mac, nothing is written to
# docs/ui-test-runs.log: the passing job is the record for its own PR
# (check-ui-test-record.sh is told by the workflow). Added 2026-11-21.
#
# Needs: DB_URL (the project's URI with its password; POOLER_HOST turns a
# direct one into the session pooler),
# FXE_URL, FXE_ANON_KEY, FXE_SERVICE_KEY. Never point DB_URL at hosted FXE:
# the reset drops every table.
set -uo pipefail
cd "$(dirname "$0")/.."
: "${DB_URL:?}" "${FXE_URL:?}" "${FXE_ANON_KEY:?}" "${FXE_SERVICE_KEY:?}"
case "$FXE_URL" in
  *amnaxvznkadkgzdxzegw*) echo "::error::FXE_URL is the live FXE project; refusing to reset it."; exit 1 ;;
esac
case "$DB_URL" in
  *amnaxvznkadkgzdxzegw*) echo "::error::DB_URL is the live FXE project; refusing to reset it."; exit 1 ;;
esac
# GitHub's runners have no IPv6, and a project's direct address
# (db.<ref>.supabase.co) is IPv6 only: the first run on 2026-11-21 failed
# with "hostname resolving error". A direct address is rewritten to the same
# project's session pooler (user postgres.<ref>, POOLER_HOST, port 5432),
# keeping the password exactly as given. A pooler address passes unchanged.
if [ -n "${POOLER_HOST:-}" ]; then
  DB_URL=$(python3 -c '
import sys, re
from urllib.parse import urlsplit, urlunsplit
url, pooler = sys.argv[1], sys.argv[2]
u = urlsplit(url)
m = re.fullmatch(r"db\.([a-z0-9]{20})\.supabase\.co", u.hostname or "")
if not m:
    print(url); sys.exit()
user = u.username or "postgres"
if user == "postgres": user = "postgres." + m.group(1)
pw = u.password or ""
netloc = f"{user}:{pw}@{pooler}:5432"
print(urlunsplit((u.scheme, netloc, u.path or "/postgres", u.query, u.fragment)))' "$DB_URL" "$POOLER_HOST")
fi
# GitHub masks the secret as a whole string; mask the password on its own
# too, since the rewritten address is a new string (public logs).
pw=$(python3 -c 'import sys; from urllib.parse import urlsplit, unquote; p = urlsplit(sys.argv[1]).password or ""; print(p); print(unquote(p))' "$DB_URL")
while IFS= read -r line; do [ -n "$line" ] && echo "::add-mask::$line"; done <<< "$pw"
unset pw
fp=$(bash scripts/app-fingerprint.sh)
xcodegen generate -q
status=0
run_one() {
  local major=$1 device=$2 udid os log
  read -r udid os < <(xcrun simctl list devices available -j | python3 -c '
import json, sys, re
want, major = sys.argv[1], sys.argv[2]
best = None
for rt, devs in json.load(sys.stdin)["devices"].items():
    m = re.search(r"iOS-(\d+)-(\d+)", rt)
    if not m or m.group(1) != major: continue
    ver = (int(m.group(1)), int(m.group(2)))
    for d in devs:
        if d["name"] == want and (best is None or ver > best[0]):
            best = (ver, d["udid"])
print(best[1], f"{best[0][0]}.{best[0][1]}") if best else print("", "")' "$device" "$major")
  if [ -z "$udid" ]; then echo "::error::No simulator \"$device\" on iOS $major on this runner."; return 1; fi
  echo "::group::Reset fxe-ci, then iOS $os on $device"
  supabase db reset --db-url "$DB_URL" --yes >/tmp/ci-reset.log 2>&1 || { tail -20 /tmp/ci-reset.log; echo "::endgroup::"; echo "::error::Resetting fxe-ci failed."; return 1; }
  echo "::endgroup::"
  log="/tmp/ui-$major.log"
  TEST_RUNNER_FXE_SUPABASE_URL="$FXE_URL" \
  TEST_RUNNER_FXE_SUPABASE_ANON_KEY="$FXE_ANON_KEY" \
  TEST_RUNNER_FXE_SUPABASE_SERVICE_KEY="$FXE_SERVICE_KEY" \
  xcodebuild test -project FXETennis.xcodeproj -scheme FXETennis \
    -destination "platform=iOS Simulator,id=$udid" \
    -derivedDataPath /tmp/dd -resultBundlePath "/tmp/ui-$major.xcresult" \
    -retry-tests-on-failure -test-iterations 2 >"$log" 2>&1
  local rc=$?
  grep -E "Executed [0-9]+ tests?, with" "$log" | sort -u | sed 's/^[[:space:]]*/  /'
  local skipped; skipped=$(grep -cE "Test Case .* skipped \(" "$log")
  grep -E "Test Case .* (failed|skipped) \(" "$log" | sed 's/^/  /'
  if [ "$rc" -ne 0 ]; then echo "::error::iOS $os on $device: RED (xcodebuild exit $rc). Full log in the xcresult artifact."; tail -40 "$log"; return 1; fi
  if [ "$skipped" -ne 0 ]; then echo "::error::iOS $os on $device: a skipped test is not a passing test."; return 1; fi
  echo "GREEN: $fp on $device, iOS $os"
  echo "- $fp PASS $device iOS $os" >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}
run_one 26 "iPhone 17 Pro" || status=1
run_one 18 "iPhone SE (3rd generation)" || status=1
exit $status
