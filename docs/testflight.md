# TestFlight runbook

How a build of this repo gets onto a phone. Written 2026-09-21 for John. Since 2026-11-11 the app is on Volee LLC's
developer account (team FBJXDTHTN4, C12) and ships to the App Store; the
latest upload is 1.0.3 build 18 (tag `v1.0.3-18`). TestFlight for testers is
C8 (LATER). Everything a build needs is on `main`; nothing lives only on
Alex's machine. Archive the tag, not `main`, so John gets exactly the build
that was tested whatever lands on `main` afterwards.

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

1. `git fetch --tags && git checkout v<version>[-<build>]`, the tag the model
   names (latest `v1.0.3-18`). The version is `MARKETING_VERSION` and the
   build number `CURRENT_PROJECT_VERSION` in `project.yml`; the model bumps
   them in the PR that makes the tag, so the tag already carries the right
   number and CI was green on it.
2. `xcodegen generate` again (the project file reflects `project.yml`).
3. In Xcode, scheme `FXETennis`, destination *Any iOS Device*, then
   **Product → Archive**. Archive builds the **Release** configuration, and
   Release is the configuration that talks to the hosted Supabase project
   (`FXETennis/Data/SupabaseClient.swift`: Debug points at `localhost`, Release
   at `amnaxvznkadkgzdxzegw.supabase.co`). A Debug build on a phone would show
   an empty app.
4. Organizer → **Distribute App → App Store Connect → Upload**. Not
   "TestFlight Internal Only": a build uploaded that way can never be added to
   External Testing (the public link) or the App Store (found 2026-10-06,
   before the first external submission).
5. Wait for Processing in App Store Connect. Add the build to the internal
   group (Tara, Kat and Alex get the TestFlight email within minutes) and to
   the external group (below).
6. Tag the commit and add the changelog line (launch checklist C10):
   ```bash
   git tag -a v<version>-<build> -m "<version> build <build>"
   git push origin v<version>-<build>
   ```

## External Testing (checklist C11)

Not used: members install from the App Store (C11 LATER). Kept in case
TestFlight is wanted again (C8).

The public link is how members install the app before the LLC's App Store
listing exists. It needs Apple's beta review, which usually takes 1 to 2
days.

1. Before John submits, Alex makes the App Review account (checklist C13;
   steps in `docs/for-alex.md` §4a) and sends John its email and password.
2. appstoreconnect.apple.com → Apps → FXE Tennis → **TestFlight** →
   External Testing → **+** → a group named `FXE Members` (once; later
   builds go into the same group).
3. Add the build. Fill in **Test Information**: What to Test, Beta App
   Description, feedback email, the sign-in for Apple's reviewer, the review
   notes and John's contact. The words are in `docs/for-alex.md` §4a.
4. **Submit for Review**.
5. Once approved: the group → **Public Link** → **Enable**, and send Alex
   the link. It becomes the QR code's target (checklist I6). Nobody gets it
   until the soft launch (checklist G7).

## What a tester sees

Sign up with a real email (the app sends no confirmation email; decision
0011), fill the profile (name, phone, rating, member yes/no, an optional note
for Tara), sign the waiver (typed full name), then Home. Payments are
live (A9, 2026-10-14): Register and Accept ask for a card, and a real card is
charged after a clinic Tara charges. Tara's account
is the one with the Manage tab; she creates it herself the same way and Alex
promotes it once (`bootstrap_first_admin`, already done on hosted).

## Rules that still apply on a phone

* **No fixtures in hosted** (CLAUDE.md): sign up as yourself, not as "Test
  Testerson". A deleted account keeps its rows as history, so a junk account
  is junk forever in Tara's Money tab.
* **Hosted is written only by `supabase db push`** from a merged `main`. A
  TestFlight upload never touches the database.
* Push is configured on hosted with Volee LLC's APNs key `42D24JXB54`
  (C2, 2026-11-11), so any build signed by the LLC receives it.

## After the transfer (2026-11-11)

The app was released on John's account first (C14, 1.0.0), then moved by
App Transfer to Volee LLC with its bundle id `com.fxetennis.app` (C12).
Builds are signed by team FBJXDTHTN4 (C2); testers reinstall nothing.
