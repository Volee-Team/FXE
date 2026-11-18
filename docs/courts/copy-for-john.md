# Court reservations: new wording for John to sign off (2026-11-16)

John, 2026-11-16: *"I will sign off on new wording. Every permission alex and
tara have, I should have."* (hard rule 13). Everything new that the courts
branch puts in front of a person. Mark each row Keep, or write what it should
say instead. Only Tara and admins see the laptop rows; the push is the only
one a member sees.

Two of these are not in `docs/copy-approved.txt`, because the copy gate does
not read them: the push is built in SQL, and the laptop's confirm boxes and
error messages are inside JavaScript lists and templates. Those rows are
marked "not gated".

## The push a member gets (notification 16)

| Where it shows | Text | Keep / Change |
|---|---|---|
| A member's lock screen and notification list, when Tara cancels their court booking before it starts (not gated) | `Your court booking on Thu, Nov 19 at 8:00 AM was canceled by FXE.` John approved it without the date (`on Thu at 8:00 AM`). The date was added because Tara can cancel more than a week out, where "Thu" alone could mean two different days. | |

## Tara's laptop: the Courts tab

| Where it shows | Text | Keep / Change |
|---|---|---|
| Top of the tab, while member booking is off | `Off for members. Court booking is in testing: only you, and the testers in Court rules on the TestFlight app, can book.` | |
| Top of the tab, once member booking is on | `Members can book courts.` | |
| Buttons above the grid | `Previous day` / `Book a court` / `Block courts` | |
| A day with no hours set | `No court hours for this day.` | |
| The list under the grid, on an empty day | `Nothing on the courts this day.` | |
| Each booking's button | `Cancel booking` | |
| Each block's button | `Remove block` | |
| Red card at the top when a clinic or block overlaps a booking | `Check these bookings`, then per row: `{name}, Court {n}, {time}, overlaps {the clinic X / your block (reason) / Y's booking}. Call them or cancel the booking.` (not gated) | |
| Confirm before cancelling a booking | `Cancel {name}'s booking ({when})? The app tells them it was canceled.` (not gated) | |
| Confirm before removing a block | `Remove the block on {when}? Members can book that time again.` (not gated) | |

### Book a court (for someone)

| Where it shows | Text | Keep / Change |
|---|---|---|
| Player search label | `Who is it for?` | |
| Before anyone is picked | `Nobody chosen yet.` | |
| Each search result's button, for screen readers | `Choose {name}` | |
| Tara's private note field | `Note (only you see this)` | |
| Booking with nobody chosen | `Choose who the court is for.` (not gated) | |

### Block courts

| Where it shows | Text | Keep / Change |
|---|---|---|
| Reason field hint | `Rain, resurfacing, a private lesson` | |
| Under the form | `Nobody can book a blocked court. Bookings already made stay until you cancel them.` | |
| After saving a block that has bookings under it | `Blocked. These bookings are under it.` then `Nobody was canceled. Call them, or cancel a booking here.` | |

### Court rules

| Where it shows | Text | Keep / Change |
|---|---|---|
| The members switch, replaced by text | `Off for members. Court booking is in testing with the testers below.` | |
| Rule labels | `Book up to (days ahead)` / `A new day opens at` / `Lengths (minutes, comma between)` / `Start every (minutes)` / `Bookings a day, per person` / `Upcoming at once, per person` / `Players per court (for clinics)` | |
| Testers heading | `Can book while courts are off (TestFlight)` | |
| Testers explanation | `Members on this list can book from the TestFlight app before court booking is on for everyone. Added and removed right away.` | |
| Empty testers list | `No testers yet.` | |
| Tester search button | `Add a tester` | |
| Screen-reader labels on Add / Remove | `Add {name} as a tester` / `Remove {name} as a tester` | |
| A tester who is not a member | `Not a member: can book only if an administrator.` | |

### Error messages (not gated)

| When | Text | Keep / Change |
|---|---|---|
| The court is already taken | `That court is taken then. Pick another court or time.` | |
| A closed or unknown court | `That court is closed or doesn't exist.` | |
| The player's account is gone | `Couldn't find that player's account.` | |
| End before start | `The end has to be after the start.` | |
| A block with no reason or bad times | `A block needs a reason, and its end after its start.` | |
| Cancelling twice | `That booking is already canceled.` | |
| Removing a block twice | `That block is already removed.` | |
| Hours, closing before opening | `Closing has to be after opening.` | |
| An unknown rule | `One of the rules isn't one the server knows.` | |
| A bad number in the rules | `One of the rules isn't valid. Check the numbers.` | |
| No day picked | `Pick a day.` | |
| The members switch from the laptop | `Court booking for members can't be turned on from here yet.` | |
