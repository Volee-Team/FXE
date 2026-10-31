# 0045. Members are in whenever there is room (2026-10-31)

**Status:** accepted by John, 2026-10-31; built in
`supabase/migrations/20261031000001_members_in_while_room.sql`.

## Her words

Tara, by text, 2026-10-30: *"And remember members are never on the waitlist
they're in automatically."* John relayed it on 2026-10-31 as the answer to
question 131 (`docs/questions-for-tara.md`), which had asked whether a member
signing up after the first 24 hours, with room left, is in or on the
Waitlist. Her text is the newer source and wins over her 10-15 email
(decision 0041), which said members after the first 24 hours join the
Waitlist for a 105.

## The rule

| Who | When | Result |
|---|---|---|
| Member | from the member open (Thursday 8am) to the close, room left | You're In! |
| Member | clinic full | Waitlist |
| Non-member | before the public open | Rejected |
| Non-member | from the public open | Waitlist |

It applies to every clinic, 105 or not. Before this, a member was in
automatically only between the member open and the public open, and went to
the Waitlist after it.

## What changed

One branch of `register_for_clinic`: the member case no longer stops at
`public_opens_at`. Capacity is still decided under the clinic row's
`FOR UPDATE` lock, so two members racing for the last spot cannot both get it
(`tests/sql/capacity_race.sh`). Nothing about non-members, the gender guard
(decision 0044), the card, the waiver, or back-to-back 105s changed.

## Still open

**Question 132:** a member when the clinic is full. Built default: the
Waitlist; the cap holds for everyone and only Tara puts someone over it.

## Tests

`tests/sql/registration_windows.sql`: `late_member_with_room_gets_in`
(was `late_member_goes_to_pool`) and the new
`late_member_when_full_goes_to_pool`. Each went red on its own: the first
against the old function, the second with the cap removed for late members.
Two older probes had a member registering late and expecting the Waitlist for
reasons unrelated to this rule: `notification_copy.sql` now fills its one-spot
clinic first, and `pricing_and_revenue.sql` counts Maria's $18 on the hour
clinic (summary $90, was $72).
