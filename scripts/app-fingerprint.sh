#!/usr/bin/env bash
# app-fingerprint.sh: one hash for everything the UI tests exercise: the app,
# its tests, the project file, and the database they run against (migrations
# and seed). Tracked files only, read from the working tree, so the hash a
# green run records here is the hash CI computes on the same commit.
# Used by run-ui-tests.sh (writes) and check-ui-test-record.sh (CI, reads).
#
# project.yml is hashed without its two version lines (MARKETING_VERSION,
# CURRENT_PROJECT_VERSION): a build number changes nothing the tests check,
# and counting it made every new TestFlight build cost three more hours of
# runs (2026-10-02).
set -euo pipefail
cd "$(dirname "$0")/.."
{
  git ls-files -z FXETennis FXETennisTests FXETennisUITests supabase/migrations supabase/seed.sql \
    | sort -z | xargs -0 shasum -a 256
  printf 'project.yml-sans-versions  '
  grep -vE '^[[:space:]]*(MARKETING_VERSION|CURRENT_PROJECT_VERSION):' project.yml | shasum -a 256
} | shasum -a 256 | cut -c1-16
