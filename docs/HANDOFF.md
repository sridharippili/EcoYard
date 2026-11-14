# EcoYard — handoff brief

Everything decided in planning, in one place. Hand this to Claude Code
as the first message of a fresh session.

---

## What EcoYard is

A backyard habitat app. You record a bird sound, it identifies the
species, and it tells you concrete, mostly-free things you can do to
support that bird — native plants to put in, a water source, leaving
leaf cover. Actions go into a personal habitat plan with progress
tracking. Strong privacy posture, no account, works offline.

It supersedes **GardenEar** (github.com/sridharippili/GardenEar), an
existing native SwiftUI app that already does record → identify →
journal → map → biodiversity score. GardenEar's working parts get
ported, not rewritten from memory.

Design: `EcoYard_UI_Mockup.png` — five screens (Home, Native Plant
Finder, Bird Details, My Habitat Plan, Privacy & Settings). Custom
styled, not platform-native.

---

## Decided

| Decision | Detail |
| --- | --- |
| **Identification — online** | NatureLM via Render router → Kaggle notebook (`gardenear-router.onrender.com`). Returns free-text common name, no scientific name |
| **Identification — offline** | BirdNET GLOBAL 6K V2.4 TFLite on-device. Returns `Scientific_Common` labels |
| **Persistence** | SQLite. **Not** SwiftData — it's Apple-only and won't port to Android |
| **Android** | A real future target, reached by porting a pure-logic layer, not by rewriting |
| **Repo** | New repo `EcoYard`, with GardenEar copied in under `reference/` as read-only source to port from |
| **Scope** | One product, one app. EcoYard replaces GardenEar |
| **Content region** | Eastern US / Northeast only for v1 |

## NOT decided — resolve before building

1. **Flutter or native Swift.** Leaning Flutter for the Android path.
   A two-day spike exists to settle it with evidence (see below). Do
   not start the real app until the spike returns a verdict.
2. Public App Store release, or portfolio/TestFlight only. This
   decides whether NatureLM can remain the default path.
3. Whether to keep GardenEar's Map and Score screens, or cut them to
   hold the bottom nav to five tabs.

---

## Do this first: the Flutter spike

Two days, hard stop, in a **separate throwaway repo**.

```
record 10s @ 48kHz mono WAV → chunk into 3s windows (144000 samples)
→ BirdNET TFLite → sigmoid → top label
```

Files already written: `SPIKE_README.md`, `pubspec.yaml`,
`lib/main.dart`. Untested — nobody has run them.

Use `tflite_flutter`, not `tflite_audio` (the latter takes a fixed
`float32[16000,1]` tensor; BirdNET wants `float32[1,144000]`, and it
looks dormant). Use the **FP32** model, not the quantized one.

Notable: the `record` package captures 48 kHz directly, so there is no
Dart resampling step. That was the main technical risk and it may
simply not exist.

**Acceptance — all four or it failed:**
1. Correct top-1 on 5 of 5 clips already verified through GardenEar
2. Inference under ~2s for a 10s clip on a real device
3. One codebase running on an iPhone and an Android phone
4. **No platform-channel Swift or Kotlin needed** ← the deciding one

If it fails, go native Swift (iOS 18, Swift 6) and don't revisit.

---

## Two problems that will bite, whichever framework wins

### 1. Species resolution is load-bearing

NatureLM returns free text parsed out of strings like
`#0.00s - 10.00s#: Laughing Kookaburra`. No scientific name, no taxon
ID, no controlled vocabulary. You'll get "Cardinal", "Northern
Cardinal", "cardinal (male)", "Red Cardinal", misspellings.

The whole product is `bird → how to support it`, and that join needs a
stable key. Build a **SpeciesResolver** before any habitat UI:

1. BirdNET path: split `Scientific_Common` on `_`, exact lookup
2. NatureLM path: normalize (lowercase, strip punctuation, strip
   `(male)`/`(juvenile)`, singularize), then alias lookup
3. Bundled alias table → eBird taxon codes (`norcar` etc.)
4. Fuzzy fallback: Levenshtein ≤ 2, only if unambiguous
5. Unresolved → show the raw name, say "no habitat tips for this one
   yet", offer generic actions. Never fake a match.

**Before writing the normalizer, capture ~50 real NatureLM outputs
from GardenEar.** Build against actual strings, not guesses.

### 2. The privacy copy in the mockup is false

The mockup says "Identified on your phone. Recording deleted" and
"Location: not stored". With NatureLM online, audio goes to a server.
And GardenEar persists `audioPath`, `latitude`, `longitude`, with a
Map tab built on stored coordinates.

Fix: make the badge **provider-aware** — "Identified on your phone"
when the on-device model answered, "Identified online, audio not kept"
when NatureLM did. Rewrite the Settings strings to match. Also audit
the Kaggle notebook so it isn't persisting uploads.

