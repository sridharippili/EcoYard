# EcoYard — Project Plan

Companion to `EcoYard_App_Spec.md` and `EcoYard_TechnicalDesign.md`.
Written against the actual state of `github.com/sridharippili/GardenEar` (read 2026-11-14).
Revised 2026-11-14: **Flutter is the framework.** No native Swift app, no native Kotlin app.

**Targets:** iOS and Android from one Flutter codebase. iOS ships first (TestFlight → App Store); Android follows from the same code with platform setup and store work, not a rewrite.

---

## 0. Read this first: conflicts between the design doc and GardenEar

You wrote the technical design as if EcoYard were greenfield. It isn't — GardenEar already does record → identify → journal → map → score. GardenEar is Swift and EcoYard is Flutter, so GardenEar is **rewritten in Dart using its source as the specification**: read the Swift, reproduce the behaviour, fix the known bugs on the way. Never rewrite from memory. These have to be settled before any code gets written.

### 0.1 Identification providers — DECIDED, with two consequences

**Decision:** NatureLM (Kaggle notebook via the Render router) for online identification, BirdNET TFLite on-device for offline once the model is downloaded. GardenEar's existing stack, kept.

That's a reasonable call — NatureLM gives you life stage and call type, which BirdNET can't, and those feed real habitat advice ("there's a juvenile, it needs cover"). But it forces two things you have to accept rather than work around.

#### Consequence 1: the mockup's privacy copy is now false and has to be rewritten

Screen 3 says **"Identified on your phone. Recording deleted."** Screen 5 says the microphone is **"Processed on your phone, then deleted"** and location is **"Not stored."**

With NatureLM as the online default, the audio goes to `gardenear-router.onrender.com` and on to a Kaggle notebook. It is not processed on the phone. And GardenEar's `Sighting` persists `audioPath`, `latitude`, and `longitude` to SQLite, with a whole Map tab built on stored coordinates.

New copy, and write it before you build the screens:

| Screen | Replace with |
| --- | --- |
| Bird Details badge | "Identified online. Audio sent for analysis, not kept." *(or "Identified on your phone" when the on-device BirdNET provider ran — the badge reflects which provider actually answered)* |
| Settings → Microphone | "Only after you tap Identify. Sent to our server for identification when you're online, processed on your phone when offline. Not kept either way." |
| Settings → Location | Either stop storing coordinates, or say "Saved with your sightings so they appear on your map. Stored on this device only." You can't keep the Map tab and claim location isn't stored. |

The badge being provider-aware is the right design. It turns an awkward disclosure into a feature: the user can see when they got the private path.

> You also need a privacy policy URL, correct App Privacy answers in App Store Connect declaring audio collection, and the Play Console Data Safety form. And confirm the Kaggle notebook doesn't write uploaded audio to `/kaggle/working/` — if it does, "not kept" is false. Phase 0, not launch week.

#### Consequence 2: Kaggle cannot be a shipped app's default path

Kaggle's free GPU quota is about 30 hours per week, sessions cap at 12 hours, and a notebook stops after roughly 60 minutes idle. Render's free tier spins services down after inactivity, with a cold start on top.

30 hours a week is 18% of the week, and only while you've manually started the notebook. For you, testing in your own backyard, that's fine. For a stranger who downloads EcoYard on a Tuesday evening, the default identification path is down most of the time. GardenEar's `NatureLMProvider` already throws `"NatureLM is not running. Start Kaggle notebook first."` — that string would be the main thing App Store reviewers and early users see.

Three ways forward:

- **Portfolio / TestFlight.** Kaggle is completely fine. You start the notebook when you're demoing.
- **Flip the default (required for the public release).** Bundle or prompt-download BirdNET TFLite and make on-device the always-works path. NatureLM becomes an opt-in "Enhanced identification" mode that the app health-checks *before* the user records, and greys out when the notebook is down. Nobody ever hits a dead end.
- **Move NatureLM to real hosting.** Modal, Replicate, RunPod serverless, or HF Inference Endpoints. Pay per call or per GPU-second. The only version where NatureLM is a genuine default, and it costs money per user.

Either way, **fix the provider chain**, because GardenEar's (Swift) has a bug:

