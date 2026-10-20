#!/bin/bash
# rehearsal.sh: every money path against REAL Stripe test mode, through the
# restricted key the live one will copy (checklist A13).
#
# Why: everything else runs against stripe-mock, which accepts requests real
# Stripe refuses (2026-10-04: no payment_method_types; 2026-09-26: no named
# card) and never says no for a missing permission. A restricted key missing
# one permission makes saving a card fail with nothing on screen. This runs
# the app's own edge functions, holding only that key, against Stripe's real
# sandbox: save a card, charge after a clinic, refund, a declined card, a
# bank demanding 3-D Secure on an off-session charge, a chargeback, payouts,
# and deleting an account.
#
# Needs (Alex, once; docs/for-alex.md "Stripe rehearsal"):
#   .env.stripe-rehearsal at the repo root (gitignored by .env.*), two lines:
#     STRIPE_SECRET_KEY=rk_test_...        the restricted sandbox key
#     STRIPE_PUBLISHABLE_KEY=pk_test_...   the same sandbox's publishable key
#   the Stripe CLI, signed in to that same sandbox (`stripe login`)
#   the local stack running (`supabase start`); Docker up
#
# Run: bash tests/stripe/rehearsal.sh
# It resets the LOCAL database first and starts its own functions server and
# `stripe listen`, both stopped at the end. Nothing here touches hosted.
# Refuses any live key.
set -u
cd "$(dirname "$0")/../.." || exit 1
ROOT=$(pwd)
API=http://127.0.0.1:54321
DB=${FXE_DB_CONTAINER:-supabase_db_FXE-Tennis}
ENVF=$ROOT/.env.stripe-rehearsal
WORK=$(mktemp -d "${TMPDIR:-/tmp}/fxe-rehearsal.XXXXXX")
FAILED=0

say() { printf '%s\n' "$*"; }
check() { if [ "$2" = "$3" ]; then say "  PASS  $1"; else say "  FAIL  $1 (expected '$2', got '$3')"; FAILED=1; fi; }
sql() { docker exec "$DB" psql -U postgres -d postgres -Atc "$1"; }
field() { python3 -c "
import sys,json
try: d=json.load(sys.stdin); print(d$1 if d else '')
except Exception: print('')"; }
fn() { curl -s -X POST "$API/functions/v1/$1" -H "Authorization: Bearer $2" -H "apikey: $ANON" -H "Content-Type: application/json" -d "$3"; }
rpc() { curl -s -X POST "$API/rest/v1/rpc/$1" -H "apikey: $ANON" -H "Authorization: Bearer $2" -H "Content-Type: application/json" -d "$3"; }
jwt() { curl -s "$API/auth/v1/token?grant_type=password" -H "apikey: $ANON" -H "Content-Type: application/json" \
          -d "{\"email\":\"$1\",\"password\":\"password\"}" | field ".get('access_token','')"; }
# wait_for LABEL SQL EXPECTED [seconds, default 40]: webhooks arrive when they arrive.
wait_for() {
  local got="" i
  for i in $(seq 1 "${4:-40}"); do got=$(sql "$2"); [ "$got" = "$3" ] && break; sleep 1; done
  check "$1" "$3" "$got"
}
stripe_api() { stripe "$@" 2>/dev/null; }   # the CLI's own sandbox key: it plays the phone's PaymentSheet

cleanup() {
  [ -n "${LISTEN_PID:-}" ] && kill "$LISTEN_PID" 2>/dev/null
  [ -n "${SERVE_PID:-}" ] && kill "$SERVE_PID" 2>/dev/null
  pkill -f "functions serve --env-file $WORK" 2>/dev/null
  rm -rf "$WORK"
}
trap cleanup EXIT

# ---------------------------------------------------------------- preflight
# Never under a UI run: the reset below would wipe its data mid-test.
if [ -d /tmp/fxe-ui-tests.lock ] && kill -0 "$(cat /tmp/fxe-ui-tests.lock/pid 2>/dev/null)" 2>/dev/null; then
  say "A UI test run holds the local database (/tmp/fxe-ui-tests.lock). Run this after it."; exit 2
fi
[ -f "$ENVF" ] || { say "No $ENVF. See docs/for-alex.md, Stripe rehearsal."; exit 2; }
SK=$(grep -E '^STRIPE_SECRET_KEY=' "$ENVF" | cut -d= -f2-)
PK=$(grep -E '^STRIPE_PUBLISHABLE_KEY=' "$ENVF" | cut -d= -f2-)
case "$SK" in rk_test_*) ;; *_live_*) say "REFUSED: a live key. The rehearsal is sandbox only."; exit 2;; *) say "STRIPE_SECRET_KEY must be a restricted sandbox key (rk_test_...)."; exit 2;; esac
case "$PK" in pk_test_*) ;; *) say "STRIPE_PUBLISHABLE_KEY must be the sandbox's pk_test_... key."; exit 2;; esac
command -v stripe >/dev/null || { say "No Stripe CLI: brew install stripe/stripe-cli/stripe, then stripe login."; exit 2; }
WHSEC=$(stripe listen --print-secret 2>/dev/null)
case "$WHSEC" in whsec_*) ;; *) say "The Stripe CLI is not signed in: run stripe login."; exit 2;; esac

