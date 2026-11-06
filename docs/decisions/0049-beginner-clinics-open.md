# 0049. A beginner clinic's number is not a minimum (2026-11-05)

**Status:** accepted; built in
`supabase/migrations/20261106000001_beginner_clinics_open.sql`.

## Her words

Asked by Alex the night decision 0048 went live, because players rated 2.0 were
refused from "Ladies Beginner - 2.5". Tara, by text, 2026-11-05: *"Yes, that is
correct. So if somebody wants to join the 3.0 clinic on Tuesdays, but they are a
2.5, I want them to just ask for approval one time and if I accept them, then
they can register for that clinic anytime they want. Beginner clinics can be open
to anyone up to a 3.0, I guess, even though it says beginner to 2.5"*

## The rule

| Clinic | A player rated below the number |
|---|---|
| Name contains "Beginner" (any case) | Registers as anyone else; no minimum |
| "Ladies 2.5+" | Asks Tara once, the same as a 2.5 for a 3.0+ (question 140) |
| "Ladies 3.0+ Clinic", "4.0 Clinic" | Asks Tara once (decision 0048) |

## What changed

`clinic_level_from_name` returns null for a beginner clinic, and existing beginner
clinics are rewritten so their stored `min_rating` follows. The app and the
members' site read `min_rating`, so this needed no new build.

## Rejected

- **A setting on each clinic for its minimum.** Tara sets the level by naming the
  clinic (decision 0048); a second place to set it would need a new form field and
  could disagree with the name.
- **Enforcing a ceiling now.** *"Up to a 3.0, I guess"* is the only word on it, and
  turning a 3.5 away is a new refusal nobody has asked for by name. Question 142.

## How we would know we were wrong

A clinic with "Beginner" in its name that Tara does want gated, or a stronger
player taking beginner spots she wanted kept for beginners.
