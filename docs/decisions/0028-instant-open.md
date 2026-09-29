# 0028: Instant open: the last good answer kept on the phone, per person

**Date:** 2026-09-28 · **Status:** Active · **Source:** Alex's "make it even
MORE AMAZING ... truly polished" (2026-09-28); the ideas list on the build 5
demo page ("Instant open")

## What we chose

1. **The app opens on what it last knew.** After every successful load it
   keeps a snapshot on the phone (`FXETennis/Data/Snapshot.swift`): who the
   person is (their account, their player, the waiver and card gates) and the
   clinic list with their own registrations. At launch, if the session stored
   on this phone belongs to the person the snapshot was saved for, Home shows
   it at once while the real load runs; the fresh answer replaces it, usually
   within a second. A list screen opening for the first time does the same.
2. **With no signal, the snapshot stays on screen with the connection line**
   ("Couldn't reach the server. Check your connection.") on Home, Clinics and
   My Clinics, instead of the Try again screen. This extends decision 0020 §1
   ("a failure keeps the last known identity") across launches.
3. **The server stays the truth.** Nothing is written from a snapshot: every
   Register, Cancel, Accept and Decline goes to the server as before, and a
   launch whose session the server has ended still signs out.
4. **Whose it is.** A snapshot is filed under the auth user id and read only
   for the session stored on this phone. Sign out, a session ended by the
   server, an account with no profile row, and account deletion all remove
   every snapshot. UI tests remove them at launch too, so a run never sees an
   earlier run's database.
5. **What is in it** is only what the person can already see: their own rows
   and the public schedule from `clinics_public`. None of the nine hidden facts
   ever reaches the phone, so none is in it. A clinic that has ended since the
   snapshot was saved is not shown again.
6. **Where.** Application Support, excluded from backups (a cache has no
   business in iCloud), written atomically with complete-until-first-unlock
   protection. A file that no longer decodes is treated as no snapshot.

## Rejected

- **URLCache / HTTP caching.** Responses are keyed by URL, and the same URL
  answers differently per signed-in person (RLS), so an HTTP cache on a shared
  phone is exactly the leak item 4 prevents.
- **UserDefaults.** Backed up by default, not meant for a few KB of records,
  and no per-file protection class.
- **Caching the clinic list but not the identity.** Launch would still wait
  on the profile load (the account, the players and three gates) before Home
  rendered, which is most of the wait.
- **Showing the snapshot with no marker when offline.** A member deciding
  whether to drive to the club needs to know the screen may be old; the
  connection line already exists and is used everywhere else.

## How we would know this was wrong

A member reports seeing a status that Tara had already changed while their
phone had signal (the refresh should replace the snapshot within a second),
or anyone ever sees another person's clinics on a shared phone. The unit
tests pin the per-person rule, the ended-clinic rule, the undecodable file
and that saving one half never wipes the other; each was shown red.