say "════ Stripe rehearsal (real sandbox, restricted key) ════"
supabase db reset >/dev/null 2>&1 || { say "supabase db reset failed (is the stack running?)"; exit 2; }
sleep 3
ANON=$(supabase status -o env 2>/dev/null | grep '^ANON_KEY' | cut -d= -f2 | tr -d '"')
printf 'STRIPE_SECRET_KEY=%s\nSTRIPE_PUBLISHABLE_KEY=%s\nSTRIPE_WEBHOOK_SECRET=%s\n' "$SK" "$PK" "$WHSEC" > "$WORK/env"
supabase functions serve --env-file "$WORK/env" > "$WORK/serve.log" 2>&1 & SERVE_PID=$!
up=""
for i in $(seq 1 60); do
  code=$(curl -s -o /dev/null -w '%{http_code}' -X POST "$API/functions/v1/stripe-webhook")
  [ "$code" = "400" ] && { up=1; break; }   # no_signature: the function is serving
  sleep 1
done
[ -n "$up" ] || { say "The functions never came up:"; tail -20 "$WORK/serve.log"; exit 2; }
stripe listen --forward-to "$API/functions/v1/stripe-webhook" > "$WORK/listen.log" 2>&1 & LISTEN_PID=$!
for i in $(seq 1 30); do grep -q 'Ready' "$WORK/listen.log" && break; sleep 1; done
grep -q 'Ready' "$WORK/listen.log" || { say "stripe listen never got ready:"; cat "$WORK/listen.log"; exit 2; }
sleep 2

TARA=11111111-1111-1111-1111-111111111111
MARIA=22222222-2222-2222-2222-222222222222; MARIA_P=a0000000-0000-0000-0000-000000000001
KEN=33333333-3333-3333-3333-333333333333;   KEN_P=a0000000-0000-0000-0000-000000000002
ROB=44444444-4444-4444-4444-444444444444;   ROB_P=a0000000-0000-0000-0000-000000000003
DANA=66666666-6666-6666-6666-666666666666;  DANA_P=a0000000-0000-0000-0000-000000000004
CLINIC=d0000000-0000-0000-0000-000000000002
CLINIC3=d0000000-0000-0000-0000-000000000003
CLINIC4=d0000000-0000-0000-0000-000000000004
TARA_JWT=$(jwt tara@fxe.test)
reg() { sql "with i as (insert into public.registrations (clinic_id, player_id, status, source, price_cents_charged, was_member, duration_minutes) values ('$1','$2','in','self',$3,true,60) returning id) select id from i"; }
sql "update public.app_settings set value='true' where key='payments_enabled'" >/dev/null

# save_card WHO_JWT ACCOUNT TEST_PM: the app's own path (consent, then
# stripe-setup-intent), with the CLI confirming the SetupIntent the way
# PaymentSheet does on the phone. Echoes the customer id.
save_card() {
  rpc record_card_consent "$1" '{"p_app_version":"stripe rehearsal"}' >/dev/null
  local out seti cus
  out=$(fn stripe-setup-intent "$1" '{}')
  seti=$(echo "$out" | field "['setupIntentClientSecret']" | sed 's/_secret_.*//')
  cus=$(echo "$out" | field "['customerId']")
  if [ -z "$seti" ]; then
    echo "  setup-intent answered: $(echo "$out" | head -c 300)" >&2   # stderr: stdout is the customer id
    return 1
  fi
  stripe_api post "/v1/setup_intents/$seti/confirm" -d "payment_method=$3" >/dev/null
  echo "$cus"
}

