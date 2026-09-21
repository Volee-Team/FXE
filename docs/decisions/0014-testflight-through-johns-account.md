# 0014: Internal TestFlight through John's account, as a stopgap

**Date:** 2026-09-21 · **Status:** Active until the LLC enrollment is approved · **Extends:** the 2026-08-19 call that the App Store account is FXE Tennis, LLC from the start

## What was said

Kat, in the group thread with Tara and Alex, 2026-09-21: *"is it possible to
get the latest version into TestFlight?"* Alex: *"not yet since LLC account
isn't approved, apple taking 3+ weeks even after calling and emailing"*, then
*"actually we could have john switch it to his acct then he could do an
internal TestFlight version"*. Kat: *"See if that works. Pls."* Alex to me:
*"john will use his dev account and publish it for them! so make sure all
code is always being pushed."*

## What this decides

1. **Internal TestFlight builds come from John's Apple Developer account**
   until FXE Tennis, LLC is enrolled. Internal testing needs no privacy URL,
   no review and shows no seller name, so the 2026-08-19 objection (an
   Individual account shows John as the seller) does not apply to it.
2. **`main` is the only source of a build.** John clones, generates the
   project with XcodeGen, archives Release, uploads. Nothing on Alex's
   machine is needed: `docs/testflight.md` is the runbook.
3. **No `DEVELOPMENT_TEAM` is committed.** Xcode's automatic signing on
   John's Mac supplies his team; the LLC's team replaces it later without a
   code change.
4. **The App Store listing and public TestFlight stay the LLC's.** This is a
   stopgap for Kat's and Tara's testing, not a change to the 08-19 call.

## Rejected

- **Waiting for Apple.** Three weeks and counting; Kat and Tara have a
  Tuesday call and nothing to hold.
- **Sideloading from Alex's Mac.** Needs a cable and the tester's device
  registered; not shareable.

## How we would know we were wrong

If a build uploaded under John's account cannot be moved to the LLC's record
later (App Store Connect supports app transfer between accounts, with the
same bundle id; if that fails, a fresh record with the same id is the
fallback and testers reinstall once).
