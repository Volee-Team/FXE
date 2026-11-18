# Juniors phase 1 on the websites: new wording for John to sign off (2026-11-18)

John, 2026-11-16: *"I will sign off on new wording."* (hard rule 13). This is
every word the juniors phase 1 web branch puts in front of a person. The
members' site rows are what a parent reads. The laptop rows are what Tara
reads, and only Tara and administrators see them. Mark each row Keep, or
write what it should say instead.

**Not here, because they are not new:** words the members' site already
uses and these screens reuse as they are. They are Save, Cancel, Edit
details, First Name, Last Name, Agree and sign, the placeholder "First and
last name", "The waiver was updated. Read it again and sign.", "Type your
first and last name.", "Couldn't find your account. Sign out and sign in
again.", "Couldn't load the waiver.", "Couldn't save your signature." and
"That didn't save. Check your connection and try again.". On the laptop the
reused words are Show archived, Note, "Someone already handled that one." and
"That just changed. Here's the latest.", plus phase 0's "Parent's phone
(name)".

**The copy gate** (`docs/copy-approved.txt`) catches some of these, but not
the ones built inside a template with a name in them. Those rows are marked
"not gated", so this file is the full list.

`{first}` and `{name}` stand for a child's or a parent's name; `{n}` is a
number; `{program}` is one of Tara's program names.

## Members' site: what a parent reads

### Profile

| Where it shows | Text | Keep / Change |
|---|---|---|
| A new button under My Clinics | `My Children` | |

### My Children

| Where it shows | Text | Keep / Change |
|---|---|---|
| Title | `My Children` | |
| No children yet | `No children added yet` | |
| The button under the list | `Add a Child` (spec 01's words) | |
| Under each child's name (not gated) | `Age {n}`, then `, Waiver signed` or `, Waiver not signed` once a junior waiver exists | |

### Add a Child / Edit details

| Where it shows | Text | Keep / Change |
|---|---|---|
| Title | `Add a Child` (adding) or `Edit details` (editing) | |
| The third field | `Birthday` | |
| A name left empty | `Add the child's first and last name.` | |
| No birthday | `Add the child's birthday.` | |

### A child's page

| Where it shows | Text | Keep / Change |
|---|---|---|
| The two lines under the name | `Birthday` / `Age` | |
| Section headings | `WAIVER` / `PROGRAMS` | |
| Waiver signed | `Signed` | |
| Waiver not signed, and its button | `Not signed yet` / `Sign the waiver` | |
| No junior waiver published yet (true until Tara's form is in) | `The waiver isn't available yet.` | |
| A program that needs approval, not asked yet | `Request Approval` | |
| After asking | `Approval requested` | |
| Tara's answer | `Approved` / `Declined` | |
| No programs at all | `No programs yet` | |
| The remove button (not gated) | `Remove {first}` | |
| Its confirmation (not gated) | `Remove {first} from your account?` then the buttons `Remove` / `Keep` | |

### The parent/guardian waiver, signed for one child

The adult waiver's checkbox sentence is Tara's own, from the last page of
her adult form. **Her parent/guardian form may have its own sentence.** If
it does, this row takes hers.

| Where it shows | Text | Keep / Change |
|---|---|---|
| Title | `Waiver` | |
| The checkbox (not gated) | `I have read and agree to this waiver for {first} {last}.` | |
| The name field | `Your full legal name` | |
| No junior waiver published | `The waiver isn't available yet.` and a `Back` button | |

### Errors a parent can see

| When | Text | Keep / Change |
|---|---|---|
| The 11th child | `An account can have up to 10 children.` | |
| The same name and birthday twice | `That child is already on your account.` | |
| A name or birthday change after Tara decided a program, or after the waiver is signed | `Only Tara can change this child's name or birthday now.` | |
| Removing a child with a clinic coming up | `This child has a clinic coming up, so they can't be removed yet.` | |
| The server finds no name | `Add the child's first and last name.` | |
| A birthday in the future | `Enter a birthday that isn't in the future.` | |
| Not their child, or a removed one | `Couldn't find that child.` | |
| Asking after Tara declined | `Tara declined this request.` | |
| Asking for a program that needs no approval (a stale page) | `This program doesn't need approval.` | |
| A program Tara archived meanwhile | `That program isn't offered now.` | |
| The list doesn't load | `Couldn't load your children.` | |
| The request doesn't go | `Couldn't send the request.` | |
| The removal doesn't go | `Couldn't remove this child.` | |

## Tara's laptop

### The Juniors tab

| Where it shows | Text | Keep / Change |
|---|---|---|
| The tab | `Juniors` | |
| Card headings | `Program approvals` / `Approve a child` / `Programs` | |
| Nothing waiting | `No requests waiting.` | |
| A request (not gated) | `{child} (age {n}) asked for {program}`, then `Parent: {name} {phone}, asked {Nov 18}`, with `Approve` / `Decline` | |
| Below the requests | `Decided` | |
| A decided row (not gated) | `{child} {program}`, then `Approved by you` (she approved the child herself), `Approved` (she approved a parent's request) or `Declined`, `, {Nov 18}. Parent: {name}`. A declined row has `Approve` | |
| Approve a child: search box | `Search children by name` | |
| Approve a child: results | `{child} (age {n})` with `Approve`, `No child by that name.`, then `Approved.` | |
| Approve a child: no program picked | `Choose a program.` | |
| Programs: the line at the top | `Parents see each program's name, ages and description.` | |
| Programs: the box beside it | `Include archived` (not "Show archived": that is the Templates box's, and two boxes with one name would read the same to a screen reader) | |
| Programs: the button | `New program` | |
| Each program (not gated) | `{program}`, `(archived)`, then its ages or `No ages yet`, `, needs your approval`, then its description or `No description yet`, with `Edit` and `Archive` or `Restore` | |
| No programs | `No programs yet.` | |

### The program dialog

| Where it shows | Text | Keep / Change |
|---|---|---|
| Title | `New program` / `Edit program` | |
| Fields | `Name` / `Ages` (example `Ages 6-10`) / `Description` / `Order in the list` / `Needs your approval` | |
| No name | `A program needs a name.` | |
| A name already used | `A program already has that name.` | |
| A program gone meanwhile | `Couldn't find that program.` | |
| A child gone meanwhile | `Couldn't find that child.` | |
| A program that needs no approval | `That program doesn't need approval.` | |

### Action Needed on This week

| Where it shows | Text | Keep / Change |
|---|---|---|
| The card's heading, when a parent has asked | `Program requests`, then the same request row as the Juniors tab | |

### Players: a child under the parent

| Where it shows | Text | Keep / Change |
|---|---|---|
| After the name | `(junior)` | |
| The line under it (not gated) | `Age {n}`, then `, Removed` if the parent removed the child, then `, Waiver signed` or `, Waiver not signed` | |
| Programs (not gated) | `Approved: {programs}`. `Asked for {programs}`. `Declined: {programs}` | |