# ---- 1. Save a card: SetupIntent, ephemeral key, the webhook writes the summary
MARIA_JWT=$(jwt maria@fxe.test)
CUS_M=$(save_card "$MARIA_JWT" "$MARIA" pm_card_visa)
check "stripe-setup-intent made a real customer" "cus_" "${CUS_M:0:4}"
check "the CLI sees the same sandbox (same customer)" "$CUS_M" "$(stripe_api customers retrieve "$CUS_M" | field "['id']")"
wait_for "the webhook wrote Visa 4242 (PaymentMethods read)" "select coalesce(card_brand,'')||' '||coalesce(card_last4,'') from public.accounts where id='$MARIA'" "visa 4242"
check "and made it the default for off-session charges" "pm_" "$(stripe_api customers retrieve "$CUS_M" | field "['invoice_settings']['default_payment_method'][:3]")"

# ---- 2. Charge after a clinic, the way Tara's Charge does it
REG=$(reg "$CLINIC" "$MARIA_P" 1800)
PAY=$(rpc admin_charge_registration "$TARA_JWT" "{\"p_registration\":\"$REG\",\"p_kind\":\"clinic_fee\"}" | field "['id']")
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
wait_for "the charge succeeded (PaymentIntents write)" "select status from public.payments where id='$PAY'" "succeeded"
check "Stripe recorded it in test mode" "f" "$(sql "select livemode from public.payments where id='$PAY'")"
# A test-mode payment never marks a registration paid (20260927200001:
# payments_sync_registration_paid skips livemode false), and every sandbox
# event is livemode false. The paid flag itself is pinned by run.sh, whose
# events are live.
check "a sandbox payment does not mark the registration paid" "f" "$(sql "select paid from public.registrations where id='$REG'")"
PI=$(sql "select stripe_payment_intent_id from public.payments where id='$PAY'")
check "Stripe has 1800 cents on that PaymentIntent" "1800 succeeded" "$(stripe_api payment_intents retrieve "$PI" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d['amount_received'], d['status'])")"

# ---- 3. Refund it
REF=$(rpc admin_refund_payment "$TARA_JWT" "{\"p_payment\":\"$PAY\"}" | field "['id']")
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
wait_for "the refund succeeded (Refunds write, Charges read)" "select status from public.payments where id='$REF'" "succeeded"

# ---- 3b. A card removed in Stripe (payment_method.detached): the payload's
# shape, previous_attributes.customer, is documented only by example, so
# this is the one check that proves the field is really there.
PM_M=$(sql "select coalesce(card_payment_method_id,'') from public.accounts where id='$MARIA'")
check "the summary knows which card it is" "pm_" "${PM_M:0:3}"
stripe_api post "/v1/payment_methods/$PM_M/detach" >/dev/null
wait_for "removing it in Stripe clears the summary" "select coalesce(card_last4,'')||'|'||coalesce(card_payment_method_id,'') from public.accounts where id='$MARIA'" "|"

# ---- 4. A card that saves and is then declined (Tara's real case). Not
# pm_card_chargeDeclined (4000...0002): Stripe refuses to attach issuer-
# decline cards at all. 4000...0341 attaches, then every charge fails.
KEN_JWT=$(jwt ken@fxe.test)
save_card "$KEN_JWT" "$KEN" pm_card_chargeCustomerFail >/dev/null
wait_for "the declining card saved fine" "select coalesce(card_last4,'') from public.accounts where id='$KEN'" "0341"
REG_K=$(reg "$CLINIC3" "$KEN_P" 1800)
PAY_K=$(rpc admin_charge_registration "$TARA_JWT" "{\"p_registration\":\"$REG_K\",\"p_kind\":\"clinic_fee\"}" | field "['id']")
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
# Stripe does not document 0341's decline code; any code at all is right,
# and the one it gave is printed for the record.
wait_for "the charge failed, with a decline code" "select status||' '||(coalesce(failure_code,'')<>'') from public.payments where id='$PAY_K'" "failed true"
say "        (Stripe's code: $(sql "select coalesce(failure_code,'none') from public.payments where id='$PAY_K'"))"
check "Ken's card is marked declined, so the app asks for a new one" "true" "$(sql "select (coalesce(card_decline_code,'')<>'')::text from public.accounts where id='$KEN'")"

