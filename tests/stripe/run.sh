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
# Added 2026-09-27 (MVP audit items 3, 4, 11): Stripe's livemode flag on the
# ledger and test-mode money kept out of the Paid flag and the board report;
# an early webhook attached by metadata; a stuck row swept back and retried
# under its own key; a dropped connection retried instead of failed; a
# customer Stripe no longer has (the sandbox-to-live swap) treated as none by
# both functions; a deleted account never charged, and delete-account
# removing the Stripe customer. stripe-mock always answers livemode false, and
# the harness signs its own events, so it plays either of Stripe's modes. The
# error rule itself (decline, idempotency, 5xx, timeout), which the mock can
# never produce, is pinned with the SDK's own error objects in
# tests/stripe/errors.test.ts, run at the end (needs deno).
#
# The dropped-connection check stops and restarts the mock container
# ($STRIPE_MOCK_CONTAINER, default stripe-mock, as in CI). Running the mock as
# the Homebrew binary instead, set STRIPE_MOCK_CONTAINER= (empty) to skip it.
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
KEN=33333333-3333-3333-3333-333333333333;   KEN_P=a0000000-0000-0000-0000-000000000002
ROB=44444444-4444-4444-4444-444444444444;   ROB_P=a0000000-0000-0000-0000-000000000003
DANA=66666666-6666-6666-6666-666666666666;  DANA_P=a0000000-0000-0000-0000-000000000004
PRIYA=55555555-5555-5555-5555-555555555555; PRIYA_P=a0000000-0000-0000-0000-000000000005
CLINIC=d0000000-0000-0000-0000-000000000002
CLINIC3=d0000000-0000-0000-0000-000000000003
CLINIC4=d0000000-0000-0000-0000-000000000004
MOCK=${STRIPE_MOCK_CONTAINER-stripe-mock}
HARNESS_PEOPLE="'$MARIA','$KEN','$ROB','$DANA','$PRIYA'"

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
event() { # type object-json [livemode, default true: the live path]
  echo "{\"id\":\"evt_$RANDOM\",\"object\":\"event\",\"api_version\":\"2024-12-18.acacia\",\"livemode\":${3:-true},\"type\":\"$1\",\"data\":{\"object\":$2}}"; }
reg() { # clinic player cents member minutes -> a You're In! registration id
  sql "with i as (insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes) values ('$1','$2','in','self',$3,$4,$5) returning id) select id from i"; }
card() { # account customer-id: a customer and a Visa ending 4242, as the webhook would leave them
  sql "update public.accounts set stripe_customer_id='$2', card_brand='visa', card_last4='4242', card_added_at=now() where id='$1'" >/dev/null; }
REGS=""   # every registration this harness makes, removed at the end

if ! curl -s -o /dev/null "$API/functions/v1/stripe-webhook" -X POST; then
  echo "Edge functions are not being served. Run: bash tests/stripe/make-env.sh > /tmp/mock.env && supabase functions serve --env-file /tmp/mock.env"; exit 1
fi

echo "════ Stripe pipeline (stripe-mock) ════"
# Clean slate for exactly the fixtures this touches (Maria on the two seed
# clinics it uses, her card, the ledger); the same rows are removed at the end.
# Nothing else of Maria's is touched: on 2026-09-12 a broader delete here wiped
# a late cancel made by hand on the simulator while it was being looked at.
CLINIC2=d0000000-0000-0000-0000-000000000001
sql "delete from public.payments; update public.accounts set stripe_customer_id=null, card_brand=null, card_last4=null, card_added_at=null, deleted_at=null where id in ($HARNESS_PEOPLE); delete from public.registrations where player_id in ('$MARIA_P','$KEN_P','$ROB_P','$DANA_P','$PRIYA_P') and clinic_id in ('$CLINIC','$CLINIC2','$CLINIC3','$CLINIC4'); update public.app_settings set value='false' where key='payments_enabled'; delete from public.app_settings where key='stripe_live_since';" >/dev/null

MARIA_JWT=$(jwt maria@fxe.test); TARA_JWT=$(jwt tara@fxe.test)
check "signed in as Maria and Tara" "2" "$([ -n "$MARIA_JWT" ] && [ -n "$TARA_JWT" ] && echo 2)"

