# EcoYard — State

The working memory for this repo. Keep it short. If this file passes
~200 lines, compress the Changelog (see Maintenance at the bottom).

---

## Current state

- **Phase:** 0 done (repo hygiene, guardrails, agents). Next: 0.5 — BirdNET Flutter spike (PLAN.md §7)
- **Status:** Phase 0 repo work complete. Still open from Phase 0 (user tasks): privacy copy in mockup, Kaggle notebook audit, privacy policy draft
- **Build:** no Dart code yet. Flutter SDK not installed on this machine
- **Blocked on:** Flutter install; a physical iPhone + Android phone for the spike
- **Setup after clone:** `scripts/setup.sh` (enables `.githooks/`)

## Decisions made

Append one line per decision. Never delete; supersede with a new line.

- 2026-11-14 — Providers: NatureLM (Kaggle via Render router) online, BirdNET TFLite on-device offline
- 2026-11-14 — Persistence: SQLite, not SwiftData. Schema must port to Room/SQLDelight
- 2026-11-14 — Deployment target: iOS 18+, Swift 6 from the first commit
- 2026-11-14 — Android is a future target, reached by porting `EcoYardCore`, not by a cross-platform framework
- 2026-11-14 — New repo rather than evolving GardenEar in place. GardenEar source is copied in as a starting point; the old repo is frozen as reference, not a dependency
- 2026-11-14 — One product, not two apps. EcoYard supersedes GardenEar
- 2026-11-14 — Framework: Flutter for iOS and Android from one codebase. No native Swift or Kotlin feature code. Supersedes the iOS 18/Swift 6 and "not by a cross-platform framework" lines above. GardenEar is rewritten in Dart using its Swift source as the spec

## Open questions

- ~~Native Swift or Flutter?~~ Resolved 2026-11-14: Flutter (spike still gates the real build)
- ~~Public release or portfolio only?~~ Resolved 2026-11-14: portfolio → TestFlight → public App Store. On-device BirdNET becomes the default for the public release
- Keep the Map and Score screens, or cut them to hold the tab bar to five?

## Architecture map

Only the parts that exist. Add rows as they are built.

| Module | Purpose | Status |
| --- | --- | --- |
| `app/` | Flutter app (iOS + Android): Home, Plants, Birds, My Plan, Settings | not created |
| `packages/ecoyard_core` | Pure Dart, zero deps. Models, SpeciesResolver, HabitatEngine, ReferenceRepository | not created |
| `packages/bird_audio` | Providers + fallback chain, recorder, BirdNET runner, SQLite, system services | not created |
| `content/*.json` | birds, plants, bird_plant, actions, tips, taxonomy_aliases | not created |
| `reference/GardenEar/` | Read-only Swift source of the old app. Spec to rewrite from, never built | copied (plain files) |
| `.githooks/` + `scripts/hooks/` | pre-commit, commit-msg, pre-push checks | done |
| `.claude/` | agents (developer, tester, reviewer, critic), guardrail hooks, settings | done |

## Gotchas

Things that cost time once. Add to this list rather than rediscovering them.

- `AudioIdentificationService.provider` in the GardenEar source returns a network provider in the offline branch. Must be replaced by the fallback chain, not copied as-is
- NatureLM returns a free-text common name with no scientific name. BirdNET returns `Scientific_Common`. Both must go through `SpeciesResolver`
- GardenEar's `Theme.swift` hardcodes light/dark colours as separate constants. Use a proper Flutter `ThemeData` light/dark pair in the rewrite
- GardenEar had a real Hugging Face token hardcoded in `Resources/Info.plist` (`HF_TOKEN`). Redacted in `reference/`, but it is in GardenEar's GitHub history — **revoke it on huggingface.co**. In EcoYard, tokens go in untracked `.env.json` only
- Flutter 3.50.0 stable (Dart 3.14.0) at `~/development/flutter`, analytics off. This Mac has only Command Line Tools — full Xcode, CocoaPods and Android Studio still needed (`flutter doctor`)
- Flutter 3.50 deprecates `package:flutter/material.dart` in favour of `package:material_ui` (5 info-level analyzer notices). Left as is; adopting material_ui is a new dependency — ask first
- Xcode 27.2 + iOS 27.2 simulator runtime installed. Run on simulator without CocoaPods (works while no plugins): `cd app && flutter build ios --simulator --debug`, then `xcrun simctl install <device> build/ios/iphonesimulator/Runner.app` and `xcrun simctl launch <device> com.sridharippili.ecoyard`
- CocoaPods 1.17.0 runs on Ruby 3.3.13 under `~/.rbenv/versions/3.3.13` (rbenv + libyaml built from source; no Homebrew). System Ruby 2.6 is too old for CocoaPods, do not use it. Before iOS builds with plugins, put it on PATH: `export PATH="$HOME/.rbenv/versions/3.3.13/bin:$PATH" LANG=en_US.UTF-8`. Android SDK still not installed (paused by choice)
- Preview the starter in Chrome: `cd app && flutter build web && cd build/web && python3 -m http.server 8765`
- No Homebrew on this machine. Hooks are plain shell (`core.hooksPath`), no lefthook/Husky/Node needed

---

## Changelog

Newest first. One line each: date, what changed, where.

- 2026-11-14 — Phase 0.5 spike project created at ~/Downloads/birdnet_spike (outside repo): analyzes clean, `pod install` OK with record 5.x + tflite_flutter 0.11. Missing: BirdNET model + labels in assets/, test clips, real iPhone
- 2026-11-14 — Toolchain: Ruby 3.3.13 (rbenv) + CocoaPods 1.17.0 installed; flutter doctor green for iOS. Ready for the BirdNET spike

- 2026-11-14 — Starter shell in app/ (iOS+web, no new packages): theme, 5-tab nav, Home from mockup, placeholders; analyze clean (5 infos), 1 widget test passes, verified in Chrome. NOT Phase 1 — no identification yet; spike still gates it
- 2026-11-14 — Phase 0: GardenEar as plain files in reference/ (HF token redacted), spike files moved to ../birdnet_spike, CLAUDE.md to root rewritten for Flutter, mockup+spec into docs/design/, .githooks + scripts/hooks, .claude agents/hooks/settings, CI workflow, Flutter .gitignore

- 2026-11-14 — PLAN.md rewritten for Flutter: §1 decision, §3 Dart package layout, Dart code samples, phases 0–9 re-cut (spike now a mandatory gate, Phase 9 = Android release), risks updated
- 2026-11-14 — Repo initialised with CLAUDE.md, docs/. No code yet

---

## Maintenance

When the Changelog passes ~40 entries, replace the oldest 20 with a
single summary line covering that span, e.g.
`- 2026-11-14 → 2026-12-20 — Phases 1–3 complete: packages split, content schema + resolver, habitat engine`.
Keep recent entries detailed. Never let this file become an archive.