# ---- 5. A bank demanding 3-D Secure on a charge made while the member is away.
# Attached directly (a setup would itself demand the bank's page); the
# summary is written as the webhook would. The charge must fail cleanly.
ROB_JWT=$(jwt rob@fxe.test)
rpc record_card_consent "$ROB_JWT" '{"p_app_version":"stripe rehearsal"}' >/dev/null
fn stripe-setup-intent "$ROB_JWT" '{}' >/dev/null
CUS_R=$(sql "select stripe_customer_id from public.accounts where id='$ROB'")
PM_R=$(stripe_api post "/v1/payment_methods/pm_card_authenticationRequired/attach" -d "customer=$CUS_R" | field "['id']")
stripe_api post "/v1/customers/$CUS_R" -d "invoice_settings[default_payment_method]=$PM_R" >/dev/null
sql "update public.accounts set card_brand='visa', card_last4='3184', card_added_at=now() where id='$ROB'" >/dev/null
REG_R=$(reg "$CLINIC4" "$ROB_P" 1800)
PAY_R=$(rpc admin_charge_registration "$TARA_JWT" "{\"p_registration\":\"$REG_R\",\"p_kind\":\"clinic_fee\"}" | field "['id']")
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
wait_for "an off-session charge needing the bank's page fails cleanly" "select status||' '||coalesce(failure_code,'') from public.payments where id='$PAY_R'" "failed authentication_required"

# ---- 6. A chargeback: Stripe disputes this card's charges by itself
DANA_JWT=$(jwt dana@fxe.test)
save_card "$DANA_JWT" "$DANA" pm_card_createDispute >/dev/null
wait_for "the disputing card saved" "select coalesce(card_last4,'') from public.accounts where id='$DANA'" "0259"
REG_D=$(reg "$CLINIC" "$DANA_P" 1800)
PAY_D=$(rpc admin_charge_registration "$TARA_JWT" "{\"p_registration\":\"$REG_D\",\"p_kind\":\"clinic_fee\"}" | field "['id']")
fn stripe-charge "$TARA_JWT" '{}' >/dev/null
wait_for "the dispute reached the fee (Balance read)" "select coalesce(dispute_status,'') from public.payments where id='$PAY_D'" "needs_response" 90

# ---- 7. Payouts: Tara's card on the laptop
OUT=$(fn stripe-payouts "$TARA_JWT" '{}')
check "stripe-payouts answers from the sandbox (Balance and Payouts read)" "False" "$(echo "$OUT" | field "['livemode']")"

# ---- 8. Deleting an account deletes the Stripe customer (Customers write)
U_OUT=$(curl -s "$API/auth/v1/signup" -H "apikey: $ANON" -H "Content-Type: application/json" -d "{\"email\":\"rehearsal-$RANDOM$RANDOM@stripe.test\",\"password\":\"rehearsal-$RANDOM$RANDOM\"}")
U=$(echo "$U_OUT" | field "['user']['id']"); U_JWT=$(echo "$U_OUT" | field "['access_token']")
rpc create_my_account "$U_JWT" '{"p_first_name":"Rehearsal","p_last_name":"Person","p_phone":"5550100","p_is_member":false,"p_adult_rating":3.5,"p_level_note":null}' >/dev/null
CUS_U=$(save_card "$U_JWT" "$U" pm_card_visa)
wait_for "the card is on file before deleting" "select coalesce(card_last4,'') from public.accounts where id='$U'" "4242"
OUT=$(fn delete-account "$U_JWT" '{}')
check "delete-account deleted the customer in Stripe" "deleted" "$(echo "$OUT" | field "['stripe']")"
check "Stripe agrees" "True" "$(stripe_api customers retrieve "$CUS_U" | field "['deleted']")"

say ""
say "Function server log: errors only"
grep -iE 'error|denied|permission|restricted' "$WORK/serve.log" | grep -v 'Using supabase' | head -15
if [ "$FAILED" -eq 0 ]; then say "PASS: Stripe rehearsal"; else say "FAIL: Stripe rehearsal (a missing key permission shows as 'permission' in the log above)"; fi
say "The local database now holds rehearsal rows: run supabase db reset before anything else."
exit "$FAILED"
