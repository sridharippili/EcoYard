# Phase 6.5: Offline identification (BirdNET on the phone)

Status: PLAN, critic-reviewed and DECIDED 2026-11-14 (B, C, D, E below answered by the user); not started. Waiting for A (hosting) and the user's go-ahead. Needs the decisions in
"Decisions for the user" before any code. Written 2026-11-14 after the user asked for GardenEar's
"Download for offline use" card in Settings.

## Why this is a phase, not a Settings card

A card that downloads a file nothing uses would be dishonest. The card is the
last 10% of the work. The 90% is an on-device identification path that has
never worked in EcoYard (or in GardenEar: its `BirdNETLocalProvider.runInference`
is a stub that throws "Offline model initializing", and its downloader read the
file one byte at a time into memory from a URL that now 404s).

What exists and what is proven (STATE.md, Phase 0.5 spike, iOS Simulator):

| Proven | Not proven |
| --- | --- |
| `tflite_flutter` ^0.11 loads the FP32 model (51,726,412 bytes) in 358 ms | top-1 accuracy on real clips |
| input `[1,144000]` (3 s at 48 kHz), output `[1,6522]` logits | inference time on a real iPhone (< 2 s for a 10 s clip) |
| 6,522 labels line up with the output | real-device microphone at 48 kHz |
| `pod install` works with `record` + `tflite_flutter` | Android |

## What the user gets

- Settings > "Offline identification" card (GardenEar-style): size, "Download",
  progress with Cancel, "Verifying", "Ready, works without internet" with
  Remove, and a clear failure state with Try again.
- When the model is ready, identifying a bird works in airplane mode, is fast,
  and the audio is not sent anywhere. The result badge then says so, per result
  and only when true: "Identified on this phone. The recording was not sent
  anywhere." (This restores the mockup's promise honestly, for that result.)
- If the offline path cannot give an answer, the existing online chain runs as
  before and the badge says the audio was sent (provider-aware, unchanged).

## Design

### 1. Model source and verification
- Two files are needed at run time: the model (`.tflite`, 51.7 MB) and the label
  list (`labels`, 260 KB, 6,522 lines `Scientific_Common`). Neither is committed
  (hook blocks > 5 MB; label file is not committed per STATE.md).
- `content/offline_model.json` (content lives in JSON, rule 5): for each file the
  URL, exact byte size and SHA-256, plus a `modelVersion`. The app refuses a
  download whose size or SHA-256 differs, and refuses a file that will not load.
- Hosting: the user hosts the two files (GitHub release or Hugging Face repo they
  control). GardenEar's old GitHub URL is dead; Zenodo only serves a 77 MB zip
  (would need an unzip package).

### 2. Download manager (`packages/bird_audio`)
- `http` streaming (`client.send`), chunks written to `<name>.part`, progress from
  Content-Length, cancel closes the client and deletes the `.part`. Never holds the
  file in memory. No resume in v1.
- On finish: size check, SHA-256 check (new package `crypto`), atomic rename,
  then a load test. Any failure deletes the `.part` and reports a specific error.
- A `.part` left by a crash is removed at start-up (same place as the audio sweep).
- Storage: the app's CACHE directory (`getApplicationCacheDirectory`). iOS does not
  back it up (a 52 MB file must not go to iCloud), and may purge it when storage is
  low; the state is re-checked every launch, and "download again" is always
  available. (Application Support would be backed up and we cannot set the
  no-backup flag without platform code, rule 1.)
- No free-space plugin: a full disk is reported as a write failure. No
  Wi-Fi detection plugin: a confirmation dialog says "About 52 MB. Wi-Fi
  recommended." before downloading.

### 3. Audio format (the biggest unknown)
- BirdNET needs 48 kHz mono float samples. Today the recorder writes AAC `.m4a`
  (the online services were tested with m4a only) and there is no decoder.
- Plan: record WAV (PCM16, 48 kHz, mono) through the `record` package that is
  already approved. WAV is parsed in pure Dart (header chunks, odd headers,
  stereo down-mix, other sample rates resampled linearly).
