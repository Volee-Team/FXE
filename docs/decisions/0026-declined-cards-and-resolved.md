# 0026: A declined card holds no spot and says why; Tara's Resolved clears it from her lists

**Date:** 2026-09-28 · **Status:** Active, three defaults for Alex and Tara to confirm (below) · **Source:** Tara's round-four answers 78 and 83 (decision 0024), branch `declined-card`, migration `20260928700001_declined_card.sql`

Her words, exactly:

> 78: "Cannot sign up without proper, transactional card. App needs to tell them why their card isn’t working, yes."
>
> 83: "Can we have a button that says “resolved” and it clears - for me only to see ofc"

## What we chose

1. **A declined card blocks a spot, nothing else.** Once a charge on a
   player's card is declined, `register_for_clinic` and an Accept in
   `respond_to_invitation` refuse `card_declined` and move nothing, until a
   card is saved again or a later charge on the account goes through.
   Declining an invitation still works, and so does everything else in the
   app (browsing, My Clinics, cancelling). Tara is exempt, as with
   `card_required`, and the rule is on exactly while `card_required` is
   (payments on and a card required), checked right after it: a player with
   no card at all is asked for a card, not told about an old decline.
2. **"Declined" means Stripe said no to the card.** A charge (a clinic fee, a
   no-show or a late cancel; never a refund) going from pending or processing
   to `failed` with Stripe's code, on real money. The code is written only
   for a card error: the webhook records it only when Stripe's error type is
   `card_error`, and `stripe-charge` no longer keeps one for a request Stripe
   refused (our parameters; nothing reached the bank). A dropped connection,
   a timeout, an idempotency error and a charge past the retry window never
   reach `failed` (decision 0019); Tara's "Did not go through" makes a held
   charge `canceled`, and a failure delivered for it later changes nothing;
   our own refusals (`no_card_on_file`, `account_deleted`) carry no code.
   None of them blocks anyone.
3. **"Later" means attempted later, not answered later.** A card error is
   written the moment Stripe refuses it; a success only when its webhook
   arrives, so the answers to one Charge clinic race. The decline therefore
   records when its charge was attempted, stands only if it is about the card
   on file (attempted after that card was saved) and no charge attempted
   after it has gone through, and is cleared only by a success attempted no
   earlier than it. Tara's "Went through" on a charge held for three days
   does not clear a decline from yesterday.
4. **The database decides, from the ledger.** Two triggers keep
   `accounts.card_declined_at` / `card_decline_code`: one on `payments` (as
   above), one on `accounts` (a card saved by the Stripe pipeline clears
   them; a card removed does not, so an Accept stays refused and Register
   asks for a card first). The swap to live clears every decline, since each
   was about a sandbox card. No client may write the two columns (hard rule
   8): the column grants refuse it, and the trigger refuses a change made for
   any signed-in person from a SECURITY DEFINER path, and clears nothing when
   such a path writes a card date. The review's mutant that tried to make
   Resolved unblock the player was refused by exactly that.
5. **The player is told why, in Tara's words.** Profile shows the decline
   under the card, beside Change card: "Declined: Insufficient funds (NSF)",
   her label after "Declined: " as her Money tab writes it. A refusal on a
   clinic page says the same line (the code rides in the error's hint) and
   opens the card step, which after a decline can be closed, and closes itself
   once the webhook has recorded a new card.
6. **Resolved is Tara's, and it only clears her lists.**
   `admin_resolve_decline(p_payment)` stamps `resolved_at` and `resolved_by`
   on a failed, unresolved charge (hard rule 3: anything else is
   `decline_not_open`, "That just changed. Here's the latest."). `money_rows`
   calls such a row `resolved` and counts it nowhere, like `settled`, so the
   decline leaves Action Needed on the web and the phone, the Money tab's
   Declined figures and the This week tab's owed list, by one definition, and
   Charge clinic does not charge it again. The ledger keeps the charge and its
   date, and the card list says "Resolved" on it. It does not unblock the
   player: the card is still the card that was declined. One tap, no
   confirmation: it moves no money, tells nobody and changes nothing for the
   player. A new decline on the same registration comes back to her.

## Defaults we picked, for Alex and Tara to confirm

- **Resolved means "I will not chase it"**, so Charge clinic never charges
  that registration again. If she means "try again later", the skip in
  `admin_charge_clinic` goes. Until she says, the default that moves no money.
- **Lost, stolen and fraud read as a plain decline to the player.** Stripe
  asks that `lost_card`, `stolen_card`, `fraudulent`, `merchant_blacklist`
  and `pickup_card` be shown to the cardholder as a generic decline, so
  someone holding a card that is not theirs is not told they were caught.
  The account keeps those as `generic_decline` and the player reads
  "Declined: Card declined"; Tara's screens keep the real reason. A code with
  no approved words is a plain decline too, never Stripe's raw code. The
  player's own payment rows (readable to them since 20260912000001) still
  carry Stripe's real code; hiding that is a grant change to make only if she
  wants these words kept from players entirely.
- **Accept checks a declined card but not a missing one.**
  `respond_to_invitation` has never checked `card_required`; this adds only
  the decline, as asked. Whether an invited player with no card should be
  refused too is a separate call.

## What the review changed (sql-auditor, 2026-09-28)

No critical finding. Four majors and four minors; the probe grew from 53 to
67 checks, each new one red first.

- **Fixed:** the order of attempts (was: of answers); a refused request
  counted as a decline; Charge clinic retrying a resolved decline; a definer
  path clearing a decline by writing a card date; a removed card clearing
  the decline (which left Accept, which checks no card, open); fraud codes
  reaching the player; the probe's gaps (the card check's order, the Declined
  figure, a second Resolved inside one transaction).