# ---- 0. The permission box (decision 0015 §7): no card setup without a
#         recorded consent to the current words. The server, not the screen.
sql "delete from public.card_consents where account_id='$MARIA'" >/dev/null
check "setup-intent refused without the permission" "card_consent_required" "$(fn stripe-setup-intent "$MARIA_JWT" '{}' | field "['error']")"
check "no customer created by the refused call" "" "$(sql "select coalesce(stripe_customer_id,'') from public.accounts where id='$MARIA'")"
curl -s -X POST "$API/rest/v1/rpc/record_card_consent" -H "apikey: $ANON" -H "Authorization: Bearer $MARIA_JWT" \
  -H "Content-Type: application/json" -d '{"p_app_version":"stripe harness"}' >/dev/null
check "consent recorded through the RPC" "1" "$(sql "select count(*) from public.card_consents where account_id='$MARIA'")"

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
# 20260927200001: Stripe's own livemode flag, which stripe-mock always answers false.
check "stripe-charge stores Stripe's livemode flag" "false" "$(sql "select coalesce(livemode::text,'NULL') from public.payments where id='$PAY'")"
check "a second stripe-charge finds nothing pending" "0" "$(fn stripe-charge "$TARA_JWT" '{}' | field "['processed']" | grep -c "$PAY")"
check "registration not paid before the webhook" "f" "$(sql "select paid from public.registrations where id='$REG'")"
PI=$(sql "select stripe_payment_intent_id from public.payments where id='$PAY'")
OBJ="{\"id\":\"$PI\",\"object\":\"payment_intent\",\"status\":\"succeeded\"}"
webhook "$(event payment_intent.succeeded "$OBJ")" >/dev/null
check "payment_intent.succeeded -> succeeded" "succeeded" "$(sql "select status from public.payments where id='$PAY'")"
check "the signed event's livemode is the one kept" "t" "$(sql "select livemode from public.payments where id='$PAY'")"
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
# Stripe's shape for an NSF decline: code card_declined, decline_code the bank's reason.
OBJ="{\"id\":\"$PI2\",\"object\":\"payment_intent\",\"status\":\"requires_payment_method\",\"last_payment_error\":{\"code\":\"card_declined\",\"decline_code\":\"insufficient_funds\",\"message\":\"Your card was declined.\"}}"
webhook "$(event payment_intent.payment_failed "$OBJ")" >/dev/null
check "payment_failed -> failed with Stripe's reason" "failed Your card was declined." "$(sql "select status||' '||failure_reason from public.payments where id='$PAY2'")"
# 20260926000010: decline_code wins over code, so Tara reads "Insufficient funds (NSF)", not "Card declined".
check "payment_failed records the decline code" "insufficient_funds" "$(sql "select coalesce(failure_code,'NULL') from public.payments where id='$PAY2'")"
# A PaymentIntent that failed and later went through (the cardholder fixed
# the card) must stop reading "Declined" on the Money tab.
OBJ="{\"id\":\"$PI2\",\"object\":\"payment_intent\",\"status\":\"succeeded\"}"
webhook "$(event payment_intent.succeeded "$OBJ")" >/dev/null
check "a later success clears the decline" "succeeded NULL" "$(sql "select status||' '||coalesce(failure_code,'NULL') from public.payments where id='$PAY2'")"
# Put the fixture back to failed so the retry below has something to retry.
sql "update public.payments set status='failed' where id='$PAY2'" >/dev/null
check "a failed fee can be charged again" "pending" "$(rpc admin_charge_registration "$TARA_JWT" "$BODY" | field "['status']")"