- GATE 2: before building further, confirm NatureLM (router) and BirdNET (HF
  Space) accept WAV uploads (about 1 MB for 10 s instead of 0.1 MB). If either does
  not, fallback: record WAV only while the offline model is ready, m4a otherwise.
  This must be verified with a real call, not assumed.

### 4. Inference (`packages/bird_audio`)
- `BirdModelRunner` interface (`Future<List<double>> scoresFor(Float32List window)`)
  with a real `TfliteRunner` (package `tflite_flutter`, run in an isolate via
  `IsolateInterpreter` so the UI never janks) and a fake for tests.
- Pure Dart pipeline (fully unit-testable, no model needed): WAV -> Float32 ->
  3 s windows (pad the last) -> runner -> sigmoid -> per-class maximum over windows
  -> top 5 -> `Detection`s (name from the label, scientific name, score 0..1).
  Detections below a floor (0.1) are dropped; none left = "heard nothing"
  (final, like today: not a reason to fall through to the online service).
- `BirdNetLocalProvider implements IdentificationProvider`: `isAvailable()` = both
  files present and the model loaded once; `identify()` runs the pipeline.
  Provider id `birdnet-local`, label "BirdNET on this phone".
- Names go through the existing `SpeciesResolver` unchanged (only 10 species have
  advice, the rest get the existing honest "no advice for X yet, general tips").

### 5. Chain order (decision C)
- Recommended: when the model is ready, the chain is local, then NatureLM, then
  BirdNET online. "Not responsive" (model missing, load failure, runner error)
  falls through; "heard nothing" is final. When not ready the chain is exactly
  today's.
- Privacy badge: derived from the provider that answered. A local answer says
  nothing left the phone. If the local step failed and an online service answered,
  the badge and fallback note say the audio was sent (existing behaviour). A test
  pins that "not sent anywhere" can never appear after a fall-through.

### 6. Settings card and "Delete my data"
- `OfflineModelController` (states: notDownloaded, confirming, downloading(progress),
  verifying, ready, failed(reason)), restored from disk at start.
- "Delete my data" also removes the model, the `.part` files and the labels
  (PLAN.md Phase 6 says so), and the dialog lists them. The card then shows
  "not downloaded". Removing the model alone is also available from the card.
- Privacy policy, onboarding page 2 and the Settings facts are updated with the same
  per-result honesty: audio is sent online UNLESS the offline model is used.

### 7. Licence
- BirdNET V2.4 is CC BY-NC-SA 4.0 (non-commercial). The user decided to ignore
  non-commercial issues for now. STATE.md must keep this as an OPEN item before any
  public/commercial release (App Store), and About must credit BirdNET (K. Lisa
  Yang Center for Conservation Bioacoustics and Chemnitz University of Technology)
  once the model ships.

## Binding rules added after the critic review

These override anything above that they contradict.

### R1. The privacy badge is derived from facts, not from an id string
- `IdentificationProvider` gets `bool get sendsAudioOffDevice` (network providers
  true, the local provider false). `IdentificationResult`/`ChainOutcome` expose
  whether ANY attempt in that identification call sent audio (the answering
  provider, or any earlier provider in `failuresBefore` that is a network
  provider and was actually tried, not merely skipped).
- `privacyBadge` takes the whole `ChainOutcome`. "Identified on this phone. The
  recording was not sent anywhere." appears only when the answer is local AND no
  network provider was tried before it. Never match on `'birdnet-local'`.
- "Try again" re-runs the chain and builds a fresh outcome and badge; the badge
  describes that run only, never "this clip" overall.
- Property test over every provider order and every failure combination: "not
  sent" appears only for a local answer with no network attempt. A recording fake
  proves no network provider's `identify` is called when the local one answers.
- Health probes (`isAvailable`) are audio-free and stay so: nobody may "fix" the
  claim by sending audio in a probe. Stated in a code comment and tested.
- Copy rule: the phrase "not sent" may appear only in that per-result badge. A test
  scans onboarding, policy, Settings, About for it. Check `scripts/hooks` (the
  false-privacy-copy hook) before step 6.

