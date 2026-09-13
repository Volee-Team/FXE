# 0011: No email verification in v1

**Date:** 2026-08-16 (recorded 2026-09-13) · **Status:** Active

## What was decided

A new member signs up with an email and a password and is in. No confirmation
email, no link to click. Tara's Screen 2 copy says so; Alex on 2026-08-16:
*"I'd rather just have no verification right now, just keep it simple."*

## Where it lives

- Local: `supabase/config.toml`, `[auth.email] enable_confirmations = false`.
- Hosted: Supabase dashboard → Authentication → Providers → Email →
  **Confirm email: OFF**, switched by Alex on 2026-08-16. This is a dashboard
  setting with no file behind it, which is why this record exists.

## Consequences

- Any **new** project starts with confirmation ON. The CI project, a restore
  into a fresh project, or a plan migration all need the switch flipped, or
  sign-up "hangs" the way it did on 2026-08-13 (the auth user existed, the
  session never arrived). `docs/launch-checklist.md` D0 carries the check.
- Password reset still needs email delivery (custom SMTP, launch-checklist D1);
  this decision removes verification, not email.

## Rejected

- Magic links or confirmation emails: Supabase's built-in sender is rate
  limited and lands in spam, and the club's members are known people vouched
  for by Tara. Verification buys little here and costs a hung sign-up.

## How we would know it was wrong

Sign-ups with mistyped emails that can never reset a password, or strangers
creating accounts. Both are visible in Tara's player directory; revisit then.
