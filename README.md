# FXE Tennis

Clinic registration and roster management for the FXE tennis program: a
native iOS app (Swift / SwiftUI) for players and for Tara's courtside admin
work, a static web admin for her weekly setup on a laptop, and one Supabase
backend (Postgres + Auth + Edge Functions) that holds every rule about who can
see and do what. Not Volee: separate repo, project, bundle id and listing.

## Where to start

| Read | For |
|---|---|
| `CLAUDE.md`, **Build & Run** | Local stack, migrations, the probe suite, and the one sanctioned way to write hosted |
| `docs/architecture.md` | The system in one document: surfaces, the security model, the schema, the RPCs, testing |
| `docs/roadmap.md` | What is in v1, v1.1, v2, what is parked, and what we are deliberately not doing |
| `docs/launch-checklist.md` | The state of the app today, and everything between here and the App Store, with an owner and a status per line. Status words live there, in `docs/backlog.md`, `docs/questions-for-tara.md` and `docs/decisions/README.md`, and nowhere else |

## How it is tested

SQL probes against a fresh local Postgres (including a concurrency probe and
an attack probe per privilege boundary), Swift unit tests, XCUITests on the
simulator, Playwright tests of the web admin, and a Stripe pipeline run
against a mock; every layer except the XCUITests runs in CI on each push. Each
suite prints its own totals; `CLAUDE.md` says why no count is quoted here.