### R2. Audio format: keep m4a online, WAV only when the model is ready
- Default path is unchanged: record m4a, upload m4a (criterion 7 stays true).
- When the model is ready the recorder writes WAV (PCM16, 48 kHz, mono) and the
  local provider decodes it. `AudioClip` gets a real `format` field (not inferred
  from `fileName`). The app owns one `OfflineModelController` and gives the
  recorder factory its readiness at the moment a recording starts.
- If the local step then falls through to the online services, those receive the
  WAV clip: Gate 2 must verify, with real uploads over a slow link, that both
  services accept WAV and that the 10x larger body (~1 MB) fits `perProviderTimeout`.
  If either rejects WAV, the rule becomes: no fall-through to that service with a
  WAV clip (honest "couldn't identify offline" instead).
- Everything that assumes `.m4a` is updated in the same change and listed here:
  `AudioClip` defaults, `RecordPackageRecorder` (extension, fileName),
  `AudioCache._ours` -> `^ecoyard_\d+\.(m4a|wav)$` (otherwise Delete my data and
  the start-up sweep silently stop cleaning WAV leftovers: a privacy regression),
  and the tests that use `.m4a` names (app_storage_test, settings_controller_test,
  http_providers_test). Those tests CHANGE (extended, not weakened); criterion 7 is
  about behaviour with no model, not about untouched test files.

### R3. Chain semantics for the local provider
- `isAvailable()` only checks that the model and label files exist and have the
  exact expected byte size. It never loads the model (probe timeout is 6 s, a cold
  52 MB load can exceed it, and a false is cached for 3 minutes).
- The model loads lazily inside `identify`. A load failure or any runner exception
  throws `ProviderException(FailureKind.unavailable)` so the chain marks it down and
  falls through (a plain exception would become `badResponse` and be retried on
  every recording).
- The per-provider timeout for the local step is sized for a cold start (load +
  isolate spawn + inference), or the model is warmed when the Birds tab is first
  opened (never at app start).
- One inference at a time. On timeout, on Remove, on Delete my data and on a load
  failure the isolate and interpreter are closed; `Future.timeout` alone does not
  stop isolate work. Tested with a fake runner that records close calls.
- A cache purge while the app runs leaves an open interpreter on a deleted file:
  harmless on iOS (purges happen when the app is not running); the next launch
  re-checks the size and shows "not downloaded".

### R4. "Heard nothing" for the local model is not final
- For the online services "heard nothing" stays final (they are the reference).
- For the local model, a result below the score floor falls through to the online
  chain when one is available, and the badge then says the audio was sent. If no
  online service answers, the empty state says plainly "The phone model heard no
  bird". This is a per-provider flag in the chain (`noDetectionIsFinal`), decided
  before step 5.
- The score floor (0.1), the window length and the top-N are numbers in
  `content/offline_model.json`, not Dart (rule 5).

### R5. Download rules
- Single flight: a second Download tap while one is running is ignored.
- Cancel before the rename deletes the `.part`; after the rename the finished file
  is kept (Cancel then means "too late", shown as ready). Delete my data during a
  download cancels it first, then deletes, so a `.part` cannot reappear.