- **Found in the review after it** (the auditor's second pass was cut off by
  an API limit, so the fixes were re-checked against its checklist by hand):
  a success and a failure recorded at the same moment could each miss the
  other, blocking a player though a later-attempted charge went through. The
  trigger now locks the account row before deciding;
  `tests/sql/declined_card_race.sh` was red without the lock and is green
  with it.
- **Open, not fixed here:** a player can remove their only saved card inside
  Stripe's sheet, which our database never hears of, so `card_last4` stays,
  `card_required` passes, and Tara's charge later fails as "no card on file".
  This predates the branch and is not a way round a decline (nothing in the
  database changes, so a declined player stays blocked). The client fix is an
  experimental Stripe SPI (`allowsRemovalOfLastSavedPaymentMethod`); the
  server fixes (clear the card summary when `stripe-charge` finds no card, or
  handle `payment_method.detached`) cannot be exercised by stripe-mock, which
  always returns a saved card. Needs a decision and a test against Stripe's
  sandbox.
- **Open, pre-existing:** `stripe-webhook`'s metadata fallback rewrites a
  charge whatever its status, so a late failure turns a canceled or succeeded
  row into `failed` on the ledger. It no longer blocks anyone (only a charge
  in flight becomes a decline); the ledger rewrite itself is untouched here.

## Rejected

- **Deciding the decline in `stripe-webhook` alone.** The webhook is where
  Stripe's word arrives, but a synchronous card error in `stripe-charge` fails
  the row first, and Tara's "Went through" is a success no webhook reports.
  A trigger on the ledger sees all three, and the probe can drive it with
  plain updates.
- **A separate flag Tara can clear.** Resolved is her note on a charge, not a
  switch on the player; a button that unblocked players would make "proper,
  transactional card" something she has to police by hand.
- **Taking resolved declines out in each client, as a deleted account's are.**
  Two clients would each have to agree with the Money figures; `money_rows`
  is already the one definition of what is owed and declined, so the state
  lives there.
- **Letting Resolved move `updated_at`.** That column is when the charge
  failed and decides which failure a row shows; the ledger trigger now leaves
  it alone for an update that changes only the resolution (or nothing, a
  replayed webhook).

## How we would know this was wrong

A player with a declined card holds a new spot; a player is blocked by a hold,
a dropped connection, a refused request or our own refusal; a decline sticks
after a charge attempted later went through, or an old success clears a newer
decline; a player is blocked without being told why, or is told "Card
reported stolen"; Resolved unblocks a player, or Charge clinic charges a
resolved decline; Tara's list still shows a decline she resolved, or no longer
shows a new one; the card list loses the charge. Pinned by
`tests/sql/declined_card.sql` (67 checks, red first against the unfixed code
and against ten mutants), section 16 of `tests/stripe/run.sh`,
`tests/stripe/errors.test.ts`, `FXETennisTests/DeclinedCardTests.swift`, the UI
test `testADeclinedCardSaysWhyAndHoldsNoSpot`, and the browser test "Resolved
clears it from Action Needed".
