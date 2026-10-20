# 0042. Release to the App Store now, on John's account; transfer to the LLC later (2026-10-19)

**Status:** accepted. Alex, after a call with Tara, Kat, John and Wayne on
2026-10-19: *"we're gonna submit it for a release tonight as soon as possible
just under John's account and then we can switch it over later"*.

**Supersedes:** the 2026-08-19 call that the App Store account is the LLC
from the start (CLAUDE.md changelog, 2026-08-19), and C12's plan of a new
bundle id for the LLC's app.

## Why

- The LLC's developer account is still not approved (C1, `docs/live-facts.md`),
  and the launch party is 2026-11-06. Waiting on Apple's enrollment queue puts
  the release at risk; John's account can submit tonight.
- `com.fxetennis.app` already lives on John's team (every TestFlight build so
  far). Apple's App Transfer moves an app between accounts **only once it has
  had an App Store release**, which is exactly what this creates. So the
  release does not lock the app to John: it is what makes the move possible,
  and the bundle id, the listing, ratings and installed copies carry over.
  The C12 plan (a new id, every tester reinstalling) is no longer needed.
- Push already signs with John's key on John's team (C3), so nothing on the
  server changes tonight.

## What it costs, written down so nobody is surprised

- **The seller name on the App Store page is John's legal name** (an
  Individual account), not "FXE Tennis, LLC", until the transfer. Copyright
  on the listing can still read FXE Tennis, LLC.
- **At the transfer, push needs the LLC's APNs key**: the key belongs to the
  team, so after the move `APNS_KEY_ID`, `APNS_TEAM_ID` and `APNS_PRIVATE_KEY`
  on hosted are replaced with the LLC's. Nothing else on the server names the
  team.
- The transfer needs both accounts in good standing and the LLC's agreements
  signed; it takes a few days and Apple does not review it.

## Rejected

- **Wait for the LLC account.** Unknown date; the party is fixed.
- **A new bundle id under the LLC later** (old C12). Only needed if the app
  could not be transferred; a released app can be.

## How we would know this was wrong

Apple refuses the transfer, or the listing's seller name costs Tara trust with
members before the move. Either way the fallback is the old C12 path: a new
id on the LLC's team and testers reinstall (accounts and cards live on our
server and carry over).
