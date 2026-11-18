# 0060. Tara's juniors answers: one purchase per weekday, winter first (2026-11-17)

**Status:** accepted. Tara answered questions 145 to 155 by text on
2026-11-17, and John relayed her answers. Amends `docs/juniors/plan.md`: the
first season is the **winter session**, not spring.

## Her answers

| # | Question | Her answer | What we build |
|---|---|---|---|
| 145 | Waiver text | "Yes" to the tennis camp parent/guardian form | That form word for word, signed once per child per year (phase 1 is unblocked) |
| 146 | Weekdays separate or one package | *"They can sign up for Monday and or Wednesday"*. Her example is Orange Dot on Tuesdays and Thursdays, 4 to 5 pm: $160 for Tuesdays, $140 for Thursdays (Thanksgiving falls on a Thursday), or $300 for both | **Each weekday of a session is its own purchase with its own price.** Both days cost the sum: there is no bundle price. Phase 2 is unblocked |
| 147 | School-year sibling discount | "None" | No school-year sibling discount |
| 148 | Summer rainouts | *"We don't cancel for rain."* If parents pick their child up early because of the weather, she sets the price herself | No canceled-day rule. A day that ends early is the full price unless she lowers it (the default) |
| 149 | Full camp day, then a spot opens | "Yes": the parent taps Accept | As the adult invites work |
| 150 | Siblings at different prices | *"just for our regular campers"*: the most expensive child pays full and the second gets $5 off | Only regular camp days get the $5. Elite camp days get none (question 168) |
| 151 | Two parents on one child | "Yes either" | Either parent books and cancels; the parent who booked pays |
| 152 | Spring dates | **Winter instead**: it starts 2027-01-04 and sign-ups open 2026-12-15. The end date is not set yet. She asked *"Too soon for app?"* | The first season is winter. The new deadline is 2026-12-15, two weeks before January 1 |
| 153 | The five programs' details | She sends them on 2026-11-18 | She types them into the laptop when the screen is ready |
| 154 | Summer registration | *"Let's say march 1 for summer for now"* | Phase 4 opens 2027-03-01. That makes 1.0.6 due on phones by mid-February |
| 155 | Treats | "$3/treat" | One price for every program, $3, a setting she can change |

## What changes in the plan

- **Phase 2's unit of sale is the weekday.** Each season gets a list of
  weekdays. Each weekday has its own dates, member and non-member price, and
  cap (question 167). A parent buys one weekday or several. Each purchase is
  its own `session_enrollments` row, so a parent can cancel, prorate or offer
  each day on its own.
- **The deadline moves from 2027-01-01 to 2026-12-15** for parents to add
  children, sign the waiver and buy winter weekdays. Drop-ins, walk-ins and
  the pros' juniors week are needed by the first class on 2027-01-04.
- **The members' website carries December 15 if Apple is late.** It already
  takes cards (`web/play/`) and deploys without App Store review. 1.0.5 is
  submitted as early as it is ready. If it is still in review on December 15,
  parents register on the website and the app follows.

## New questions (166 to 168, section AI)

- 166: the winter end date and the days off;
- 167: whether each weekday has its own cap;
- 168: what a regular camper's sibling pays on an Elite day.