- https only (reject http); redirects are followed (GitHub releases and Hugging Face
  answer with a 302 to a CDN, up to the client's limit); progress is indeterminate
  when Content-Length is missing. Both are tested with a fake client.
- Hash once, at download time, then rename and load that file; on later launches
  re-check size only (hashing 52 MB every start is wasteful). `modelVersion` is part
  of the file name, so an app build never trusts a replaced older file. Updating the
  hosted file means a new app build (the hash is bundled), stated in the plan.
- A separate `ModelSweeper` removes `.part` files from the cache directory at
  start-up and in Delete my data (`AudioCache` only looks at the temp directory).
- Delete my data order: cancel download, close the runner, wipe the database in its
  transaction, then remove the model files; a failure removing the model is
  reported honestly but never leaves the database wipe half done. The model IS
  removed (PLAN.md Phase 6); this is not a user question any more.

### R6. `content/offline_model.json` and the release gate
- Fields: `schemaVersion`, `reviewStatus`/`reviewedBy`/`reviewedOn` (same gate as
  the other files), `modelVersion`, `files[]` {name, https url, bytes, sha256},
  `windowSeconds`, `scoreFloor`, `topN`.
- `validate_content.dart` rules: https URL, 64 hex sha256, positive byte size,
  unique names. `--strict` (release_check.sh) FAILS on placeholder or unreviewed
  values, so a release with a dead URL (GardenEar's failure) is impossible.
- It joins `app/assets/content/` through `scripts/sync_content.sh` and the drift
  test, and `ReferenceRepository` or a small separate parser reads it.
- release_check.sh also fails while the BirdNET licence item (CC BY-NC-SA 4.0) is
  open: a release gate, not only prose in STATE.md.

### R7. Measurable acceptance (replaces criteria 1-3 above)
1. Clips: 5 named clips (species with content, e.g. Northern Cardinal, American
   Robin, Blue Jay, American Goldfinch, Black-capped Chickadee), supplied by the
   user or CC-licensed from Xeno-canto, with a licence/credit list committed
   (`docs/offline_clips.md`); the audio itself is NOT committed. Pass = post-sigmoid
   top-1 after the SpeciesResolver equals the expected eBird id on at least 4 of 5,
   on a real iPhone.
2. Speed: inference for a 10 s clip under 2 s on a named real iPhone, in a RELEASE
   (or profile) build, reported cold (first run after launch) and warm. Debug builds
   do not count (5-10x slower).
3. Offline: a test with a `http.Client` that throws on any call proves the local
   path makes no request; on the device, airplane mode plus a proxy/network log
   confirms it (airplane mode alone proves nothing, the online providers would
   simply fail).
4-7 unchanged.

## New packages (need the user's approval, CLAUDE.md working agreement)

| Package | Why | Notes |
| --- | --- | --- |
| `tflite_flutter` ^0.11 | run the model | already used in the spike (pods OK on iOS simulator) |
| `crypto` | SHA-256 of the download | dart-lang first party, pure Dart |

No unzip package, no connectivity/disk-space/permission packages, no platform
channels (rule 1).

## Steps (each ends with tests and analyzer clean)

0. Decisions + model hosting by the user (below). Nothing else starts before this.
1. GATE 1, in-app proof (hard stop): add `tflite_flutter`, load the model from a
   file path on the simulator, run 3 known clips, print top-1 and timing.
   Pass: model loads from a plain file path; no build breakage with Flutter 3.50 /
   iOS 15+ / current pods. If it fails: stop, report, no further work.
2. GATE 2, formats: verify the two online services accept 48 kHz mono WAV; decide
   the recorder format rule.
3. Pure pipeline + tests: WAV parsing, windowing, sigmoid/top-k/aggregation, label
   parsing, `Detection` mapping. No model needed.
4. Download manager + `content/offline_model.json` + tests with a fake http client
   (progress, cancel, size/hash mismatch, crash leftovers, atomic rename, disk full).
5. `BirdNetLocalProvider` + `TfliteRunner` + chain wiring + badges/copy + tests with
   the fake runner (never needs the real model in unit tests).
6. Settings card, controller, Delete my data, policy/onboarding/About copy + tests.
7. Verification on a real iPhone (the unproven items below), mutation checks,
   reviewer, then the critic at the end of the phase.

## Acceptance criteria (all must be met, with evidence)

1. Top-1 correct on at least 4 of 5 real clips of species we have content for
   (clips supplied by the user, or CC-licensed with credit), on a real iPhone.
2. A 10 s recording is identified in under 2 s of inference on that iPhone.
3. In airplane mode, with the model ready: Record -> result works, and no network
   request is made (checked, not assumed).
4. Download: progress shown, Cancel works and leaves nothing behind, a wrong size or
   hash is rejected, killing the app mid-download leaves no usable partial file.
5. Delete my data removes the model, labels and any partial file (checked on disk).
6. The badge never claims "not sent" unless that exact result came from the local
   model with no earlier online attempt (a test fails if it appears otherwise).
7. Existing behaviour is unchanged when no model is downloaded (all current tests
   pass untouched).

## Risks (ranked)

1. Online services may reject WAV (Gate 2). Cost: format rule + two recorder paths.
2. Global BirdNET labels with no regional filter will name species that do not occur
   in the Northeast. Mitigations: show top candidates, a score floor, and the
   existing "possible match" wording. A regional species filter is a later, separate
   task (needs the BirdNET meta model or a species list).
3. `tflite_flutter` is lightly maintained; native build breakage with a newer Flutter
   or Xcode. Gate 1 exists for this.
4. iOS may purge the cache directory: a ready model can vanish. Handled by
   re-checking at launch and by the "download again" state.
5. 52 MB on cellular without Wi-Fi detection. Handled by the confirmation text only.
6. Licence (above). Not a blocker for development, a blocker for release.
7. Android is paused: nothing here is iOS-specific, but only iOS is verified.

## Out of scope

Regional species filter, NatureLM on device, background download, resume, model
updates (`modelVersion` is stored for a later update flow), Android verification,
a sightings journal.

## Gate results (2026-11-14)

### Gate 1: model runs inside EcoYard: PASS (mechanics); accuracy NOT yet measured
- iOS Simulator (iPhone 18 Pro, iOS 27.2), DEBUG build, `tflite_flutter` 0.11.0 via
  CocoaPods, model loaded with `Interpreter.fromFile` from the app's
  `Library/Caches` (a plain file, not an asset): load 129 ms; input 144000,
  output 6522, labels 6522; one 3 s window 30-36 ms after the first run (142 ms
  cold). A 10 s clip (3-4 windows) is about 0.1-0.15 s of inference here.
  Real-iPhone RELEASE timing (acceptance 2) is still to measure.
- No real bird clips yet, so top-1 accuracy (acceptance 1) is unmeasured.
- FINDING (blocks step 5): pure white noise scored "Lesser Spotted Woodpecker"
  (a European bird) at 0.463 post-sigmoid. With the planned 0.1 floor and no
  regional filter, the offline path would confidently name birds that cannot be
  in the user's yard. Silence and a pure tone stayed below 0.01 (top classes
  "Engine", "Human vocal"). Decision needed before step 5 (see "Decision F").

### Gate 2: online services accept WAV: PASS for BirdNET online; NatureLM UNTESTED
- BirdNET (HF Space `/analyze`), 10 s 48 kHz mono PCM16 WAV (960 KB, synthetic
  chirps): decoded and analysed (HTTP 404 "No species detected", the expected
  answer). Control: 960 KB of random bytes named `.wav` -> HTTP 500 "Audio
  conversion failed", so the WAV really was parsed (the Space runs ffmpeg, which
  reads the content, not the name). Over a throttled ~0.5 Mbit/s uplink: 14.7 s,
  inside the 40 s timeout of `standardOnlineChain`.
