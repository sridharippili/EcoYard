# EcoYard — State

The working memory for this repo. Keep it short. If this file passes
~200 lines, compress the Changelog (see Maintenance at the bottom).

---

## Current state

- **Phase:** 3 — HabitatEngine: built and tested; engine cases are a DRAFT awaiting the user's review and promotion to `fixtures/engine_cases.json`
- **Status:** `ecoyard_core` now has `HabitatEngine` (ranked actions, plants, need coverage). `dart run scripts/recommend.dart "Northern Cardinal" --month 10` prints a full recommendation from a name. Not wired into the app (Phase 4)
- **Build:** `scripts/hooks/pre-push.sh` passes: app 21 + ecoyard_core 191 (+1 opt-in skipped) + bird_audio 47 tests, analyzers clean
- **Release gate:** `scripts/release_check.sh` fails until (a) `fixtures/engine_cases.json` exists, (b) every content file is `reviewed` with `reviewedBy`/`reviewedOn`, (c) every plant has a real photo. It is NOT wired into CI/hooks (guarded files): the user should add it to the release workflow
- **Setup after clone:** `scripts/setup.sh` (enables `.githooks/`)

## Known gaps handed to Phase 4 (UI) — see docs/ENGINE_SPEC.md

- A need can have no remedy now (`NeedCoverage.hasRemedy == false`). Show "nothing to do this month" and point at `laterActionIds` ("try in spring"); never show a bare need. A remedy that exists but is not among the three shown is "also possible" (`coveredByShownActions` false, `remedyActionIds` not empty)
- Plants are not month-filtered. Do not imply "plant now" from the plant list
- `plantsHiddenByFilters` > 0 or an empty plant list in shade: say "no plant fits this sun" / "N more need different sun"
- The UI maps a state (NJ) to region `us-ne` before calling the engine; any other region throws
- Engine needs are coarse (every bird has food/shelter/nesting/water/safety). Signature actions are marked by hand with `featuredForBirdIds` in `content/actions.json` (seed heads: goldfinch; nest box: chickadee, titmouse, wren; dead wood: downy, nuthatch). Any new action that is the point of a species needs the same
- The engine may return FEWER than three actions (no padding: after the free first step an action must cover a need not yet covered). A hummingbird on a balcony in July gets one. The UI must cope with 1-3
- A need blocked only by budget has `moreBudgetActionIds` ("a small budget would unlock..."); one blocked by season has `laterActionIds`. Use them instead of "nothing can help"
- A plant is never linked for `nesting` unless it gives nesting cover soon after planting (shrubs, vines), never trees
- Content rows a person must check before release: tip-mar timing wording, `norcar`/`northern-spicebush`, `carwre`/`white-oak` weight, plus everything (all content is unreviewed)

## Open items (need a human or a later phase)

- **Promote the engine fixtures:** read `packages/ecoyard_core/test/engine_cases.draft.json` (especially the `why` of c02, c11, c19), then run the promote commands in docs/ENGINE_SPEC.md. Until then the engine is pinned only by a draft I wrote

- **Capture ~50 real NatureLM outputs** (PLAN §5) — not possible while the Kaggle notebook is off. Only ONE genuine NatureLM string exists in the repo ("Laughing Kookaburra"); every other resolver test row is marked `synthetic` in `packages/ecoyard_core/test/resolver_cases.json`. Add captures as `real` rows
- **Review all content** (`content/*.json`): written by Claude from general knowledge, never checked against USDA PLANTS / sources. Flip each file's `reviewStatus` to `reviewed` only after a person checks it
- **Plant photos** (15): Wikimedia Commons CC0/CC-BY or USDA, store attribution, add credits screen
- **Router token header format** for `/identify`; Kaggle notebook + HF Space audio-retention audits (needed before saying "not kept"); real iPhone + Android checks
- Remaining content scale-up to 50 birds / 60 plants (Phase 8). White-breasted Nuthatch has only one plant link

## Decisions made

Append one line per decision. Never delete; supersede with a new line.

