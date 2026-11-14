# EcoYard

Flutter app for iOS and Android from one Dart codebase. Backyard habitat
advice driven by bird sound ID. iOS ships first; Android is the same code.

`reference/GardenEar/` is a read-only copy of my previous app (Swift). Read
it and rewrite its behaviour in Dart. Never build it, never modify it, never
add it as a dependency.

## Context protocol — read this first

Do NOT read the full planning docs unless the task needs them.

| File | When to read |
| --- | --- |
| `docs/STATE.md` | **Start of every session.** Short by design. Tells you where things stand |
| `docs/PLAN.md` | Only when starting a new phase, or when STATE.md points you at a section |
| `docs/design/EcoYard_UI_Mockup.png` | Only when building a screen |
| `docs/design/EcoYard_App_Specification.md` | Only when building a screen or feature it describes |

Read a *section* of PLAN.md, not the whole file (`grep -n '^#' docs/PLAN.md`
for the outline).

At the end of any change, **append** one line to the Changelog in
`docs/STATE.md`. Append — do not rewrite the file. Update the "Current
state" block only when the phase or status actually changes.

## Non-negotiable rules

1. **Flutter only.** No native Swift or Kotlin feature code. `ios/` and
   `android/` are touched only for configuration (Info.plist, manifest,
   Gradle/Podfile settings, entitlements). If something seems to need a
   platform channel, stop and ask.
2. `packages/ecoyard_core` is **pure Dart with zero dependencies**: no
   Flutter SDK, no plugins, no `dart:io`/`dart:ui` in `lib/`. Models,
   SpeciesResolver, HabitatEngine, ReferenceRepository live here. Device and
   network code goes in `packages/bird_audio`.
3. **Persistence is SQLite**, one schema for both platforms. Migrations are
   numbered and append-only.
4. **No platform or UI types in the domain model.** Own `Coordinate` class,
   hex colour strings, ISO-8601 strings. Never Flutter's `Color` or a
   plugin's `Position` inside ecoyard_core.
5. **Content lives in JSON** (`content/`), never in Dart. No hardcoded lists
   of plants, birds, actions or tips.
6. Engine and resolver behaviour is pinned by `fixtures/engine_cases.json`.
   Only the user changes it, deliberately — never to make a test pass.
7. Never claim in UI copy that audio stays on the device. NatureLM is an
   online provider. The badge is provider-aware.
8. No secrets in the repo. Tokens go in an untracked `.env.json` passed with
   `--dart-define-from-file`.

## Agents and workflow

Agents live in `.claude/agents/`. They run **one after another**, never in parallel.

**Feature work:** `developer` → `tester` → `reviewer` → back to `developer`
if anything is BLOCKING → repeat tester/reviewer. `critic` runs only twice per
phase: on the plan at phase start, and on the result at phase end.

**Bug-fix protocol** (build error, failing test, or reported bug):
1. `tester` **reproduces** it with a failing test and confirms it fails for the right reason.
2. `tester` **pinpoints** the exact file, class and method where the bug originates.
3. `developer` fixes **only that method/class** — smallest possible diff. No
   reformatting, renaming or tidying elsewhere. If the fix needs a signature
   change or edits in other places, stop and ask the user first.
4. Reproduction test passes; all other tests still pass.
5. `reviewer` rejects any line changed outside the pinpointed code.

## Guardrails (enforced, not optional)

- Git hooks in `.githooks/` (enable once with `scripts/setup.sh`):
  - pre-commit: secrets, model files / files over 5 MB, `reference/` lock, ecoyard_core purity, `dart format` + `dart analyze`, content JSON validation, false privacy copy.
  - commit-msg: message quality; `[fixtures]` tag required when fixtures change.
  - pre-push: analyze + test every package.
- Claude hooks in `.claude/hooks/` block: edits to `reference/`, `fixtures/` and
  guardrail files; `--no-verify`; force-push; `reset --hard`; broad `rm -rf`;
  reading credential files. After each Dart edit, `dart analyze` runs and
  errors come straight back. Before a turn ends, tests of changed packages run.
- Never bypass a guardrail. If one is wrong, explain why and let the user change it.

## Working agreement

- One phase per session. Stop at the phase boundary and say so.
- Ask before adding any third-party package.
- Don't refactor outside the current phase's scope.
- Analyze and tests must pass before you append to the Changelog.
- Anything that cost more than 15 minutes goes in STATE.md's Gotchas.
