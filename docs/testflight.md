# TestFlight runbook

How a build of this repo gets onto a phone. Written 2026-09-21 for John, who
uploads TestFlight builds from his own Apple Developer account while the FXE
Tennis, LLC enrollment sits in Apple's queue (decision 0014; checklist C1).
Everything a build needs is on `main`; nothing lives only on Alex's machine.

**The next upload is build 10, the tag `v0.1.0-rc10`** (checklist C8), made
when the `build-10` branch merges (decision 0040 merged in PR #93). It goes up as **App Store Connect**,
not TestFlight Internal Only, and then to External Testing (checklist C11):
see "External Testing" below. Archive the tag, not `main`, so John gets
exactly the build that was tested whatever lands on `main` afterwards.

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

1. `git fetch --tags && git checkout v0.1.0-rc<build>`, the tag Alex names
   (for build 10, `v0.1.0-rc10`). The build number is
   `CURRENT_PROJECT_VERSION` in `project.yml` (`MARKETING_VERSION` is 0.1.0);
   the model bumps it in the PR that makes the tag, so the tag already
   carries the right number and CI was green on it.
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
   git tag -a v0.1.0-tf<build> -m "TestFlight build <build>, uploaded by John"
   git push origin v0.1.0-tf<build>
   ```

## External Testing (checklist C11)

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
for Tara), sign the waiver (typed full name), then Home. Nothing charges
anyone: the payment switch stays off (launch checklist A9) until Apple has
approved the external build (C11) and the live keys and their rehearsal are
done (A10, A13), and then only when Alex says go. Tara's account
is the one with the Manage tab; she creates it herself the same way and Alex
promotes it once (`bootstrap_first_admin`, already done on hosted).

## Rules that still apply on a phone

* **No fixtures in hosted** (CLAUDE.md): sign up as yourself, not as "Test
  Testerson". A deleted account keeps its rows as history, so a junk account
  is junk forever in Tara's Money tab.
* **Hosted is written only by `supabase db push`** from a merged `main`. A
  TestFlight upload never touches the database.
* Push is configured on hosted with John's APNs key (checklist C3), so a
  TestFlight build can receive it; the first push seen on a real lock screen
  is C3's row.

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
LLC's. Until then, members install through external TestFlight on John's
account (checklist C11).