- 2026-11-14 — Providers: NatureLM (Kaggle via Render router) online, BirdNET TFLite on-device offline
- 2026-11-14 — Persistence: SQLite, not SwiftData. Schema must port to Room/SQLDelight
- 2026-11-14 — Deployment target: iOS 18+, Swift 6 from the first commit
- 2026-11-14 — Android is a future target, reached by porting `EcoYardCore`, not by a cross-platform framework
- 2026-11-14 — New repo rather than evolving GardenEar in place. GardenEar source is copied in as a starting point; the old repo is frozen as reference, not a dependency
- 2026-11-14 — One product, not two apps. EcoYard supersedes GardenEar
- 2026-11-14 — v1 identification is ONLINE ONLY. Chain: (1) NatureLM via gardenear-router `/health` then `/identify`; (2) if unresponsive, BirdNET online (`ippili7-gardenear-api.hf.space/analyze`, multipart m4a); (3) neither reachable → fail honestly with a clear offline message. On-device BirdNET is deferred, not cancelled. (User decision; supersedes the on-device step in PLAN.md §0.1 for v1)
- 2026-11-14 — Framework: Flutter for iOS and Android from one codebase. No native Swift or Kotlin feature code. Supersedes the iOS 18/Swift 6 and "not by a cross-platform framework" lines above. GardenEar is rewritten in Dart using its Swift source as the spec

- 2026-11-14 — Taxon ids are eBird species codes, verified against eBird's species pages 2026-11-14 (one wrong id, `ruthum`, was caught and fixed to `rthhum` before any data was stored). Ids are persisted from Phase 4 on: never rename without a migration
- 2026-11-14 — Resolver test cases live in `packages/ecoyard_core/test/resolver_cases.json`; `fixtures/engine_cases.json` is for the Phase 3 HabitatEngine only. (CLAUDE.md rule 6 still says "engine and resolver behaviour is pinned by fixtures/engine_cases.json": the user should reword it)
- 2026-11-14 — `test` (dart-lang) approved by the user as a DEV dependency of packages/ecoyard_core. Earlier approvals: http, record, path_provider

- 2026-11-14 — Engine ranking deviates from PLAN §6's literal "free always above paid": slot 1 is the best FREE action (guaranteed free first step), later slots pick by uncovered needs, free wins only ties. Reason: strict free-first hides the nest box and window action in every month. User to confirm
- 2026-11-14 — Engine also: signature actions (`featuredForBirdIds`, +2 in selection), no padding (after slot 1 an action must cover a new need, so 1-3 actions), budget-blocked remedies reported. These were decided by the assistant after the critic's end-of-phase review, so user to confirm, especially "fewer than three actions"
- 2026-11-14 — Every bird now has a `safety` need (window collisions) so `mark-windows` can earn a slot by the same rule as other actions

## Open questions

- ~~Native Swift or Flutter?~~ Resolved 2026-11-14: Flutter (spike still gates the real build)
- ~~Public release or portfolio only?~~ Resolved 2026-11-14: portfolio → TestFlight → public App Store. On-device BirdNET becomes the default for the public release
- Keep the Map and Score screens, or cut them to hold the tab bar to five?

## Architecture map

Only the parts that exist. Add rows as they are built.

| Module | Purpose | Status |
| --- | --- | --- |
| `app/` | Flutter app (iOS + Android): Home, Plants, Birds, My Plan, Settings | not created |
| `packages/ecoyard_core` | Pure Dart, zero runtime deps (dev: `test`). Models, ReferenceRepository, content validator, SpeciesResolver, HabitatEngine | Phases 2-3 done |
| `packages/bird_audio` | Providers + fallback chain, recorder, BirdNET runner, SQLite, system services | not created |
| `content/*.json` | birds, plants, bird_plant, actions, tips, taxonomy_aliases (all `schemaVersion` 1) | 10 birds, 15 plants, 40 links, 10 actions (priority + optional forBirdIds), 12 tips — DRAFT |
| `scripts/validate_content.dart` | Content checks; same normalizer as the resolver; `--strict` = release gate | done |
| `scripts/recommend.dart` | Prints a recommendation from a bird name (resolver + engine) | done |
| `docs/ENGINE_SPEC.md` | The engine's rules in prose | done |
| `reference/GardenEar/` | Read-only Swift source of the old app. Spec to rewrite from, never built | copied (plain files) |
| `.githooks/` + `scripts/hooks/` | pre-commit, commit-msg, pre-push checks | done |
| `.claude/` | agents (developer, tester, reviewer, critic), guardrail hooks, settings | done |

## Gotchas

