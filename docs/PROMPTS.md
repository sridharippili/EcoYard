# Claude Code session prompts

Copy-paste these. One phase per session, then `/clear`.

---

## Before you open Claude Code

Set the repo up by hand. It's five minutes and it avoids an agent
guessing at your folder layout.

```bash
mkdir EcoYard && cd EcoYard
git init

# the old codebase, as read-only reference to port from
mkdir reference
cp -R /path/to/GardenEar reference/GardenEar
rm -rf reference/GardenEar/.git

mkdir -p docs Packages
# drop CLAUDE.md in the root, PLAN.md / STATE.md / PROMPTS.md in docs/

git add -A && git commit -m "Initial: docs and GardenEar reference copy"
```

`reference/GardenEar/` is source to read and port from. It is never a
build dependency and never gets compiled.

---

## Phase 1 — scaffold the app and split the packages

```
Read CLAUDE.md and docs/STATE.md, then read ONLY the "Phase 1" section
and section 0.1 of docs/PLAN.md. Do not read the rest of the plan.

This is a fresh repo. reference/GardenEar/ is a read-only copy of my
previous app — port from it, don't build it, don't modify it.

Work in this order, building after each step:

1. Scaffold a new iOS app target named EcoYard via xcodegen.
   iOS 18 deployment target, Swift 6 language mode, bundle id
   com.sridharippili.ecoyard. Add SQLite.swift via SPM and
   TensorFlowLiteSwift via CocoaPods, matching the versions in
   reference/GardenEar/project.yml and Podfile.
   Acceptance: empty app builds and launches in the simulator.

2. Create Packages/EcoYardCore as a local SPM package with ZERO
   declared dependencies. Leave it empty apart from a placeholder.
   The emptiness is the point — it's the Android boundary.

3. Create Packages/BirdAudioKit as a local SPM package. Port into it
   from reference/GardenEar/GardenEar/Services/:
   the four providers, AudioIdentificationService, NetworkMonitor,
   OfflineModelManager, and Database/DatabaseManager.swift.
   Fix Swift 6 strict-concurrency diagnostics as you go — Sendable
   conformances and actor isolation on the three singletons and on
   the @MainActor static var provider.

4. Add protocols for the three singletons and build AppEnvironment
   with .live() and .preview() factories.

5. Replace provider selection with the fallback chain from section 0.1:
   NatureLM (online + cached /health passes) → BirdNET local (model
   downloaded) → BirdNET HF Space (online) → throw .noProviderAvailable.
   Surface which provider answered in IdentificationResult.
   Do NOT copy the existing selection logic — it returns a network
   provider in the offline branch.

6. Port RecordView and RecordViewModel into the app target as the only
   screen, wired to AppEnvironment. Nothing else yet — no Journal,
   no Map, no Score.

Acceptance: EcoYard builds, records audio, identifies a bird, and shows
the result. Plus unit tests for the fallback chain using a fake
NetworkMonitoring and a fake failing NatureLM — assert it lands on
BirdNET local rather than throwing.

Stop at the end of Phase 1. Append your Changelog lines to
docs/STATE.md and update the Current state block.
```

---

## Generic phase template

Reuse this for Phases 2 onward.

```
Read CLAUDE.md and docs/STATE.md, then read ONLY the "Phase N" section
of docs/PLAN.md. Do not read the rest of the plan unless a specific
question requires it, and say so if you do.

Implement Phase N. Build after each meaningful step.

Rules from CLAUDE.md apply — especially EcoYardCore's zero dependencies.

Stop at the phase boundary. Then:
- Append one Changelog line per change to docs/STATE.md
- Update the Current state block
- Add any new module to the Architecture map
- Add anything that cost you more than 15 minutes to Gotchas
```

---

## Porting a screen from GardenEar (Phases 4–5)

```
Port <SCREEN> from reference/GardenEar/GardenEar/Screens/<X>/ into the
EcoYard app target.

Rules:
- Don't copy verbatim. The old code predates AppEnvironment and Swift 6.
- Any business logic goes to EcoYardCore or BirdAudioKit, not the View.
- Check the screen against EcoYard_UI_Mockup.png — EcoYard's design is
  not GardenEar's.
- Flag anything in the original that looks wrong rather than porting
  the bug.
```

---

## Phase 0.5 — Flutter spike (only if you're doing it)

Run this in a **separate throwaway repo**, not this one.

```
Create a minimal Flutter app that does exactly this and nothing else:

record 10s of audio → resample to 48 kHz mono → chunk into 3s windows
→ run BirdNET GLOBAL 6K V2.4 TFLite → print the top label

Use tflite_flutter, not tflite_audio (its fixed float32[16000,1] tensor
shape doesn't fit BirdNET's float32[1,144000]).

UI is one button and one text field. No navigation, no styling, no
database, no map.

Tell me immediately if you need to write platform-channel Swift or
Kotlin to make any part of this work. That's a result I need to know
about, not a problem to solve quietly.
```

Acceptance: correct top-1 on 5 of 5 known clips, inference under ~2s on
a real device, runs on an iPhone and an Android phone from one codebase,
and no platform-channel native code was needed. Hard stop at two days.

---

## End-of-session prompt

If a session is ending mid-phase:

```
Stop here. Append to docs/STATE.md:
- Changelog lines for what actually changed
- Update Current state with the exact next step
- Anything that surprised you, into Gotchas

Keep it to a few lines. Don't summarise the whole session.
```

---

## Prompts to avoid

- "Read the plan and build EcoYard" — pulls ~5000 words in and produces
  a shallow pass at everything.
- "Port GardenEar to EcoYard" — too broad. Port one screen at a time.
- "Continue where we left off" without STATE.md — it will guess.
- "Also refactor X while you're in there" — scope creep is how phases
  stop ending.
