# 0038: Every time in the app is Charlotte time

**Date:** 2026-10-04 · **Status:** Active · **Source:** Tara, relayed by Alex
2026-10-04, after a tester in Wisconsin saw every clinic an hour early: *"The
times should not convert to where the phone is. It always needs to be 9
o'clock ... Or whatever time it's at Charlotte time"*.

## What we chose

The app runs in America/New_York whatever the phone's own zone is.
`ClubTime.apply()` (`FXETennis/Models/ServiceWeek.swift`) runs first in the
app's `init`: it sets the process's `TZ` to Charlotte, resets the system zone
and sets `NSTimeZone.default`, and the root view also sets SwiftUI's
`\.timeZone`. One switch, so no screen can be missed. Charlotte's zone, not a
fixed offset, so daylight saving moves with the clubs' clocks.

Unchanged and correct: Remind me (its triggers name UTC), Add to Calendar and
the subscribed calendar (absolute moments; a calendar on a phone in
Wisconsin shows the true local moment, which is what a calendar is for).

## Rejected

- **Setting a time zone on each formatter.** About a dozen files format
  dates; the next screen would forget.
- **`NSTimeZone.default` alone.** The first version. Calendar and
  DateFormatter followed it, but `.formatted()`, which most screens use,
  reads the system zone and did not: a simulator launched in Central time
  still showed 3:59 PM for a 4:59 PM clinic. `TZ` is what put that simulator
  in Central, so `TZ` is what moves it back.
- **Showing both zones ("9:00 AM ET").** Nobody asked; every member is local.

## How we would know we were wrong

A member travelling sees a time that is not the clinic's Charlotte time.
Verified 2026-10-04 on iOS 26.2 launched with `TZ=America/Chicago`: Home and
Clinics read 4:59 PM for the 4:59 PM clinic (3:59 PM before the fix).
`ClubTimeTests` (red on three checks with `apply()` emptied). Not yet seen on
a real phone outside Eastern time.
