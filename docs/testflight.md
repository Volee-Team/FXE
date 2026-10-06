# TestFlight runbook

How a build of this repo gets onto a phone. Written 2026-09-21 for John, who
is uploading internal TestFlight builds from his own Apple Developer account
while the FXE Tennis, LLC enrollment sits in Apple's queue (decision 0014).
Everything a build needs is on `main`; nothing lives only on Alex's machine.

## Before the first build (once)

1. **Clone `main`** of `github.com/Volee-Team/FXE` and open a terminal in it.
2. **Install XcodeGen** (the `.xcodeproj` is generated, never committed):
   ```bash
   brew install xcodegen
   ```
3. **Generate the project** from `project.yml`, then open it:
   ```bash
   xcodegen generate && open FXETennis.xcodeproj
   ```
4. **Signing, in Xcode**: target `FXETennis` → Signing & Capabilities →
   tick *Automatically manage signing* and pick your Team. Xcode registers
   the bundle id `com.fxetennis.app` on your team and adds the Push
   Notifications capability that the `aps-environment` entitlement needs.
   If Xcode says the bundle id is taken, change `PRODUCT_BUNDLE_IDENTIFIER`
   in `project.yml` (all three targets share the prefix), rerun step 3, and
   tell Alex which id you used so the App Store Connect record matches.
   Do not commit a `DEVELOPMENT_TEAM`: the LLC's team replaces yours later.
5. **App Store Connect**: create the app record under your account with the
   same bundle id. Internal testers (Tara, Kat, Alex) need an App Store
   Connect user each; internal TestFlight needs no privacy URL and no review.

## Every build

1. `git pull` on `main`. The build number is `CURRENT_PROJECT_VERSION` in
   `project.yml` (`MARKETING_VERSION` is 0.1.0). Bump the build number by one,
   commit it on a branch, open a PR; CI must be green before you upload.
2. `xcodegen generate` again (the project file reflects `project.yml`).
3. In Xcode, scheme `FXETennis`, destination *Any iOS Device*, then
   **Product → Archive**. Archive builds the **Release** configuration, and
   Release is the configuration that talks to the hosted Supabase project
   (`FXETennis/Data/SupabaseClient.swift`: Debug points at `localhost`, Release
   at `amnaxvznkadkgzdxzegw.supabase.co`). A Debug build on a phone would show
   an empty app.
4. Organizer → **Distribute App → App Store Connect → Upload**. Not
   "TestFlight Internal Only": a build uploaded that way can never be added to
   External Testing (the public link) or the App Store, which build 9 needs
   (found 2026-10-06, before the first external submission).
5. In App Store Connect, add the build to the internal group. Testers get the
   TestFlight email within minutes.
6. Tag the commit and add the changelog line (launch checklist C10):
   ```bash
   git tag -a v0.1.0-tf<build> -m "TestFlight build <build>, uploaded by John"
   git push origin v0.1.0-tf<build>
   ```

## What a tester sees

Sign up with a real email (the app sends no confirmation email; decision
0011), fill the profile (name, phone, rating, member yes/no, an optional note
for Tara), sign the waiver (typed full name), then Home. Nothing charges
anyone: Stripe's sandbox keys are in (2026-09-27), but the payment switch
stays off until Alex says go (launch checklist A9), after build 5 is on
phones. Tara's account
is the one with the Manage tab; she creates it herself the same way and Alex
promotes it once (`bootstrap_first_admin`, already done on hosted).

## Rules that still apply on a phone

* **No fixtures in hosted** (CLAUDE.md): sign up as yourself, not as "Test
  Testerson". A deleted account keeps its rows as history, so a junk account
  is junk forever in Tara's Money tab.
* **Hosted is written only by `supabase db push`** from a merged `main`. A
  TestFlight upload never touches the database.
* Push notifications do not deliver yet (decision 0008: the sender waits on
  an APNs key). The permission sheet still appears; that is expected.

## When the LLC account is approved

**The bundle id cannot move.** Apple transfers an app between accounts only
if it has had at least one App Store release, and uploading a build ties the
bundle id to the account that uploaded it. `com.fxetennis.app` is therefore
John's for good unless the app is released under his name first, which the
roadmap rules out (2026-08-19: the seller is the LLC). So the LLC's app gets a
**new bundle id** (launch checklist C12, Alex decides the name), a new App
Store Connect record, and the LLC's Team in Xcode; testers install it once as
a new app and sign in with the same account, because accounts live on our
server, not on the phone. Public TestFlight and the App Store listing are the
LLC's. If the LLC is late for 2026-10-16, the fallback is external TestFlight
on John's account (checklist C11).
