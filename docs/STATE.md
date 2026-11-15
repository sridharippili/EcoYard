# EcoYard — State

The working memory for this repo. Keep it short. If this file passes
~200 lines, compress the Changelog (see Maintenance at the bottom).

---

## Current state

- **Phase:** 6.5 — Offline identification IN PROGRESS: Gate 1 (model runs in the app) PASS, Gate 2 (WAV accepted) PASS for BirdNET online, NatureLM untested (notebook off). Phase 6 committed; Phases 1-5 committed. Next planned: Phase 7 (weather, notifications, polish). User asked (after Phase 6) for an offline-model download in Settings: see Open items, it reverses the v1 online-only decision and needs approval
- **Status:** Settings tab: saved defaults (space/sun/budget), privacy facts, Manage my data (real counts, copy as JSON), Delete my data (one transaction, VACUUM, returns to first launch), draft privacy policy, About (sources from content), 3-screen onboarding. Tab bar is a floating frosted-glass pill (`GlassNavBar`). Verified in the iOS Simulator (real v1->v2 DB migration, real erase)
- **Build:** app 229 + ecoyard_core 235 (+1 opt-in skipped) + bird_audio 131 tests, analyzers clean
- **Release gate:** `scripts/release_check.sh` fails until every content file is `reviewed` with `reviewedBy`/`reviewedOn` and every plant has a real photo. It is NOT wired into CI/hooks (guarded files): the user should add it to the release workflow
- **Setup after clone:** `scripts/setup.sh` (enables `.githooks/`)

## Known gaps (UI) — see docs/ENGINE_SPEC.md

- A need can have no remedy now (`NeedCoverage.hasRemedy == false`). Show "nothing to do this month" and point at `laterActionIds` ("try in spring"); never show a bare need. A remedy that exists but is not among the three shown is "also possible" (`coveredByShownActions` false, `remedyActionIds` not empty)
- Plants are not month-filtered. Do not imply "plant now" from the plant list
- `plantsHiddenByFilters` > 0 or an empty plant list in shade: say "no plant fits this sun" / "N more need different sun"
- The UI maps a state (NJ) to region `us-ne` before calling the engine; any other region throws
- Engine needs are coarse (every bird has food/shelter/nesting/water/safety). Signature actions are marked by hand with `featuredForBirdIds` in `content/actions.json` (seed heads: goldfinch; nest box: chickadee, titmouse, wren; dead wood: downy, nuthatch). Any new action that is the point of a species needs the same
- The engine may return FEWER than three actions (no padding: after the free first step an action must cover a need not yet covered). A hummingbird on a balcony in July gets one. The UI must cope with 1-3
- A need blocked only by budget has `moreBudgetActionIds` ("a small budget would unlock..."); one blocked by season has `laterActionIds`. Use them instead of "nothing can help"
- A plant is never linked for `nesting` unless it gives nesting cover soon after planting (shrubs, vines), never trees
- Content rows a person must check before release: tip-mar timing wording, `norcar`/`northern-spicebush`, `carwre`/`white-oak` weight, plus everything (all content is unreviewed)

## Known gaps from Phase 6

- **Deviations from spec 4.5 / 6.x (deliberate):** no toggles for approximate location, progress data or research sharing (each would control nothing: no location use, plan is always saved, no sharing exists); no in-app microphone toggle (opening iOS Settings needs a plugin; the text points to iPhone Settings); export is "Copy my data" to the clipboard, not a share sheet (needs a package); About has no photo credits yet; "21 bird names" counts are plan actions/birds (there is no sightings journal)
- Footer "No ads. No analytics in the app. We don't sell your data." and the privacy policy are DRAFT wording: the owner (and ideally a lawyer) must confirm them; the draft labels follow `repo.reviewStatus`
- `Documents/ecoyard.db` can be in iCloud backups; "Delete my data" cannot erase older backups (the dialog and policy say what it does not erase). Audio sent to NatureLM/BirdNET is outside the app: never claim it is deleted or "not kept" until both are audited
- A VACUUM failure after a committed erase is ignored (best effort); no test forces it
- `Shell` does not close a storage open that is still in flight at dispose (harmless)
- Glass tab bar: lists scroll behind it; every tab list uses `tabListPadding(context)` (adds `MediaQuery.padding.bottom`). A new tab screen must do the same or its last item hides behind the bar

