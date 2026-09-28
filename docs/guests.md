# Guests: a member brings a friend

Status: **designed, not built** (2026-09-28). It moves money and has a legal
edge, so it waits on two answers from Tara: question 93 (the sentence that
tells the member they will be charged) and question 95 (the waiver).

## What Tara asked for

Question 72, answered 2026-09-28 (decision 0024), verbatim:

> "The guest always is charged Nonmember price, correct. If in the app the
> player can click a button that says “imvite a friend” (and they can send the
> app to them or ask me to write their friends name in.. that’s perfect.) and
> notify them they (the person inviting the guest) will be charged for their
> guest. Idk if that makes sense"

And on 2026-09-22 (decision 0016): *"these people “should” have the app in
order to come. But sometimes won’t and that’s ok but the person inviting them
will get charged."*

So there are two paths behind one **Invite a friend** button:

1. **Send the app.** The friend installs it and signs up like anyone else: a
   non-member with their own card, their own waiver, their own sign-ups. No
   billing change at all. This is the path Tara prefers ("should have the app").
2. **Ask Tara to write the friend in.** For the friend who will not install
   it. The member asks from a clinic they are in; Tara adds the guest; the
   **member's** card pays the guest's fee at the **non-member** price.

## How path 2 fits the schema we already have

The data model already has the right shape: a `players` row belongs to an
`accounts` row (`players.account_id`), an account can own more than one player
(the future parent-and-children case), and every fee is charged to the
account's card. A guest is therefore **a player owned by the member's
account**, marked as a guest:

| Piece | What it is |
|---|---|
| `players.is_guest` (new, default false) | A player row that is a member's guest: owned by the member's account, `is_member` false, no sign-in of its own |
| Price | Nothing new: the registration snapshots the non-member price because the guest is not a member (decision 0002) |
| Who pays | Nothing new: `admin_charge_clinic` charges the account that owns the player, which is the member's |
| The request | A row like a late request (`guest_requests`: clinic, member, guest's first and last name, pending / approved / declined), shown in Tara's Action Needed |
| Tara's answer | Approve creates (or reuses) the guest player under the member's account and places them in the clinic through `place_player`, so capacity never blocks her (decision 4); Decline sends the member a plain "No room" style answer (her words, like the late request's) |
| Tara adding one herself | The laptop's Add player gains "a guest of…": pick the member, type the guest's name. The same RPC as her approval |

## What must hold (each becomes a probe check before anything ships)

- A guest's name is never shown to any other player (hard rule 1: it is
  another player's name). Only Tara and the member who brought them see it.
- The member cannot make themselves a guest, cannot make a guest a member,
  and cannot move a guest to another account (hard rule 8: `players.account_id`
  already decides who owns a person, and stays unwritable).
- The guest's fee is charged once, at the non-member price, to the member's
  card, and a declined card blocks the member exactly as it blocks their own
  sign-ups (question 78).
- A guest has no device, so notifications about the guest's spot must not
  arrive as if they were the member's own spot. Today every producer notifies
  the owning account; for a guest player they must send nothing, and the
  member gets one line when Tara approves (question 93's words).
- The board report counts a guest as a non-member who attended.
- Deleting the member's account removes the guest's name with the member's
  (the deletion scrub already covers every player of the account).

## What waits on Tara

- **Question 93**, the sentence the member sees: that they will be charged the
  non-member price for their guest. Her own phrasing was "they (the person
  inviting the guest) will be charged for their guest"; the app does not
  invent a sentence with a promise in it (hard rule 13).
- **Question 95, the waiver.** Every player signs her waiver in the app before
  they can register (decision 0013 §4). A guest who never installs the app
  never signs it. Does the member sign for their guest, does the guest sign a
  paper waiver at the club, or is a guest who has not signed not allowed on
  court? This is the club's liability, not a detail.
- Path 1's button needs the app's install link (checklist I6): until it exists
  the shared link would open "Not available yet."

## Rejected

- **A guest with no player row** (a name typed on a registration): it would
  need a second, parallel path through pricing, charging, the roster, the
  board report and deletion. A player owned by the member's account reuses
  every one of them.
- **Billing the guest directly**: they have no card on file and no account;
  Tara's rule is that the member pays.
- **Letting the member add a guest without Tara**: she makes every placement
  decision (the product rule at the top of `CLAUDE.md`).
