#!/usr/bin/env bash
# check-doc-status.sh: a live doc must not carry a status that git can
# already prove is stale.
#
# Alex, 2026-10-12: "we have tons of docs and some are becoming outdated and
# we need a SOLID system and ASOT to stick to". The rule that came out of it:
# status words live in four places only (docs/launch-checklist.md,
# docs/backlog.md, docs/questions-for-tara.md, docs/decisions/README.md) and
# every other doc points at a row. This script is the part of that rule a
# machine can enforce: three kinds of stale status that git can see.
#
#   bash scripts/check-doc-status.sh
#
# (a) OLD BUILDS. "build N", "rcN" or "tfN" on a line that is not DONE and
#     not plainly history, with N below CURRENT_PROJECT_VERSION - 1 from
#     project.yml. The audit of 2026-10-12 found "OPEN: in build 5" while
#     build 9 was current: a status that was true once and nobody moved.
# (b) MERGED BRANCHES. A branch named on a line that also says "branch", in a
#     line that is not DONE and does not say it merged, when that branch is
#     already an ancestor of origin/main. "the app's half on branch
#     `push-client`" sat in an OPEN row for two weeks after it merged.
# (c) FORBIDDEN INSTRUCTIONS, from scripts/doc-forbidden.txt: an instruction
#     that has hurt production before (a bare `vercel --prod`;
#     `apply_migration` against hosted).
#
# LIVE DOCS: every *.md under docs/ except docs/archive/ (snapshots, each
# with an "Archived" banner), docs/decisions/NNNN-*.md (a decision record is
# a dated snapshot; its README is live), and docs/prompt-log/ (a transcript);
# plus README.md, web/README.md, supabase/functions/README.md, the agent
# briefs in .claude/agents/, and CLAUDE.md above "## Changelog" (a diary is
# allowed to be old). A file whose first five lines say
# `check-doc-paths: skip` describes another repository and is skipped.
#
# HISTORY: a line that says DONE, or reads as history ("was", "shipped",
# "landed", "merged", "uploaded", "tagged", "since", "until",
# "earlier", "never archived"), or sits under a "Done log" heading, is not a
# status claim and is not checked by (a) or (b). (c) checks every line.
#
# CI checks out with full history (fetch-depth: 0) so origin/main and every
# remote branch exist. Locally, local branches count too. A branch name that
# is not a ref here is not checked (it may live on one laptop only).
#
# Exit 1 on any finding; one line per finding.
set -u
cd "$(dirname "$0")/.." || exit 2

# CURRENT_BUILD=N overrides project.yml, to see what the next build bump
# will flag before it lands.
CUR=${CURRENT_BUILD:-$(sed -nE 's/^ *CURRENT_PROJECT_VERSION: *"?([0-9]+)"?.*/\1/p' project.yml | head -1)}
[ -n "$CUR" ] || { echo "  FAIL  no CURRENT_PROJECT_VERSION in project.yml"; exit 1; }

MAIN=origin/main
git rev-parse -q --verify "$MAIN" >/dev/null || MAIN=main
# Branch names (short, without origin/) that are already in main.
MERGED=$(git for-each-ref --format='%(refname)' refs/heads refs/remotes/origin \
  | sed -E 's#^refs/(heads|remotes/origin)/##' | grep -vE '^(HEAD|main)$' | sort -u \
  | while read -r b; do
      ref=$(git rev-parse -q --verify "refs/remotes/origin/$b" || git rev-parse -q --verify "refs/heads/$b")
      [ -n "$ref" ] && git merge-base --is-ancestor "$ref" "$MAIN" 2>/dev/null && echo "$b"
    done)

MERGED="$MERGED" python3 - "$CUR" "$MAIN" <<'PY'
import os, re, sys, glob
cur, main = int(sys.argv[1]), sys.argv[2]
merged = set(os.environ.get("MERGED", "").split())

files = []
for root, dirs, names in os.walk("docs"):
    dirs[:] = [d for d in dirs if os.path.join(root, d) not in ("docs/archive", "docs/prompt-log")]
    for n in names:
        p = os.path.join(root, n)
        if not n.endswith(".md"):
            continue
        if root == "docs/decisions" and n != "README.md":
            continue
        files.append(p)
files += [p for p in ["README.md", "web/README.md", "supabase/functions/README.md"] if os.path.exists(p)]
files += sorted(glob.glob(".claude/agents/*.md"))
files.append("CLAUDE.md")

rules = []
for raw in open("scripts/doc-forbidden.txt", encoding="utf-8"):
    if not raw.strip() or raw.lstrip().startswith("#"):
        continue
    parts = [x.strip() for x in raw.rstrip("\n").split(" ;; ")]
    if len(parts) != 4:
        print(f"  FAIL  scripts/doc-forbidden.txt: malformed rule: {raw.strip()[:60]}")
        continue
    pat, need, excuse, why = parts
    rules.append((re.compile(pat, re.I), None if need == "-" else re.compile(need, re.I), re.compile(excuse, re.I), why))

HISTORY = re.compile(r"\bDONE\b|\b(was|were|shipped|landed|merged|uploaded|tagged|since|until|earlier|never archived)\b", re.I)
BUILD = re.compile(r"\bbuild (\d+)\b|\brc(\d+)\b|\btf(\d+)\b", re.I)
TICK = re.compile(r"`([^`]+)`")
bad = []
for f in sorted(set(files)):
    try:
        lines = open(f, encoding="utf-8").read().splitlines()
    except OSError:
        continue
    if any("check-doc-paths: skip" in l for l in lines[:5]):
        continue
    in_done_log = False
    for n, line in enumerate(lines, 1):
        if f == "CLAUDE.md" and line.startswith("## Changelog"):
            break
        if line.startswith("#"):
            in_done_log = bool(re.match(r"#+ .*\bdone log\b", line, re.I))
        for pat, need, excuse, why in rules:
            if pat.search(line) and (need is None or need.search(line)) and not excuse.search(line):
                bad.append(f"{f}:{n}  forbidden instruction '{pat.pattern}': {why}")
        if in_done_log or HISTORY.search(line):
            continue
        for m in BUILD.finditer(line):
            num = int(next(g for g in m.groups() if g))
            if num < cur - 1:
                bad.append(f"{f}:{n}  '{m.group(0)}' is an old build (current {cur}) on a line that is not DONE or history")
        if re.search(r"\bbranch(es)?\b", line, re.I):
            for tok in TICK.findall(line):
                if tok in merged:
                    bad.append(f"{f}:{n}  branch '{tok}' is already merged into {main}; say so or point at its row")

for b in bad:
    print("  FAIL ", b)
print(f"{len(set(files))} live docs checked against build {cur} and {len(merged)} merged branches: {len(bad)} problem(s).")
sys.exit(1 if bad else 0)
PY