```swift
if isOnline { return NatureLMProvider() }
else if hasLocalModel { return BirdNETLocalProvider() }
else { return BirdNETProvider() }   // ← requires network, but we're offline here
```

Two problems. The last branch returns a network provider in the offline case, so the "falls back gracefully" comment isn't true. And when NatureLM is reachable but the notebook is down, nothing falls back at all — the user just gets an error. **Do not port this logic as-is.**

In Dart, make it a chain that tries in order rather than a single selection:

```dart
// try in order, fall through on failure, report which one answered
// 1. NatureLM          (online + cached /health passes + enhanced mode on)
// 2. BirdNET local     (model downloaded)
// 3. BirdNET HF Space  (online)
// 4. throw NoProviderAvailable — with copy that explains what to do
```

Run `/health` *before* showing the record button, not after the user has already recorded ten seconds of audio. Cache the result for a few minutes.

### 0.2 Persistence: SQLite, one schema for both platforms

SQLite, accessed from Dart, so iOS and Android share the same schema, migrations, and queries — literally the same code. No platform-specific storage (SwiftData, Core Data, Room) anywhere.

**Package choice is a Phase 1 decision (ask before adding):**
- **drift** — type-safe queries, a real migration API, schema defined once in Dart, testable in-memory. Recommended.
- **sqflite** — thinner, raw SQL, fewer moving parts.

Either way: write migrations as numbered, append-only steps, and keep the schema in plain SQL-compatible types (TEXT ISO-8601 dates, REAL coordinates, TEXT ids) so the file stays readable by any SQLite tool.

### 0.3 "No third-party SDKs in v1" is already false

A Flutter app that records audio and runs TFLite needs packages: `tflite_flutter`, `record`, a SQLite package, an HTTP client, connectivity, location, file paths. Drop that non-goal or you'll trip over it. It should read: **"no analytics, ads, or crash-reporting SDKs."** Every package is added deliberately and listed in `docs/STATE.md`.

### 0.4 The species handoff is the real integration risk

`NatureLMProvider` sends *"What is the common name of the bird species in this audio? Answer:"* and parses free text out of a string like `#0.00s - 10.00s#: Laughing Kookaburra`. No scientific name, no taxon ID, no controlled vocabulary. BirdNET returns `Scientific_Common` labels.

EcoYard's whole value is `bird → how to support it`. That lookup must join on something stable. Free-text common names from a language model will not join reliably — you'll get "Cardinal", "Northern Cardinal", "cardinal (male)", "Red Cardinal", misspellings. Your habitat table will miss.

**You need a `SpeciesResolver` before you need any EcoYard UI.** Spec'd in §5.

---

## 1. Cross-platform strategy — DECIDED: Flutter

One Dart codebase for iOS and Android: UI, logic, persistence, networking, and on-device inference. The mockup is custom-styled rather than platform-native, which is exactly where Flutter renders identically on both platforms with no fight.

| Asset | Cost to build | Shared iOS ↔ Android? |
| --- | --- | --- |
| Content JSON (50 birds, 60 plants, 250 links, tips, actions) | **Weeks** | 100% — data |
| Species alias table | Days, grows forever | 100% — data |
| BirdNET `.tflite` model + labels | Already done | 100% — `tflite_flutter` on both |
| HabitatEngine + SpeciesResolver | ~700 lines | 100% — pure Dart |
| SQLite schema + migrations | Days | 100% — same Dart code |
| Audio capture | Days | ~100% — `record` package; permissions differ |
| UI | **Weeks** | ~100% — one Flutter widget tree |
| Permissions, manifests, store listings, icons | Days | Per platform, unavoidable |

**What it costs:** GardenEar's 37 Swift files are rewritten in Dart up front, including the only working audio-and-ML pipeline you have. Providers are easy (they're HTTP). MapKit becomes `flutter_map` (OpenStreetMap tiles, no API key) or `google_maps_flutter` (API key + billing). That cost is paid once, instead of paying for a second UI later.

