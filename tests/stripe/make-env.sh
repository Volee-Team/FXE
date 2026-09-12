#!/bin/bash
# Print the env for `supabase functions serve --env-file` when the functions
# should talk to stripe-mock instead of Stripe.
#
# The secret key is made up here, every time, and never written to the repo:
# GitHub's push protection (correctly) refuses any sk_test_-shaped string, and
# stripe-mock accepts any sk_test_ followed by letters and digits. The webhook
# secret only has to match what tests/stripe/run.sh signs with (its default).
#
#   bash tests/stripe/make-env.sh > /tmp/mock.env
#   bash tests/stripe/make-env.sh host.docker.internal > /tmp/mock.env   # Mac, binary on the host
#
# $1 is the host the edge runtime reaches the mock at: `stripe-mock` (the
# container on the Supabase network, what CI does) or `host.docker.internal`.
HOST=${1:-stripe-mock}
KEY="sk_test_$(LC_ALL=C tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 24)"
cat <<ENV
STRIPE_SECRET_KEY=$KEY
STRIPE_WEBHOOK_SECRET=${STRIPE_WEBHOOK_SECRET:-whsec_stripe_mock_only}
STRIPE_PUBLISHABLE_KEY=pk_test_stripe_mock_only
STRIPE_API_HOST=$HOST
STRIPE_API_PORT=12111
ENV
