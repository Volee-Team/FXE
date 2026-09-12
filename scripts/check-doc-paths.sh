#!/bin/bash
# check-doc-paths.sh: every backtick-quoted repo path named in a Markdown file
# must exist. A doc that points at a file that is not there is the cheapest
# kind of rot to detect and the most expensive to obey: "read tests/sql/x.sql"
# sends the reader to a file that was renamed weeks ago.
#
#   bash scripts/check-doc-paths.sh              # from anywhere inside the repo
#   bash scripts/check-doc-paths.sh /path/to/repo
#   RAW=1 bash scripts/check-doc-paths.sh        # audit mode: no tightening rules
#
# Runs on macOS /bin/bash 3.2 as well as CI's bash 5: no associative arrays,
# no mapfile. Needs git, grep, awk, sort; nothing else.
#
# WHAT COUNTS AS A PATH REFERENCE
# A backtick-quoted token, or any whitespace-separated word inside one (so the
# command `bash tests/run-probes.sh` is checked too), that either
#   * contains a slash and ends in a known extension
#     (.md .sql .sh .swift .yml .ts .py .mjs .html .css .txt .json .plist .xcprivacy), or
#   * starts with a repo directory:
#     docs/ tests/ supabase/ FXETennis/ FXETennisTests/ FXETennisUITests/ web/ scripts/ .github/ .claude/
# Before the test, a leading `./`, `(` or the repo's own folder name
# `FXE-Tennis/` is dropped, and trailing punctuation (`docs/x.md.` `docs/x.md,`
# `docs/x.md:` `docs/x.md)`) and a line suffix (`docs/x.md:42`, `docs/x.md:42-50`)
# are stripped. A glob such as `tests/sql/*.sql` passes when at least one file
# matches, and `docs/decisions/0007` is read as `docs/decisions/0007-*.md`.
#
# TIGHTENING RULES (all off under RAW=1), each earned by a real false positive
# on the first run, 2026-09-12:
#   * tokens starting with `~`, `/`, `$` or a URL scheme are outside the repo
#     by construction (`~/Documents/...`, `/usr/lib/postgresql/17/bin/pg_dump`)
#   * tokens containing `<`, `>`, `…`, `...`, `NNNN` or `YYYY` are placeholders
#     (`docs/screens/<version>/`, `docs/decisions/NNNN-*.md`, `docs/prompt-log/YYYY-MM.md`)
#   * tokens containing `:` after the line-suffix strip are not paths
#     (`supabase/postgres:17.6.1.155` is a Docker image tag)
#   * tokens containing `\` are escaped Swift or regex fragments
#   * `Volee/...` names a file in the other repo, on purpose (docs/ntrp-chart.md)
#   * a path git deliberately ignores counts as present even when absent
#     (`web/node_modules`, `supabase/.env.local`: their absence is normal)
#   * a path not found from the repo root is retried relative to the doc's own
#     folder (`_shared/stripe.ts` inside supabase/functions/README.md)
#
# WHAT IS SCANNED
# Every *.md outside node_modules, .git, .build and docs/prompt-log (a
# transcript records what was said; it does not make claims), and never
# docs/copy-approved.txt. CLAUDE.md is a *.md and is included. A doc whose
# first five lines carry `check-doc-paths: skip` is left alone: that is for a
# file that deliberately describes another repository.
#
# OUTPUT
# One line per missing reference, `<doc file>:<line>  <token>`, then a count,
# exit 1 if any. A reference that exists on disk but is neither tracked nor
# ignored by git is listed as a warning: present for you, missing for anyone
# who clones, and it WILL fail this check in CI where only tracked files
# exist. Exit 0 with a count of references checked when everything resolves.

set -uo pipefail
shopt -s extglob