# ---- 5b. A refund made in Stripe's dashboard (where refunds happen in v1,
#          Kat 2026-09-22) reaches the ledger, once, linked to its charge.
OBJ="{\"id\":\"ch_dash_probe\",\"object\":\"charge\",\"payment_intent\":\"$PI\",\"refunds\":{\"object\":\"list\",\"data\":[{\"id\":\"re_dash_probe\",\"object\":\"refund\",\"status\":\"succeeded\",\"amount\":500,\"currency\":\"usd\",\"payment_intent\":\"$PI\",\"metadata\":{}}]}}"
webhook "$(event charge.refunded "$OBJ")" >/dev/null
check "dashboard refund recorded against its charge" "refund 500 succeeded $PAY" "$(sql "select kind||' '||amount_cents||' '||status||' '||refunds_payment_id from public.payments where stripe_refund_id='re_dash_probe'")"
webhook "$(event charge.refunded "$OBJ")" >/dev/null
check "a redelivered dashboard refund is recorded once" "1" "$(sql "select count(*) from public.payments where stripe_refund_id='re_dash_probe'")"

# ---- 7. Test mode is not money (20260927200001, audit item 3). A sandbox
#         success is recorded as test mode, marks nobody paid, and the board
#         report does not count it; Tara still sees it listed before the switch.
REG_T=$(reg "$CLINIC3" "$MARIA_P" 1800 true 60); REGS="$REGS,'$REG_T'"
PAY_T=$(rpc admin_charge_registration "$TARA_JWT" "{\"p_registration\":\"$REG_T\",\"p_kind\":\"clinic_fee\"}" | field "['id']")
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
PI_T=$(sql "select stripe_payment_intent_id from public.payments where id='$PAY_T'")
# JSON goes into a variable first: bash 3.2 (macOS) brace-expands a quoted
# "{a,b}" inside "$(...)", which split these bodies in two on the first run.
OBJ="{\"id\":\"$PI_T\",\"object\":\"payment_intent\",\"status\":\"succeeded\"}"
webhook "$(event payment_intent.succeeded "$OBJ" false)" >/dev/null
check "a test-mode success is recorded as test mode" "succeeded false" "$(sql "select status||' '||livemode from public.payments where id='$PAY_T'")"
check "a test-mode fee marks nobody paid" "f" "$(sql "select paid from public.registrations where id='$REG_T'")"
DAY3=$(sql "select (starts_at at time zone 'America/New_York')::date from public.clinics where id='$CLINIC3'")
BODY="{\"p_from\":\"$DAY3\",\"p_to\":\"$DAY3\"}"
check "the board report counts no test-mode money" "0" "$(rpc admin_board_report_clinics "$TARA_JWT" "$BODY" | python3 -c "
import sys,json
try: print(sum(r['collected_cents'] for r in json.load(sys.stdin) if r['clinic_id']=='$CLINIC3'))
except Exception as e: print('error', e)")"
check "Tara still sees the test row before the switch" "false" "$(curl -s "$API/rest/v1/payments_ledger?id=eq.$PAY_T&select=livemode" -H "apikey: $ANON" -H "Authorization: Bearer $TARA_JWT" | field "[0]['livemode']" | tr 'TF' 'tf')"

