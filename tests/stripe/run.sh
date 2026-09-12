#!/bin/bash
# The payments pipeline, end to end, against Stripe's own mock server.
#
#   docker run -d --name stripe-mock --network supabase_network_FXE-Tennis stripe/stripe-mock
#   bash tests/stripe/make-env.sh > /tmp/mock.env
#   supabase functions serve --env-file /tmp/mock.env   (in another shell)
#   bash tests/stripe/run.sh
#
# Why this exists (2026-09-12): the three edge functions, the ledger RPCs, the
# webhook signature check and the paid-flag trigger had never run as one
# chain, because there is no Stripe account yet. stripe-mock answers every
# Stripe API call with spec-shaped data, so everything on OUR side of the wire
# can be proven now: the customer id lands on the account, the card summary
# is written only by a signed webhook, a charge goes pending -> processing ->
# succeeded and marks the registration paid, a refund unmarks it, a decline
# lands as failed with a reason, and an unsigned webhook changes nothing.
# What it cannot prove: Stripe's real behaviour (3DS, declines, real ids).
# That needs the test keys and a real test card.
#
# Prints one PASS/FAIL line per check, like the SQL probes.

set -uo pipefail
cd "$(dirname "$0")/../.." || exit 1

API=${FXE_API_URL:-http://127.0.0.1:54321}
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
WHSEC=${STRIPE_WEBHOOK_SECRET:-whsec_stripe_mock_only}
ANON=$(supabase status -o env 2>/dev/null | grep '^ANON_KEY' | cut -d= -f2 | tr -d '"')
MARIA=22222222-2222-2222-2222-222222222222
MARIA_P=a0000000-0000-0000-0000-000000000001
CLINIC=d0000000-0000-0000-0000-000000000002

FAILED=0
check() { # name expected actual
  if [ "$2" = "$3" ]; then echo "  PASS  $1"; else echo "  FAIL  $1 (expected '$2', got '$3')"; FAILED=1; fi
}
sql() { docker exec "$DB" psql -U postgres -d postgres -Atc "$1"; }
jwt() { curl -s "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
          -d "{\"email\":\"$1\",\"password\":\"password\"}" | python3 -c "import sys,json;print(json.load(sys.stdin).get('access_token',''))"; }
fn() { # name jwt body
  curl -s -X POST "$API/functions/v1/$1" -H "Authorization: Bearer $2" -H "apikey: $ANON" -H "Content-Type: application/json" -d "$3"; }
rpc() { # name jwt body
  curl -s -X POST "$API/rest/v1/rpc/$1" -H "apikey: $ANON" -H "Authorization: Bearer $2" -H "Content-Type: application/json" -d "$3"; }
field() { python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d$1 if d else '')
except Exception: print('')"; }
# Stripe's signature scheme: t=<unix>,v1=hex(HMAC_SHA256(secret, "<unix>.<payload>")).
webhook() { # payload [secret]
  local secret=${2:-$WHSEC} ts payload sig
  ts=$(date +%s); payload="$1"
  sig=$(printf '%s.%s' "$ts" "$payload" | openssl dgst -sha256 -hmac "$secret" | sed 's/^.* //')
  curl -s -X POST "$API/functions/v1/stripe-webhook" -H "Content-Type: application/json" \
       -H "stripe-signature: t=$ts,v1=$sig" -d "$payload"; }
event() { # type object-json
  echo "{\"id\":\"evt_$RANDOM\",\"object\":\"event\",\"api_version\":\"2024-12-18.acacia\",\"type\":\"$1\",\"data\":{\"object\":$2}}"; }

if ! curl -s -o /dev/null "$API/functions/v1/stripe-webhook" -X POST; then
  echo "Edge functions are not being served. Run: bash tests/stripe/make-env.sh > /tmp/mock.env && supabase functions serve --env-file /tmp/mock.env"; exit 1
fi

echo "════ Stripe pipeline (stripe-mock) ════"
# Clean slate for exactly the fixtures this touches (Maria on the two seed
# clinics it uses, her card, the ledger); the same rows are removed at the end.
# Nothing else of Maria's is touched: on 2026-09-12 a broader delete here wiped
# a late cancel made by hand on the simulator while it was being looked at.
CLINIC2=d0000000-0000-0000-0000-000000000001
sql "delete from public.payments; update public.accounts set stripe_customer_id=null, card_brand=null, card_last4=null, card_added_at=null where id='$MARIA'; delete from public.registrations where player_id='$MARIA_P' and clinic_id in ('$CLINIC','$CLINIC2'); update public.app_settings set value='false' where key='payments_enabled';" >/dev/null

MARIA_JWT=$(jwt maria@fxe.test); TARA_JWT=$(jwt tara@fxe.test)
check "signed in as Maria and Tara" "2" "$([ -n "$MARIA_JWT" ] && [ -n "$TARA_JWT" ] && echo 2)"

# ---- 1. SetupIntent: customer created and stored, secret handed back, nothing charged
out=$(fn stripe-setup-intent "$MARIA_JWT" '{}')
check "setup-intent returns a client secret" "seti_" "$(echo "$out" | field "['setupIntentClientSecret'][:5]")"
CUS=$(sql "select stripe_customer_id from public.accounts where id='$MARIA'")
check "stripe customer id stored on the account" "cus_" "${CUS:0:4}"
out2=$(fn stripe-setup-intent "$MARIA_JWT" '{}')
check "second tap reuses the customer" "$CUS" "$(echo "$out2" | field "['customerId']")"
check "no card summary before the webhook" "" "$(sql "select coalesce(card_brand,'') from public.accounts where id='$MARIA'")"
check "anon cannot ask for a setup intent" "not_authenticated" "$(fn stripe-setup-intent "$ANON" '{}' | field "['error']")"

# ---- 2. Webhook writes the card summary, and only when signed
si="{\"id\":\"seti_1\",\"object\":\"setup_intent\",\"customer\":\"$CUS\",\"payment_method\":\"pm_card_visa\",\"status\":\"succeeded\"}"
check "unsigned webhook is rejected" "no_signature" "$(curl -s -X POST "$API/functions/v1/stripe-webhook" -d "$(event setup_intent.succeeded "$si")" | field "['error']")"
check "wrong secret is rejected" "bad_signature" "$(webhook "$(event setup_intent.succeeded "$si")" whsec_wrong | field "['error']")"
check "still no card after the bad ones" "" "$(sql "select coalesce(card_brand,'') from public.accounts where id='$MARIA'")"
check "signed setup_intent.succeeded accepted" "True" "$(webhook "$(event setup_intent.succeeded "$si")" | field "['received']")"
check "card summary written by the webhook" "yes" "$(sql "select case when card_brand is not null and card_last4 ~ '^[0-9]{4}$' and card_added_at is not null then 'yes' else 'no' end from public.accounts where id='$MARIA'")"

# ---- 3. A charge: Tara's tap -> pending -> processing (Stripe id) -> webhook -> succeeded + paid
REG=$(sql "with i as (insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes) values ('$CLINIC','$MARIA_P','in','self',2200,true,90) returning id) select id from i")
sql "update public.app_settings set value='true' where key='payments_enabled'" >/dev/null
BODY="{\"p_registration\":\"$REG\",\"p_kind\":\"clinic_fee\"}"
PAY=$(rpc admin_charge_registration "$TARA_JWT" "$BODY" | field "['id']")
check "admin_charge_registration made a pending row" "pending 2200" "$(sql "select status||' '||amount_cents from public.payments where id='$PAY'")"
check "a player cannot run stripe-charge" "not_authorized" "$(fn stripe-charge "$MARIA_JWT" '{}' | field "['error']")"
out=$(fn stripe-charge "$TARA_JWT" '{}')
check "stripe-charge processed the row" "1" "$(echo "$out" | field "['processed']" | grep -c "$PAY")"
check "row is processing with a PaymentIntent id" "processing pi_" "$(sql "select status||' '||left(stripe_payment_intent_id,3) from public.payments where id='$PAY'")"
check "a second stripe-charge finds nothing pending" "0" "$(fn stripe-charge "$TARA_JWT" '{}' | field "['processed']" | grep -c "$PAY")"
check "registration not paid before the webhook" "f" "$(sql "select paid from public.registrations where id='$REG'")"
PI=$(sql "select stripe_payment_intent_id from public.payments where id='$PAY'")
OBJ="{\"id\":\"$PI\",\"object\":\"payment_intent\",\"status\":\"succeeded\"}"
webhook "$(event payment_intent.succeeded "$OBJ")" >/dev/null
check "payment_intent.succeeded -> succeeded" "succeeded" "$(sql "select status from public.payments where id='$PAY'")"
check "registration marked paid by the ledger" "t" "$(sql "select paid from public.registrations where id='$REG'")"
check "double tap is one fee" "already_charged" "$(rpc admin_charge_registration "$TARA_JWT" "$BODY" | field "['message']")"

# ---- 4. Refund: pending -> processing (refund id) -> webhook -> succeeded, paid flag cleared
BODY="{\"p_payment\":\"$PAY\"}"
REF=$(rpc admin_refund_payment "$TARA_JWT" "$BODY" | field "['id']")
check "admin_refund_payment made a pending refund" "refund pending 2200" "$(sql "select kind||' '||status||' '||amount_cents from public.payments where id='$REF'")"
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
check "refund row is processing with a refund id" "processing re_" "$(sql "select status||' '||left(stripe_refund_id,3) from public.payments where id='$REF'")"
RE=$(sql "select stripe_refund_id from public.payments where id='$REF'")
OBJ="{\"id\":\"$RE\",\"object\":\"refund\",\"status\":\"succeeded\"}"
webhook "$(event refund.updated "$OBJ")" >/dev/null
check "refund.updated -> succeeded" "succeeded" "$(sql "select status from public.payments where id='$REF'")"
check "registration unpaid after the refund" "f" "$(sql "select paid from public.registrations where id='$REG'")"

# ---- 5. A decline lands as failed with the reason, and the fee can be tried again
REG2=$(sql "with i as (insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes) values ('$CLINIC2','$MARIA_P','in','self',1800,true,60) returning id) select id from i")
BODY="{\"p_registration\":\"$REG2\",\"p_kind\":\"late_cancel\"}"
PAY2=$(rpc admin_charge_registration "$TARA_JWT" "$BODY" | field "['id']")
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
PI2=$(sql "select stripe_payment_intent_id from public.payments where id='$PAY2'")
OBJ="{\"id\":\"$PI2\",\"object\":\"payment_intent\",\"status\":\"requires_payment_method\",\"last_payment_error\":{\"code\":\"card_declined\",\"message\":\"Your card was declined.\"}}"
webhook "$(event payment_intent.payment_failed "$OBJ")" >/dev/null
check "payment_failed -> failed with Stripe's reason" "failed Your card was declined." "$(sql "select status||' '||failure_reason from public.payments where id='$PAY2'")"
check "a failed fee can be charged again" "pending" "$(rpc admin_charge_registration "$TARA_JWT" "$BODY" | field "['status']")"

# ---- 6. Switched off again, nothing new can be charged
sql "update public.app_settings set value='false' where key='payments_enabled'" >/dev/null
BODY="{\"p_registration\":\"$REG\",\"p_kind\":\"no_show\"}"
check "payments_disabled once the switch is off" "payments_disabled" "$(rpc admin_charge_registration "$TARA_JWT" "$BODY" | field "['message']")"

# Restore the seed state this touched.
sql "delete from public.payments; delete from public.registrations where id in ('$REG','$REG2'); update public.accounts set stripe_customer_id=null, card_brand=null, card_last4=null, card_added_at=null where id='$MARIA';" >/dev/null

echo ""
if [ $FAILED -eq 0 ]; then echo "PASS: Stripe pipeline"; else echo "FAIL: Stripe pipeline"; exit 1; fi
