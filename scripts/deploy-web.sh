#!/usr/bin/env bash
# deploy-web.sh: deploy web/ to Vercel production and PROVE it landed.
#
# Three times (2026-09-12, 2026-09-21, 2026-09-22) `vercel --prod` printed
# nothing and changed nothing, and the second run took. A deploy that is not
# verified by fetching the live page is a hope. This script deploys, fetches
# a marker from the live site, and deploys once more if the marker is missing.
#
#   bash scripts/deploy-web.sh            # marker: the git short SHA is not on the page,
#                                          # so the marker is a string from web/index.html
set -u
cd "$(dirname "$0")/../web" || exit 2
SITE="https://fxe-tennis-admin.vercel.app"
# A line that only the current index.html has: the last <link> or <script> src hash
# is not available, so use a content fingerprint: the md5 of the local file's
# <title>…</title> plus the tokens.css navy value.
NAVY=$(grep -o -- '--fxe-navy: #[0-9A-Fa-f]*' tokens.css | head -1)
TABS=$(grep -c 'role="tab"' index.html)
# 2026-09-27: the navy value and the tab count both stayed the same through a
# release that added the whole board report, so this check passed while the
# live page was the old one (51 KB live against 59 KB local): the fourth
# silent no-op, and the first one the script itself missed. A fingerprint has
# to change whenever the content does. Vercel serves static files byte for
# byte, so compare the md5 of every page and stylesheet with the working tree,
# and confirm the files .vercelignore keeps out are really out.
md5of() { if command -v md5 >/dev/null; then md5 -q "$1"; else md5sum "$1" | cut -d' ' -f1; fi; }
check() {
  local f live
  for f in index.html review.html reset.html tokens.css config.js; do
    [ -f "$f" ] || continue
    live=$(curl -s "$SITE/$f" -o /tmp/deploy-live-check && md5of /tmp/deploy-live-check)
    if [ "$live" != "$(md5of "$f")" ]; then echo "  live $f differs from the working tree"; return 1; fi
  done
  for f in privacy.html; do
    if [ "$(curl -s -o /dev/null -w '%{http_code}' "$SITE/$f")" != "404" ]; then echo "  $f is live but .vercelignore keeps it out"; return 1; fi
  done
}
for attempt in 1 2; do
  echo "deploy attempt $attempt"
  npx -y vercel --prod --yes > /tmp/vercel-deploy.log 2>&1
  sleep 8
  if check; then echo "live site matches the working tree byte for byte (index, review, reset, tokens, config; privacy draft absent)"; exit 0; fi
  echo "live site does not match yet"
done
echo "DEPLOY NOT VERIFIED after two attempts; see /tmp/vercel-deploy.log"; exit 1