ROOT=${1:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
cd "$ROOT" || exit 1
RAW=${RAW:-0}

EXT_RE='\.(md|sql|sh|swift|yml|ts|py|mjs|html|css|txt|json|plist|xcprivacy)$'
PREFIX_RE='^(docs|tests|supabase|FXETennis|FXETennisTests|FXETennisUITests|web|scripts|\.github|\.claude)/'
LINE_SUFFIX_RE='^(.+):[0-9]+(-[0-9]+)?$'
DECISION_RE='^docs/decisions/[0-9]{4}$'

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
REFS="$TMP/refs"; STATUS="$TMP/status"; FILTERED="$TMP/filtered"
: > "$REFS"; : > "$STATUS"; : > "$FILTERED"

# ---------------------------------------------------------------- pass 1 ----
# Every (file, line, token) worth checking, one per line, tab separated.
find . -name '*.md' \
    -not -path '*/node_modules/*' \
    -not -path './.git/*' \
    -not -path './.build/*' \
    -not -path './docs/prompt-log/*' \
  | sed 's#^\./##' | grep -v '^docs/copy-approved\.txt$' | sort > "$TMP/files"

while IFS= read -r f; do
  # A doc that describes ANOTHER repo (docs/dev-practices-for-john.md is
  # Volee's practices pack) opts out with this marker in its first five lines.
  if head -5 "$f" | grep -q 'check-doc-paths: skip'; then continue; fi
  # grep -on prints "LINE:`token`" once per backtick span on that line.
  grep -on '`[^`]*`' "$f" 2>/dev/null | while IFS= read -r hit; do
    line=${hit%%:*}
    tok=${hit#*:}
    tok=${tok#\`}; tok=${tok%\`}
    [ -z "$tok" ] && continue

    # Split on whitespace WITHOUT glob expansion (read -ra never globs).
    read -ra words <<< "$tok"
    for w in "${words[@]}"; do
      w=${w#\(}
      w=${w#./}
      [ "$RAW" != "1" ] && w=${w#FXE-Tennis/}
      w=${w%%+([:,.;\)])}
      if [[ $w =~ $LINE_SUFFIX_RE ]]; then w=${BASH_REMATCH[1]}; fi
      w=${w%%+([:,.;\)])}
      [ -z "$w" ] && continue

      # The two criteria.
      if ! { [[ $w == */* && $w =~ $EXT_RE ]] || [[ $w =~ $PREFIX_RE ]]; }; then
        continue
      fi

      # Tightening rules: shapes that are not repo paths.
      if [ "$RAW" != "1" ]; then
        case $w in
          '~'*|/*|'$'*|http://*|https://*|*'<'*|*'>'*|*'…'*|*'...'*|*NNNN*|*YYYY*|*:*|*'\'*|Volee/*)
            printf '%s\n' "$w" >> "$FILTERED"; continue ;;
        esac
      fi
      printf '%s\t%s\t%s\n' "$f" "$line" "$w" >> "$REFS"
    done
  done
done < "$TMP/files"

# ---------------------------------------------------------------- pass 2 ----
# Each unique (doc dir, token) resolved once: ok | missing | untracked.
exists() {  # 0 if a file/dir exists, or a glob matches at least one entry
  if [[ $1 == *[\*\?\[]* ]]; then compgen -G "$1" >/dev/null 2>&1; else [ -e "$1" ]; fi
}
tracked_or_ignored() {  # 0 if git tracks it, or deliberately ignores it (generated)
  [[ $1 == *[\*\?\[]* ]] && return 0
  git check-ignore -q -- "$1" 2>/dev/null && return 0
  if [ -d "$1" ]; then [ -n "$(git ls-files -- "$1" | head -1)" ]
  else git ls-files --error-unmatch -- "$1" >/dev/null 2>&1; fi
}
resolve() {  # doc-dir token -> ok | untracked | missing
  local dir=$1 p=$2 cand
  [ "$RAW" != "1" ] && [[ $p =~ $DECISION_RE ]] && p="$p-*.md"
  for cand in "$p" "$dir/$p"; do
    [ "$RAW" = "1" ] && [ "$cand" != "$p" ] && continue      # no doc-relative retry in RAW
    if exists "$cand"; then
      if tracked_or_ignored "$cand"; then echo ok; else echo untracked; fi
      return
    fi
  done
  # Absent but deliberately ignored (node_modules, .env.local): normal. Asked
  # twice because a `node_modules/` pattern only matches a directory, and git
  # cannot tell that a path which does not exist would have been one.
  if [ "$RAW" != "1" ] && { git check-ignore -q -- "$p" 2>/dev/null || git check-ignore -q -- "$p/" 2>/dev/null; }; then
    echo ok; return
  fi
  echo missing
}

awk -F'\t' '{ n=split($1, a, "/"); d=(n>1) ? substr($1, 1, length($1)-length(a[n])-1) : "."; print d "\t" $3 }' "$REFS" \
  | sort -u | while IFS=$'\t' read -r d p; do
  printf '%s\t%s\t%s\n' "$d" "$p" "$(resolve "$d" "$p")" >> "$STATUS"
done

# ---------------------------------------------------------------- report ----
# Join refs to status on (doc dir, token); awk keeps the doc order of pass 1.
awk -F'\t' '
  NR==FNR { st[$1 "\t" $2]=$3; next }
  { n=split($1, a, "/"); d=(n>1) ? substr($1, 1, length($1)-length(a[n])-1) : ".";
    print $1 ":" $2 "  " $3 "\t" st[d "\t" $3] }' "$STATUS" "$REFS" > "$TMP/joined"

CHECKED=$(wc -l < "$REFS" | tr -d ' ')
awk -F'\t' '$2=="missing" { print $1 }' "$TMP/joined"
MISSING=$(awk -F'\t' '$2=="missing"' "$TMP/joined" | wc -l | tr -d ' ')
UNIQUE=$(awk -F'\t' '$3=="missing" { print $2 }' "$STATUS" | sort -u | wc -l | tr -d ' ')
echo ""
echo "MISSING: $MISSING reference(s) to $UNIQUE path(s) that do not exist, out of $CHECKED checked in $(wc -l < "$TMP/files" | tr -d ' ') files."

if awk -F'\t' '$2=="untracked"' "$TMP/joined" | grep -q .; then
  echo ""
  echo "UNTRACKED (exists here, not in git: missing for a clone and for CI):"
  awk -F'\t' '$2=="untracked" { print "  " $1 }' "$TMP/joined"
fi

if [ "$RAW" != "1" ] && [ -s "$FILTERED" ]; then
  echo ""
  echo "FILTERED as non-repo shapes ($(sort -u "$FILTERED" | wc -l | tr -d ' ') unique; RAW=1 checks them anyway):"
  sort -u "$FILTERED" | sed 's/^/  /'
fi

[ "$MISSING" -eq 0 ]