**What is NOT allowed:** native Swift or Kotlin feature code. If something seems to need a platform channel, stop and look for a Flutter/Dart-level solution first (another package, `dart:ffi`, a different approach). Platform files are touched only for configuration: `Info.plist`, `AndroidManifest.xml`, Gradle/Podfile settings, entitlements.

### The discipline that keeps the core clean

Flutter already shares the code. These rules keep it **testable and honest**:

1. **A pure-Dart core package with zero Flutter imports.** `packages/ecoyard_core` depends on the Dart SDK only — no `flutter` SDK dependency in its `pubspec.yaml`, no `package:flutter/...` imports, no plugins. Models, `SpeciesResolver`, `HabitatEngine`, `ReferenceRepository` live here. Its tests run with plain `dart test` in seconds. Enforce it in `pubspec.yaml` and a pre-commit check, not by memory.
2. **No platform or UI types in the domain model.** Not Flutter's `Color`, not a location plugin's `Position`, no `DateTime` formatting. Own `Coordinate` class, hex colour strings, ISO-8601 strings.
3. **Content lives in JSON, never in Dart.** No `const plants = [...]` lists in code.
4. **The engine's behaviour is pinned by fixtures.** `fixtures/engine_cases.json` — 20 input/expected-output cases. It's the regression safety net and the definition of correct behaviour. Change it deliberately, never to make a test pass.
5. **Write the engine spec in prose** in `EcoYard_TechnicalDesign.md` — the ranking rules, in English. Reviewers and future-you read the spec, not the code.

---

## 2. App strategy: one app or two?

**Decided: Option 1 — EcoYard is GardenEar's next version.** Keep Record/Journal (Map and Score are an open question, see §9), add Plants / My Plan / habitat engine. One codebase, one listing per store, one review cycle, one 50 MB model. "You heard a cardinal" → "here's how to support it" is one user story, not two apps.

GardenEar (Swift) is frozen as reference and stops being developed.

---

## 3. Target architecture

```
EcoYard/                         (repo root)
├── app/                         Flutter app — iOS + Android
│   ├── lib/
│   │   ├── app/                 AppEnvironment, theme, router, bottom nav shell
│   │   ├── features/
│   │   │   ├── home/            HomeScreen, HomeController
│   │   │   ├── birds/           RecordScreen, BirdDetailsScreen   (from GardenEar)
│   │   │   ├── plants/          PlantFinderScreen, PlantDetailScreen
│   │   │   ├── plan/            HabitatPlanScreen, PlanController
│   │   │   ├── journal/         JournalScreen (+ Map/Score if kept) (from GardenEar)
│   │   │   └── settings/        PrivacySettingsScreen, DataManagementScreen
│   │   └── main.dart
│   ├── assets/                  plant photos, BirdNET labels (model downloaded, not committed)
│   ├── ios/  android/           configuration only — no feature code
│   └── test/                    widget tests
│
├── packages/
│   ├── ecoyard_core/            ← PURE DART. Zero Flutter, zero plugins
│   │   ├── lib/src/models/      Bird, Plant, HabitatAction, Tip, Coordinate, SpeciesMatch
│   │   ├── lib/src/resolver/    SpeciesResolver
│   │   ├── lib/src/engine/      HabitatEngine
│   │   ├── lib/src/reference/   ReferenceRepository (takes JSON strings in, no file I/O)
│   │   └── test/                dart test, runs fixtures/engine_cases.json
│   │
│   └── bird_audio/              Flutter package — device and network concerns
│       ├── providers/           IdentificationProvider + NatureLM, BirdNET local, BirdNET HF
│       ├── chain/               ProviderChain (the §0.1 fallback)
│       ├── audio/               Recorder (48 kHz mono WAV via `record`)
│       ├── inference/           BirdNET runner (`tflite_flutter`, 3 s windows, sigmoid)
│       ├── persistence/         Database, migrations
│       └── system/              Connectivity, model download manager, location
│
├── content/                     birds.json, plants.json, bird_plant.json, actions.json, tips.json,
│                                taxonomy_aliases.json
├── fixtures/engine_cases.json
└── scripts/validate_content.dart
```

Dependency direction is one way: `app` → `bird_audio` → `ecoyard_core`. `ecoyard_core` depends on nothing.

### Layer rules