# ---- 8. The early webhook (audit item 4): Stripe can call back before
#         stripe-charge has stored the PaymentIntent id. Matched by id alone the
#         event found no row, answered 200, and the charge sat in processing
#         for good. A PaymentIntent this app made names its row in metadata.
REG_E1=$(reg "$CLINIC3" "$KEN_P" 1800 true 60); REG_E2=$(reg "$CLINIC3" "$ROB_P" 2300 false 60); REGS="$REGS,'$REG_E1','$REG_E2'"
PAY_E1=$(sql "with i as (insert into public.payments (registration_id, account_id, kind, amount_cents, status) values ('$REG_E1','$KEN','clinic_fee',1800,'processing') returning id) select id from i")
PAY_E2=$(sql "with i as (insert into public.payments (registration_id, account_id, kind, amount_cents, status) values ('$REG_E2','$ROB','clinic_fee',2300,'processing') returning id) select id from i")
PI_E1="pi_early_$RANDOM$RANDOM"; PI_E2="pi_early_$RANDOM$RANDOM"
OBJ="{\"id\":\"$PI_E1\",\"object\":\"payment_intent\",\"status\":\"succeeded\",\"metadata\":{\"fxe_payment_id\":\"$PAY_E1\"}}"
webhook "$(event payment_intent.succeeded "$OBJ")" >/dev/null
check "an early success lands on the row its metadata names" "succeeded $PI_E1 true" "$(sql "select status||' '||coalesce(stripe_payment_intent_id,'NULL')||' '||coalesce(livemode::text,'NULL') from public.payments where id='$PAY_E1'")"
check "and marks that registration paid" "t" "$(sql "select paid from public.registrations where id='$REG_E1'")"
OBJ="{\"id\":\"$PI_E2\",\"object\":\"payment_intent\",\"status\":\"requires_payment_method\",\"last_payment_error\":{\"code\":\"card_declined\",\"decline_code\":\"expired_card\",\"message\":\"Your card has expired.\"},\"metadata\":{\"fxe_payment_id\":\"$PAY_E2\"}}"
webhook "$(event payment_intent.payment_failed "$OBJ")" >/dev/null
check "an early decline lands on its row with the reason" "failed $PI_E2 expired_card" "$(sql "select status||' '||coalesce(stripe_payment_intent_id,'NULL')||' '||coalesce(failure_code,'NULL') from public.payments where id='$PAY_E2'")"
OBJ="{\"id\":\"pi_other_$RANDOM\",\"object\":\"payment_intent\",\"status\":\"succeeded\",\"metadata\":{\"fxe_payment_id\":\"$PAY_E2\"}}"
webhook "$(event payment_intent.succeeded "$OBJ")" >/dev/null
check "another PaymentIntent cannot take a row that has one" "failed $PI_E2" "$(sql "select status||' '||stripe_payment_intent_id from public.payments where id='$PAY_E2'")"
OBJ="{\"id\":\"pi_other_$RANDOM\",\"object\":\"payment_intent\",\"status\":\"succeeded\",\"metadata\":{\"fxe_payment_id\":\"$REF\"}}"
webhook "$(event payment_intent.succeeded "$OBJ")" >/dev/null
check "a PaymentIntent event never lands on a refund row" "NULL" "$(sql "select coalesce(stripe_payment_intent_id,'NULL') from public.payments where id='$REF'")"

# ---- 9. A call that died between the claim and storing the id left its row
#         in processing with no id. Inside Stripe's 24-hour idempotency window
#         the sweep retries it as the SAME row (so the same key); past it the
#         row is held for a person. A row claimed moments ago is not touched.
card "$PRIYA" cus_harness_priya
REG_S1=$(reg "$CLINIC3" "$PRIYA_P" 2300 false 60); REG_S2=$(reg "$CLINIC3" "$DANA_P" 1800 true 60); REG_S3=$(reg "$CLINIC4" "$KEN_P" 1800 true 60)
REGS="$REGS,'$REG_S1','$REG_S2','$REG_S3'"
PAY_S1=$(sql "with i as (insert into public.payments (registration_id, account_id, kind, amount_cents, status, created_at, updated_at) values ('$REG_S1','$PRIYA','clinic_fee',2300,'processing', now() - interval '10 minutes', now() - interval '10 minutes') returning id) select id from i")
PAY_S2=$(sql "with i as (insert into public.payments (registration_id, account_id, kind, amount_cents, status, created_at, updated_at) values ('$REG_S2','$DANA','clinic_fee',1800,'processing', now() - interval '25 hours', now() - interval '25 hours') returning id) select id from i")
PAY_S3=$(sql "with i as (insert into public.payments (registration_id, account_id, kind, amount_cents, status) values ('$REG_S3','$KEN','clinic_fee',1800,'processing') returning id) select id from i")
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
check "a stuck charge is retried as the same row" "processing pi_ 1" "$(sql "select status||' '||coalesce(left(stripe_payment_intent_id,3),'NULL')||' '||(select count(*) from public.payments where registration_id='$REG_S1') from public.payments where id='$PAY_S1'")"
check "one stuck past the key's lifetime is held for a person" "processing retry_window_passed NULL" "$(sql "select status||' '||coalesce(failure_reason,'NULL')||' '||coalesce(stripe_payment_intent_id,'NULL') from public.payments where id='$PAY_S2'")"
check "a charge claimed moments ago is left to its call" "processing NULL NULL" "$(sql "select status||' '||coalesce(stripe_payment_intent_id,'NULL')||' '||coalesce(failure_reason,'NULL') from public.payments where id='$PAY_S3'")"

