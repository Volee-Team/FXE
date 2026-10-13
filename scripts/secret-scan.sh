#!/bin/bash
# secret-scan.sh: fail if a secret or a personal identifier is tracked by git.
#
# Run from the root of the repository to scan (CI runs it on every push and
# PR; run it locally the same way). Scans tracked files only.
#
# Why a script and not inline workflow lines (2026-10-13): every check used to
# be `if git grep ... | grep -q .`, so a pattern git grep could not compile
# printed nothing and read as "clean". The SSN check had exactly that bug from
# 2026-09-16 to 2026-10-13: `(?i)` is not POSIX ERE, git grep exited 128
# ("repetition-operator operand invalid"), and a tracked SSN would have
# passed. Here git grep's exit status is read directly: 0 is a match (fail),
# 1 is no match (pass), anything else is a broken check (fail, loudly).
#
# Patterns are portable ERE: no \b, no (?i), no \d. Use -i for case.
set -u
FAIL=0

# scan LABEL FLAGS PATTERN [PATHSPEC...]
scan() {
  local label=$1 flags=$2 pattern=$3; shift 3
  local out rc
  out=$(git grep -n $flags -E "$pattern" -- "$@" 2>&1); rc=$?
  case $rc in
    0) echo "::error::$label"; printf '%s\n' "$out" | cut -c1-80; FAIL=1 ;;
    1) ;;
    *) echo "::error::The check for \"$label\" could not run (git grep exit $rc): $out"; FAIL=1 ;;
  esac
}

# Any .env that is not the committed template.
envs=$(git ls-files | grep -E '^\.env' | grep -v '^\.env\.example$')
if [ -n "$envs" ]; then
  echo "::error::A .env file is tracked by git:"; printf '%s\n' "$envs"; FAIL=1
fi

# Supabase secret keys and service-role JWTs. The sb_publishable_ keys in
# SupabaseClient.swift are anon keys, designed to sit in a client binary. A
# key is the prefix plus at least ten key characters: supabase-js itself
# (web/vendor) tests whether a string starts with the bare prefix.
scan "Possible service-role key committed:" "" \
  "sb_secret_[A-Za-z0-9_-]{10,}|service_role.{0,40}eyJ|SUPABASE_SERVICE_ROLE_KEY *= *[\"'][^\"']" \
  ':!*.md' ':!.github/workflows/*' ':!scripts/secret-scan.sh'

# Stripe secret and restricted keys and webhook signing secrets. Docs are
# scanned too: the prompt log is a doc, and a pasted key would land there.
# Publishable keys (pk_) are public by design and not matched.
scan "Possible Stripe key or webhook secret committed (rotate it in Stripe, then remove it):" "" \
  '(sk|rk)_(live|test)_[A-Za-z0-9]{10,}|whsec_[A-Za-z0-9]{16,}' \
  ':!.github/workflows/*' ':!scripts/secret-scan.sh'

# A reset link's token (decision 0017) is a one-hour sign-in as a member.
scan "A password-reset token is committed:" "" \
  'token_hash=[0-9a-fA-F]{20,}' \
  ':!.github/workflows/*' ':!scripts/secret-scan.sh'

# Personal identifiers. Tara sent her SSN and bank details on 2026-09-16 and
# the prompt-log hook copied them into a tracked file before it learned to
# redact. Docs are scanned too.
scan "Something shaped like a Social Security number is tracked:" "" \
  '(^|[^0-9])[0-9]{3}-[0-9]{2}-[0-9]{4}([^0-9]|$)' \
  ':!.github/workflows/*' ':!scripts/secret-scan.sh'
scan "Something shaped like a bank routing number is tracked:" "-i" \
  'routing (number|no\.?)[ :#]*[0-9]{6,}' \
  ':!.github/workflows/*' ':!scripts/secret-scan.sh'

# A password assigned a real value in a tracked file.
scan "Possible hard-coded password:" "" \
  "(PASSWORD|password) *= *[\"'][^\"']{6,}" \
  ':!*.md' ':!tests/*' ':!supabase/seed.sql' ':!.github/workflows/*' ':!scripts/secret-scan.sh'

[ "$FAIL" -eq 0 ] && echo "No secrets found." || exit 1