Things that cost time once. Add to this list rather than rediscovering them.

- `AudioIdentificationService.provider` in the GardenEar source returns a network provider in the offline branch. Must be replaced by the fallback chain, not copied as-is
- NatureLM returns a free-text common name with no scientific name. BirdNET returns `Scientific_Common`. Both must go through `SpeciesResolver`
- GardenEar's `Theme.swift` hardcodes light/dark colours as separate constants. Use a proper Flutter `ThemeData` light/dark pair in the rewrite
- GardenEar had a real Hugging Face token hardcoded in `Resources/Info.plist` (`HF_TOKEN`). Redacted in `reference/`, but it is in GardenEar's GitHub history — **revoke it on huggingface.co**. In EcoYard, tokens go in untracked `.env.json` only
- **GardenEar's offline mode never worked as shipped:** `OfflineModelManager` downloads from a GitHub release URL (`.../releases/download/v2.4/...tflite`) that now 404s, and its bundled `Resources/BirdNET_GLOBAL_6K_V2.4_Labels.txt` contains the literal text `404: Not Found`. Do not port either. Official source: Zenodo record 15050749, `BirdNET_v2.4_tflite.zip` (77 MB, md5 c13f7fd28a5f7a3b092cd993087f93f7): `audio-model.tflite` is the FP32 model, `labels/en_us.txt` is the 6,522-line `Scientific_Common` label list. The model must be fetched/hosted by us; the GitHub repo no longer ships it
- Spike: `record` ^5.x fails to build (record_linux/platform_interface mismatch). Use `record` ^7.2.0 (spike uses it). Re-check API when porting to the app
- Flutter 3.50.0 stable (Dart 3.14.0) at `~/development/flutter`, analytics off. This Mac has only Command Line Tools — full Xcode, CocoaPods and Android Studio still needed (`flutter doctor`)
- Flutter 3.50 deprecates `package:flutter/material.dart` in favour of `package:material_ui` (5 info-level analyzer notices). `material_ui` is already declared in app/pubspec.yaml (added by the 3.50 `flutter create` template, unused), so switching imports needs no new package. Not done yet
- **Live service facts (2026-11-14):** router `/health` is open and instant, returns `{"status":"ok","active_providers":[]}` when the Kaggle notebook is off (then NatureLM is skipped). The BirdNET Space has no health route (`/` and `/docs` return 404) and took 19 s to wake from sleep; `/analyze` accepted our m4a. Router `/identify` auth is still unknown: GardenEar sent no header, but a new router token exists. Ask the user the header format before relying on it
- **BirdNET returns non-bird classes** ("Human vocal", "Gun"; probably also Engine, Dog, etc.). Phase 1 shows them as "Possible match". The Phase 2 SpeciesResolver must treat them as "not a bird", from a JSON list, not Dart
- Birds tab probes service health on app start (IndexedStack builds every tab), which sends two harmless GETs and wakes Render/the Space. Make it lazy if that bothers you
- iOS Simulator tap tool and screenshots lag by a few seconds; twice the mic seemed to start without a Record tap. Could not reproduce; a widget test now pins "no Record tap, no recording"
- Widget tests: assets load through `rootBundle` never completes in 2nd+ test under fake async. Inject loaders through `AppEnvironment` (done for Home)
- **Resolver rules that must not be loosened:** species-level aliases only (never "chickadee", "wren", "jay"... they would turn an out-of-slice bird into one of ours); fuzzy matching only for names of 8+ chars, 1 edit under 12 chars, 2 edits above, same word count, and only when exactly one species is closest; an unresolved name is shown as the provider said it. The negative cases in `resolver_cases.json` guard this. Revisit aliases when Carolina Chickadee / House Wren etc. join the content
- `lib/` of `ecoyard_core` imports sibling files by RELATIVE path only (no `package:`), because `scripts/validate_content.dart` has no pubspec and imports them directly. Tests may use `package:`
- `flutter analyze` fails on info-level notices by default, so pre-push failed from Phase 0 until Phase 2. Fixed (material_ui imports, private named params). Keep analyze at zero issues
- BirdNET labels are NOT committed (model licence). Full-label resolver test is opt-in: `BIRDNET_LABELS=/path/to/BirdNET_GLOBAL_6K_V2.4_Labels.txt dart test` in packages/ecoyard_core. Result 2026-11-14: 6,522 labels -> exactly 10 resolved (exactLabel), 11 not-a-bird, 6,501 unresolved
- BirdNET's non-bird classes: Human vocal, Human non-vocal, Human whistle, Dog, Engine, Environmental, Fireworks, Gun, Noise, Power tools, Siren (11)
- Xcode 27.2 + iOS 27.2 simulator runtime installed. Run on simulator without CocoaPods (works while no plugins): `cd app && flutter build ios --simulator --debug`, then `xcrun simctl install <device> build/ios/iphonesimulator/Runner.app` and `xcrun simctl launch <device> com.sridharippili.ecoyard`
- CocoaPods 1.17.0 runs on Ruby 3.3.13 under `~/.rbenv/versions/3.3.13` (rbenv + libyaml built from source; no Homebrew). System Ruby 2.6 is too old for CocoaPods, do not use it. Before iOS builds with plugins, put it on PATH: `export PATH="$HOME/.rbenv/versions/3.3.13/bin:$PATH" LANG=en_US.UTF-8`. Android SDK still not installed (paused by choice)
- Preview the starter in Chrome: `cd app && flutter build web && cd build/web && python3 -m http.server 8765`
- No Homebrew on this machine. Hooks are plain shell (`core.hooksPath`), no lefthook/Husky/Node needed