## Known gaps from Phase 5

- Deferred from the spec: plant "Add to my plan" (needs plan migration 2 + a plan-item kind), Water-Saving Tips tile (needs a forecast), weather card and weather-based tips, location row "Change"/ZIP (region is static text), header notifications button, plant photos and credits ("Photo coming soon" placeholder), care guidance beyond size/water/sun/bloom, tip choice by space type
- Finder budget rule differs on purpose from the bird advice: the Finder shows a plant when its own `costTier` is allowed by the budget (so "Free only" shows none while every plant is `low`); `HabitatEngine` never offers plants on a free budget. `BudgetTier.any` == `low` while there are two cost tiers (a test fails loudly when a third is added)
- `PlantFinder` lists every plant, linked or not (an unlinked plant ranks last). The engine's generic mode would drop unlinked plants (black-chokeberry): do not swap it in
- Draft wording on Plants/Home/Detail follows `repo.reviewStatus` (draft while ANY content file is draft)
- `nativityLabel` says "Native to the Northeast" for any region: make it region-aware before a second region exists
- Home is stateless and reads the clock in `build`: a month change while the app stays open shows the old tip until Home rebuilds
- My Plan's "See native plants" always resets the Finder to defaults (documented rule), even for an action about shade/balcony plants

## Known gaps from Phase 4

- Deferred from the spec: weekly reminder toggle (needs a notifications package, Phase 7), bird photo, reference-call player, sightings/journal (engine `journalBirdIds` is passed empty), "See native shrubs" link (Plants tab is a placeholder)
- Space/sun/budget are session-only chips ("For this suggestion"), not stored (Settings, Phase 6). Budget offers Free / Free + low cost only: `BudgetTier.any` behaves the same as `low` while there are two cost tiers
- Advice runs on the TOP detection only. An unknown bird gets general advice with no "add to plan" (the plan is keyed by bird id). A medium/low-confidence second detection is only listed under "Also heard"
- A fuzzy (misspelled) name with no provider score is `low` confidence (resolver rule), so it gets no advice: NatureLM gives no score, so this matters if it misspells
- (Fixed in Phase 5) Home used to overflow at 320 px + 2x text; Home, Plants, Detail, Birds result and My Plan are now tested at 320/420 px and 1x/2x text
- The database sits in iOS `Documents/ecoyard.db`, which iCloud backup can include. Revisit with the Phase 6 privacy screen ("Delete my data" = `PlanStore.clear()`, already there, no UI)
- Adding to the plan dismisses the identification result (clip dropped): "back" shows an empty Birds tab. Intentional for now
- The result card is always light green; the advice inside it is forced to the light theme so it stays legible in dark mode (tested). A proper dark card is a design task

## Open items (need a human or a later phase)

- **Promote the engine fixtures:** read `packages/ecoyard_core/test/engine_cases.draft.json` (especially the `why` of c02, c11, c19), then run the promote commands in docs/ENGINE_SPEC.md. Until then the engine is pinned only by a draft I wrote

