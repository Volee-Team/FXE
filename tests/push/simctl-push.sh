#!/bin/bash
# Show a push on the simulator exactly as supabase/functions/push/index.ts
# sends it, to check the client half of decision 0008 by eye: the banner
# while the app is open, a tap opening its clinic, the number on the icon.
# Apple is not involved: simctl hands the payload to the app as if APNs had
# delivered it. A person runs this; no test does.
#
#   supabase db reset
#       the seed ends by having invite_from_pool write Maria's invitation
#   build and run the Debug app on a booted simulator, sign in as maria@fxe.test
#   bash tests/push/simctl-push.sh
#       pushes tests/push/simctl-invitation.apns: "A spot opened in Evening
#       Coed. Accept or decline.", naming the seeded row and its registration
#   bash tests/push/simctl-push.sh --latest tara@fxe.test
#       builds the payload from that account's newest notification the way
#       index.ts does (the body, sound, the unread count as the badge, the row
#       id, its type and entity), so any producer's row can be checked. For
#       Tara: invite someone from the web admin, accept as them in the app,
#       sign in as Tara, then push her "... accepted." row.
#
# What to see. App open: a banner, and Home reloads (the bell's number
# moves). App in the background, tap the notification: the clinic opens in
# a sheet (Maria: Accept and Decline; Tara: her roster for that clinic), the
# row reads as read, and the icon's number drops by one. With the bell open,
# the clinic opens inside the bell instead.
#
# SIM=<udid> targets a simulator other than the booted one;
# FXE_DB_CONTAINER picks the local stack for --latest.

set -euo pipefail
cd "$(dirname "$0")/../.." || exit 1
SIM=${SIM:-booted}
BUNDLE=com.fxetennis.app
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
FILE=tests/push/simctl-invitation.apns

if [ "${1:-}" = "--latest" ]; then
  EMAIL=${2:?usage: simctl-push.sh --latest <email>}
  FILE=$(mktemp -t fxe-push)
  # Same fields, same order of work as index.ts:67-79. psql -v binds the email.
  docker exec -i "$DB" psql -U postgres -d postgres -At -v email="$EMAIL" -f - > "$FILE" <<'SQL'
select json_build_object(
         'Simulator Target Bundle', 'com.fxetennis.app',
         'aps', json_build_object(
                  'alert', json_build_object('body', n.body),
                  'sound', 'default',
                  'badge', (select count(*) from public.notifications u
                             where u.account_id = n.account_id and u.read_at is null)),
         'notification_id', n.id,
         'type', n.type,
         'entity_type', n.entity_type,
         'entity_id', n.entity_id)
  from public.notifications n join public.accounts a on a.id = n.account_id
 where a.email = :'email'
 order by n.created_at desc
 limit 1;
SQL
  [ -s "$FILE" ] || { echo "No notification for $EMAIL"; exit 1; }
fi

cat "$FILE"; echo
xcrun simctl push "$SIM" "$BUNDLE" "$FILE"