- NatureLM: router `/health` reports `active_providers: []` (Kaggle notebook off),
  so WAV acceptance cannot be tested. Rule until tested: a WAV clip may still go
  to NatureLM; if it is rejected, the chain falls through to BirdNET online,
  which is now known to accept WAV. Re-test when the notebook is on.

### Decision F (needed before step 5): what may the offline model name?
- (a) Closed set: only species we have content for (10 now), plus the non-bird
  classes. Anything else = "couldn't identify offline" and falls through to the
  online services. High precision, honest, small.
- (b) A Northeast species list (a few hundred, as `content/` JSON from a sourced
  regional checklist, reviewed by a person); species outside our content get
  the existing general advice.
- (c) BirdNET's location model: needs location, which the app does not use. No.
- Either way the score floor goes up from 0.1 (noise reached 0.46) and is set
  from real clips, not guessed.

## Decisions (answered 2026-11-14)

- A. Model hosting: OPEN. The user uploads the model and label files to a
  GitHub release or Hugging Face repo they control and gives the two URLs. Gate 1
  does not need them (it can use the spike's local copy); step 4 does.
- B. Packages: APPROVED `tflite_flutter` and `crypto`. Nothing else (no unzip,
  connectivity, disk-space or permission package; no platform channel).
- C. Order: OFFLINE FIRST when the model is ready, then NatureLM, then BirdNET
  online.
- D. Storage: CACHE directory (not in iCloud backups; may be purged).
- E. When the local model hears nothing: fall through to the online services (the
  badge then says the audio was sent), per rule R4.
- Delete my data removes the model: decided by PLAN.md Phase 6.