- **Offline model (Phase 6.5), planned and decided, not started (2026-11-14):** see `docs/OFFLINE_MODEL_PLAN.md`. Approved: `tflite_flutter` + `crypto`, offline-first, cache directory, fall through to online when the phone model hears nothing. WAITING ON THE USER: host the model (51.7 MB) and label files at URLs they control and send them (needed from step 4; Gate 1, the in-app proof, can use the spike's local copy). Gates: (1) tflite loads and runs in the app, (2) both online services accept WAV. Licence CC BY-NC-SA 4.0 stays a release-gate item
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
- 2026-11-14 — Plan storage: `sqflite` (+ `sqflite_common_ffi` dev only, for tests) approved by the user. Tables `plan_actions` + `plan_action_birds`; PLAN.md's `plan_progress` is derived instead of stored. Each row keeps a snapshot of the action's title/body/cost, so reworded or removed content never changes or breaks a saved plan. Re-adding a done action keeps it done and adds the bird; the banner counts only newly added actions. Region is fixed `us-ne` (the content's region)
- 2026-11-14 — Stored timestamps are UTC ISO-8601 with exactly 3 fractional digits (`stampFor`), one millisecond apart per action in a single add, so text order = time order. The plan view compares parsed times anyway
- 2026-11-14 — Confidence tiers on screen: high/medium resolved -> advice; low resolved -> "couldn't identify"; unresolved bird -> general advice only if provider score is null or >= 0.4, else "couldn't identify"; non-bird -> "something other than a bird"
- 2026-11-14 — Phase 5: Plant Finder logic is a pure `PlantFinder` in ecoyard_core (all plants, ranking by summed link weight then cost then id, hidden count), not the engine's generic mode. Shell owns one `PlantFinderController`: the Plants tab button keeps the user's filters; "Find Native Plants" and My Plan's link reset to defaults; "Small Space" sets Balcony. Home = greeting, Identify, 3 tiles, month tip
- 2026-11-14 — Phase 6: one shared SQLite file for plan + settings (`AppStorage`, migration 2 = settings table; migration 1 untouched). Defaults only seed the Plants filters and a NEW bird result; presets (Small Space = Balcony) override for that visit and never write back; an untouched Plants tab follows a changed default, a touched one keeps its choice. Delete my data = plan + settings in one transaction + VACUUM + leftover-recording sweep, and returns the app to first launch (introduction shows again). Saves are serialised; a save after a failed load re-reads first and never writes defaults over unreadable stored values
- 2026-11-14 — UI: bottom tab bar is a floating frosted-glass pill (`GlassNavBar`, BackdropFilter, no new package). GardenEar's tab bar was opaque, so this is new, per the user's request
- 2026-11-14 — Offline identification will be built as Phase 6.5 (user request), reversing "v1 is online only" for users who download the model. Decisions: offline first when ready; cache directory; hears-nothing falls through to online; Delete my data removes the model; per-result privacy badge derived from facts (any network attempt), never from an id string. Packages tflite_flutter + crypto approved

## Open questions

- ~~Native Swift or Flutter?~~ Resolved 2026-11-14: Flutter (spike still gates the real build)
- ~~Public release or portfolio only?~~ Resolved 2026-11-14: portfolio → TestFlight → public App Store. On-device BirdNET becomes the default for the public release
- Keep the Map and Score screens, or cut them to hold the tab bar to five?

## Architecture map

Only the parts that exist. Add rows as they are built.

| Module | Purpose | Status |
| --- | --- | --- |
| `app/` | Flutter app (iOS + Android): Home, Plants (+ detail), Birds (+ advice panel), My Plan, Settings (+ onboarding), glass tab bar | all five tabs built |
| `packages/ecoyard_core` | Pure Dart, zero runtime deps (dev: `test`). Models, ReferenceRepository, content validator, SpeciesResolver, HabitatEngine, plan view, PlantFinder | Phases 2-5 done |
| `packages/bird_audio` | Providers + fallback chain, recorder, AppStorage (plan + settings, SQLite + numbered migrations), audio sweep | Phases 1, 4, 6 done |
| `content/*.json` | birds, plants, bird_plant, actions, tips, taxonomy_aliases (all `schemaVersion` 1) | 10 birds, 15 plants, 40 links, 10 actions (priority + optional forBirdIds), 12 tips — DRAFT |
| `scripts/validate_content.dart` | Content checks; same normalizer as the resolver; `--strict` = release gate | done |
| `scripts/recommend.dart` | Prints a recommendation from a bird name (resolver + engine) | done |
| `app/assets/content/` | Copies of `content/*.json` for bundling; `scripts/sync_content.sh` copies, `app/test/bundled_content_test.dart` fails on drift | done |
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

- sqflite shares ONE connection per database path: closing a second handle to the same file closes the store's too (bit a test). Tests that peek at the file must not close their handle until the store is closed
- ISO-8601 strings with different fractional digits do NOT sort as text (`.000Z` sorts after `.000001Z`). Never `compareTo` stored dates; use `stampFor` / parse them
- `setState(() => x = future)` throws (callback returned a Future): use a block body. Hit in the content-retry button
- Widget tests: set a tall surface (`pumpApp` does) or long result lists sit below the fold and taps miss; `pumpAndSettle` never returns while a spinner is on screen (use `pump(duration)`)

- `tflite_flutter` adds CocoaPods to app/ios: always build iOS with the rbenv Ruby on PATH (`export PATH="$HOME/.rbenv/versions/3.3.13/bin:$PATH" LANG=en_US.UTF-8`). Reinstalling the app in the simulator can move its data container: never bake a container path into a build, resolve it at run time

---

## Changelog

Newest first. One line each: date, what changed, where.

- 2026-11-14 — Phase 6.5 gates: `tflite_flutter` 0.11.0 added to bird_audio (approved), `BirdModelRunner`/`TfliteRunner` (load from a plain file); CocoaPods now integrated in app/ios (Podfile, xcconfigs, pbxproj; the pbxproj also carries the user's DEVELOPMENT_TEAM). Gate 1 PASS in the simulator (129 ms load, ~33 ms per 3 s window, debug); white noise -> a European woodpecker at 0.46, so a regional filter/higher floor is needed (Decision F). Gate 2: BirdNET online accepts WAV (control with garbage fails), 14.7 s at ~0.5 Mbit/s; NatureLM untested
- 2026-11-14 — Offline-model plan written and critic-reviewed (docs/OFFLINE_MODEL_PLAN.md); five decisions recorded; no code yet. Critic found: badge must derive from facts + property test, WAV change touches AudioClip/recorder/AudioCache regex/tests (privacy regression if the sweep regex is missed), chain rules for load/timeout/isolate, download races/redirects, measurable acceptance, validator + release-gate rules for offline_model.json
- 2026-11-14 — Phase 6: AppSettings/DataSummary/exportMyData (core), migration 2 + AppStorage/SettingsStore/AudioCache (bird_audio), Settings screen + Manage/Delete/Policy/About + onboarding + SettingsController (app), `FileMeta.sources`. Critic (start): delete wording, atomic wipe, v1->v2 test first, defaults vs presets, onboarding scope (all done). Reviewer: VACUUM best-effort, onboarding save failure dead end, serialised saves, no default-overwrite after failed load, sweep after first frame (all done). Found by tests: setState-with-Future in Manage retry, hung-DB spinner (5 s timeout). Glass tab bar added at the user's request. Mutation-checked (14 caught, 1 dead-code removed). Spec deviations in Known gaps from Phase 6
- 2026-11-14 — Phase 5: pure `PlantFinder` (+15 tests, counts cross-checked against the JSON), `PlantFinderController`, Plants tab + Plant Detail, Home with the real monthly tip (weather card, sample JSON and Water-Saving tile removed), My Plan "See native plants" link. Critic (start): engine generic mode drops unlinked plants (own finder), free-only empty state, native/draft wording from data, preset rules, dead-end detail (all done). Reviewer: draft wording from all files, tip draft marker, label wrap at 2x text, explicit checkmarks (done). Found by tests: Home tile row infinite height, header + photo placeholder overflow at 2x. Mutation-checked (6 caught, 1 equivalent). [scope] items in Known gaps from Phase 5 deferred
- 2026-11-14 — App icon: revised artwork (softer tail, darker leaf, visible circle, legs, sound arcs; inside the Android safe zone) in `docs/design/app_icon.svg` + `app_icon_1024.png` (opaque, no alpha), installed in `app/ios/Runner/Assets.xcassets/AppIcon.appiconset` (all sizes via `sips`). Android adaptive icon (foreground + background) not made yet; no package added
- 2026-11-14 — Phase 4: plan domain (core `plan.dart`), SQLite `PlanStore` + migrations (bird_audio, new packages sqflite / sqflite_common_ffi approved), content bundled as assets with drift test, content/DB failure states, BirdDetailsPanel under the Birds result, My Plan screen. Critic (start): required snapshot rows, add semantics, no false copy, failure states (all done). Reviewer: dark-mode legibility, controller dispose/double-init, same timestamp per add, non-atomic load, missing drift test (all fixed). Edge-case pass found and fixed: ISO text-sort bug, `add`/`load` threw synchronously on a closed store, same action twice in one add, no-actions state showing a dead button, double-tap, Try again/Done row overflow at 2x text. Mutation-checked (12 mutations caught). [scope] reminders/photo/call player/journal deferred; Home overflow at 320px left
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
