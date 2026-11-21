# Juniors phase 1, the app: new wording for John to sign off (2026-11-18)

John, 2026-11-16: *"I will sign off on new wording."* (hard rule 13). Every
new word the phase 1 app screens put in front of a parent. Mark each row Keep,
or write what it should say instead. All of it is in `docs/copy-approved.txt`
(the copy gate). Words that are Tara's own, from her juniors document
(`docs/juniors/spec-2026-11-07.md`), are marked "hers"; changing those means
asking her.

Where it is: Profile → My Children (a list of the parent's children) → a
child's page (details, waiver, programs) → Sign the waiver (a sheet). Also My
Children → Programs (read only). Nothing here books a child into anything;
that is phase 2.

## Profile and My Children

| Where it shows | Text | Keep / Change |
|---|---|---|
| Profile, under My Clinics | `My Children` (hers: "Profile → My Children → Add a Child") | |
| My Children, title | `My Children` | |
| My Children, no children yet | `No children added yet.` | |
| My Children, button | `Add a Child` (hers) | |
| My Children, button | `Programs` | |
| Each child's row, under the name | `Age 8 · Waiver needed` (or `Waiver signed`, or `Waiver not available yet`) | |
| The list could not load | `Couldn't load your children.` | |

## Add a Child / Edit Child (a sheet)

| Where it shows | Text | Keep / Change |
|---|---|---|
| Title | `Add a Child` (hers) / `Edit Child` | |
| Field labels | `First Name`, `Last Name` (as Edit details), `Birthday` (a date wheel) | |
| Buttons | `Cancel`, `Save` (as Edit details). Save stays grey until a birthday is chosen, so the wheel's starting date is never saved by accident | |

## A child's page

| Where it shows | Text | Keep / Change |
|---|---|---|
| Under the child's name | `Age 8` | |
| Details card | `Birthday`, then e.g. `March 1, 2017`; button `Edit` | |
| Waiver section heading | `WAIVER` | |
| Waiver status | `Waiver signed` / `Waiver needed` / `Waiver not available yet` | |
| Button, when a waiver is needed | `Sign the waiver` | |
| No parent/guardian text published yet (true until Tara's file arrives) | `The waiver for children isn't available yet.` | |
| Programs section heading | `PROGRAMS` | |
| Each program | Tara's name, her age guidance (e.g. `Ages 3-6`), her description once she types it | |
| Under Junior Elite and Elite | `Tara approval required` (hers, spec 01's table) | |
| Button on Junior Elite and Elite | `Request Approval` (hers, spec 06). VoiceOver reads `Request Approval for Elite` | |
| After asking | `Approval requested` | |
| After Tara answers | `Approved` / `Not approved` | |
| No programs | `No programs yet.` | |
| Foot of the page | `Remove child` | |
| Confirm before removing | `Remove Sam from your account?` with `Remove` / `Cancel` | |

## Sign the waiver (a sheet), for one child

The waiver's own title and text are Tara's parent/guardian form, shown as she
sends it (question 145). Until then this sheet never opens.

| Where it shows | Text | Keep / Change |
|---|---|---|
| Top of the sheet | `For Sam Lee` | |
| The checkbox sentence | `I am Sam's parent or guardian, and I have read and agree to this waiver for them.` **A stand-in:** the adult checkbox sentence is Tara's own, from the last page of her adult waiver. If her parent/guardian form gives its own sentence, that replaces this one | |
| Name field label | `Your full legal name` (the adult sheet says `Full legal name`; here it is the parent's name, not the child's) | |
| Name field hint, button | `First and last name`, `Agree and sign` (both as the adult waiver) | |
| Close button | `Close` (the adult waiver cannot be closed; this one can, since nothing waits on it until phase 2) | |
| Could not load | `Couldn't load the waiver.` and `Try again` (as the adult waiver) | |

## Messages when the server says no

| When | Text | Keep / Change |
|---|---|---|
| The same name and birthday twice | `This child is already on your account.` | |
| A blank name | `Add a first and last name.` | |
| A birthday in the future | `Pick a birthday in the past.` | |
| Not this account's child (or removed meanwhile) | `Couldn't find this child on your account.` | |
| Removing a child with a spot or a late request coming up | `This child has a spot coming up, so they can't be removed yet. Contact Tara.` | |
| Changing name or birthday after Tara approved or declined them, or after a waiver was signed | `Only Tara can change this child's name or birthday now. Contact Tara.` | |
| An 11th child (the limit is 10, decision 0061) | `You can add up to 10 children.` | |
| Asking again after Tara declined | `Tara didn't approve this request. Contact Tara.` | |
| Asking for a program that needs no approval | `This program doesn't need approval.` | |
| A program Tara has archived | `This program isn't available anymore.` | |
| Signing while no text is published | `The waiver for children isn't available yet.` | |
| Anything else that did not save | `That didn't save. Check your connection and try again.` (already approved) | |
| Programs could not load | `Couldn't load the programs.` | |