# ---- 10. A dropped connection may have charged, so the row goes back to
#          pending (it used to be marked failed, and Tara's second tap made a
#          new row, a new key and a second charge). The next call reaches
#          Stripe as the same row, under the same key.
if [ -n "$MOCK" ]; then
  card "$ROB" cus_harness_rob
  REG_C=$(reg "$CLINIC4" "$ROB_P" 2300 false 60); REGS="$REGS,'$REG_C'"
  PAY_C=$(rpc admin_charge_registration "$TARA_JWT" "{\"p_registration\":\"$REG_C\",\"p_kind\":\"clinic_fee\"}" | field "['id']")
  if docker stop "$MOCK" >/dev/null 2>&1; then
    fn stripe-charge "$TARA_JWT" '{}' >/dev/null
    check "a dropped connection puts the charge back to pending, not failed" "pending NULL NULL" "$(sql "select status||' '||coalesce(stripe_payment_intent_id,'NULL')||' '||coalesce(failure_reason,'NULL') from public.payments where id='$PAY_C'")"
    docker start "$MOCK" >/dev/null
    for i in $(seq 1 20); do
      fn stripe-charge "$TARA_JWT" '{}' >/dev/null
      [ -n "$(sql "select stripe_payment_intent_id from public.payments where id='$PAY_C'")" ] && break
      sleep 1
    done
    check "the retry reaches Stripe as the same row (the same key)" "processing pi_ 1" "$(sql "select status||' '||coalesce(left(stripe_payment_intent_id,3),'NULL')||' '||(select count(*) from public.payments where registration_id='$REG_C') from public.payments where id='$PAY_C'")"
  else
    check "the mock container $MOCK can be stopped (STRIPE_MOCK_CONTAINER)" "stopped" "not found"
  fi
else
  echo "  SKIP  dropped connection: STRIPE_MOCK_CONTAINER is empty (the mock is not a container)"
fi

# ---- 11. A customer Stripe does not have: every sandbox customer once the
#          live key is in ("No such customer"), or one deleted in the dashboard.
#          stripe-mock answers 404 to a path it does not know, and a customer id
#          with a "/" in it becomes exactly that, so it stands in for Stripe's 404
#          here. Both functions treat such a customer as none.
card "$MARIA" 'cus_sandbox/maria'
out=$(fn stripe-setup-intent "$MARIA_JWT" '{}')
NEW=$(echo "$out" | field "['customerId']")
check "setup-intent makes a new customer for one Stripe does not have" "cus_ stored" "${NEW:0:4} $([ "$NEW" != 'cus_sandbox/maria' ] && [ "$NEW" = "$(sql "select stripe_customer_id from public.accounts where id='$MARIA'")" ] && echo stored)"
check "the stale card summary goes with the old customer" "NULL" "$(sql "select coalesce(card_last4,'NULL') from public.accounts where id='$MARIA'")"
card "$KEN" 'cus_sandbox/ken'
REG_G=$(reg "$CLINIC2" "$KEN_P" 1800 true 60); REGS="$REGS,'$REG_G'"
PAY_G=$(rpc admin_charge_registration "$TARA_JWT" "{\"p_registration\":\"$REG_G\",\"p_kind\":\"clinic_fee\"}" | field "['id']")
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
check "a charge on a customer Stripe does not have fails as no card" "failed no_card_on_file" "$(sql "select status||' '||coalesce(failure_reason,'NULL') from public.payments where id='$PAY_G'")"
check "and the member is asked for a card again" "NULL NULL" "$(sql "select coalesce(stripe_customer_id,'NULL')||' '||coalesce(card_last4,'NULL') from public.accounts where id='$KEN'")"