---

## Changelog

Newest first. One line each: date, what changed, where.

- 2026-11-14 — Phase 3: HabitatEngine (+ HabitatQuery/Recommendation/NeedCoverage/BudgetTier), docs/ENGINE_SPEC.md, scripts/recommend.dart, 21 hand-derived draft cases + property tests over 3,564 inputs (mutation-checked: breaking the free slot, season filter, featured bonus, no-padding rule or budget list fails 7 / 10 / 5 / 8 / 2 tests). Content: `priority` + optional `forBirdIds` on actions, `safety` need on every bird. Critic (start) found strict free-first hides the nest box (greedy need coverage), irrelevant actions ranking first (forBirdIds), soft fixture lock (release_check requires fixtures/engine_cases.json). Critic (end) found budget-blocked needs reported as hopeless (moreBudgetActionIds), goldfinch seed-heads never shown (featuredForBirdIds), repeated-need padding (no-padding rule); all fixed and the draft cases re-derived by hand. NOT locked until the user promotes fixtures. [scope] not shown in the app yet

- 2026-11-14 — Phase 2: content/ slice (10 birds, 15 plants, 40 links, 10 actions, 12 tips, aliases; all DRAFT, photos pending); review gate needs reviewedBy + reviewedOn; scripts/release_check.sh; ecoyard_core models + ReferenceRepository + validateContent + SpeciesResolver + shared normalizer; scripts/validate_content.dart; 145 core tests; app moved to material_ui and zero analyzer issues so pre-push passes. New dev dependency (approved): `test` in ecoyard_core. [scope] resolver not yet shown in the app (Phase 4). Critic (end of phase) found a wrong eBird code (ruthum -> rthhum, fixed and all 10 re-verified), no real review gate (added reviewedBy/reviewedOn + scripts/release_check.sh), overstated nesting links and a few tip/action wording mismatches (fixed; 2 actions added)

- 2026-11-14 — Phase 1: packages/ecoyard_core (empty, pure Dart) + packages/bird_audio (ProviderChain with health cache + timeouts, NatureLM and BirdNET-online providers, recorder, parser; packages added with approval: http, record ^7.2, path_provider) + app Birds tab (controller, privacy badge without "not kept"), AppEnvironment injection. Verified live in Simulator. [scope change] no SQLite/save-sighting yet; Android and real-iPhone checks outstanding
- 2026-11-14 — Critic (run as general-purpose stand-in; .claude/agents load only at session start) reviewed Phase 1: adopted noDetection-is-final, null NatureLM confidence, timeouts, probe never blocks Record, no "not kept" until audits, HTTP tests, m4a + 10 s cap, mic Info.plist string

- 2026-11-14 — Spike partial result (iOS Simulator): BirdNET FP32 loads via tflite_flutter in 358 ms, input [1,144000], output [1,6522], 6,522 labels match; no Swift/Kotlin written (criterion 4 holding). NOT yet proven: top-1 accuracy on 5 clips, <2 s inference, real-device mic at 48 kHz, Android
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
