#!/bin/bash
# Print the env for `supabase functions serve --env-file` when the push
# function should talk to tests/push/mock-apns.ts instead of Apple.
#
# The signing key is generated here, every run, and never written to the repo:
# a throwaway P-256 key in the same PKCS#8 shape as Apple's .p8 file. The mock
# reads the same env file and verifies every provider token's signature with
# the public half, so the ES256 signing is checked, not just its header. The
# webhook secret is random per run too; tests/push/run.sh reads it back from
# the file it is given.
#
#   bash tests/push/make-env.sh > /tmp/push.env
#   bash tests/push/make-env.sh http://172.17.0.1:12222 > push.env   # CI: the docker gateway
#
# $1 is the APNs host the edge runtime reaches the mock at. On a Mac that is
# host.docker.internal; on Linux the docker network's gateway address.
HOST=${1:-http://host.docker.internal:12222}
# One line: the function strips the PEM markers and whitespace, and a dotenv
# file cannot hold a multi-line value portably.
KEY=$(openssl ecparam -name prime256v1 -genkey -noout 2>/dev/null \
      | openssl pkcs8 -topk8 -nocrypt 2>/dev/null \
      | tr -d '\n')
if [ -z "$KEY" ]; then echo "make-env.sh: openssl produced no key" >&2; exit 1; fi
cat <<ENV
APNS_KEY_ID=TESTKEY123
APNS_TEAM_ID=TESTTEAM12
APNS_TOPIC=com.fxetennis.app
APNS_HOST=$HOST
APNS_PRIVATE_KEY=$KEY
PUSH_WEBHOOK_SECRET=$(openssl rand -hex 24)
ENV