# ---- 12. Deleted accounts (audit item 11). Nothing is charged on the way
#          out, and deleting removes the person from Stripe.
card "$DANA" cus_harness_dana
REG_D=$(reg "$CLINIC4" "$DANA_P" 1800 true 60); REGS="$REGS,'$REG_D'"
PAY_D=$(rpc admin_charge_registration "$TARA_JWT" "{\"p_registration\":\"$REG_D\",\"p_kind\":\"clinic_fee\"}" | field "['id']")
sql "update public.accounts set deleted_at = now() where id='$DANA'" >/dev/null
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
check "a deleted account is never charged, card or not" "failed account_deleted NULL" "$(sql "select status||' '||coalesce(failure_reason,'NULL')||' '||coalesce(stripe_payment_intent_id,'NULL') from public.payments where id='$PAY_D'")"
sql "update public.accounts set deleted_at = null where id='$DANA'" >/dev/null

signup() { curl -s "$API/auth/v1/signup" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"$1\",\"password\":\"harness-$RANDOM$RANDOM\"}"; }
SIGNED=""   # auth users made here, hard-deleted at the end
U1_OUT=$(signup "harness-a-$RANDOM$RANDOM@stripe.test"); U1=$(echo "$U1_OUT" | field "['user']['id']"); U1_JWT=$(echo "$U1_OUT" | field "['access_token']")
U2_OUT=$(signup "harness-b-$RANDOM$RANDOM@stripe.test"); U2=$(echo "$U2_OUT" | field "['user']['id']"); U2_JWT=$(echo "$U2_OUT" | field "['access_token']")
U3_OUT=$(signup "harness-c-$RANDOM$RANDOM@stripe.test"); U3=$(echo "$U3_OUT" | field "['user']['id']"); U3_JWT=$(echo "$U3_OUT" | field "['access_token']")
SIGNED="'$U1','$U2','$U3'"
PROFILE='{"p_first_name":"Harness","p_last_name":"Person","p_phone":"5550100","p_is_member":false,"p_adult_rating":3.5,"p_level_note":null}'
rpc create_my_account "$U1_JWT" "$PROFILE" >/dev/null; rpc create_my_account "$U2_JWT" "$PROFILE" >/dev/null
CUS_DEL="cus_harness_del_$RANDOM$RANDOM"   # unique per run: the mock's log outlives a run
sql "update public.accounts set stripe_customer_id='$CUS_DEL' where id='$U1'; update public.accounts set stripe_customer_id='cus_gone/deleted' where id='$U2'" >/dev/null
out=$(fn delete-account "$U1_JWT" '{}')
check "delete-account deletes the Stripe customer" "$U1 deleted" "$(echo "$out" | field "['deleted']") $(echo "$out" | field "['stripe']")"
check "and forgets its id once Stripe has let go" "NULL Deleted true" "$(sql "select coalesce(stripe_customer_id,'NULL')||' '||first_name||' '||(deleted_at is not null) from public.accounts where id='$U1'")"
[ -n "$MOCK" ] && check "Stripe was asked to delete that customer" "1" "$(docker logs "$MOCK" 2>&1 | grep -c "DELETE /v1/customers/$CUS_DEL")"
check "the sign-in is removed after Stripe" "t" "$(sql "select deleted_at is not null from auth.users where id='$U1'")"
out=$(fn delete-account "$U2_JWT" '{}')
check "a customer Stripe no longer has counts as removed" "$U2 already_gone NULL" "$(echo "$out" | field "['deleted']") $(echo "$out" | field "['stripe']") $(sql "select coalesce(stripe_customer_id,'NULL') from public.accounts where id='$U2'")"
out=$(fn delete-account "$U3_JWT" '{}')
check "no profile yet: nothing to scrub, the sign-in still goes" "$U3 none t" "$(echo "$out" | field "['deleted']") $(echo "$out" | field "['stripe']") $(sql "select deleted_at is not null from auth.users where id='$U3'")"

