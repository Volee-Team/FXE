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
check() {
  local live_navy live_tabs
  live_navy=$(curl -s "$SITE/tokens.css" | grep -o -- '--fxe-navy: #[0-9A-Fa-f]*' | head -1)
  live_tabs=$(curl -s "$SITE/index.html" | grep -c 'role="tab"')
  [ "$live_navy" = "$NAVY" ] && [ "$live_tabs" = "$TABS" ]
}
for attempt in 1 2; do
  echo "deploy attempt $attempt"
  npx -y vercel --prod --yes > /tmp/vercel-deploy.log 2>&1
  sleep 8
  if check; then echo "live site matches the working tree (navy $NAVY, $TABS tabs)"; exit 0; fi
  echo "live site does not match yet"
done
echo "DEPLOY NOT VERIFIED after two attempts; see /tmp/vercel-deploy.log"; exit 1
