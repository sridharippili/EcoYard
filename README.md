# EcoYard

Backyard habitat advice driven by bird sound. Record a bird, EcoYard works out
which species it probably is, and suggests mostly free ways to help it: simple
actions and native plants for your yard, balcony or containers. First region:
the Northeast US.

One Flutter codebase for iOS and Android. **iOS ships first; Android uses the
same code and is paused until the iOS app is done.**

> Status: in development, not released. All content is a draft written for
> testing and has not been reviewed by a person (see
> [Release checklist](#release-checklist)).

## What it does

- **Identify a bird by sound.** Record up to 10 seconds. Three ways to answer,
  in this order:
  1. an **offline model on the phone** (BirdNET, downloaded once from Settings,
     about 52 MB) when you have it: nothing is sent anywhere;
  2. otherwise the recording is sent **at the same time** to NatureLM (more
     accurate, about 20 s) and BirdNET online (about 1 s). The quick answer
     shows first, and NatureLM confirms or replaces it.
- **Habitat advice** for the species: what the bird needs (food, shelter,
  water, nesting, safety), up to three simple actions chosen by a rules engine,
  and native plants that help it.
- **Native plant finder** with filters for space, sunlight and budget.
- **My Habitat Plan**: tick off actions, optional weekly reminder (local
  notification only).
- **Weather card** on Home. Off until you choose a town or allow an
  approximate location.
- **Photos** of species, with credits. Bundled for 10 birds and 15 plants; for
  other birds a photo is looked up on Wikimedia Commons (species name only).
- **Privacy controls**: see and copy everything stored, share it as a file, or
  erase it all (including the offline model) in one step.
- Light and dark themes that follow the phone; on iOS the real system tab bar
  (Liquid Glass on iOS 26 and later).

## Privacy in one paragraph

No account, no analytics, no ads. The plan and settings are stored on the phone
(SQLite). What can leave it: the recording (to NatureLM and BirdNET, unless the
offline model answered), a rounded location or a town name (to Open-Meteo, only
if you set one), and a bird's name (to Wikimedia, to find a photo). The app
never claims the recording is not kept by those services, because nobody has
audited them. The full, in-app wording is in
`app/lib/features/settings/privacy_pages.dart`.

## Repository layout

| Path | What it is |
| --- | --- |
| `app/` | The Flutter app: screens, controllers, theme, tests |
| `packages/ecoyard_core/` | **Pure Dart, no dependencies**: models, species resolver, habitat engine, plant finder, plan, settings, weather and offline-model value types |
| `packages/bird_audio/` | Everything that touches the device or network: recorder, identification providers and the chain, SQLite storage, offline model download and inference, weather, location, reminders, sharing, photo lookup |
| `content/` | All reference content as JSON (birds, plants, actions, tips, aliases, photo credits, offline model address). Nothing is hard-coded in Dart |
| `fixtures/` | `engine_cases.json` pins the engine and resolver behaviour |
| `scripts/` | Content validation and sync, photo fetching, release check, hook scripts |
| `docs/` | Plan, specification, design mockup, working notes (`STATE.md`) |
| `reference/GardenEar/` | A read-only copy of the earlier Swift app, for reading only |
| `.githooks/`, `.claude/` | Git hooks and the AI-assistant guardrails (see below) |

Dependency direction: `app` -> `bird_audio` -> `ecoyard_core`.

## Getting started

You need Flutter 3.50 or later (Dart 3.14) and, for iOS, Xcode with CocoaPods.

```bash
git clone <this repo> && cd EcoYard
bash scripts/setup.sh              # enables the git hooks (once)
cd app && flutter pub get
```

Run on a device or simulator:

```bash
flutter run --release -d <device-id>     # a phone: use release, see below
flutter run -d <simulator-id>            # simulator: debug is fine
```

On a real iPhone, **debug builds only start from Xcode or Flutter tooling**.
Install a release (or profile) build to open the app from the home screen. In
Xcode: Product > Scheme > Edit Scheme > Run > Build Configuration > Release.

The app needs no keys. If one is ever needed it goes in an untracked
`.env.json` and is passed with `--dart-define-from-file=.env.json`. Never commit
it.

### Content

`content/*.json` is the single source of truth. The app bundles copies in
`app/assets/content/`; after editing content run:

```bash
bash scripts/sync_content.sh
dart run scripts/validate_content.dart          # normal checks
dart run scripts/validate_content.dart --strict # release gate
```

A test fails if the two copies drift apart.

### Tests

```bash
bash scripts/hooks/pre-push.sh   # analyze + test every package + validate content
```

or per package: `cd app && flutter test`, `cd packages/bird_audio && flutter
test`, `cd packages/ecoyard_core && dart test`.

## Working rules

The rules this project is built under are in [`CLAUDE.md`](CLAUDE.md). The
important ones: Flutter only (no Swift or Kotlin feature code); `ecoyard_core`
stays pure Dart; persistence is SQLite with numbered, append-only migrations;
content lives in JSON; engine behaviour is pinned by `fixtures/` and changed
only deliberately; the UI never claims audio stays on the device; no secrets in
the repo.

Git hooks (`.githooks/`, enabled by `scripts/setup.sh`) check secrets, large
files, formatting, analysis, content validity and privacy wording before every
commit and push. CI (`.github/workflows/ci.yml`) runs the same checks on Linux.

`docs/STATE.md` is the short, current status of the project and its decisions.

## Third-party services and licences

See [`THIRD_PARTY_NOTICES.md`](THIRD_PARTY_NOTICES.md). Two things matter before
any public release:

- the BirdNET models are **CC BY-NC-SA 4.0 (non-commercial)**;
- bundled photos are CC BY or CC BY-SA and must keep their credits.

## Release checklist

Not done yet, and enforced by `scripts/release_check.sh`:

- every content file reviewed by a person (`reviewStatus: reviewed`);
- the offline model's score floor set from real recordings, and its licence
  question settled;
- a real-iPhone check of the offline model (accuracy and speed);
- the privacy policy and About text reviewed.

## Licence

No open-source licence has been chosen. Until one is, all rights are reserved:
see [`LICENSE`](LICENSE).