Separately: Kaggle free tier is ~30 GPU-hours/week, 12-hour session
cap, ~60-minute idle stop, and needs manual starting. That's fine for
demos, unusable as a shipped app's default. For a public release,
flip the default to on-device and make NatureLM opt-in "Enhanced
identification", health-checked *before* the record button appears.

### 3. Fix the provider chain — the current one has a bug

GardenEar's selection logic:

```swift
if isOnline { return NatureLMProvider() }
else if hasLocalModel { return BirdNETLocalProvider() }
else { return BirdNETProvider() }   // network provider, but we're offline
```

The last branch returns a network provider in the offline case. And
when NatureLM is reachable but its notebook is down, nothing falls
back. Replace with a chain that tries in order and falls through:

```
NatureLM (online + cached /health passes)
  → BirdNET local (model downloaded)
  → BirdNET HF Space (online)
  → fail honestly
```

Do not port this logic as-is.

---

## Architecture rules — non-negotiable

These are what make the Android port cheap. They decay first under
deadline pressure, so enforce them structurally.

1. **A pure logic layer with ZERO dependencies.** Models,
   SpeciesResolver, HabitatEngine, ReferenceRepository. Foundation
   only in Swift; no Flutter imports in Dart. Let the build system
   enforce it.
2. **No platform types in the domain model.** Own `Coordinate` struct,
   hex colour strings, ISO-8601 strings. Never `CLLocationCoordinate2D`
   or `Color`.
3. **Content lives in JSON, never in code.** No hardcoded arrays of
   plants, birds, actions, tips.
4. **Behaviour pinned by `fixtures/engine_cases.json`** — ~20
   input/expected-output cases. This file is the acceptance test for
   any future port. Change it deliberately, never to make a test pass.
5. **SQLite schema must be readable by Room/SQLDelight later.**

---

## The content is the actual project

The code is roughly three weeks of evenings. The content is the rest,
and it determines whether the app is any good.

Five bundled JSON files, each with a `schemaVersion`:
`birds.json`, `plants.json`, `bird_plant.json`, `actions.json`,
`tips.json`.

v1 targets: 50 birds, 60 plants, ~250 join rows, 25 actions, 36 tips.
**Start with a vertical slice of 10 birds and 15 plants** and prove
the whole loop before scaling.

**Licensing — do not get this wrong.** USDA PLANTS is public domain
and is your base layer. Audubon's and NWF's native-plant databases are
excellent but their terms do not permit redistribution — research
sources for hand-curation only, never bundled. Plant photos from
Wikimedia Commons CC0/CC-BY or USDA, with the attribution string
stored in `plants.json` and a credits screen.

Write `scripts/validate_content` and run it in CI. Fail on: join rows
pointing at missing ids, plants with no photo attribution, birds with
zero plant links, duplicate aliases across taxa, schemaVersion
mismatches. Hand-curated JSON rots silently.

---

## Working agreement for Claude Code sessions

- **One phase per session.** Stop at the boundary and say so.
- Read `docs/STATE.md` at session start; read only the relevant
  *section* of `docs/PLAN.md`, never the whole file.
- Append one line to `docs/STATE.md`'s Changelog per change. Append,
  don't rewrite.
- Build must pass before appending to the Changelog.
- Ask before adding any third-party dependency.
- Don't refactor outside the current phase's scope.
- Anything that cost more than 15 minutes goes in STATE.md's Gotchas.

## Repo state right now — needs fixing

The initial commit went wrong:

- GardenEar was cloned to the repo root and committed as a **submodule**
  (`mode 160000`), so none of its source is actually readable
- `CLAUDE.md` is in `docs/`; it must be at the repo root to auto-load
- `docs/PLAN.md` was never committed
- `gh` isn't installed, so nothing was pushed
- git identity defaulted to the machine hostname

Fix before starting Phase 1.

## Files that exist

| File | What it is |
| --- | --- |
| `docs/PLAN.md` | Full plan, ~5000 words, phases 0–9. Read by section |
| `docs/STATE.md` | Working memory. Decisions, open questions, gotchas, changelog |
| `docs/PROMPTS.md` | Copy-paste session prompts |
| `CLAUDE.md` | Short rules file, auto-loaded every session |
| `EcoYard_UI_Mockup.png` | The five screens |
| `reference/GardenEar/` | Read-only source to port from. Never built |
| spike files | `SPIKE_README.md`, `pubspec.yaml`, `lib/main.dart` |

---

## Realistic timeline

15–19 weekends for a native iOS v1, including content. Flutter
removes the later ~6–8 weekends of Compose UI but costs the GardenEar
Swift port up front.

The failure mode to watch for is not picking the wrong framework. It's
replanning instead of shipping.
