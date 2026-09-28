# 0023: The first open: answering from the lock screen, the calendar, reminders, and text anyone can read

**Date:** 2026-09-28 · **Status:** Active · **Source:** Alex, 2026-09-27 (*"PUT THIS IN MEMOERY - WE WANT EXTRA FEATURES NOT JUST MVP"*; *"do wow things ... make the app as POLISHED as possibly"*), branches `player-wow` and `a11y-audit`. Supersedes the mechanism of decision 0020 item 5 (Larger Text), not its rule.

## What we chose

1. **Accept and Decline on the invitation itself.** The app registers the
   `INVITATION` notification category (`FXETennis/App/InvitationActions.swift`);
   both buttons need the phone unlocked, Decline is marked destructive, and
   neither opens the app. The answer goes through the same
   `respond_to_invitation` as the clinic page, under a background task. Only
   those two buttons answer (hard rule 2): a tap on the banner opens the clinic
   and answers nothing. If the invitation changed first, Tara's line "Sorry,
   someone beat you to the punch. Here's the latest!" arrives and opens the
   clinic; with no signal, the connection line; on a shared phone, for someone
   else's invitation, nothing.
2. **Add to Calendar** under You're In!, before the clinic starts: Apple's own
   editor with the clinic's name and times in New York time, and **nothing in
   location, URL or notes** (hard rule 1: the calendar is player-facing). No
   calendar permission is asked or needed (iOS 17 and later).
3. **Remind me** where registration has not opened for this player: a
   notification on the phone at that player's own opening moment (members at
   the member open, everyone else at the public one), in Tara's words
   ("Registration is LIVE!! Hope to see you on the court"). Local, not
   server-sent, so it works before push is live. Moved or dropped whenever a
   list loads, and cleared at sign-out.
4. **Feel:** a success haptic when a registration lands, a warning when it is
   refused; the status chip changes over 0.35 s (a crossfade with Reduce
   Motion), never delaying a tap.
5. **Text follows Larger Text live.** Every style is applied through
   `.brandFont(_:)`, which reads the size from the environment; a `Font` made
   from a `UIFont` was fixed at the size it was made with. Apple's
   accessibility audit now runs as a UI test on every player screen and Tara's
   main ones; each exception it accepts is written in the test with its
   measured evidence (glass bar buttons at 16.4:1 from pixels, the logo's fixed
   size).
6. **The clock is readable on navy.** Light mode is locked by
   `UIUserInterfaceStyle` in Info.plist instead of
   `.preferredColorScheme(.light)`, which pinned the status bar to black on
   every navy header; screens with a navy top ask for light status text. A UI
   test reads the clock's pixels.
7. **The guide, applied where the system was still showing through:** page
   titles in the navy serif (Kat's guide: serif for what names, navy for
   headlines, no third family), outlined tab icons, navy (not green) for
   buttons inside a screen so a sheet's Cancel and Save pass contrast, and the
   clinic page's name drawn once, not twice.
8. **Return moves through the forms**: email to password to sign in; first
   name to last name to phone.

## Rejected

- **A server-sent "registration is open" push.** Needs a scheduler and
  Tara's say on which window and which recipients (the 2026-08-02 changelog);
  a reminder the player asks for needs neither.
- **Opening the app from Accept.** iOS cannot bring an app forward from a
  background action, and a lock-screen answer that opens the app is a worse
  version of a tap on the banner.
- **Dropping the audit's findings as noise.** Each one was either fixed or
  measured; an exception with no evidence is not allowed in the test.

## How we would know this was wrong

A player accepts from the lock screen and the app disagrees about their spot,
a calendar entry shows anything about where FXE is, a reminder goes off for a
clinic that is not opening, or someone with large text reports a screen they
cannot read.