# ---- 13. The key swap (stripe_cutover_to_live, 20260927200001), end to end
#          through the API as the lead would run it (service_role; the SQL
#          editor as postgres is the other way). It refuses while live money
#          exists; once run, every card is gone, a charge queued before the swap
#          is never sent with the live key, test rows leave Tara's Money list,
#          and the next card setup makes a new customer. The client-role refusal
#          is asserted by has_function_privilege in stripe_live_cutover.sql,
#          not by calling it: the local image crashes a backend that calls a
#          function it may not execute (CLAUDE.md, known local defect).
SERVICE=$(supabase status -o env 2>/dev/null | grep '^SERVICE_ROLE_KEY' | cut -d= -f2 | tr -d '"')
cutover() { curl -s -X POST "$API/rest/v1/rpc/stripe_cutover_to_live" -H "apikey: $SERVICE" -H "Authorization: Bearer $SERVICE" -H "Content-Type: application/json" -d '{}'; }
check "the swap is refused while live money exists" "live_payments_exist" "$(cutover | field "['message']")"
card "$MARIA" cus_before_swap
REG_Q=$(reg "$CLINIC4" "$MARIA_P" 1800 true 60); REGS="$REGS,'$REG_Q'"
PAY_Q=$(rpc admin_charge_registration "$TARA_JWT" "{\"p_registration\":\"$REG_Q\",\"p_kind\":\"clinic_fee\"}" | field "['id']")
# "The swap happened before any live charge": this run's live rows go first.
sql "delete from public.payments where livemode is true and kind = 'refund'; delete from public.payments where livemode is true" >/dev/null
check "the swap runs through the API as service_role" "True" "$(cutover | python3 -c "import sys,json; r=json.load(sys.stdin); print(isinstance(r,list) and r[0]['accounts_cleared']>=1)")"
check "every card is gone after the swap" "0" "$(sql "select count(*) from public.accounts where stripe_customer_id is not null or card_last4 is not null")"
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
check "a charge queued before the swap is never sent" "canceled NULL" "$(sql "select status||' '||coalesce(stripe_payment_intent_id,'NULL') from public.payments where id='$PAY_Q'")"
check "test rows leave Tara's Money list" "0" "$(curl -s "$API/rest/v1/payments_ledger?id=eq.$PAY_T&select=id" -H "apikey: $ANON" -H "Authorization: Bearer $TARA_JWT" | python3 -c "import sys,json; print(len(json.load(sys.stdin)))")"
out=$(fn stripe-setup-intent "$MARIA_JWT" '{}')
NEW=$(echo "$out" | field "['customerId']")
check "the next card setup makes a new customer" "cus_ stored" "${NEW:0:4} $([ "$NEW" != 'cus_before_swap' ] && [ "$NEW" = "$(sql "select stripe_customer_id from public.accounts where id='$MARIA'")" ] && echo stored)"
check "the swap runs once" "already_live" "$(cutover | field "['message']")"

# ---- 6. Switched off again, nothing new can be charged
sql "update public.app_settings set value='false' where key='payments_enabled'" >/dev/null
BODY="{\"p_registration\":\"$REG\",\"p_kind\":\"no_show\"}"
check "payments_disabled once the switch is off" "payments_disabled" "$(rpc admin_charge_registration "$TARA_JWT" "$BODY" | field "['message']")"

# Restore the seed state this touched.
sql "delete from public.card_consents where account_id='$MARIA'; delete from public.payments; delete from public.registrations where id in ('$REG','$REG2'$REGS); update public.accounts set stripe_customer_id=null, card_brand=null, card_last4=null, card_added_at=null, deleted_at=null where id in ($HARNESS_PEOPLE); delete from auth.users where id in (${SIGNED:-'00000000-0000-0000-0000-000000000000'}); delete from public.app_settings where key='stripe_live_since';" >/dev/null

# ---- E. The error rule stripe-mock cannot exercise, with the Stripe SDK's
#         own error objects (tests/stripe/errors.test.ts).
if command -v deno >/dev/null 2>&1; then
  unit=$(NO_COLOR=1 deno test --allow-env --allow-read tests/stripe/errors.test.ts 2>&1)
  echo "$unit" | grep -E '\.\.\. (ok|FAILED)' | sed 's/^/        /'
  check "error rule, SDK error objects (deno test)" "ok" "$(echo "$unit" | grep -qE '^ok \|' && echo ok || echo "$(echo "$unit" | tail -1)")"
else
  check "error rule, SDK error objects (deno test)" "ok" "deno is not installed"
fi

echo ""
if [ $FAILED -eq 0 ]; then echo "PASS: Stripe pipeline"; else echo "FAIL: Stripe pipeline"; exit 1; fi
