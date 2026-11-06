# 0050. Members join the Waitlist after the public open (2026-11-06)

**Status:** accepted by John, 2026-11-06; built in
`supabase/migrations/20261106000003_members_waitlist_after_public_open.sql`.
Supersedes the timing in decision 0045.

## Her words

Tara, by text, 2026-11-06 2:30 PM, two and a half hours after non-member
registration opened:

> What should be happening: members signing up after Friday noon should be on
> waitlist like rest of nonmembers. Automatically in between Thur 8am-Friday
> noon.
>
> What is happening: members are automatically in even after Friday noon

Then: *"Lmk if this is an update or can be fixed ... Like today"*.

Decision 0045 had built her 10-30 text (*"members are never on the waitlist
they're in automatically"*) as "at any time". Her newer text is the source and
wins (CLAUDE.md, "Which source wins"): the 10-30 text meant inside the member
window.

## The rule

| Who | When | Result |
|---|---|---|
| Member | member open (Thursday 8am) to public open (Friday noon), room left | You're In! |
| Member | same window, clinic full | Waitlist |
| Member | from the public open | Waitlist |
| Non-member | before the public open | Rejected |
| Non-member | from the public open | Waitlist |

This is the rule as it stood before 2026-10-31. Tara still puts anyone in with
Move In (decision 0047).

## What changed

One branch of `register_for_clinic`: the member case stops at
`public_opens_at` again. Server only; the 1.0.1 and 1.0.2 apps and the members'
site show whatever status the server returns, so no app update. Pushed to
hosted 2026-11-06 about 3 PM, and the hosted function's hash matched local.

## Already in

Five member sign-ups landed in You're In! between noon and the fix, all in
Sunday 11-08 Coed "105" clinics (Whitney Axley-Andrews in both the 4:30 and the
6:00; Emily Blair, Sarah Cooper, Jessica Stone in the 4:30). They were left in;
whether to move them to the Waitlist is Tara's call.

## Tests

`tests/sql/registration_windows.sql`: `late_member_goes_to_pool` (was
`late_member_with_room_gets_in`). `pricing_and_revenue.sql`: Maria, a member
registering after the public open, is now on the Waitlist and owes nothing, so
the summary's expected total is $74 (`summary_expected_7400`, was $92).
