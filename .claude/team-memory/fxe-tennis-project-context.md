---
name: fxe-tennis-project-context
description: "FXE Tennis is its own app and repo, not Volee; the two share a developer and patterns only; the working directory and memory directory must be the FXE ones"
metadata:
  type: project
---

Two apps, two repos, two Supabase projects, two bundle ids, two memory directories: **Volee** (`/Users/alex/Documents/GITHUB/Volee`, memory under `-Users-alex-Documents-GITHUB-Volee`) and **FXE Tennis** (`/Users/alex/Documents/GITHUB/FXE-Tennis`, memory under `-Users-alex-Documents-GITHUB-FXE-Tennis`). On 2026-08-13 a session worked in the wrong repo; on 2026-09-12 a session ran from a folder beside the repo (`~/Documents/FXE Tennis`, since deleted) and wrote docs there. Check `git rev-parse --show-toplevel` before writing anything. Volee's memory holds two preferences that apply to Alex everywhere (no em-dashes in chat, do the task not the plan); they are copied into [[feedback-session-hygiene]].

**Why:** the same developer, the same patterns, and a wrong-repo edit is silent. Related: [[project-accounts-and-tooling]].