- Widgets render state and send intents. No business logic, no service calls.
- Controllers own screen state, call services and repositories.
- Services wrap plugins behind abstract classes so tests use fakes.
- `ecoyard_core` knows nothing about Flutter, files, networks, or the screen.

### State management

Decide in Phase 1 (ask before adding a package). Default: Flutter's built-in `ChangeNotifier` / `ValueNotifier` with constructor injection — zero dependencies. Move to Riverpod only if the built-ins start hurting.

### Dependency injection

`AppEnvironment.live()` wires real services; `AppEnvironment.fake()` wires fakes for tests and previews. Everything is passed in through constructors — no global singletons (GardenEar's `.shared` singletons are not carried over).

```dart
abstract interface class ConnectivityChecking {
  Future<bool> get isConnected;
}
```

### Platform floors

- Dart 3, sound null safety, `flutter analyze` with zero warnings from the first commit.
- iOS deployment target 18 (decided). Android `minSdk` set in Phase 1 by what `tflite_flutter` and `record` require.
- Pin the Flutter SDK version in the repo (`.fvmrc` or documented in STATE.md) so builds are reproducible.

---

## 4. The data model — this is the actual project

The Dart is maybe four weeks of evenings, including the GardenEar rewrite. The **content** is the hard part and determines whether the app is good. Budget accordingly.

### 4.1 Five bundled JSON files

```
birds.json       → taxon id, scientific name, common name, aliases[], region tags[],
                   support needs (food / shelter / water / nesting)
plants.json      → plant id, common + scientific name, native ranges[], sun, soil,
                   water need, mature size, bloom window, cost tier, photo asset,
                   photo attribution
bird_plant.json  → join: taxon id → plant ids, with the reason
                   ("seeds for finches", "winter berries + nesting cover")
actions.json     → action id, title, body, cost tier (free / low), season, related plants[]
tips.json        → rotating "Today's Habitat Tip" pool, keyed by month + region
```

Version the schema (`"schemaVersion": 1` at the root of each). You'll thank yourself when you ship region packs.

### 4.2 Where content comes from — and the licensing trap

Do not scrape and bundle someone else's plant database. Check terms before building on any of these:

- **USDA PLANTS Database** — public domain, native distribution by state. Your base layer for "is this native to NJ."
- **Audubon Native Plants Database** — ZIP → plants with bird value. Excellent, but the terms do not permit redistribution. Research source for hand-curation only.
- **National Wildlife Federation Native Plant Finder** — built on Doug Tallamy's host-plant research. Same caveat.
- **Xerces Society** regional pollinator lists — PDFs, check per-document terms.
- **Doug Tallamy's published host-plant rankings** — the research behind your "leave the leaves" tip. Cite it.

Photos: use **Wikimedia Commons CC0/CC-BY** or **USDA PLANTS** images, store the attribution string in `plants.json`, render a credits screen. ~150 KB per plant; 60 plants ≈ 9 MB. One asset folder serves both platforms.

### 4.3 Scope v1 content honestly

| Dataset | v1 target | Why |
| --- | --- | --- |
| Birds | 50 species | ~90% of Eastern US backyard sightings |
| Plants | 60 species | Eastern US natives. NJ/NY/PA/CT first |
| Bird→plant links | ~250 rows | ~5 plants per bird |
| Actions | 25 | Mostly free or low-cost, reusable across birds |
| Tips | 36 | Three per month |

Ship **one region**. Region expansion is a content problem with a solved code path — the best kind of backlog item.

### 4.4 Validation

Write `scripts/validate_content.dart` (Dart, so the repo has one language) that runs in pre-commit when `content/` changes, and in CI, and fails on:
- a `bird_plant` row referencing a missing taxon or plant id
- a plant with no photo asset or no attribution string
- a bird with zero plant links
- duplicate aliases across different taxa
- any file whose `schemaVersion` doesn't match the expected version

Hand-curated JSON rots silently. This is the cheapest quality control you'll ever write.

---

## 5. SpeciesResolver — missing from your design doc

Lives in `ecoyard_core`. Pure Dart.

```dart
enum ResolutionSource { exactLabel, alias, fuzzy, unresolved }

final class SpeciesMatch {
  const SpeciesMatch({
    required this.taxonId,        // stable key, e.g. "norcar" (eBird code)
    required this.scientificName,
    required this.commonName,
    required this.confidence,
    required this.source,
  });
  final String taxonId;
  final String scientificName;
  final String commonName;
  final double confidence;
  final ResolutionSource source;
}

abstract interface class SpeciesResolving {
  SpeciesMatch? resolve({
    required String rawName,
    String? scientificName,
    required double confidence,
  });
}
```

The signature takes primitives, not a provider result type. That keeps `ecoyard_core` free of any dependency on `bird_audio`.

Resolution order:

1. **BirdNET path** — labels are `Scientific_Common`. Split on `_`, look up scientific name. Near-100%.
2. **NatureLM path** — free text. Normalize (lowercase, strip punctuation, strip `(male)`/`(female)`/`juvenile`, singularize), then alias lookup.
3. **Alias table** — bundled `taxonomy_aliases.json`: `"cardinal"`, `"red cardinal"`, `"northern cardinal"`, `"cardinalis cardinalis"` → `norcar`. Seed from eBird/Clements taxonomy, grow from real misses.
4. **Fuzzy fallback** — Levenshtein ≤ 2 against the alias set, only if the top candidate is unambiguous.
5. **Unresolved** — the UI must handle this. Show the raw name, say "We don't have habitat tips for this one yet," offer generic actions. Don't fake it.

**Before writing the normalizer, capture ~50 real NatureLM outputs from GardenEar.** Build against actual strings, not guesses.

Log unresolved strings locally (no network, no PII) so Settings → Manage my data can show them and you can grow the alias table from real usage.

The mockup's `POSSIBLE MATCH · HIGH CONFIDENCE` badge should be driven by **both** provider confidence and resolution source. A fuzzy match at 0.9 provider confidence is not high confidence.

---

## 6. HabitatEngine

`ecoyard_core`. Pure Dart, zero I/O, zero UI, fully fixture-tested. The most valuable thing you will write.

```dart
enum SpaceType { yard, balcony, containers }
enum SunExposure { full, partial, shade }
enum BudgetTier { free, low, any }

final class HabitatEngine {
  HabitatRecommendation recommendations({
    required SpeciesMatch match,
    required SpaceType space,
    required SunExposure sun,
    required BudgetTier budget,
    required String regionCode,
    required int month,
  });
}

final class HabitatRecommendation {
  final List<SupportNeed> supportNeeds;   // food / shelter / water, with the "why"
  final List<HabitatAction> actions;      // ranked, filtered by budget + space + season
  final List<Plant> plants;               // ranked, filtered by sun + space + region
  final bool isGeneric;                   // true when species was unresolved
}
```

Ranking rules — also written in prose in the design doc:

- Free actions always rank above paid. The mockup's "Free first step: leave fallen leaves under shrubs" is exactly right and should be a guaranteed slot.
- Plants serving multiple birds already in the user's journal rank higher.
- Season-appropriate actions first. Don't suggest planting in January in NJ.
- Never more than three actions at once. The mockup gets this right; protect it.

Pin it with `fixtures/engine_cases.json` — 20 input/expected-output cases.

---

## 7. Phases

Each phase ends with something runnable. None longer than three weekends. One phase per Claude Code session.

### Phase 0 — Decisions and setup (one evening)
- Framework (§1) and app strategy (§2) are decided. Providers are decided (§0.1).
- Repo hygiene: GardenEar copied into `reference/GardenEar/` as plain files (no nested `.git`), `CLAUDE.md` at the repo root, git identity set.
- Dev guardrails: lefthook pre-commit / commit-msg / pre-push checks, Claude Code permissions and hooks, the agent definitions.
- Rewrite the three privacy strings from §0.1 into the mockup before any screen gets built.
- Audit the Kaggle notebook: confirm it doesn't persist uploaded audio.
- Amend `EcoYard_TechnicalDesign.md`: Flutter, SQLite, honest non-goals, the discipline rules from §1, the engine ranking rules in prose.
- Draft the privacy policy. It must declare audio leaving the device.

### Phase 0.5 — Flutter BirdNET spike (two days, hard stop, mandatory gate)

Flutter is decided; this proves the riskiest piece works before the real build depends on it. Separate throwaway folder, not this repo.

**Build only this. Nothing else.**

```
record 10s @ 48 kHz mono WAV → chunk into 3s windows (144000 samples)
→ BirdNET TFLite (FP32) → sigmoid → top label
```

No UI beyond a button and a text field. No navigation, no map, no database, no styling.

**Notes before you start:**
- Use `tflite_flutter`, not `tflite_audio`. The audio-specific plugin takes a fixed `float32[16000,1]` tensor and BirdNET GLOBAL 6K V2.4 wants `float32[1,144000]`; it also looks dormant.
- Use the **FP32** model, not the quantized one.
- The `record` package captures 48 kHz directly, so there may be no Dart resampling step at all.
- Test on physical devices, not the simulator/emulator.

**Acceptance criteria:**

1. Correct top-1 label on 5 of 5 known test recordings (clips already verified through GardenEar).
2. Inference under ~2 seconds for a 10-second clip on a real device.
3. Same code runs on an iPhone and an Android phone.
4. No platform-channel Swift or Kotlin needed.

**If it fails:** do not switch frameworks. Diagnose within Flutter — a different TFLite binding, `dart:ffi`, the quantized model with correct int8 input, or online-only identification for v1 with on-device added later. Record what failed in STATE.md's Gotchas.

### Phase 1 — Scaffold + identification pipeline (two to three weekends)
- `flutter create` the app; create `packages/ecoyard_core` (pure Dart, **zero dependencies** — that emptiness is the architecture) and `packages/bird_audio`.
- Decide and add (with approval): SQLite package, state management approach, HTTP client.
- Rewrite in Dart from `reference/GardenEar/`: the three providers, recorder, BirdNET runner (from the spike), connectivity, model download manager, database + first migration.
- **Build the provider fallback chain from §0.1**, with a cached `/health` probe. The highest-value hour in the phase.
- `AppEnvironment.live()` / `.fake()`.
- First tests: the chain with a fake connectivity checker and a failing NatureLM — assert it lands on BirdNET local rather than throwing.
- Acceptance: record → identify → save a sighting works on an iPhone and an Android phone.

### Phase 1.5 — GardenEar screens (one to two weekends)
- Rewrite Record and Journal screens from GardenEar. Map and Score only if §9 says keep them.
- Acceptance: everything GardenEar did that we're keeping, now in Flutter, on both platforms.

### Phase 2 — Content + SpeciesResolver (two to three weekends)
- Define the five JSON schemas with `schemaVersion`. Hand-curate a vertical slice: **10 birds, 15 plants**. Not the full set.
- `ReferenceRepository` in `ecoyard_core` — takes JSON strings in, no file I/O (the app loads assets and hands them over).
- `SpeciesResolver` + seed alias table, built against 50 real NatureLM output strings captured from GardenEar.
- `validate_content.dart` in pre-commit and CI.

### Phase 3 — HabitatEngine (one weekend)
- Pure logic + the 20-case fixture suite.
- At the end of this phase you can print a full recommendation from a species name with `dart run`. That's the whole product, headless.

### Phase 4 — Bird Details + My Plan (two weekends)
- `BirdDetailsScreen` wired to the identification result. This is the moment the two apps become one product.
- `HabitatPlanScreen` + plan persistence (`plan_actions`, `plan_progress` tables), written as a proper migration.
- "Add these to my plan" → progress → checkbox state.

### Phase 5 — Plant Finder + Home (two weekends)
- `PlantFinderScreen` with three filter pickers over `ReferenceRepository`.
- `PlantDetailScreen`.
- `HomeScreen` with the tip engine. Ship Home without the weather card first.

### Phase 6 — Privacy & Settings (one weekend)
- Build the Settings screen exactly as drawn. Per-permission toggles with plain-language explanations are the best thing in the design.
- `Manage my data` — real counts, real deletion.
- `Delete my data` — must actually wipe SQLite, cached audio, and the downloaded model.
- Onboarding (3 screens max, permission priming before the system prompts on both platforms).

### Phase 7 — Weather, notifications, polish (two weekends)
- Weather via a cross-platform HTTP API (e.g. Open-Meteo — free, no key) behind a `WeatherProviding` interface in the app layer; never in `ecoyard_core`. If it becomes a hassle, cut it; the app works without weather.
- Coarse location only (approximate accuracy on both platforms). To keep "approximate · not stored" true: round to ~2 decimals, hold in memory, never write it.
- Weekly reminder via local notifications, off by default as drawn.

### Phase 8 — Content scale-up and iOS ship (three to four weekends)
- Grow to 50 birds / 60 plants in batches of 10 with the validator running.
- Accessibility: large text scaling, `Semantics` labels on every icon button, 4.5:1 contrast. Check the orange "Low cost" badges specifically — they're the risk.
- Screenshots, App Store copy, privacy nutrition labels, TestFlight with 5–10 real users, then App Store.

### Phase 9 — Android release (two to three weekends)
- No rewrite. Same code. Work is: device testing across a few Android phones, permissions and manifest polish, adaptive icon, Play Console Data Safety form, internal testing track, Play Store listing.

**Realistic total: ~19–24 weekends for both platforms.** The GardenEar rewrite is paid up front; the native plan's separate 10–12 weekends of Kotlin + Compose later disappear.

---

## 8. Risks, ranked

| Risk | Likelihood | Mitigation |
| --- | --- | --- |
| **NatureLM unavailable for real users** | **Very high** — 30 GPU-hrs/week, 12-hr sessions, 60-min idle stop, manual start | Fallback chain (§0.1), health check before recording, on-device default for public release |
| Content curation stalls the project | **High** | Vertical slice of 10 birds in Phase 2. Prove the loop before scaling |
| Species resolution misses too often | **High** — NatureLM free text is the primary online path | SpeciesResolver + alias table + honest "no tips yet" state. Collect 50 real outputs first |
| GardenEar rewrite in Dart drags | **Medium** | Rewrite only what's kept; use the Swift source as the spec; spike first proves the hardest part |
| On-device BirdNET doesn't work well in Flutter | **Medium** | Phase 0.5 spike before any real code |
| Shipping privacy copy that isn't true | **Medium** | Rewrite the three strings in §0.1 before building the screens. Provider-aware badge |
| `ecoyard_core` purity erodes under deadline | **Medium** | No Flutter dependency in its pubspec; pre-commit check rejects `package:flutter` imports there |
| A key Flutter plugin goes unmaintained | **Medium** | Keep plugins behind interfaces in `bird_audio` so one can be swapped without touching features |
| Plant data licensing | **Medium** | Hand-curate from USDA (public domain). Never bundle Audubon/NWF data |
| Kaggle notebook persists uploaded audio | **Medium** | Audit the notebook. If it writes to `/kaggle/working/`, "not kept" is false |

---

## 9. What I'd change in the mockup

Strong design — restrained, honest, and the privacy screen is better than most shipping apps. Four notes:

1. **"Identified on your phone. Recording deleted."** — false with NatureLM online. Make the badge provider-aware (§0.1) so it tells the truth in both modes. Add a third state for when identification failed entirely because no provider was reachable.
2. **Six tabs is too many** once GardenEar merges in (Home, Plants, Birds, My Plan, Settings, plus Journal/Map/Score). Fold Map and Score into Journal as segmented views; put Journal under Birds. Android's bottom nav caps at five too, and with Flutter it's literally the same nav bar on both. **Open question:** keep Map and Score this way, or cut them.
3. **No empty states drawn.** Design the zero state for My Plan, Plant Finder with no results, and Bird Details for an unresolved species — those are what a new user sees first.
4. **"3 actions added" banner** should be transient. As drawn it looks permanent and will read as stale on the second visit.

---

## 10. Immediate next step

Framework (Flutter), providers, and app strategy are settled.

1. Phase 0: repo hygiene, guardrails and agents, privacy copy rewrite.
2. Phase 0.5: the BirdNET spike on a real iPhone and a real Android phone.
3. Then Phase 1 — scaffold, provider chain, identification pipeline — as a single Claude Code session.

Open: keep or cut Map and Score (§9).
